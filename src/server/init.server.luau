--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Template = ReplicatedStorage:WaitForChild("Template")
local Config = require(Template:WaitForChild("Shared").TemplateConfig)

local Services = script.Services
local AnnouncementService = require(Services.AnnouncementService)
local FeedbackService = require(Services.FeedbackService)
local InventoryService = require(Services.InventoryService)
local LeaderboardService = require(Services.LeaderboardService)
local NotificationService = require(Services.NotificationService)
local ProfileService = require(Services.ProfileService)
local PublicProfileService = require(Services.PublicProfileService)
local RemoteService = require(Services.RemoteService)
local RewardService = require(Services.RewardService)
local RuneService = require(Services.RuneService)
local EconomyService = require(Services.EconomyService)
local SocialService = require(Services.SocialService)
local StoreService = require(Services.StoreService)
local StageRuntimeService = require(Services.StageRuntimeService)
local StagePlatformService = require(Services.StagePlatformService)
local TowerDefenseService = require(Services.TowerDefenseService)
local PortalService = require(Services.PortalService)
local DungeonService = require(Services.DungeonService)
local EconomyRateProvider = require(script.Providers.DefaultEconomyRateProvider)
local DataStoreRuntime = require(script.Util.DataStoreRuntime)
local DungeonEventStore = require(script.Util.DungeonEventStore)

-- Publish one explicit, immutable runtime mode before any client-facing service
-- starts. Lobby clients use it to return before waiting on lobby-only world/UI,
-- while the dedicated dungeon controller remains active in both modes.
local dungeonMode = Config.features.dungeon and DungeonService.isDungeonServer()
Template:SetAttribute("RuntimeMode", if dungeonMode then "dungeon" else "lobby")

DataStoreRuntime.announce(Template)
RemoteService.initialize()
-- Receipt processing must remain installed even when the store UI is disabled;
-- pending developer-product receipts must never be silently acknowledged.
StoreService.initialize()
ProfileService.startAutosave()
if Config.features.leaderboards then
	LeaderboardService.start()
end
if Config.features.crossServerChat then
	AnnouncementService.start(RemoteService.broadcastAnnouncement)
end
if Config.features.runes and not dungeonMode then
	-- Surge channeling competes in the strongest-temporary-boost bucket; the
	-- provider keeps EconomyService unaware of the rune altar.
	EconomyService.setChannelBoostProvider(RuneService.channelEarningsMultiplier)
	RuneService.start({
		publish = function(player, result)
			RemoteService.sendEvent(player, "RuneResult", result)
		end,
		publishChannel = function(player, channel)
			RemoteService.sendEvent(player, "RuneChannel", channel)
		end,
	})
end
if Config.features.towerDefense and not dungeonMode then
	StagePlatformService.start()
	StageRuntimeService.start({
		origin = StagePlatformService.originFor,
		available = StagePlatformService.hasPlatform,
		publishActiveStage = StagePlatformService.publishActiveStage,
	})
	TowerDefenseService.start({
		publish = RemoteService.publish,
		publishEnemies = RemoteService.publishTowerEnemies,
		publishPlacements = RemoteService.publishTowerPlacements,
	})
end
if Config.features.dungeon then
	-- An empty allowlist disables the global override entirely. This prevents a
	-- previously persisted, non-expiring event from becoming impossible to clear
	-- after a recipe removes its event administrators.
	local dungeonEventsEnabled = #Config.dungeon.eventAdminUserIds > 0
	-- The same place boots as a lobby or a reserved dungeon server.
	-- DungeonService self-gates (it only runs the boss fight in a reserved
	-- server); the portal pad loop must run in the lobby only, or a dungeon
	-- server would try to launch a nested dungeon from its own pad.
	DungeonService.start({
		publish = function(players, data)
			for _, player in players do
				if player.Parent == Players then
					RemoteService.sendEvent(player, "DungeonState", data)
				end
			end
		end,
		award = EconomyService.awardCurrencyRaw,
		fallbackCurrencyId = Config.economy.primaryCurrencyId,
		notify = function(player, message)
			RemoteService.sendEvent(player, "PortalNotice", { message = message })
		end,
		ready = function(player)
			return ProfileService.get(player) ~= nil
		end,
		equippedItemId = InventoryService.equippedItemId,
		ensureEquipped = InventoryService.ensureEquipped,
		grantItem = InventoryService.grant,
		setSavedBossId = function(player, bossId)
			local profile = ProfileService.get(player)
			if profile == nil or type(profile.dungeon) ~= "table" then
				return false
			end
			profile.dungeon.selectedBossId = bossId
			ProfileService.markDirty(player, "dungeon:selectBoss")
			return true
		end,
		notePadBossPick = PortalService.setBossPick,
	})
	if not dungeonMode then
		-- The event boss is a global value shared by every lobby; keep it fresh so
		-- an admin's change on any server takes effect here within a refresh cycle.
		-- Wait briefly for the first read before the portal can launch; an unavailable
		-- store fails open to normal party/personal/default selection after that bound.
		if dungeonEventsEnabled then
			local eventStoreReady = DungeonEventStore.start()
			if not eventStoreReady then
				warn("[Dungeon] Event boss store was not ready at startup; using normal boss selection.")
			end
		end
		PortalService.start({
			publish = function(data)
				RemoteService.broadcast("PortalState", data)
			end,
			launch = DungeonService.launchParty,
			savedBossId = function(player)
				local profile = ProfileService.get(player)
				if profile ~= nil and type(profile.dungeon) == "table" then
					return profile.dungeon.selectedBossId
				end
				return nil
			end,
			eventBossId = function()
				if not dungeonEventsEnabled then
					return nil
				end
				return DungeonEventStore.activeBossId(os.time())
			end,
		})
		-- Admin surface for the forced event boss: a server-created chat command,
		-- gated to the configured allowlist inside DungeonService.setEventBoss. Only
		-- created when a recipe actually names admins, so it never appears otherwise.
		if dungeonEventsEnabled then
			local EVENT_COMMAND_COOLDOWN_SECONDS = 2
			local eventCommandLastAttemptAt: { [number]: number } = {}
			local function commandParts(message: string): { string }
				local parts: { string } = {}
				for part in string.gmatch(message, "%S+") do
					table.insert(parts, part)
				end
				return parts
			end
			local function sendCommandFeedback(userId: number, message: string)
				local player = Players:GetPlayerByUserId(userId)
				if player ~= nil then
					RemoteService.sendEvent(player, "PortalNotice", { message = message })
				end
			end
			local command = Instance.new("TextChatCommand")
			command.Name = "DungeonEventCommand"
			command.PrimaryAlias = "/dungeonevent"
			command.SecondaryAlias = "/de"
			command.Triggered:Connect(function(textSource: TextSource, message: string)
				local now = os.clock()
				local lastAttemptAt = eventCommandLastAttemptAt[textSource.UserId]
				if lastAttemptAt ~= nil and now - lastAttemptAt < EVENT_COMMAND_COOLDOWN_SECONDS then
					return
				end
				eventCommandLastAttemptAt[textSource.UserId] = now

				local parts = commandParts(message)
				if #parts < 2 or #parts > 3 then
					sendCommandFeedback(textSource.UserId, "Usage: /dungeonevent <bossId|off> [minutes]")
					return
				end
				local bossId = parts[2]
				local durationMinutes: number? = nil
				if string.lower(bossId) == "off" then
					if parts[3] ~= nil then
						sendCommandFeedback(textSource.UserId, "The off command does not accept a duration.")
						return
					end
					bossId = "off"
				elseif parts[3] ~= nil then
					local parsed = tonumber(parts[3])
					if
						parsed == nil
						or parsed ~= parsed
						or parsed == math.huge
						or parsed == -math.huge
						or parsed <= 0
					then
						sendCommandFeedback(
							textSource.UserId,
							"Duration must be a positive number of minutes."
						)
						return
					end
					durationMinutes = parsed
				end
				local _, feedback = DungeonService.setEventBoss(textSource.UserId, bossId, durationMinutes)
				sendCommandFeedback(textSource.UserId, feedback)
			end)
			command.Parent = TextChatService
		end
	end
end

local function playerAdded(player: Player)
	task.spawn(function()
		-- Reserved dungeons never claim a tower-defense platform. Hybrid lobbies
		-- may also opt out of join-time platform admission while every actual
		-- tower-defense request continues to require an authoritative platform.
		if
			Config.features.towerDefense
			and Config.towerDefense.requirePlatformOnJoin
			and not dungeonMode
			and not StagePlatformService.hasPlatform(player)
		then
			if player.Parent then
				player:Kick(
					"No playable platform was available in this server. Please rejoin to enter another server."
				)
			end
			return
		end
		local profile = ProfileService.load(player)
		if profile == nil then
			if player.Parent then
				player:Kick("Your data could not be loaded safely. Please rejoin.")
			end
			return
		end
		if Config.features.dungeon then
			-- Every dungeon-enabled profile owns one usable saved weapon. Existing
			-- profiles are upgraded through the inventory map without a schema reset,
			-- and a player-selected weapon is never overwritten.
			InventoryService.ensureEquipped(
				player,
				Config.dungeon.equipmentSlot,
				Config.dungeon.starterWeaponId
			)
		end
		NotificationService.cancel(player)
		StoreService.refreshEntitlements(player)
		SocialService.refresh(player)
		player:GetPropertyChangedSignal("MembershipType"):Connect(function()
			SocialService.refresh(player)
		end)
		if Config.features.offlineEarnings then
			RewardService.prepareOffline(player)
		end
		if Config.features.leaderboards then
			LeaderboardService.updateLeaderstats(player)
		end
		if Config.features.profiles then
			PublicProfileService.publish(player)
		end
		RemoteService.publish(player)
		SocialService.refreshAll()
	end)
end

local function playerRemoving(player: Player)
	if Config.features.notifications then
		NotificationService.scheduleOnLeave(player)
	end
	if Config.features.profiles then
		PublicProfileService.publish(player)
	end
	if Config.features.leaderboards then
		LeaderboardService.flushPlayer(player)
	end
	RewardService.forget(player)
	RuneService.forget(player)
	TowerDefenseService.forget(player)
	StagePlatformService.forget(player)
	StageRuntimeService.forget(player)
	PortalService.forget(player)
	DungeonService.forget(player)
	FeedbackService.forget(player)
	RemoteService.forget(player)
	ProfileService.release(player)
	task.defer(SocialService.refreshAll)
end

Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(playerRemoving)
for _, player in Players:GetPlayers() do
	playerAdded(player)
end

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			local profile = ProfileService.get(player)
			if profile then
				profile.stats.playSeconds += 60
				profile.lastSeenAt = os.time()
				profile.offlineRateSnapshot = EconomyRateProvider.getRate(player)
				ProfileService.markDirty(player, "playtime")
				if Config.features.profiles then
					PublicProfileService.publish(player)
				end
			end
		end
	end
end)

game:BindToClose(function()
	ProfileService.close()
end)

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	})
	if not dungeonMode then
		PortalService.start({
			publish = function(data)
				RemoteService.broadcast("PortalState", data)
			end,
			launch = DungeonService.launchParty,
		})
	end
end

local function playerAdded(player: Player)
	task.spawn(function()
		-- In a reserved dungeon server the party is here to fight the boss, not to
		-- claim a tower-defense platform, so never bounce them for lacking one.
		if
			Config.features.towerDefense
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

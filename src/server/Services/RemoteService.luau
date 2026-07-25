--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Catalogs = require(Shared.Catalogs)
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local RemoteNames = require(Shared.RemoteNames)
local TowerDefenseRequest = require(Shared.TowerDefenseRequest)

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local AfkService = require(script.Parent.AfkService)
local DungeonService = require(script.Parent.DungeonService)
local EconomyService = require(script.Parent.EconomyService)
local FeedbackService = require(script.Parent.FeedbackService)
local InventoryService = require(script.Parent.InventoryService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local LikesService = require(script.Parent.LikesService)
local ProfileService = require(script.Parent.ProfileService)
local PublicProfileService = require(script.Parent.PublicProfileService)
local RewardService = require(script.Parent.RewardService)
local RuneService = require(script.Parent.RuneService)
local SettingsService = require(script.Parent.SettingsService)
local StagePlatformService = require(script.Parent.StagePlatformService)
local TowerDefenseService = require(script.Parent.TowerDefenseService)

local RemoteService = {}
local limiter = RateLimiter.new()
local stateRemote: RemoteEvent
local requestRemote: RemoteEvent
local queryRemote: RemoteFunction

-- The shared RNG Defender place uses a reserved server as its dungeon. Keep the
-- authored/configured feature table intact, but expose and accept only the
-- systems that are actually started in this runtime mode. Otherwise a dungeon
-- client can call tower-defense remotes against an intentionally unstarted
-- service and the snapshot misleadingly renders lobby gameplay as available.
local runtimeFeatures: { [string]: boolean } = table.clone(Config.features)
local runtimeMode = if Config.features.dungeon == true and DungeonService.isDungeonServer()
	then "dungeon"
	else "lobby"
if runtimeMode == "dungeon" then
	runtimeFeatures.towerDefense = false
	runtimeFeatures.runes = false
end

local function featureEnabled(name: string): boolean
	return runtimeFeatures[name] == true
end

local requestFeatures: { [string]: string } = {
	BuyItem = "store",
	UseItem = "inventory",
	ToggleEquip = "inventory",
	ClaimDaily = "dailyRewards",
	ClaimOffline = "offlineEarnings",
	RedeemCode = "codes",
	UpdateSetting = "settings",
	SubmitFeedback = "feedback",
	SetRuneMode = "runes",
	RollUnit = "towerDefense",
	SetTowerLoadout = "towerDefense",
	UnlockTowerLoadoutSlot = "towerDefense",
	EquipBestUnits = "towerDefense",
	PlaceUnit = "towerDefense",
	AutoPlaceBestUnits = "towerDefense",
	StartTowerWave = "towerDefense",
	RunTowerWavePlaytest = "towerDefense",
	ResetTowerDefense = "towerDefense",
	ActivateTowerStage = "towerDefense",
	TravelToTowerPlatform = "towerDefense",
	DungeonAttack = "dungeon",
	DungeonDodge = "dungeon",
	UseDungeonAbility = "dungeon",
	SelectDungeonBoss = "dungeon",
}

-- Per-action rate-limit overrides (capacity, tokens/second). Actions absent here
-- use the default 6-burst / 1-per-second bucket. Click-to-attack is already paced
-- by DungeonService's per-player cooldown, so its bucket only guards raw spam.
local requestRates: { [string]: { number } } = {
	TravelToTowerPlatform = { 2, 0.5 },
	DungeonAttack = { 12, 8 },
	DungeonDodge = { 4, 2 },
}

local queryActions: { [string]: boolean } = {
	InitialState = true,
	SearchProfile = true,
	GlobalLeaderboard = true,
}

local noPayloadActions: { [string]: boolean } = {
	RollUnit = true,
	UnlockTowerLoadoutSlot = true,
	EquipBestUnits = true,
	AutoPlaceBestUnits = true,
	StartTowerWave = true,
	ResetTowerDefense = true,
	TravelToTowerPlatform = true,
	DungeonAttack = true,
	DungeonDodge = true,
}

local function getOrCreate(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function RemoteService.snapshot(player: Player): any
	local profile = ProfileService.snapshot(player)
	if profile == nil then
		return nil
	end
	local likes = LikesService.getLikes()
	local towerPlacements = {}
	local towerPlacementRevision = 0
	if featureEnabled("towerDefense") then
		towerPlacements, towerPlacementRevision = TowerDefenseService.presentationSnapshot()
	end
	return {
		profile = profile,
		currencyDefinitions = Config.economy.currencies,
		catalog = Catalogs.items,
		features = runtimeFeatures,
		runtimeMode = runtimeMode,
		version = Config.version,
		serverTime = os.time(),
		friendBonus = Calculations.friendBonus(
			profile.social.friendCountInServer,
			Config.economy.friendBonusPerFriend,
			Config.economy.friendBonusCap
		),
		premiumBonus = if profile.entitlements.premium then Config.economy.premiumBonus else 0,
		potionMultiplier = Calculations.potionMultiplier(profile.boosts, os.time()),
		runeMultiplier = EconomyService.getRuneMultiplier(player),
		channelMultiplier = RuneService.channelEarningsMultiplier(player),
		temporaryMultiplier = Calculations.temporaryMultiplier(
			profile.boosts,
			os.time(),
			RuneService.channelEarningsMultiplier(player)
		),
		runes = if featureEnabled("runes") then RuneService.snapshotFor(player) else nil,
		towerDefense = if featureEnabled("towerDefense")
			then TowerDefenseService.snapshotFor(player)
			else nil,
		towerPlacements = towerPlacements,
		towerPlacementRevision = towerPlacementRevision,
		offline = RewardService.getPendingOffline(player),
		likes = likes,
		dailyRewards = Config.rewards.daily,
		likesMilestones = Config.rewards.likesMilestones,
		serverLeaderboard = LeaderboardService.serverBoard(),
		productAvailability = {
			coinPackSmall = Config.products.coinPackSmall.id > 0,
			coinPackLarge = Config.products.coinPackLarge.id > 0,
			extendedOffline = Config.economy.extendedOfflineGamePassId > 0,
		},
		productIds = {
			coinPackSmall = Config.products.coinPackSmall.id,
			coinPackLarge = Config.products.coinPackLarge.id,
			extendedOffline = Config.economy.extendedOfflineGamePassId,
		},
		integrationAvailability = {
			community = Config.features.communityVerification and Config.identity.communityId > 0,
			discord = false,
			guilds = false,
			notificationWorker = Config.notifications.workerUrl ~= "",
		},
	}
end

function RemoteService.publish(player: Player)
	if stateRemote and player.Parent then
		stateRemote:FireClient(player, { kind = "Snapshot", data = RemoteService.snapshot(player) })
	end
end

function RemoteService.publishTowerEnemies(player: Player)
	if featureEnabled("towerDefense") and stateRemote and player.Parent then
		stateRemote:FireClient(
			player,
			{ kind = "TowerEnemies", data = TowerDefenseService.snapshotFor(player) }
		)
	end
end

function RemoteService.publishTowerPlacements()
	if featureEnabled("towerDefense") and stateRemote then
		local placements, revision = TowerDefenseService.presentationSnapshot()
		stateRemote:FireAllClients({
			kind = "TowerPlacements",
			data = placements,
			revision = revision,
		})
	end
end

local function result(player: Player, ok: boolean, message: string, data: any?)
	stateRemote:FireClient(player, { kind = "Result", ok = ok, message = message, data = data })
	RemoteService.publish(player)
end

local function handleRequest(player: Player, packet: any)
	if type(packet) ~= "table" or type(packet.action) ~= "string" then
		return
	end
	local action = packet.action
	local payload = packet.payload
	local requiredFeature = requestFeatures[action]
	if requiredFeature == nil and action ~= "AfkRollover" then
		if limiter:allow(player, "unknown-request", 2, 0.25) then
			result(player, false, "Unknown request")
		end
		return
	end
	local rateCapacity, rateRefill = 6, 1
	local rateOverride = requestRates[action]
	if rateOverride then
		rateCapacity, rateRefill = rateOverride[1], rateOverride[2]
	end
	if not limiter:allow(player, action, rateCapacity, rateRefill) then
		-- Dungeon attacks are fire-and-forget. Silently drop excess clicks so an
		-- attacker cannot turn rate-limit rejection into an unbounded stream of
		-- full profile snapshots through result(). Hotbar abilities share this
		-- path; their own per-ability server cooldown already paces real use.
		if action == "DungeonAttack" or action == "DungeonDodge" or action == "UseDungeonAbility" then
			return
		end
		if action == "SelectDungeonBoss" then
			RemoteService.sendEvent(player, "DungeonBossSelected", {
				accepted = false,
				reason = "rateLimited",
			})
			return
		end
		result(player, false, "Please slow down")
		return
	end
	if requiredFeature and not featureEnabled(requiredFeature) then
		result(player, false, "This system is not enabled in this game")
		return
	end
	if noPayloadActions[action] and not TowerDefenseRequest.acceptsNoPayload(payload) then
		if action ~= "DungeonAttack" and action ~= "DungeonDodge" then
			result(player, false, "Invalid request")
		end
		return
	end

	if action == "BuyItem" then
		local itemId = if type(payload) == "table" then payload.itemId else nil
		if type(itemId) ~= "string" or #itemId > 64 then
			result(player, false, "Invalid item")
			return
		end
		result(player, InventoryService.buy(player, itemId))
	elseif action == "UseItem" then
		local itemId = if type(payload) == "table" then payload.itemId else nil
		if type(itemId) ~= "string" or #itemId > 64 then
			result(player, false, "Invalid item")
			return
		end
		result(player, InventoryService.consume(player, itemId))
	elseif action == "ToggleEquip" then
		local itemId = if type(payload) == "table" then payload.itemId else nil
		if type(itemId) ~= "string" or #itemId > 64 then
			result(player, false, "Invalid item")
			return
		end
		result(player, InventoryService.toggleEquip(player, itemId))
	elseif action == "ClaimDaily" then
		result(player, RewardService.claimDaily(player))
	elseif action == "ClaimOffline" then
		result(player, RewardService.claimOffline(player))
	elseif action == "RedeemCode" then
		result(
			player,
			RewardService.redeemCode(player, if type(payload) == "table" then payload.code else nil)
		)
	elseif action == "UpdateSetting" then
		if type(payload) ~= "table" then
			result(player, false, "Invalid setting")
			return
		end
		result(player, SettingsService.update(player, payload.key, payload.value))
	elseif action == "SubmitFeedback" then
		if type(payload) ~= "table" then
			result(player, false, "Invalid feedback")
			return
		end
		result(player, FeedbackService.submit(player, payload.category, payload.message))
	elseif action == "SetRuneMode" then
		-- Only shape checks live here; RuneService re-validates that the mode
		-- exists and is unlocked for this player.
		local modeId = if type(payload) == "table" then payload.modeId else nil
		if type(modeId) ~= "string" or #modeId < 1 or #modeId > 40 then
			result(player, false, "Invalid channel mode")
			return
		end
		result(player, RuneService.setMode(player, modeId))
	elseif action == "RollUnit" then
		result(player, TowerDefenseService.rollUnit(player))
	elseif action == "SetTowerLoadout" then
		local loadout = TowerDefenseRequest.parseLoadout(payload, Config.towerDefense.loadoutSlots)
		if loadout == nil then
			result(player, false, "Invalid loadout")
			return
		end
		result(player, TowerDefenseService.setLoadout(player, loadout.unitIds))
	elseif action == "UnlockTowerLoadoutSlot" then
		result(player, TowerDefenseService.unlockLoadoutSlot(player))
	elseif action == "EquipBestUnits" then
		result(player, TowerDefenseService.equipBest(player))
	elseif action == "PlaceUnit" then
		local placement = TowerDefenseRequest.parsePlacement(payload)
		if placement == nil then
			result(player, false, "Invalid placement")
			return
		end
		result(
			player,
			TowerDefenseService.placeUnit(player, placement.unitId, placement.column, placement.row)
		)
	elseif action == "AutoPlaceBestUnits" then
		result(player, TowerDefenseService.autoPlaceBest(player))
	elseif action == "StartTowerWave" then
		result(player, TowerDefenseService.startWave(player))
	elseif action == "RunTowerWavePlaytest" then
		local playtest = TowerDefenseRequest.parseWavePlaytest(payload)
		if playtest == nil then
			result(player, false, "Invalid playtest wave")
			return
		end
		result(player, TowerDefenseService.runWavePlaytest(player, playtest.stageId, playtest.waveNumber))
	elseif action == "ResetTowerDefense" then
		result(player, TowerDefenseService.resetMatch(player))
	elseif action == "ActivateTowerStage" then
		local activation = TowerDefenseRequest.parseStageActivation(payload)
		if activation == nil then
			result(player, false, "Invalid stage")
			return
		end
		result(player, TowerDefenseService.activateStage(player, activation.stageId))
	elseif action == "TravelToTowerPlatform" then
		result(player, StagePlatformService.travelToPlatform(player))
	elseif action == "DungeonAttack" then
		-- Combat stays payload-free and server-authoritative. A tiny acknowledgement
		-- powers hit/rejection feedback without sending a full profile snapshot.
		local accepted, reason, damage = DungeonService.registerHit(player)
		RemoteService.sendEvent(player, "DungeonAttackResult", {
			action = "attack",
			accepted = accepted,
			reason = reason,
			damage = damage,
		})
	elseif action == "DungeonDodge" then
		local accepted, reason = DungeonService.registerDodge(player)
		RemoteService.sendEvent(player, "DungeonAttackResult", {
			action = "dodge",
			accepted = accepted,
			reason = reason,
		})
	elseif action == "UseDungeonAbility" then
		-- Shape check only; DungeonService re-validates the id against the catalog
		-- plus liveness, arena, cooldown, range, and line of sight before any effect.
		local abilityId = if type(payload) == "table" then payload.abilityId else nil
		if type(abilityId) ~= "string" or #abilityId < 1 or #abilityId > 32 then
			RemoteService.sendEvent(player, "DungeonAbilityResult", {
				accepted = false,
				reason = "invalid",
			})
			return
		end
		local accepted, reason, damage = DungeonService.useAbility(player, abilityId)
		RemoteService.sendEvent(player, "DungeonAbilityResult", {
			abilityId = abilityId,
			accepted = accepted,
			reason = reason,
			damage = damage,
		})
	elseif action == "SelectDungeonBoss" then
		-- Shape check only; DungeonService re-validates the id against the catalog
		-- and owns whether the pick also becomes the pad party's choice.
		local bossId = if type(payload) == "table" then payload.bossId else nil
		if type(bossId) ~= "string" or #bossId < 1 or #bossId > 32 then
			result(player, false, "Invalid boss")
			return
		end
		local accepted, reason = DungeonService.selectBoss(player, bossId)
		RemoteService.sendEvent(player, "DungeonBossSelected", {
			accepted = accepted,
			bossId = if accepted then bossId else nil,
			reason = if accepted then nil else reason,
		})
	elseif action == "AfkRollover" then
		local profile = ProfileService.get(player)
		if profile == nil or not profile.settings.afKRollOver then
			result(player, false, "AFK rollover is disabled")
			return
		end
		result(player, AfkService.rollOver(player))
	end
end

local function handleQuery(player: Player, action: any, payload: any): any
	if type(action) ~= "string" then
		return { ok = false, message = "Request unavailable" }
	end
	if queryActions[action] ~= true then
		if limiter:allow(player, "query:unknown", 2, 0.25) then
			return { ok = false, message = "Unknown query" }
		end
		return { ok = false, message = "Request unavailable" }
	end
	if not limiter:allow(player, `query:{action}`, 4, 0.5) then
		return { ok = false, message = "Request unavailable" }
	end
	if action == "InitialState" then
		return { ok = true, data = RemoteService.snapshot(player) }
	elseif action == "SearchProfile" then
		if Config.features.profiles ~= true then
			return { ok = false, message = "Profiles are not enabled in this game" }
		end
		local username = if type(payload) == "table" then payload.username else nil
		local ok, data = PublicProfileService.find(username)
		return { ok = ok, data = if ok then data else nil, message = if ok then nil else data }
	elseif action == "GlobalLeaderboard" then
		if Config.features.leaderboards ~= true then
			return { ok = false, message = "Leaderboards are not enabled in this game" }
		end
		local ok, data = LeaderboardService.globalBoard()
		return { ok = ok, data = if ok then data else nil, message = if ok then nil else data }
	end
	return { ok = false, message = "Request unavailable" }
end

function RemoteService.initialize()
	local folder = ReplicatedStorage:FindFirstChild(RemoteNames.folder)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = RemoteNames.folder
		folder.Parent = ReplicatedStorage
	end
	requestRemote = getOrCreate("RemoteEvent", RemoteNames.request, folder) :: RemoteEvent
	stateRemote = getOrCreate("RemoteEvent", RemoteNames.state, folder) :: RemoteEvent
	queryRemote = getOrCreate("RemoteFunction", RemoteNames.query, folder) :: RemoteFunction
	requestRemote.OnServerEvent:Connect(handleRequest)
	queryRemote.OnServerInvoke = handleQuery
	ProfileService.changed:Connect(function(player)
		if Config.features.leaderboards then
			LeaderboardService.updateLeaderstats(player)
		end
		RemoteService.publish(player)
	end)
end

function RemoteService.broadcastAnnouncement(message: string)
	stateRemote:FireAllClients({ kind = "Announcement", message = message })
end

-- One-off server-pushed events (for example rune roll reveals) that ride the
-- existing state channel without forcing a full snapshot shape.
function RemoteService.sendEvent(player: Player, kind: string, data: any)
	if stateRemote and player.Parent then
		stateRemote:FireClient(player, { kind = kind, data = data })
	end
end

-- Server-owned lobby broadcasts such as the public portal roster/countdown.
-- Dungeon HUD state deliberately uses sendEvent per admitted party member.
function RemoteService.broadcast(kind: string, data: any)
	if stateRemote then
		stateRemote:FireAllClients({ kind = kind, data = data })
	end
end

function RemoteService.forget(player: Player)
	limiter:forget(player)
end

return RemoteService

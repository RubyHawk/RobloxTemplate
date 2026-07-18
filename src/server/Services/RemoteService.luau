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
local TowerDefenseService = require(script.Parent.TowerDefenseService)

local RemoteService = {}
local limiter = RateLimiter.new()
local stateRemote: RemoteEvent
local requestRemote: RemoteEvent
local queryRemote: RemoteFunction

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
	EquipBestUnits = "towerDefense",
	PlaceUnit = "towerDefense",
	AutoPlaceBestUnits = "towerDefense",
	StartTowerWave = "towerDefense",
	ResetTowerDefense = "towerDefense",
	ActivateTowerStage = "towerDefense",
}

local queryActions: { [string]: boolean } = {
	InitialState = true,
	SearchProfile = true,
	GlobalLeaderboard = true,
}

local towerDefenseNoPayloadActions: { [string]: boolean } = {
	RollUnit = true,
	EquipBestUnits = true,
	AutoPlaceBestUnits = true,
	StartTowerWave = true,
	ResetTowerDefense = true,
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
	if Config.features.towerDefense == true then
		towerPlacements, towerPlacementRevision = TowerDefenseService.presentationSnapshot()
	end
	return {
		profile = profile,
		currencyDefinitions = Config.economy.currencies,
		catalog = Catalogs.items,
		features = Config.features,
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
		runes = if Config.features.runes == true then RuneService.snapshotFor(player) else nil,
		towerDefense = if Config.features.towerDefense == true
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
	if stateRemote and player.Parent then
		stateRemote:FireClient(
			player,
			{ kind = "TowerEnemies", data = TowerDefenseService.snapshotFor(player) }
		)
	end
end

function RemoteService.publishTowerPlacements()
	if stateRemote then
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
	if not limiter:allow(player, action, 6, 1) then
		result(player, false, "Please slow down")
		return
	end
	if requiredFeature and Config.features[requiredFeature] ~= true then
		result(player, false, "This system is not enabled in this game")
		return
	end
	if towerDefenseNoPayloadActions[action] and not TowerDefenseRequest.acceptsNoPayload(payload) then
		result(player, false, "Invalid request")
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
	elseif action == "ResetTowerDefense" then
		result(player, TowerDefenseService.resetMatch(player))
	elseif action == "ActivateTowerStage" then
		local activation = TowerDefenseRequest.parseStageActivation(payload)
		if activation == nil then
			result(player, false, "Invalid stage")
			return
		end
		result(player, TowerDefenseService.activateStage(player, activation.stageId))
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

function RemoteService.forget(player: Player)
	limiter:forget(player)
end

return RemoteService

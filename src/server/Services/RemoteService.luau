--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Catalogs = require(Shared.Catalogs)
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local RemoteNames = require(Shared.RemoteNames)

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
	RollUnit = "towerDefense",
	SetTowerLoadout = "towerDefense",
	EquipBestUnits = "towerDefense",
	PlaceUnit = "towerDefense",
	AutoPlaceBestUnits = "towerDefense",
	StartTowerWave = "towerDefense",
	ResetTowerDefense = "towerDefense",
	ActivateTowerStage = "towerDefense",
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
		runes = if Config.features.runes == true then RuneService.snapshotFor(player) else nil,
		towerDefense = if Config.features.towerDefense == true
			then TowerDefenseService.snapshotFor(player)
			else nil,
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
	if not limiter:allow(player, action, 6, 1) then
		result(player, false, "Please slow down")
		return
	end
	local requiredFeature = requestFeatures[action]
	if requiredFeature and Config.features[requiredFeature] ~= true then
		result(player, false, "This system is not enabled in this game")
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
	elseif action == "RollUnit" then
		result(player, TowerDefenseService.rollUnit(player))
	elseif action == "SetTowerLoadout" then
		local unitIds = if type(payload) == "table" then payload.unitIds else nil
		result(player, TowerDefenseService.setLoadout(player, unitIds))
	elseif action == "EquipBestUnits" then
		result(player, TowerDefenseService.equipBest(player))
	elseif action == "PlaceUnit" then
		if type(payload) ~= "table" then
			result(player, false, "Invalid placement")
			return
		end
		result(player, TowerDefenseService.placeUnit(player, payload.unitId, payload.column, payload.row))
	elseif action == "AutoPlaceBestUnits" then
		result(player, TowerDefenseService.autoPlaceBest(player))
	elseif action == "StartTowerWave" then
		result(player, TowerDefenseService.startWave(player))
	elseif action == "ResetTowerDefense" then
		result(player, TowerDefenseService.resetMatch(player))
	elseif action == "ActivateTowerStage" then
		local stageId = if type(payload) == "table" then payload.stageId else nil
		result(player, TowerDefenseService.activateStage(player, stageId))
	elseif action == "AfkRollover" then
		local profile = ProfileService.get(player)
		if profile == nil or not profile.settings.afKRollOver then
			result(player, false, "AFK rollover is disabled")
			return
		end
		result(player, AfkService.rollOver(player))
	else
		result(player, false, "Unknown request")
	end
end

local function handleQuery(player: Player, action: any, payload: any): any
	if type(action) ~= "string" or not limiter:allow(player, `query:{action}`, 4, 0.5) then
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
	return { ok = false, message = "Unknown query" }
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

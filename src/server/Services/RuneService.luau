--!strict

-- Server-authoritative rune altar. Players stand inside an authored circle;
-- this service alone decides when a roll happens: it re-checks the character's
-- position, spends the configured currency, rolls a weighted rarity (with a
-- pity guarantee), and persists the owned runes. The client never submits a
-- roll request, a price, or an outcome.
--
-- Paid-random-items compliance (docs/internal/2026-07-10-rune-policy-check.md):
-- when the rune currency can be bought with Robux, players whose
-- ArePaidRandomItemsRestricted policy is true are blocked with a visible
-- unavailable state, and policy lookup failures fail closed.

local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local RuneCatalog = require(Shared.RuneCatalog)
local RuneLogic = require(Shared.RuneLogic)
local Types = require(Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)

type RuneRollResult = Types.RuneRollResult
type RuneClientState = Types.RuneClientState
type RuneChannelState = Types.RuneChannelState

local RuneService = {}

local rng = Random.new()
local circles: { BasePart } = {}
-- Momentum is deliberately ephemeral: it lives only in this table, starts
-- when the player enters the circle, survives mode swaps, and resets on
-- exit, death, or disconnect. Nothing about it is trusted from the client.
local standing: {
	[Player]: {
		nextRollAt: number,
		wasInside: boolean,
		channelStartedAt: number,
		tierIndex: number,
		modeId: string,
	},
} =
	{}
local policyStatus: { [Player]: "allowed" | "restricted" } = {}
local policyPending: { [Player]: boolean } = {}
local publishResult: ((player: Player, result: RuneRollResult) -> ())? = nil
local publishChannel: ((player: Player, channel: RuneChannelState) -> ())? = nil
local modeUnlockProvider: ((player: Player, modeId: string) -> boolean)? = nil
local loopRunning = false

local INACTIVE_CHANNEL: RuneChannelState = table.freeze({
	active = false,
	modeId = "",
	kind = "",
	momentumSeconds = 0,
	tierIndex = 0,
	tierValue = 1,
})

local function runeCurrencyId(): string
	return Config.economy.primaryCurrencyId
end

-- The template's coin packs sell the primary currency for Robux. While their
-- product IDs are 0 (placeholders) nothing is purchasable and rune rolls are
-- not "paid" random items.
local function currencyPurchasableWithRobux(): boolean
	if runeCurrencyId() ~= Config.economy.primaryCurrencyId then
		return false
	end
	return Config.products.coinPackSmall.id > 0 or Config.products.coinPackLarge.id > 0
end

local function refreshPolicy(player: Player)
	if policyPending[player] or policyStatus[player] ~= nil then
		return
	end
	policyPending[player] = true
	task.spawn(function()
		local success, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		policyPending[player] = nil
		if player.Parent == nil then
			return
		end
		if success and type(info) == "table" then
			policyStatus[player] = if info.ArePaidRandomItemsRestricted then "restricted" else "allowed"
		else
			-- Fail closed: without a policy answer we must not sell random items.
			policyStatus[player] = "restricted"
		end
		ProfileService.markDirty(player, "runes:policy")
	end)
end

-- Returns whether this player may roll right now. When the currency is not
-- Robux-purchasable the policy does not apply; otherwise the cached policy
-- answer decides, and an unknown answer blocks while the lookup runs.
local function rollAllowed(player: Player): boolean
	if not currencyPurchasableWithRobux() then
		return true
	end
	local status = policyStatus[player]
	if status == nil then
		refreshPolicy(player)
		return false
	end
	return status == "allowed"
end

function RuneService.isRestricted(player: Player): boolean
	if not currencyPurchasableWithRobux() then
		return false
	end
	return policyStatus[player] == "restricted"
end

local function circleRadius(circle: BasePart): number
	-- Authored discs are cylinders rotated onto their side, so the disc plane
	-- spans the part's Y/Z axes. Padding forgives players on the rim.
	return math.max(circle.Size.Y, circle.Size.Z) / 2 + Config.runes.circlePadding
end

local function isInsideCircle(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	for _, circle in circles do
		if circle.Parent ~= nil then
			local offset = root.Position - circle.Position
			local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
			if
				horizontal <= circleRadius(circle)
				and math.abs(offset.Y) <= Config.runes.circleHeightTolerance
			then
				return true
			end
		end
	end
	return false
end

local function pityMinimumIndex(): number
	return RuneCatalog.rarityIndex(Config.runes.pityMinimumRarity) or (#RuneCatalog.rarities + 1)
end

function RuneService.nextCost(player: Player): number
	local profile = ProfileService.get(player)
	local totalRolls = if profile then profile.runes.totalRolls else 0
	return RuneLogic.rollCost(
		Config.runes.baseCost,
		Config.runes.costGrowth,
		totalRolls,
		Config.runes.maxCost
	)
end

local function unlockStats(profile: any): { totalRolls: number, runesOwned: number }
	return {
		totalRolls = profile.runes.totalRolls,
		runesOwned = RuneLogic.countOwned(profile.runes.owned),
	}
end

local function providerUnlocked(player: Player, mode: any): boolean?
	local provider = modeUnlockProvider
	if provider == nil then
		return nil
	end
	return provider(player, mode.id) == true
end

-- The mode in effect right now: the persisted selection when it is configured
-- and unlocked, otherwise the configured default (when that is unlocked too).
-- The saved selection is never overwritten here, so a mode that unlocks later
-- or returns to the config snaps back automatically.
local function activeMode(player: Player, profile: any): any
	local modes = Config.runes.channelModes
	local modeId = RuneLogic.resolveModeId(profile.runes.selectedMode, modes, Config.runes.defaultChannelMode)
	local mode = RuneLogic.findMode(modes, modeId)
	if
		mode ~= nil and RuneLogic.isModeUnlocked(mode, unlockStats(profile), providerUnlocked(player, mode))
	then
		return mode
	end
	local fallback = RuneLogic.findMode(modes, Config.runes.defaultChannelMode)
	if
		fallback ~= nil
		and RuneLogic.isModeUnlocked(fallback, unlockStats(profile), providerUnlocked(player, fallback))
	then
		return fallback
	end
	return nil
end

local function momentumFor(state: { channelStartedAt: number }, now: number): number
	return math.max(now - state.channelStartedAt, 0)
end

-- Live channel state for snapshots and transition events. nil when the player
-- is not standing in a circle or no configured mode is available. The luck
-- kind carries the exact adjusted weights so the client discloses the odds
-- the server actually rolls with.
local function channelStateFor(player: Player): RuneChannelState?
	local state = standing[player]
	if state == nil or not state.wasInside then
		return nil
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	local mode = activeMode(player, profile)
	if mode == nil then
		return nil
	end
	local momentum = momentumFor(state, os.clock())
	local tierIndex, tierValue = RuneLogic.momentumTier(mode.tiers, momentum)
	local effectiveWeights: { number }? = nil
	if mode.kind == "luck" and tierValue > 1 then
		local adjusted =
			RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, tierValue, Config.runes.minCommonWeight)
		local weights = table.create(#adjusted)
		for index, rarity in adjusted do
			weights[index] = rarity.weight
		end
		effectiveWeights = weights
	end
	return {
		active = true,
		modeId = mode.id,
		kind = mode.kind,
		momentumSeconds = momentum,
		tierIndex = tierIndex,
		tierValue = tierValue,
		nextTierAtSeconds = RuneLogic.nextTierAt(mode.tiers, momentum),
		effectiveWeights = effectiveWeights,
	}
end

local function pushChannel(player: Player)
	local publish = publishChannel
	if publish == nil or player.Parent == nil then
		return
	end
	publish(player, channelStateFor(player) or INACTIVE_CHANNEL)
end

-- One server-decided roll. Every precondition is re-validated here so the
-- outcome never depends on anything the client sent.
local function tryRoll(player: Player): RuneRollResult?
	local profile = ProfileService.get(player)
	if profile == nil or not rollAllowed(player) or not isInsideCircle(player) then
		return nil
	end
	local cost = RuneService.nextCost(player)
	if not EconomyService.spendCurrency(player, runeCurrencyId(), cost, "runes:roll") then
		return nil
	end

	-- Luck momentum bends the odds server-side only; channelStateFor builds
	-- the same adjusted table, so the disclosed odds match this roll.
	local rarities = RuneCatalog.rarities
	local state = standing[player]
	local mode = activeMode(player, profile)
	if state ~= nil and mode ~= nil and mode.kind == "luck" then
		local _, tierValue = RuneLogic.momentumTier(mode.tiers, momentumFor(state, os.clock()))
		if tierValue > 1 then
			rarities = RuneLogic.luckAdjustedRarities(rarities, tierValue, Config.runes.minCommonWeight)
		end
	end

	local rarityIndex, pityTriggered = RuneLogic.pickRarityIndex(
		rarities,
		rng:NextNumber(),
		profile.runes.rollsSincePity,
		Config.runes.pityThreshold,
		pityMinimumIndex()
	)
	local rarity = rarities[rarityIndex]
	local pool = RuneCatalog.runesForRarity(rarity.id)
	local rune = pool[RuneLogic.pickRuneIndex(#pool, rng:NextNumber())]
	if rune == nil then
		-- A rarity without authored runes is a catalog bug; refund rather than
		-- swallowing the spend.
		EconomyService.awardCurrencyRaw(player, runeCurrencyId(), cost, "runes:refund")
		warn(`RuneCatalog has no runes for rarity {rarity.id}; refunding roll`)
		return nil
	end

	local entry = profile.runes.owned[rune.id]
	local isNew = entry == nil
	local ownedCount = if entry == nil then 1 else math.min(entry.count + 1, Config.runes.maxOwnedPerRune)
	if entry == nil then
		profile.runes.owned[rune.id] = { count = ownedCount }
	else
		-- Mutated in place so unknown keys a future schema stores on the
		-- entry survive this write.
		entry.count = ownedCount
	end
	profile.runes.totalRolls = math.min(profile.runes.totalRolls + 1, Config.runes.maxTotalRolls)
	if rarityIndex >= pityMinimumIndex() then
		profile.runes.rollsSincePity = 0
	else
		profile.runes.rollsSincePity += 1
	end

	local result: RuneRollResult = {
		runeId = rune.id,
		rarityId = rarity.id,
		cost = cost,
		ownedCount = ownedCount,
		isNew = isNew,
		pityTriggered = pityTriggered,
		totalRolls = profile.runes.totalRolls,
		nextCost = RuneService.nextCost(player),
		totalBonusPercent = RuneLogic.totalBonusPercent(
			profile.runes.owned,
			RuneCatalog,
			Config.runes.copyMilestones,
			Config.runes.maxTotalBonusPercent
		),
		multiplier = RuneLogic.multiplier(
			profile.runes,
			RuneCatalog,
			Config.runes.copyMilestones,
			Config.runes.maxTotalBonusPercent
		),
	}
	ProfileService.markDirty(player, "runes:roll")
	return result
end

function RuneService.snapshotFor(player: Player): RuneClientState?
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	local owned: { [string]: Types.RuneOwnedEntry } = {}
	for runeId, entry in profile.runes.owned do
		if type(runeId) == "string" and type(entry) == "table" and type(entry.count) == "number" then
			owned[runeId] = { count = entry.count }
		end
	end
	local modes: { Types.RuneModeAvailability } = {}
	for _, mode in Config.runes.channelModes do
		table.insert(modes, {
			id = mode.id,
			unlocked = RuneLogic.isModeUnlocked(mode, unlockStats(profile), providerUnlocked(player, mode)),
		})
	end
	return {
		owned = owned,
		totalRolls = profile.runes.totalRolls,
		rollsSincePity = profile.runes.rollsSincePity,
		pityThreshold = Config.runes.pityThreshold,
		nextCost = RuneService.nextCost(player),
		currencyId = runeCurrencyId(),
		totalBonusPercent = RuneLogic.totalBonusPercent(
			profile.runes.owned,
			RuneCatalog,
			Config.runes.copyMilestones,
			Config.runes.maxTotalBonusPercent
		),
		multiplier = RuneLogic.multiplier(
			profile.runes,
			RuneCatalog,
			Config.runes.copyMilestones,
			Config.runes.maxTotalBonusPercent
		),
		restricted = RuneService.isRestricted(player),
		selectedMode = RuneLogic.resolveModeId(
			profile.runes.selectedMode,
			Config.runes.channelModes,
			Config.runes.defaultChannelMode
		),
		modes = modes,
		channel = channelStateFor(player),
	}
end

-- Map scripts hand authored circle parts to the reusable service; the service
-- itself never assumes a specific map layout.
function RuneService.registerCircle(circle: BasePart)
	if Config.features.runes ~= true then
		return
	end
	if table.find(circles, circle) == nil then
		table.insert(circles, circle)
	end
end

local function tickPlayers()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local inside = isInsideCircle(player)
		local state = standing[player]
		if not inside then
			if state then
				-- Leaving (or dying) resets momentum; tell the client so
				-- meters and adjusted odds clear immediately.
				standing[player] = nil
				pushChannel(player)
			end
			continue
		end
		if state == nil or not state.wasInside then
			-- Entering the circle: give the odds a beat to be read before the
			-- first automatic spend, and start the momentum clock.
			local profile = ProfileService.get(player)
			local mode = if profile ~= nil then activeMode(player, profile) else nil
			standing[player] = {
				nextRollAt = now + Config.runes.firstRollChargeSeconds,
				wasInside = true,
				channelStartedAt = now,
				tierIndex = 0,
				modeId = if mode ~= nil then mode.id else "",
			}
			if currencyPurchasableWithRobux() then
				refreshPolicy(player)
			end
			pushChannel(player)
			continue
		end
		-- Publish only on tier or mode transitions so channel traffic stays
		-- rare while meters and disclosed odds still track server truth.
		local profile = ProfileService.get(player)
		local mode = if profile ~= nil then activeMode(player, profile) else nil
		local modeId = if mode ~= nil then mode.id else ""
		local tierIndex = 0
		if mode ~= nil then
			tierIndex = RuneLogic.momentumTier(mode.tiers, momentumFor(state, now))
		end
		if tierIndex ~= state.tierIndex or modeId ~= state.modeId then
			state.tierIndex = tierIndex
			state.modeId = modeId
			pushChannel(player)
		end
		if now >= state.nextRollAt then
			local result = tryRoll(player)
			if result ~= nil then
				state.nextRollAt = now + Config.runes.autoRollSeconds
				local publish = publishResult
				if publish then
					publish(player, result)
				end
			else
				-- Not affordable (or blocked): keep watching so the roll fires
				-- the moment enough currency arrives.
				state.nextRollAt = now + Config.runes.tickSeconds
			end
		end
	end
end

-- Validated mode swap; every check is server-side. Momentum is preserved so
-- swapping strategies mid-channel is never punished.
function RuneService.setMode(player: Player, modeId: any): (boolean, string)
	if Config.features.runes ~= true then
		return false, "Runes are not enabled in this game"
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile not loaded"
	end
	if type(modeId) ~= "string" or #modeId < 1 or #modeId > 40 then
		return false, "Invalid channel mode"
	end
	local mode = RuneLogic.findMode(Config.runes.channelModes, modeId)
	if mode == nil then
		return false, "Unknown channel mode"
	end
	if not RuneLogic.isModeUnlocked(mode, unlockStats(profile), providerUnlocked(player, mode)) then
		return false, "That channel mode is still locked"
	end
	profile.runes.selectedMode = modeId
	local state = standing[player]
	if state ~= nil then
		state.modeId = modeId
		state.tierIndex = RuneLogic.momentumTier(mode.tiers, momentumFor(state, os.clock()))
	end
	ProfileService.markDirty(player, "runes:mode")
	pushChannel(player)
	return true, `Channeling {mode.name}`
end

-- Game recipes can gate "provider" unlocks by their own progression (stage,
-- rebirth, quest). Without a registered provider those modes stay locked.
function RuneService.setModeUnlockProvider(provider: (player: Player, modeId: string) -> boolean)
	modeUnlockProvider = provider
end

-- Live surge value for the strongest-temporary-boost bucket; 1 whenever the
-- player is not channeling a surge mode. Never persisted and never stacked.
function RuneService.channelEarningsMultiplier(player: Player): number
	if Config.features.runes ~= true then
		return 1
	end
	local state = standing[player]
	if state == nil or not state.wasInside then
		return 1
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return 1
	end
	local mode = activeMode(player, profile)
	if mode == nil or mode.kind ~= "surge" then
		return 1
	end
	local _, tierValue = RuneLogic.momentumTier(mode.tiers, momentumFor(state, os.clock()))
	return tierValue
end

function RuneService.start(options: {
	publish: (player: Player, result: RuneRollResult) -> (),
	publishChannel: ((player: Player, channel: RuneChannelState) -> ())?,
})
	publishResult = options.publish
	publishChannel = options.publishChannel
	if Config.features.runes ~= true or loopRunning then
		return
	end
	loopRunning = true
	task.spawn(function()
		while true do
			task.wait(Config.runes.tickSeconds)
			tickPlayers()
		end
	end)
end

function RuneService.forget(player: Player)
	standing[player] = nil
	policyStatus[player] = nil
	policyPending[player] = nil
end

return RuneService

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

local RuneService = {}

local TICK_SECONDS = 0.25

local rng = Random.new()
local circles: { BasePart } = {}
local standing: { [Player]: { nextRollAt: number, wasInside: boolean } } = {}
local policyStatus: { [Player]: "allowed" | "restricted" } = {}
local policyPending: { [Player]: boolean } = {}
local publishResult: ((player: Player, result: RuneRollResult) -> ())? = nil
local loopRunning = false

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

	local rarityIndex, pityTriggered = RuneLogic.pickRarityIndex(
		RuneCatalog.rarities,
		rng:NextNumber(),
		profile.runes.rollsSincePity,
		Config.runes.pityThreshold,
		pityMinimumIndex()
	)
	local rarity = RuneCatalog.rarities[rarityIndex]
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
	local ownedCount = if entry == nil then 1 else math.min(entry.count + 1, 1e9)
	profile.runes.owned[rune.id] = { count = ownedCount }
	profile.runes.totalRolls = math.min(profile.runes.totalRolls + 1, 1e9)
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
		totalBonusPercent = RuneLogic.totalBonusPercent(profile.runes.owned, RuneCatalog),
		multiplier = RuneLogic.multiplier(profile.runes, RuneCatalog),
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
	return {
		owned = owned,
		totalRolls = profile.runes.totalRolls,
		rollsSincePity = profile.runes.rollsSincePity,
		pityThreshold = Config.runes.pityThreshold,
		nextCost = RuneService.nextCost(player),
		currencyId = runeCurrencyId(),
		totalBonusPercent = RuneLogic.totalBonusPercent(profile.runes.owned, RuneCatalog),
		multiplier = RuneLogic.multiplier(profile.runes, RuneCatalog),
		restricted = RuneService.isRestricted(player),
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
				standing[player] = nil
			end
			continue
		end
		if state == nil or not state.wasInside then
			-- Entering the circle: give the odds a beat to be read before the
			-- first automatic spend.
			standing[player] = {
				nextRollAt = now + Config.runes.firstRollChargeSeconds,
				wasInside = true,
			}
			if currencyPurchasableWithRobux() then
				refreshPolicy(player)
			end
			continue
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
				state.nextRollAt = now + TICK_SECONDS
			end
		end
	end
end

function RuneService.start(options: { publish: (player: Player, result: RuneRollResult) -> () })
	publishResult = options.publish
	if Config.features.runes ~= true or loopRunning then
		return
	end
	loopRunning = true
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
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

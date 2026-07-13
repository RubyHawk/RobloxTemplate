--!strict

-- Pure rune altar math: weighted rarity rolls, pity promotion, optional roll
-- cost growth, and the permanent generation multiplier granted by owned runes.
-- Dependency-free like Calculations: callers pass the catalog in, so Lune
-- specs can exercise every branch deterministically without a Roblox runtime.

export type RarityLike = {
	id: string,
	name: string,
	weight: number,
	color: { number },
}

export type OwnedRunes = { [string]: { count: number } }

export type CopyMilestoneLike = {
	copies: number,
	multiplier: number,
}

-- Structural view of RuneCatalog so this module never requires it.
export type CatalogLike = {
	rune: (runeId: string) -> { bonusPercent: number, rarityId: string }?,
}

local RuneLogic = {}

-- Keeps a corrupt or maliciously large save from producing a multiplier that
-- overflows downstream award math.
local MAX_TOTAL_BONUS_PERCENT = 1_000_000

local function sanitizedCount(entry: any): number
	if type(entry) ~= "table" then
		return 0
	end
	local count = entry.count
	if type(count) ~= "number" or count ~= count or count == math.huge then
		return 0
	end
	return math.max(math.floor(count), 0)
end

function RuneLogic.weightTotal(rarities: { RarityLike }, firstIndex: number?): number
	local total = 0
	for index = firstIndex or 1, #rarities do
		total += rarities[index].weight
	end
	return total
end

function RuneLogic.oddsPercent(rarity: RarityLike): number
	return rarity.weight / 100
end

-- roll01 must be in [0, 1). Returns the picked rarity index plus whether the
-- pity guarantee promoted this roll. Pity forces at least the rarity at
-- pityMinimumIndex once rollsSincePity reaches pityThreshold - 1 completed
-- dry rolls (so the guaranteed roll is roll number pityThreshold).
function RuneLogic.pickRarityIndex(
	rarities: { RarityLike },
	roll01: number,
	rollsSincePity: number,
	pityThreshold: number,
	pityMinimumIndex: number
): (number, boolean)
	local firstIndex = 1
	local pityTriggered = false
	if pityThreshold > 0 and pityMinimumIndex > 1 and rollsSincePity >= pityThreshold - 1 then
		firstIndex = math.min(pityMinimumIndex, #rarities)
		pityTriggered = true
	end
	local total = RuneLogic.weightTotal(rarities, firstIndex)
	local scaled = math.clamp(roll01, 0, 1) * total
	local accumulated = 0
	for index = firstIndex, #rarities do
		accumulated += rarities[index].weight
		if scaled < accumulated then
			return index, pityTriggered
		end
	end
	return #rarities, pityTriggered
end

-- Uniform pick inside one rarity's rune list.
function RuneLogic.pickRuneIndex(count: number, roll01: number): number
	if count <= 0 then
		return 0
	end
	return math.clamp(math.floor(math.clamp(roll01, 0, 1) * count) + 1, 1, count)
end

-- Soft-currency sink: the current rune altar config keeps costGrowth at 1 for
-- a flat price, while generated recipes can still opt into growth.
function RuneLogic.rollCost(baseCost: number, costGrowth: number, totalRolls: number, maxCost: number): number
	local cost = math.floor(baseCost * math.max(costGrowth, 1) ^ math.max(totalRolls, 0))
	return math.clamp(cost, 1, math.max(maxCost, 1))
end

-- Highest copy milestone reached by `count` copies of one rune, or 1. Corrupt
-- entries (bad numbers, weakening multipliers) contribute nothing, so a broken
-- override can never reduce a player's authored bonus.
function RuneLogic.milestoneMultiplier(milestones: any, count: number): number
	if type(milestones) ~= "table" or type(count) ~= "number" or count ~= count then
		return 1
	end
	local best = 1
	for _, milestone in milestones do
		if type(milestone) == "table" then
			local copies = milestone.copies
			local multiplier = milestone.multiplier
			if
				type(copies) == "number"
				and copies == copies
				and copies ~= math.huge
				and type(multiplier) == "number"
				and multiplier == multiplier
				and multiplier ~= math.huge
				and multiplier >= 1
				and count >= copies
				and multiplier > best
			then
				best = multiplier
			end
		end
	end
	return best
end

-- Closest milestone still ahead of `count`, for "NEXT AT n COPIES" labels.
function RuneLogic.nextMilestone(milestones: any, count: number): CopyMilestoneLike?
	if type(milestones) ~= "table" or type(count) ~= "number" or count ~= count then
		return nil
	end
	local best: CopyMilestoneLike? = nil
	for _, milestone in milestones do
		if type(milestone) == "table" then
			local copies = milestone.copies
			local multiplier = milestone.multiplier
			if
				type(copies) == "number"
				and copies == copies
				and copies ~= math.huge
				and type(multiplier) == "number"
				and multiplier == multiplier
				and multiplier ~= math.huge
				and multiplier >= 1
				and copies > count
				and (best == nil or copies < best.copies)
			then
				best = { copies = copies, multiplier = multiplier }
			end
		end
	end
	return best
end

-- Sum of every owned copy's permanent bonus, with each rune's contribution
-- scaled by its reached copy milestone. Unknown rune ids stay saved in the
-- profile (never discarded) but contribute nothing until a catalog update
-- defines them again.
function RuneLogic.totalBonusPercent(
	owned: any,
	catalog: CatalogLike,
	milestones: any?,
	maxTotal: number?
): number
	if type(owned) ~= "table" then
		return 0
	end
	local cap = if type(maxTotal) == "number"
			and maxTotal == maxTotal
			and maxTotal > 0
		then maxTotal
		else MAX_TOTAL_BONUS_PERCENT
	local total = 0
	for runeId, entry in owned do
		if type(runeId) == "string" then
			local rune = catalog.rune(runeId)
			if rune then
				local count = sanitizedCount(entry)
				total += rune.bonusPercent * count * RuneLogic.milestoneMultiplier(milestones, count)
			end
		end
	end
	return math.min(total, cap)
end

function RuneLogic.multiplier(
	runesState: any,
	catalog: CatalogLike,
	milestones: any?,
	maxTotal: number?
): number
	if type(runesState) ~= "table" then
		return 1
	end
	return 1 + RuneLogic.totalBonusPercent(runesState.owned, catalog, milestones, maxTotal) / 100
end

-- Momentum tier reached after channeling uninterrupted for momentumSeconds.
-- Returns (tier index, tier value); (0, 1) when no tier is reached or the
-- inputs are corrupt. Tier values below 1 are ignored so momentum only helps.
function RuneLogic.momentumTier(tiers: any, momentumSeconds: number): (number, number)
	if type(tiers) ~= "table" or type(momentumSeconds) ~= "number" or momentumSeconds ~= momentumSeconds then
		return 0, 1
	end
	local tierIndex = 0
	local tierValue = 1
	local bestAt = -1
	for index, tier in tiers do
		if type(index) == "number" and type(tier) == "table" then
			local atSeconds = tier.atSeconds
			local value = tier.value
			if
				type(atSeconds) == "number"
				and atSeconds == atSeconds
				and atSeconds ~= math.huge
				and type(value) == "number"
				and value == value
				and value ~= math.huge
				and value >= 1
				and momentumSeconds >= atSeconds
				and atSeconds > bestAt
			then
				bestAt = atSeconds
				tierIndex = index
				tierValue = value
			end
		end
	end
	return tierIndex, tierValue
end

-- Seconds threshold of the next tier still ahead, for progress meters.
function RuneLogic.nextTierAt(tiers: any, momentumSeconds: number): number?
	if type(tiers) ~= "table" or type(momentumSeconds) ~= "number" or momentumSeconds ~= momentumSeconds then
		return nil
	end
	local nextAt: number? = nil
	for _, tier in tiers do
		if type(tier) == "table" then
			local atSeconds = tier.atSeconds
			if
				type(atSeconds) == "number"
				and atSeconds == atSeconds
				and atSeconds ~= math.huge
				and atSeconds > momentumSeconds
				and (nextAt == nil or atSeconds < nextAt)
			then
				nextAt = atSeconds
			end
		end
	end
	return nextAt
end

-- Luck momentum: multiplies every rarity weight above the first (common)
-- entry by luckFactor and takes the increase out of the common weight.
-- Integer floors plus a clamped effective factor keep the parts-per-10000
-- total EXACT at every tier, boosted weights never drop below their authored
-- values, and the common weight never drops below minCommonWeight — so the
-- odds shown to a player always describe the roll the server performs.
function RuneLogic.luckAdjustedRarities(
	rarities: { RarityLike },
	luckFactor: number,
	minCommonWeight: number?
): { RarityLike }
	local result: { RarityLike } = {}
	for index, rarity in rarities do
		result[index] = {
			id = rarity.id,
			name = rarity.name,
			weight = rarity.weight,
			color = rarity.color,
		}
	end
	if #rarities <= 1 or type(luckFactor) ~= "number" or luckFactor ~= luckFactor or luckFactor <= 1 then
		return result
	end
	local total = RuneLogic.weightTotal(rarities)
	local tailTotal = RuneLogic.weightTotal(rarities, 2)
	if tailTotal <= 0 or total <= tailTotal then
		return result
	end
	local floorWeight = math.clamp(math.floor(minCommonWeight or 0), 0, rarities[1].weight)
	local effectiveFactor = math.min(luckFactor, (total - floorWeight) / tailTotal)
	local boostedTotal = 0
	for index = 2, #result do
		local boosted = math.max(math.floor(rarities[index].weight * effectiveFactor), rarities[index].weight)
		result[index].weight = boosted
		boostedTotal += boosted
	end
	result[1].weight = total - boostedTotal
	return result
end

function RuneLogic.findMode(modes: any, modeId: any): any?
	if type(modes) ~= "table" or type(modeId) ~= "string" then
		return nil
	end
	for _, mode in modes do
		if type(mode) == "table" and mode.id == modeId then
			return mode
		end
	end
	return nil
end

-- The persisted selection is kept verbatim on disk; this only decides which
-- configured mode is in effect right now, falling back to the default when
-- the save references a mode this recipe does not configure.
function RuneLogic.resolveModeId(selected: any, modes: any, defaultId: string): string
	if RuneLogic.findMode(modes, selected) ~= nil then
		return selected :: string
	end
	return defaultId
end

-- stats carries server-derived progression numbers; providerUnlocked is the
-- optional answer from a game-specific provider. Provider unlocks and unknown
-- unlock kinds fail closed.
function RuneLogic.isModeUnlocked(
	mode: any,
	stats: { totalRolls: number, runesOwned: number },
	providerUnlocked: boolean?
): boolean
	if type(mode) ~= "table" then
		return false
	end
	local unlock = mode.unlock
	if unlock == nil then
		return true
	end
	if type(unlock) ~= "table" then
		return false
	end
	local threshold = if type(unlock.value) == "number" and unlock.value == unlock.value
		then unlock.value
		else math.huge
	if unlock.kind == "always" then
		return true
	elseif unlock.kind == "totalRolls" then
		return stats.totalRolls >= threshold
	elseif unlock.kind == "runesOwned" then
		return stats.runesOwned >= threshold
	elseif unlock.kind == "provider" then
		return providerUnlocked == true
	end
	return false
end

function RuneLogic.countOwned(owned: any): number
	if type(owned) ~= "table" then
		return 0
	end
	local total = 0
	for _, entry in owned do
		total += sanitizedCount(entry)
	end
	return total
end

function RuneLogic.countOwnedForRarity(owned: any, rarityId: string, catalog: CatalogLike): number
	if type(owned) ~= "table" then
		return 0
	end
	local total = 0
	for runeId, entry in owned do
		if type(runeId) == "string" then
			local rune = catalog.rune(runeId)
			if rune and rune.rarityId == rarityId then
				total += sanitizedCount(entry)
			end
		end
	end
	return total
end

return table.freeze(RuneLogic)

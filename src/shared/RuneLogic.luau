--!strict

-- Pure rune altar math: weighted rarity rolls, pity promotion, escalating
-- roll costs, and the permanent generation multiplier granted by owned runes.
-- Dependency-free like Calculations: callers pass the catalog in, so Lune
-- specs can exercise every branch deterministically without a Roblox runtime.

export type RarityLike = {
	id: string,
	name: string,
	weight: number,
	color: { number },
}

export type OwnedRunes = { [string]: { count: number } }

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

-- Escalating soft-currency sink: cost grows geometrically per completed roll
-- and clamps at maxCost so late-game rolls stay purchasable.
function RuneLogic.rollCost(baseCost: number, costGrowth: number, totalRolls: number, maxCost: number): number
	local cost = math.floor(baseCost * math.max(costGrowth, 1) ^ math.max(totalRolls, 0))
	return math.clamp(cost, 1, math.max(maxCost, 1))
end

-- Sum of every owned copy's permanent bonus. Unknown rune ids stay saved in
-- the profile (never discarded) but contribute nothing until a catalog update
-- defines them again.
function RuneLogic.totalBonusPercent(owned: any, catalog: CatalogLike): number
	if type(owned) ~= "table" then
		return 0
	end
	local total = 0
	for runeId, entry in owned do
		if type(runeId) == "string" then
			local rune = catalog.rune(runeId)
			if rune then
				total += rune.bonusPercent * sanitizedCount(entry)
			end
		end
	end
	return math.min(total, MAX_TOTAL_BONUS_PERCENT)
end

function RuneLogic.multiplier(runesState: any, catalog: CatalogLike): number
	if type(runesState) ~= "table" then
		return 1
	end
	return 1 + RuneLogic.totalBonusPercent(runesState.owned, catalog) / 100
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

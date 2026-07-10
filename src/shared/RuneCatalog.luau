--!strict

-- Rune altar catalog: rarity tiers and the finite rune card set.
-- Pure data so Lune tests and the client can require it directly. Colors are
-- {r, g, b} 0-255 tables because Color3 is unavailable outside Roblox.
-- Rarity weights are integer parts-per-ten-thousand and MUST sum to exactly
-- 10000 so the disclosed odds always total 100% (see
-- docs/internal/2026-07-10-rune-policy-check.md).

export type RuneRarity = {
	id: string,
	name: string,
	weight: number,
	color: { number },
}

export type RuneDefinition = {
	id: string,
	name: string,
	rarityId: string,
	glyph: string,
	-- Permanent additive bonus to currency generation, in percent.
	bonusPercent: number,
	flavor: string,
}

-- Ordered from most to least common; pity promotion uses this order.
local Rarities: { RuneRarity } = {
	{ id = "common", name = "Common", weight = 5400, color = { 156, 163, 175 } },
	{ id = "uncommon", name = "Uncommon", weight = 2600, color = { 74, 222, 128 } },
	{ id = "rare", name = "Rare", weight = 1250, color = { 96, 165, 250 } },
	{ id = "epic", name = "Epic", weight = 550, color = { 192, 132, 252 } },
	{ id = "legendary", name = "Legendary", weight = 170, color = { 251, 191, 36 } },
	{ id = "mythic", name = "Mythic", weight = 30, color = { 244, 114, 182 } },
}

local Runes: { RuneDefinition } = {
	{
		id = "ember_rune",
		name = "Ember Rune",
		rarityId = "common",
		glyph = "🔥",
		bonusPercent = 2,
		flavor = "A faint spark that never quite goes out.",
	},
	{
		id = "pebble_rune",
		name = "Pebble Rune",
		rarityId = "common",
		glyph = "🪨",
		bonusPercent = 3,
		flavor = "Small, dependable, and always underfoot.",
	},
	{
		id = "frost_rune",
		name = "Frost Rune",
		rarityId = "uncommon",
		glyph = "❄️",
		bonusPercent = 5,
		flavor = "Cold enough to slow time around your vault.",
	},
	{
		id = "gale_rune",
		name = "Gale Rune",
		rarityId = "uncommon",
		glyph = "🌪️",
		bonusPercent = 6,
		flavor = "Carries loose change straight to your pocket.",
	},
	{
		id = "storm_rune",
		name = "Storm Rune",
		rarityId = "rare",
		glyph = "⚡",
		bonusPercent = 10,
		flavor = "Charged with the fury of a hundred waves.",
	},
	{
		id = "vine_rune",
		name = "Vine Rune",
		rarityId = "rare",
		glyph = "🌿",
		bonusPercent = 12,
		flavor = "Profits grow wherever its roots take hold.",
	},
	{
		id = "magma_rune",
		name = "Magma Rune",
		rarityId = "epic",
		glyph = "🌋",
		bonusPercent = 20,
		flavor = "Forged in the heart of a sleeping mountain.",
	},
	{
		id = "void_rune",
		name = "Void Rune",
		rarityId = "epic",
		glyph = "🌀",
		bonusPercent = 24,
		flavor = "Pulls stray riches in from other realms.",
	},
	{
		id = "dragon_rune",
		name = "Dragon Rune",
		rarityId = "legendary",
		glyph = "🐉",
		bonusPercent = 45,
		flavor = "Hoards treasure the way dragons always have.",
	},
	{
		id = "phoenix_rune",
		name = "Phoenix Rune",
		rarityId = "legendary",
		glyph = "🦅",
		bonusPercent = 50,
		flavor = "Every ending it touches pays out twice.",
	},
	{
		id = "celestial_rune",
		name = "Celestial Rune",
		rarityId = "mythic",
		glyph = "🌟",
		bonusPercent = 100,
		flavor = "A shard of the night sky, still warm.",
	},
	{
		id = "eternity_rune",
		name = "Eternity Rune",
		rarityId = "mythic",
		glyph = "♾️",
		bonusPercent = 120,
		flavor = "It was already yours. It always will be.",
	},
}

local runesById: { [string]: RuneDefinition } = {}
local runesByRarity: { [string]: { RuneDefinition } } = {}
local raritiesById: { [string]: RuneRarity } = {}
local rarityIndexById: { [string]: number } = {}

for index, rarity in Rarities do
	raritiesById[rarity.id] = rarity
	rarityIndexById[rarity.id] = index
	runesByRarity[rarity.id] = {}
end

for _, rune in Runes do
	runesById[rune.id] = rune
	local bucket = runesByRarity[rune.rarityId]
	assert(bucket ~= nil, `rune {rune.id} references unknown rarity {rune.rarityId}`)
	table.insert(bucket, rune)
end

local RuneCatalog = {
	rarities = Rarities,
	runes = Runes,
}

function RuneCatalog.rune(runeId: string): RuneDefinition?
	return runesById[runeId]
end

function RuneCatalog.rarity(rarityId: string): RuneRarity?
	return raritiesById[rarityId]
end

function RuneCatalog.rarityIndex(rarityId: string): number?
	return rarityIndexById[rarityId]
end

function RuneCatalog.runesForRarity(rarityId: string): { RuneDefinition }
	return runesByRarity[rarityId] or {}
end

return table.freeze(RuneCatalog)

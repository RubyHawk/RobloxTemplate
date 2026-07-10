--!strict

local TowerDefenseCatalog = {}

export type RarityDefinition = {
	id: string,
	name: string,
	weight: number,
	sortOrder: number,
}

export type UnitDefinition = {
	id: string,
	name: string,
	rarityId: string,
	damage: number,
	range: number,
	fireRate: number,
	deployCost: number,
	targeting: "First" | "Nearest",
	rollWeight: number,
}

export type EnemyDefinition = {
	id: string,
	name: string,
	health: number,
	speed: number,
	reward: number,
	baseDamage: number,
}

export type WaveDefinition = {
	enemyId: string,
	count: number,
	spacingSeconds: number,
	healthScale: number,
	rewardScale: number,
}

local rarities: { RarityDefinition } = {
	{ id = "common", name = "Common", weight = 7000, sortOrder = 1 },
	{ id = "uncommon", name = "Uncommon", weight = 2200, sortOrder = 2 },
	{ id = "rare", name = "Rare", weight = 700, sortOrder = 3 },
	{ id = "epic", name = "Epic", weight = 100, sortOrder = 4 },
}

local units: { UnitDefinition } = {
	{
		id = "forest_archer",
		name = "Forest Archer",
		rarityId = "common",
		damage = 11,
		range = 20,
		fireRate = 0.85,
		deployCost = 45,
		targeting = "First",
		rollWeight = 55,
	},
	{
		id = "moss_guard",
		name = "Moss Guard",
		rarityId = "common",
		damage = 18,
		range = 14,
		fireRate = 1.2,
		deployCost = 55,
		targeting = "Nearest",
		rollWeight = 45,
	},
	{
		id = "vine_sniper",
		name = "Vine Sniper",
		rarityId = "uncommon",
		damage = 34,
		range = 28,
		fireRate = 1.45,
		deployCost = 85,
		targeting = "First",
		rollWeight = 32,
	},
	{
		id = "mushroom_bomber",
		name = "Mushroom Bomber",
		rarityId = "rare",
		damage = 52,
		range = 18,
		fireRate = 1.75,
		deployCost = 120,
		targeting = "Nearest",
		rollWeight = 12,
	},
	{
		id = "ancient_treant",
		name = "Ancient Treant",
		rarityId = "epic",
		damage = 96,
		range = 22,
		fireRate = 2.2,
		deployCost = 180,
		targeting = "First",
		rollWeight = 3,
	},
}

local enemies: { [string]: EnemyDefinition } = {
	forest_grunt = {
		id = "forest_grunt",
		name = "Forest Grunt",
		health = 45,
		speed = 7,
		reward = 12,
		baseDamage = 1,
	},
}

local waves: { WaveDefinition } = {
	{ enemyId = "forest_grunt", count = 8, spacingSeconds = 0.7, healthScale = 1, rewardScale = 1 },
	{ enemyId = "forest_grunt", count = 12, spacingSeconds = 0.6, healthScale = 1.25, rewardScale = 1.08 },
	{ enemyId = "forest_grunt", count = 16, spacingSeconds = 0.5, healthScale = 1.55, rewardScale = 1.16 },
	{ enemyId = "forest_grunt", count = 22, spacingSeconds = 0.45, healthScale = 2, rewardScale = 1.25 },
}

local unitLookup: { [string]: UnitDefinition } = {}
for _, unit in units do
	unitLookup[unit.id] = unit
end

local rarityLookup: { [string]: RarityDefinition } = {}
for _, rarity in rarities do
	rarityLookup[rarity.id] = rarity
end

function TowerDefenseCatalog.unit(unitId: string): UnitDefinition?
	return unitLookup[unitId]
end

function TowerDefenseCatalog.rarity(rarityId: string): RarityDefinition?
	return rarityLookup[rarityId]
end

function TowerDefenseCatalog.enemy(enemyId: string): EnemyDefinition?
	return enemies[enemyId]
end

function TowerDefenseCatalog.wave(index: number): WaveDefinition
	return waves[((math.max(index, 1) - 1) % #waves) + 1]
end

TowerDefenseCatalog.rarities = table.freeze(rarities)
TowerDefenseCatalog.units = table.freeze(units)
TowerDefenseCatalog.enemies = table.freeze(enemies)
TowerDefenseCatalog.waves = table.freeze(waves)

return table.freeze(TowerDefenseCatalog)

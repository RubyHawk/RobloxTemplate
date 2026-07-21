--!strict

local IconCatalog = require(script.Parent.IconCatalog)

export type ItemDefinition = {
	id: string,
	name: string,
	description: string,
	category: "Consumable" | "Equipment" | "Misc",
	icon: string,
	maxStack: number,
	priceCoins: number?,
	equipmentSlot: string?,
	boostMultiplier: number?,
	boostDurationSeconds: number?,
}

local Items: { [string]: ItemDefinition } = {
	double_coins_potion = {
		id = "double_coins_potion",
		name = "Double Coins Potion",
		description = "Applies the strongest x2 Coins boost for 15 minutes.",
		category = "Consumable",
		icon = IconCatalog.get("potionX2"),
		maxStack = 99,
		priceCoins = 1000,
		boostMultiplier = 2,
		boostDurationSeconds = 15 * 60,
	},
	triple_coins_potion = {
		id = "triple_coins_potion",
		name = "Triple Coins Potion",
		description = "Applies the strongest x3 Coins boost for 10 minutes.",
		category = "Consumable",
		icon = IconCatalog.get("potionX3"),
		maxStack = 99,
		priceCoins = 2500,
		boostMultiplier = 3,
		boostDurationSeconds = 10 * 60,
	},
	starter_tool = {
		id = "starter_tool",
		name = "Starter Tool",
		description = "An equipment placeholder for games built from this template.",
		category = "Equipment",
		icon = IconCatalog.get("starterTool"),
		maxStack = 1,
		priceCoins = 500,
	},
	warden_blade = {
		id = "warden_blade",
		name = "Warden Blade",
		description = "A dependable dungeon blade granted free when no weapon is equipped.",
		category = "Equipment",
		icon = IconCatalog.get("starterTool"),
		maxStack = 1,
		equipmentSlot = "DungeonWeapon",
	},
	thorn_spear = {
		id = "thorn_spear",
		name = "Thorn Spear",
		description = "A long-reaching dungeon weapon forged from hardened forest thorns.",
		category = "Equipment",
		icon = IconCatalog.get("starterTool"),
		maxStack = 1,
		priceCoins = 25_000,
		equipmentSlot = "DungeonWeapon",
	},
	grove_hammer = {
		id = "grove_hammer",
		name = "Grove Hammer",
		description = "A heavy dungeon weapon awarded only for defeating the forest boss.",
		category = "Equipment",
		icon = IconCatalog.get("starterTool"),
		maxStack = 1,
		equipmentSlot = "DungeonWeapon",
	},
}

return table.freeze({
	items = table.freeze(Items),
})

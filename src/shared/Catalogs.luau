--!strict

export type ItemDefinition = {
	id: string,
	name: string,
	description: string,
	category: "Consumable" | "Equipment" | "Misc",
	icon: string,
	maxStack: number,
	priceCoins: number?,
	boostMultiplier: number?,
	boostDurationSeconds: number?,
}

local Items: { [string]: ItemDefinition } = {
	double_coins_potion = {
		id = "double_coins_potion",
		name = "Double Coins Potion",
		description = "Applies the strongest x2 Coins boost for 15 minutes.",
		category = "Consumable",
		icon = "",
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
		icon = "",
		maxStack = 99,
		priceCoins = 2500,
		boostMultiplier = 3,
		boostDurationSeconds = 10 * 60,
	},
	starter_tool = {
		id = "starter_tool",
		name = "Starter Tool",
		description = "An equipment placeholder for map branches.",
		category = "Equipment",
		icon = "",
		maxStack = 1,
		priceCoins = 500,
	},
}

return table.freeze({
	items = table.freeze(Items),
})

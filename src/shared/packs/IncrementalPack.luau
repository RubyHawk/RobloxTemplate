--!strict

-- Incremental / idle pack (the template default). Prioritises currencies, a
-- multiplier readout, daily-streak progress, and quick shop/reward actions.
-- Every binding points at a real snapshot path; safe defaults cover missing data.

local Types = require(script.Parent.Parent.Types)
type PackDescriptor = Types.PackDescriptor

local pack: PackDescriptor = {
	id = "incremental",
	displayName = "Incremental",
	authoredRoot = "IncrementalPackRoot",

	currencies = {
		{ id = "coins", displayName = "Coins", icon = "coin", primary = true },
		{ id = "gems", displayName = "Gems", icon = "gem" },
	},

	hud = {
		stats = {
			{
				slot = 1,
				path = "currencies.coins",
				icon = "coin",
				caption = "COINS",
				format = "number",
				color = "accent",
				default = 0,
			},
			{
				slot = 2,
				path = "currencies.gems",
				icon = "gem",
				caption = "GEMS",
				format = "number",
				color = "secondary",
				default = 0,
			},
			{
				slot = 3,
				path = "multiplier",
				icon = "multiplier",
				caption = "MULTIPLIER",
				format = "ratio",
				color = "success",
				default = 1,
			},
		},
		progress = {
			{
				slot = 1,
				path = "daily.streak",
				caption = "DAILY STREAK",
				format = "number",
				bar = { max = 7, color = "accent" },
				default = 0,
			},
		},
		actions = {
			{ slot = 1, action = "OpenScreen", screen = "Store", label = "Shop", icon = "shop" },
			{ slot = 2, action = "OpenScreen", screen = "Rewards", label = "Rewards", icon = "rewards" },
		},
	},

	screens = {
		"Inventory",
		"Store",
		"Rewards",
		"Profile",
		"Settings",
		"Codes",
		"Boards",
		"Community",
		"Feedback",
	},

	navigation = {
		{ screen = "Inventory", icon = "bag", label = "Bag" },
		{ screen = "Store", icon = "shop", label = "Shop" },
		{ screen = "Rewards", icon = "rewards", label = "Rewards" },
		{ screen = "Profile", icon = "profile", label = "Profile" },
	},
}

return table.freeze(pack)

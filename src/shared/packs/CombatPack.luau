--!strict

-- Combat pack. Proves the architecture is reusable: the SAME authored slot pool
-- renders a completely different HUD (vital bars + ability buttons + objective)
-- purely through this descriptor and a theme override. Health/stamina are
-- client-local UI state fed from the character (see VitalsFeeder); gold and the
-- objective come from the server snapshot.

local Types = require(script.Parent.Parent.Types)
type PackDescriptor = Types.PackDescriptor

local pack: PackDescriptor = {
	id = "combat",
	displayName = "Combat",
	themeId = "combat",

	currencies = {
		{ id = "coins", displayName = "Gold", icon = "coin", primary = true },
	},

	hud = {
		stats = {
			{
				slot = 1,
				path = "local.health",
				icon = "health",
				caption = "HEALTH",
				format = "number",
				color = "danger",
				bar = { maxPath = "local.maxHealth", color = "danger" },
				default = 100,
			},
			{
				slot = 2,
				path = "local.stamina",
				icon = "stamina",
				caption = "STAMINA",
				format = "number",
				color = "secondary",
				bar = { maxPath = "local.maxStamina", color = "secondary" },
				default = 100,
			},
			{
				slot = 3,
				path = "currencies.coins",
				icon = "coin",
				caption = "GOLD",
				format = "number",
				color = "accent",
				default = 0,
			},
		},
		progress = {
			{
				slot = 1,
				path = "progress.objectives.wave",
				caption = "OBJECTIVE: WAVE",
				format = "number",
				bar = { max = 10, color = "primary" },
				default = 0,
			},
		},
		actions = {
			{
				slot = 1,
				action = "Ability",
				value = "strike",
				label = "Strike",
				icon = "ability",
				cooldown = 3,
			},
			{
				slot = 2,
				action = "Ability",
				value = "guard",
				label = "Guard",
				icon = "ability",
				cooldown = 5,
			},
			{ slot = 3, action = "Ability", value = "dash", label = "Dash", icon = "ability", cooldown = 2 },
		},
	},

	localFeeds = { health = true },

	screens = { "Inventory", "Profile", "Settings", "Boards" },

	navigation = {
		{ screen = "Inventory", icon = "bag", label = "Gear" },
		{ screen = "Profile", icon = "profile", label = "Profile" },
	},
}

return table.freeze(pack)

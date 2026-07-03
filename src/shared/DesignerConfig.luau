--!strict

-- The default recipe used by the normal template build. The desktop Game
-- Designer writes a separate generated copy for exported test experiences;
-- it never rewrites this source file or another preset's authored UI.
return {
	experienceMode = "template",
	preset = "incremental",
	dataNamespace = "incremental",
	identity = {
		universeId = 0,
		placeId = 0,
	},
	currencies = {
		{
			id = "coins",
			name = "Coins",
			symbol = "$",
			color = { 255, 202, 10 },
			startingAmount = 2500,
		},
	},
	features = {},
}

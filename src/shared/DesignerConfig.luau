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
			iconAssetId = "105300168575798",
			color = { 255, 202, 10 },
			startingAmount = 100_000_000_000,
		},
	},
	features = {},
}

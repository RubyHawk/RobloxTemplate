--!strict

-- Patch-only recipe for the shared RNG Defender place. This keeps the reusable
-- template workbench in mock mode while this Rojo patch saves real profile data.
return {
	experienceMode = "playable",
	preset = "incremental",
	dataNamespace = "rngdefender",
	identity = {
		universeId = 10479279603,
		placeId = 128136881672145,
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
	features = {
		runes = true,
		towerDefense = true,
		dungeon = true,
	},
}

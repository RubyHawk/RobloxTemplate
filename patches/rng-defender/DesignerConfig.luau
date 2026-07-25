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
	-- Stagewright uses this exact-place opt-in to remove gallery roots left by
	-- an accidental bare `rojo serve`. It never removes the Team Create island.
	cleanupLegacyGalleryArtifacts = true,
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
	towerDefense = {
		-- RNG Defender is a hybrid lobby. Missing Stagewright world anchors must
		-- disable tower-defense actions, not eject players before they can use the
		-- rune and dungeon systems.
		requirePlatformOnJoin = false,
		-- The existing Team Create world owns all island and upgrade scenery.
		-- Stagewright only needs the shared radial origin so it can place one
		-- 32x27 logical grid on each of the six first-island play areas.
		platformCenterPosition = { 0, 15.5, 0 },
	},
}

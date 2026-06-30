--!strict

local Types = require(script.Parent.Types)
type PlayerProfile = Types.PlayerProfile

local ProfileTemplate = {}

-- Bump alongside Migrations.CURRENT_VERSION whenever the persisted shape changes.
ProfileTemplate.CURRENT_VERSION = 2

function ProfileTemplate.create(now: number): PlayerProfile
	return {
		schemaVersion = ProfileTemplate.CURRENT_VERSION,
		coins = 0,
		currencies = {
			-- "coins" mirrors the top-level `coins` field for back-compat; secondary
			-- currencies (gems, etc.) live only here. See EconomyService.
			coins = 0,
			gems = 0,
		},
		upgrades = {},
		unlocks = {},
		progress = {
			rebirths = 0,
			prestige = 0,
			objectives = {},
		},
		tutorial = {
			completedSteps = {},
			dismissed = false,
		},
		selectedPack = "",
		inventory = {
			double_coins_potion = { quantity = 1 },
		},
		boosts = {},
		settings = {
			musicVolume = 0.5,
			sfxVolume = 0.7,
			uiScale = 1,
			reducedMotion = false,
			announcements = true,
			afKRollOver = true,
			notifications = false,
		},
		stats = {
			playSeconds = 0,
			joins = 0,
			totalCoinsEarned = 0,
		},
		daily = {
			lastClaimDay = -1,
			streak = 0,
		},
		redemptions = {},
		entitlements = {
			extendedOffline = false,
			premium = false,
		},
		social = {
			friendCountInServer = 0,
			communityVerified = false,
			discordVerified = false,
		},
		guild = {},
		lastSeenAt = now,
		offlineRateSnapshot = 0,
		createdAt = now,
		updatedAt = now,
	}
end

return ProfileTemplate

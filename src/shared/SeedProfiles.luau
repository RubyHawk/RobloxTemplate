--!strict

-- Deterministic profile fixtures for the Studio canary store. Values are fixed
-- (no os.time / math.random) so Data Delve Canary always shows the same readable
-- data per archetype. ProfileService.seedCanary writes these through the normal
-- envelope path, so they migrate and lock exactly like real profiles.

local ProfileTemplate = require(script.Parent.ProfileTemplate)

local SeedProfiles = {}

-- Fixed timestamp keeps createdAt/updatedAt stable across seed runs.
local FIXED_TIMESTAMP = 1_700_000_000

local function base(): any
	return ProfileTemplate.create(FIXED_TIMESTAMP)
end

function SeedProfiles.all(): { [string]: any }
	local incremental = base()
	incremental.coins = 125000
	incremental.currencies.coins = 125000
	incremental.currencies.gems = 320
	incremental.upgrades = { autoClicker = 5, luck = 2, vault = 3 }
	incremental.unlocks = { vipZone = true, secondShop = true }
	incremental.progress.rebirths = 3
	incremental.daily.streak = 4
	incremental.stats.totalCoinsEarned = 980000
	incremental.selectedPack = "incremental"
	incremental.selectedTheme = "incremental"

	local combat = base()
	combat.coins = 8200
	combat.currencies.coins = 8200
	combat.progress.objectives = { wave = 6, bosses = 1 }
	combat.unlocks = { swordTier2 = true }
	combat.stats.totalCoinsEarned = 41000
	combat.selectedPack = "combat"
	combat.selectedTheme = "combat"

	return {
		incremental = incremental,
		combat = combat,
	}
end

return SeedProfiles

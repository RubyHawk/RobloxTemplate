--!strict

-- Pure, sequential profile migration steps, kept dependency-free so they can be
-- unit-tested directly (the Migrations entry point uses Roblox `script` requires
-- and cannot run under Lune). Each step mutates `raw` in place and handles only
-- the non-additive part of a version bump; additive fields are filled afterwards
-- by MigrationCore.reconcile, and unknown keys are preserved by deepCopy.

local ProfileMigrationSteps = {}

-- v1 -> v2: introduce the multi-currency map, seeding the canonical "coins" entry
-- from the legacy top-level field so no balance is lost.
function ProfileMigrationSteps.v1ToV2(raw: any)
	if type(raw.currencies) ~= "table" then
		raw.currencies = {}
	end
	if raw.currencies.coins == nil then
		raw.currencies.coins = if type(raw.coins) == "number" then raw.coins else 0
	end
end

-- Indexed by the version a profile is migrating *from*.
ProfileMigrationSteps.byVersion = {
	[1] = ProfileMigrationSteps.v1ToV2,
} :: { [number]: (any) -> () }

return ProfileMigrationSteps

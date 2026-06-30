--!strict

local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)
local ProfileMigrationSteps = require(script.Parent.ProfileMigrationSteps)

local Migrations = {}
Migrations.CURRENT_VERSION = 2

function Migrations.migrate(raw: any, now: number): any
	local defaults = ProfileTemplate.create(now)
	if type(raw) ~= "table" then
		return MigrationCore.migrate(raw, defaults, Migrations.CURRENT_VERSION)
	end

	-- Apply each sequential step needed to reach the current version. Steps only
	-- move/derive data; purely additive fields are reconciled below and unknown
	-- keys are preserved by MigrationCore.deepCopy.
	local version = if type(raw.schemaVersion) == "number" then raw.schemaVersion else 1
	while version < Migrations.CURRENT_VERSION do
		local step = ProfileMigrationSteps.byVersion[version]
		if step then
			step(raw)
		end
		version += 1
	end

	return MigrationCore.migrate(raw, defaults, Migrations.CURRENT_VERSION)
end

return Migrations

--!strict

local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)

local Migrations = {}
Migrations.CURRENT_VERSION = 1

function Migrations.migrate(raw: any, now: number): any
	return MigrationCore.migrate(raw, ProfileTemplate.create(now), Migrations.CURRENT_VERSION)
end

return Migrations

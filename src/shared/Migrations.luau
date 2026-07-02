--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)
local Config = require(script.Parent.TemplateConfig)

local Migrations = {}
Migrations.CURRENT_VERSION = 2

function Migrations.migrate(raw: any, now: number): any
	local previousVersion = if type(raw) == "table" and type(raw.schemaVersion) == "number"
		then raw.schemaVersion
		else 0
	local profile = MigrationCore.migrate(raw, ProfileTemplate.create(now), Migrations.CURRENT_VERSION)
	CurrencyConfig.reconcileProfileCurrencies(
		profile,
		Config.economy.currencies,
		Config.economy.primaryCurrencyId,
		previousVersion
	)
	return profile
end

return Migrations

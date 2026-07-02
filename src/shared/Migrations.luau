--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)
local Config = require(script.Parent.TemplateConfig)

local Migrations = {}
Migrations.CURRENT_VERSION = 4

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
	if previousVersion < 3 and type(profile.feedback) ~= "table" then
		profile.feedback = { lastSubmittedAt = 0 }
	end
	if previousVersion < 4 and type(profile.offline) ~= "table" then
		profile.offline = { pendingAmount = 0, pendingElapsed = 0, preparedAt = 0 }
	end
	return profile
end

return Migrations

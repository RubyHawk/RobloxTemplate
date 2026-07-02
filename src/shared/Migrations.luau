--!strict

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
	if type(profile.currencies) ~= "table" then
		profile.currencies = {}
	end
	local primaryId = Config.economy.primaryCurrencyId
	if previousVersion < 2 or type(profile.currencies[primaryId]) ~= "number" then
		profile.currencies[primaryId] = if type(profile.coins) == "number" then profile.coins else 0
	end
	for _, definition in Config.economy.currencies do
		if type(profile.currencies[definition.id]) ~= "number" then
			profile.currencies[definition.id] = 0
		end
	end
	profile.coins = profile.currencies[primaryId]
	if previousVersion < 3 and type(profile.feedback) ~= "table" then
		profile.feedback = { lastSubmittedAt = 0 }
	end
	if previousVersion < 4 and type(profile.offline) ~= "table" then
		profile.offline = { pendingAmount = 0, pendingElapsed = 0, preparedAt = 0 }
	end
	return profile
end

return Migrations

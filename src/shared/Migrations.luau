--!strict

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
	return profile
end

return Migrations

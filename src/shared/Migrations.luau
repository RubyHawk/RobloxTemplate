--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)
local Config = require(script.Parent.TemplateConfig)

local Migrations = {}
Migrations.CURRENT_VERSION = 7

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
	if previousVersion < 5 and type(profile.runes) ~= "table" then
		profile.runes = { owned = {}, totalRolls = 0, rollsSincePity = 0 }
	end
	if previousVersion < 6 and type(profile.towerDefense) ~= "table" then
		profile.towerDefense = {
			ownedUnits = {},
			loadout = {},
			stats = {
				wins = 0,
				losses = 0,
				bestWave = 0,
			},
		}
	end
	-- v7: channel-mode selection. An unknown saved mode id is kept on disk (a
	-- recipe may re-add the mode later); runtime resolution falls back to the
	-- configured default without overwriting the player's choice.
	if
		previousVersion < 7
		and type(profile.runes) == "table"
		and type(profile.runes.selectedMode) ~= "string"
	then
		profile.runes.selectedMode = Config.runes.defaultChannelMode
	end
	return profile
end

return Migrations

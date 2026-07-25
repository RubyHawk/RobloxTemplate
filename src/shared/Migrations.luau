--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local ProfileTemplate = require(script.Parent.ProfileTemplate)
local MigrationCore = require(script.Parent.MigrationCore)
local Config = require(script.Parent.TemplateConfig)
local StageCatalog = require(script.Parent.StageCatalog)

local Migrations = {}
Migrations.CURRENT_VERSION = 9

function Migrations.migrate(raw: any, now: number): any
	local startingStageId = StageCatalog.defaultStageId()
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
			selectedStageId = startingStageId,
			stageProgress = {},
			stats = {
				wins = 0,
				losses = 0,
				bestWave = 0,
			},
		}
	end
	if previousVersion < 7 then
		local towerDefense = profile.towerDefense
		if type(towerDefense.selectedStageId) ~= "string" or towerDefense.selectedStageId == "" then
			towerDefense.selectedStageId = startingStageId
		end
		if type(towerDefense.stageProgress) ~= "table" then
			towerDefense.stageProgress = {}
		end
		local startingProgress = towerDefense.stageProgress[startingStageId]
		if type(startingProgress) ~= "table" then
			towerDefense.stageProgress[startingStageId] = {
				unlocked = true,
				clears = 0,
				bestWave = if type(towerDefense.stats) == "table"
						and type(towerDefense.stats.bestWave) == "number"
					then towerDefense.stats.bestWave
					else 0,
			}
		else
			startingProgress.unlocked = true
		end
		-- An unknown saved mode id is kept on disk (a recipe may re-add the
		-- mode later); runtime resolution falls back without overwriting it.
		if type(profile.runes) == "table" and type(profile.runes.selectedMode) ~= "string" then
			profile.runes.selectedMode = Config.runes.defaultChannelMode
		end
	end
	if previousVersion < 8 and type(profile.dungeon) ~= "table" then
		profile.dungeon = { selectedBossId = "" }
	end
	if previousVersion < 9 then
		local towerDefense = profile.towerDefense
		local existingLoadoutCount = if type(towerDefense.loadout) == "table"
			then #towerDefense.loadout
			else 0
		towerDefense.unlockedLoadoutSlots = math.clamp(
			math.max(Config.towerDefense.startingLoadoutSlots, existingLoadoutCount),
			Config.towerDefense.startingLoadoutSlots,
			Config.towerDefense.loadoutSlots
		)
	end
	return profile
end

return Migrations

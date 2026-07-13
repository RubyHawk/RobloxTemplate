--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local StageHierarchy = require("../src/shared/StageHierarchy")
local StageSchema = require("../src/shared/StageSchema")

local PROJECT_PATH = "stage-data/stagewright-project.json"
local LEVEL_COUNT = 10

local function clone(value: any): any
	return serde.decode("json", serde.encode("json", value))
end

local project = StageSchema.migrateProject(serde.decode("json", fs.readFile(PROJECT_PATH)))
local ids = StageHierarchy.sortedIds(project.stages)
assert(#ids == 1 or #ids == LEVEL_COUNT, "Starter seeding expects either one level or the completed set")

local firstId = ids[1]
local first = project.stages[firstId]
StageHierarchy.assign(first, "stage_group_1", 1, 1)
first.name = "Level 1"
first.displayOrder = 1
first.unlockRequirements = {}

if #ids == 1 then
	local previousId = firstId
	for levelNumber = 2, LEVEL_COUNT do
		local level = clone(first)
		local levelId = `stage_1_level_{string.format("%02d", levelNumber)}`
		level.id = levelId
		level.name = `Level {levelNumber}`
		level.displayOrder = levelNumber
		StageHierarchy.assign(level, "stage_group_1", 1, levelNumber)
		level.unlockRequirements = { { kind = "StageUnlocked", stageId = previousId } }
		project.stages[levelId] = level
		previousId = levelId
	end
end

project.metadata = project.metadata or {}
project.metadata["stagewright.starterLevelCount"] = LEVEL_COUNT
project.metadata["stagewright.starterStageGroupId"] = "stage_group_1"
project.schemaVersion = StageSchema.AUTHORING_VERSION

fs.writeFile(PROJECT_PATH, StageSchema.encodeCanonical(project) .. "\n")
print(`Seeded Stage 1 with Levels 1-{LEVEL_COUNT}`)

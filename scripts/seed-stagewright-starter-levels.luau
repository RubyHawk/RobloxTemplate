--!strict

local fs = require("@lune/fs")

local StageSchema = require("../src/shared/StageSchema")
local StageStarterProject = require("../src/shared/StageStarterProject")

local PROJECT_PATH = "stage-data/stagewright-project.json"
local LEVEL_COUNT = 10

local counters: { [string]: number } = {}
local function deterministicId(prefix: string): string
	local nextValue = (counters[prefix] or 0) + 1
	counters[prefix] = nextValue
	if prefix == "stage" then
		-- Level 1 keeps the long-lived stage_default identity. Subsequent levels
		-- retain the public hierarchy IDs already consumed by runtime tooling.
		return `stage_1_level_{nextValue + 1}`
	end
	return `{prefix}_{string.format("%03d", nextValue)}`
end

local project = StageStarterProject.build(LEVEL_COUNT, deterministicId, "stage_default", "stage_group_1")

fs.writeFile(PROJECT_PATH, StageSchema.encodeCanonical(project) .. "\n")
print(`Replaced Stagewright starter data with revision {StageStarterProject.REVISION}`)

--!strict

local StageGraph = require("../src/shared/StageGraph")
local StagePath = require("../src/shared/StagePath")
local StageSchema = require("../src/shared/StageSchema")

local function timed(callback: () -> ()): number
	local started = os.clock()
	callback()
	return os.clock() - started
end

local function requireBudget(label: string, elapsed: number, budget: number)
	print(string.format("%-42s %8.3f ms (budget %.3f ms)", label, elapsed * 1_000, budget * 1_000))
	assert(elapsed <= budget, `{label} exceeded its performance budget`)
end

local denseCells: { [string]: any } = {}
for row = 1, 256 do
	for column = 1, 256 do
		denseCells[`{column}:{row}`] = {
			buildPolicy = if (column + row) % 7 == 0 then "Blocked" else "Allowed",
		}
	end
end
local denseStage = {
	id = "benchmark_dense",
	mapId = "benchmark_map",
	stageGroupId = "benchmark_group",
	stageNumber = 1,
	levelNumber = 1,
	grid = {
		columns = 256,
		rows = 256,
		cellSize = 4,
		defaultCell = { terrainId = "ground", buildPolicy = "Allowed", enemyTraversalPolicy = "Allowed" },
		cells = denseCells,
	},
	pathGraphs = {},
}
local denseValidation = timed(function()
	local issues = StageSchema.validateStage(denseStage)
	assert(#issues == 0, "dense grid benchmark fixture must remain valid")
end)
requireBudget("256x256 dense grid validation", denseValidation, 1)

local nodes: { [string]: any } = {}
for index = 1, 1_000 do
	local id = `node_{index}`
	nodes[id] = {
		id = id,
		kind = if index == 1 then "Spawn" elseif index == 1_000 then "Goal" else "Junction",
	}
end
local edges: { [string]: any } = {}
for index = 1, 999 do
	local id = `fallback_{index}`
	edges[id] = {
		id = id,
		fromNodeId = `node_{index}`,
		toNodeId = `node_{index + 1}`,
		priority = 2,
		predicates = {},
	}
end
for index = 1, 501 do
	local id = `conditional_{index}`
	edges[id] = {
		id = id,
		fromNodeId = `node_{index}`,
		toNodeId = `node_{index + 1}`,
		priority = 1,
		predicates = { { kind = "WaveRange", minimum = 5, maximum = 10 } },
	}
end
local largeGraph = {
	nodes = nodes,
	edges = edges,
	maxNodeVisitsPerEnemy = 2_000,
	maxTravelDistance = 100_000,
}
local graphValidation = timed(function()
	local issues = StageGraph.validate(largeGraph)
	assert(#issues == 0, "large graph benchmark fixture must remain valid")
end)
requireBudget("1000-node / 1500-edge validation", graphValidation, 1)

local samples, length = StagePath.bake(
	{ x = -50, y = 0, z = 0 },
	{ x = -20, y = 8, z = 24 },
	{ x = 20, y = -4, z = -24 },
	{ x = 50, y = 0, z = 0 }
)
local distances: { number } = {}
for index = 1, 500 do
	distances[index] = (index / 500) * length
end
local updateCount = 200
local enemyBatchElapsed = timed(function()
	for _ = 1, updateCount do
		for index = 1, 500 do
			distances[index] = (distances[index] + 7 / 20) % length
			assert(
				StagePath.sample(samples, length, distances[index]) ~= nil,
				"500-enemy benchmark sample must resolve"
			)
		end
	end
end)
requireBudget("500-enemy 20 Hz route sample batch", enemyBatchElapsed / updateCount, 0.008)

local sixPlatformDistances: { number } = {}
for index = 1, 3_000 do
	sixPlatformDistances[index] = (index / 3_000) * length
end
local sixPlatformElapsed = timed(function()
	for _ = 1, updateCount do
		for index = 1, 3_000 do
			sixPlatformDistances[index] = (sixPlatformDistances[index] + 7 / 20) % length
			assert(
				StagePath.sample(samples, length, sixPlatformDistances[index]) ~= nil,
				"six-platform benchmark sample must resolve"
			)
		end
	end
end)
requireBudget("6-platform / 3000-enemy sample batch", sixPlatformElapsed / updateCount, 0.03)

local visibleMutationElapsed = timed(function()
	for iteration = 1, 100 do
		for index = 1, 900 do
			local column = ((index - 1) % 30) + 1
			local row = math.floor((index - 1) / 30) + 1
			denseCells[`{column}:{row}`].buildPolicy = if iteration % 2 == 0 then "Allowed" else "Blocked"
		end
	end
end)
requireBudget("900 visible-cell incremental mutation", visibleMutationElapsed / 100, 0.016)

print("Stagewright performance budgets passed.")

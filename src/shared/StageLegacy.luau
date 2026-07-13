--!strict

local StageSchema = if script ~= nil then require(script.Parent.StageSchema) else require("./StageSchema")

local StageLegacy = {}

export type Vec3 = { x: number, y: number, z: number }
export type LegacyInput = {
	columns: number,
	rows: number,
	cellSize: number,
	rowValues: { string },
	controlPositions: { Vec3 },
	stageId: string?,
	graphId: string?,
	stageName: string?,
	blankFallback: boolean?,
}

local function cellPosition(
	columns: number,
	rows: number,
	cellSize: number,
	column: number,
	row: number
): Vec3
	return {
		x = -(columns * cellSize) * 0.5 + (column - 0.5) * cellSize,
		y = 0,
		z = -(rows * cellSize) * 0.5 + (row - 0.5) * cellSize,
	}
end

local function cellForPosition(input: LegacyInput, position: Vec3): (number, number)
	local column = math.floor((position.x + input.columns * input.cellSize * 0.5) / input.cellSize) + 1
	local row = math.floor((position.z + input.rows * input.cellSize * 0.5) / input.cellSize) + 1
	return math.clamp(column, 1, input.columns), math.clamp(row, 1, input.rows)
end

local function roleCells(cells: { [string]: any }, role: string): { { column: number, row: number } }
	local result: { { column: number, row: number } } = {}
	for key, cell in cells do
		if cell.roles ~= nil and cell.roles[role] == true then
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			local column = tonumber(columnText)
			local row = tonumber(rowText)
			if column ~= nil and row ~= nil then
				table.insert(result, { column = column, row = row })
			end
		end
	end
	table.sort(result, function(left, right)
		return if left.row == right.row then left.column < right.column else left.row < right.row
	end)
	return result
end

local function addRole(cells: { [string]: any }, column: number, row: number, role: string)
	local key = StageSchema.cellKey(column, row)
	local cell = cells[key] or {}
	cell.buildPolicy = "Blocked"
	cell.roles = cell.roles or {}
	cell.roles[role] = true
	cells[key] = cell
end

local function subtract(left: Vec3, right: Vec3): Vec3
	return { x = left.x - right.x, y = left.y - right.y, z = left.z - right.z }
end

local function scale(value: Vec3, amount: number): Vec3
	return { x = value.x * amount, y = value.y * amount, z = value.z * amount }
end

function StageLegacy.project(input: LegacyInput): (any, { string })
	assert(input.columns >= 1 and input.rows >= 1, "Legacy grid dimensions must be positive")
	assert(input.cellSize > 0, "Legacy cell size must be positive")
	local notices: { string } = {}
	local cells = StageSchema.legacyCells(input.rowValues, input.columns)
	local spawnCells = roleCells(cells, "EnemySpawn")
	local goalCells = roleCells(cells, "EnemyGoal")
	local inferredControlSpawn = false

	if #spawnCells == 0 and #input.controlPositions > 0 then
		local column, row = cellForPosition(input, input.controlPositions[1])
		addRole(cells, column, row, "EnemySpawn")
		spawnCells = { { column = column, row = row } }
		inferredControlSpawn = true
		table.insert(notices, `Enemy spawn inferred from Control_001 at cell {column}:{row}`)
	elseif #spawnCells == 0 and input.blankFallback == true then
		local column = math.clamp(4, 1, input.columns)
		local row = math.ceil(input.rows / 2)
		addRole(cells, column, row, "EnemySpawn")
		spawnCells = { { column = column, row = row } }
	end

	if #goalCells == 0 and input.blankFallback == true then
		local column = math.clamp(input.columns - 3, 1, input.columns)
		local row = math.ceil(input.rows / 2)
		addRole(cells, column, row, "EnemyGoal")
		goalCells = { { column = column, row = row } }
	end

	local nodes: { [string]: any } = {}
	local orderedNodeIds: { string } = {}
	local orderedPositions: { Vec3 } = {}
	local spawnCell = spawnCells[1]
	if spawnCell ~= nil then
		local spawnPosition = if inferredControlSpawn
			then input.controlPositions[1]
			else cellPosition(input.columns, input.rows, input.cellSize, spawnCell.column, spawnCell.row)
		nodes.node_spawn = {
			id = "node_spawn",
			name = "Spawn",
			kind = "Spawn",
			position = spawnPosition,
			tags = if inferredControlSpawn then { "InferredFromLegacyControl" } else {},
		}
		table.insert(orderedNodeIds, "node_spawn")
		table.insert(orderedPositions, spawnPosition)
	end

	local firstControl = if inferredControlSpawn then 2 else 1
	for index = firstControl, #input.controlPositions do
		local nodeId = `node_control_{string.format("%03d", index)}`
		local position = input.controlPositions[index]
		nodes[nodeId] = {
			id = nodeId,
			name = `Legacy Control {index}`,
			kind = "Junction",
			position = position,
			tags = {},
		}
		table.insert(orderedNodeIds, nodeId)
		table.insert(orderedPositions, position)
	end

	local goalCell = goalCells[1]
	if goalCell ~= nil then
		local goalPosition =
			cellPosition(input.columns, input.rows, input.cellSize, goalCell.column, goalCell.row)
		nodes.node_goal = {
			id = "node_goal",
			name = "Goal",
			kind = "Goal",
			position = goalPosition,
			tags = {},
		}
		table.insert(orderedNodeIds, "node_goal")
		table.insert(orderedPositions, goalPosition)
	end

	for index = 2, #spawnCells do
		local nodeId = `node_extra_spawn_{string.format("%03d", index)}`
		local cell = spawnCells[index]
		nodes[nodeId] = {
			id = nodeId,
			name = `Unconnected Legacy Spawn {index}`,
			kind = "Spawn",
			position = cellPosition(input.columns, input.rows, input.cellSize, cell.column, cell.row),
			tags = { "NeedsRepair" },
		}
	end
	for index = 2, #goalCells do
		local nodeId = `node_extra_goal_{string.format("%03d", index)}`
		local cell = goalCells[index]
		nodes[nodeId] = {
			id = nodeId,
			name = `Unconnected Legacy Goal {index}`,
			kind = "Goal",
			position = cellPosition(input.columns, input.rows, input.cellSize, cell.column, cell.row),
			tags = { "NeedsRepair" },
		}
	end

	local edges: { [string]: any } = {}
	for index = 1, #orderedNodeIds - 1 do
		local p0 = orderedPositions[math.max(index - 1, 1)]
		local p1 = orderedPositions[index]
		local p2 = orderedPositions[index + 1]
		local p3 = orderedPositions[math.min(index + 2, #orderedPositions)]
		local edgeId = `edge_{string.format("%03d", index)}`
		edges[edgeId] = {
			id = edgeId,
			fromNodeId = orderedNodeIds[index],
			toNodeId = orderedNodeIds[index + 1],
			outHandleOffset = scale(subtract(p2, p0), 1 / 6),
			inHandleOffset = scale(subtract(p1, p3), 1 / 6),
			laneProfileId = "lane_default",
			priority = 1,
			predicates = {},
		}
	end

	local stageId = input.stageId or "stage_default"
	local graphId = input.graphId or "graph_main"
	local metadata: any = {
		legacyImport = {
			sourceKind = "CellMap/PathPoints",
			spawnInferredFrom = if inferredControlSpawn then "Control_001" else nil,
		},
	}
	local stage = {
		schemaVersion = StageSchema.AUTHORING_VERSION,
		id = stageId,
		stageGroupId = "stage_group_legacy_1",
		stageNumber = 1,
		levelNumber = 1,
		name = input.stageName or "Imported Stage",
		displayOrder = 1,
		grid = {
			columns = input.columns,
			rows = input.rows,
			cellSize = input.cellSize,
			defaultCell = {
				terrainId = "ground",
				buildPolicy = "Allowed",
				enemyTraversalPolicy = "Allowed",
			},
			cells = cells,
		},
		pathGraphs = {
			[graphId] = {
				id = graphId,
				name = "Main Route",
				nodes = nodes,
				edges = edges,
				laneProfiles = {
					lane_default = { id = "lane_default", offsets = { 0 }, clearanceRadius = 2 },
				},
				maxNodeVisitsPerEnemy = 64,
				maxTravelDistance = 10_000,
			},
		},
		waveSetId = "default",
		themeId = "default",
		modifierIds = {},
		unlockRequirements = {},
		metadata = metadata,
	}
	return {
		schemaVersion = StageSchema.AUTHORING_VERSION,
		startingStageId = stageId,
		stages = { [stageId] = stage },
	},
		notices
end

return table.freeze(StageLegacy)

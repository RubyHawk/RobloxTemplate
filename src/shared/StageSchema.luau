--!strict

local StageGraph = if script ~= nil then require(script.Parent.StageGraph) else require("./StageGraph")

local StageSchema = {}

StageSchema.AUTHORING_VERSION = 2
StageSchema.RUNTIME_VERSION = 1

export type JsonValue = string | number | boolean | { JsonValue } | { [string]: JsonValue }
export type Issue = {
	severity: "Error" | "Warning",
	code: string,
	message: string,
	stageId: string?,
	graphId: string?,
	objectId: string?,
}

local VALID_ROLES = {
	EnemySpawn = true,
	EnemyGoal = true,
	AutoPlace = true,
	Hazard = true,
	Reward = true,
	Trigger = true,
	StageTransition = true,
	DecorationAnchor = true,
	Reserved = true,
}
local VALID_BUILD_POLICIES = { Allowed = true, Blocked = true, AutoOnly = true }
local VALID_TRAVERSAL_POLICIES = { Allowed = true, Blocked = true }

local function escapeString(value: string): string
	local escaped = string.gsub(value, "\\", "\\\\")
	escaped = string.gsub(escaped, '"', '\\"')
	escaped = string.gsub(escaped, "\b", "\\b")
	escaped = string.gsub(escaped, "\f", "\\f")
	escaped = string.gsub(escaped, "\n", "\\n")
	escaped = string.gsub(escaped, "\r", "\\r")
	escaped = string.gsub(escaped, "\t", "\\t")
	return `"{escaped}"`
end

local function isArray(value: { [any]: any }): (boolean, number)
	local count = 0
	local maximum = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, 0
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	return count == maximum, maximum
end

local function encodeCanonical(value: any, ancestors: { [table]: boolean }): string
	local valueType = type(value)
	if valueType == "nil" then
		return "null"
	elseif valueType == "boolean" then
		return if value then "true" else "false"
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("canonical JSON cannot encode NaN or infinity")
		end
		return string.format("%.17g", value)
	elseif valueType == "string" then
		return escapeString(value)
	elseif valueType ~= "table" then
		error(`canonical JSON cannot encode {valueType}`)
	end
	if ancestors[value] then
		error("canonical JSON cannot encode recursive tables")
	end
	ancestors[value] = true
	local array, length = isArray(value)
	local encoded: { string } = {}
	if array then
		for index = 1, length do
			table.insert(encoded, encodeCanonical(value[index], ancestors))
		end
		ancestors[value] = nil
		return "[" .. table.concat(encoded, ",") .. "]"
	end
	local keys: { string } = {}
	for key in value do
		if type(key) ~= "string" then
			error("canonical JSON object keys must be strings")
		end
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(encoded, `{escapeString(key)}:{encodeCanonical(value[key], ancestors)}`)
	end
	ancestors[value] = nil
	return "{" .. table.concat(encoded, ",") .. "}"
end

function StageSchema.encodeCanonical(value: JsonValue): string
	return encodeCanonical(value, {})
end

function StageSchema.checksum(value: JsonValue): string
	local encoded = StageSchema.encodeCanonical(value)
	local hash = 2_166_136_261
	for index = 1, #encoded do
		hash = bit32.bxor(hash, string.byte(encoded, index))
		-- 16,777,619 = 2^24 + 403. Split the multiplication so every
		-- intermediate remains exactly representable by Luau's number type.
		hash = (bit32.lshift(hash, 24) + hash * 403) % 4_294_967_296
	end
	return string.format("fnv1a32-%08x", hash)
end

function StageSchema.cellKey(column: number, row: number): string
	return `{math.floor(column)}:{math.floor(row)}`
end

function StageSchema.migrateProject(project: any): any
	assert(type(project) == "table", "Stagewright project must be a table")
	local version = if type(project.schemaVersion) == "number" then math.floor(project.schemaVersion) else 0
	assert(version <= StageSchema.AUTHORING_VERSION, "Stagewright project schema is newer than this plugin")
	if version == 0 then
		project.stages = project.stages or {}
		project.startingStageId = project.startingStageId or ""
		project.schemaVersion = 1
		version = 1
	end
	if version == 1 then
		for _, stage in project.stages do
			stage.schemaVersion = StageSchema.AUTHORING_VERSION
			stage.metadata = stage.metadata or {}
			stage.modifierIds = stage.modifierIds or {}
			stage.unlockRequirements = stage.unlockRequirements or {}
			stage.grid.defaultCell = stage.grid.defaultCell
				or {
					terrainId = "ground",
					buildPolicy = "Allowed",
					enemyTraversalPolicy = "Allowed",
				}
			stage.grid.cells = stage.grid.cells or {}
			for _, graph in stage.pathGraphs or {} do
				graph.name = graph.name or "Route"
				graph.laneProfiles = graph.laneProfiles
					or {
						lane_default = { id = "lane_default", offsets = { 0 }, clearanceRadius = 2 },
					}
				graph.maxNodeVisitsPerEnemy = graph.maxNodeVisitsPerEnemy or 64
				graph.maxTravelDistance = graph.maxTravelDistance or 10_000
				for _, edge in graph.edges or {} do
					edge.laneProfileId = edge.laneProfileId or "lane_default"
					edge.priority = edge.priority or 1
					edge.predicates = edge.predicates or {}
				end
			end
		end
		project.schemaVersion = StageSchema.AUTHORING_VERSION
	end
	return project
end

function StageSchema.legacyCells(rows: { string }, columns: number): { [string]: any }
	local cells: { [string]: any } = {}
	for row, rowValue in rows do
		for column = 1, columns do
			local code = string.sub(rowValue, column, column)
			local cell: any? = nil
			if code == "#" then
				cell = { buildPolicy = "Blocked" }
			elseif code == "P" then
				cell = { buildPolicy = "Blocked", roles = { EnemySpawn = true } }
			elseif code == "G" then
				cell = { buildPolicy = "Blocked", roles = { EnemyGoal = true } }
			elseif code == "A" then
				cell = { buildPolicy = "Allowed", roles = { AutoPlace = true } }
			elseif code ~= "." and code ~= "" then
				cell = { metadata = { legacyCode = code } }
			end
			if cell ~= nil then
				cells[StageSchema.cellKey(column, row)] = cell
			end
		end
	end
	return cells
end

function StageSchema.validateStage(stage: any): { Issue }
	local issues: { Issue } = {}
	if type(stage) ~= "table" or type(stage.id) ~= "string" or stage.id == "" then
		return { { severity = "Error", code = "InvalidStage", message = "Stage has no stable ID" } }
	end
	local stageId = stage.id
	local grid = stage.grid
	if type(grid) ~= "table" or type(grid.columns) ~= "number" or type(grid.rows) ~= "number" then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidGrid",
			message = "Stage grid dimensions are missing",
			stageId = stageId,
		})
	else
		if grid.columns < 1 or grid.columns > 512 or grid.rows < 1 or grid.rows > 512 then
			table.insert(issues, {
				severity = "Error",
				code = "GridBounds",
				message = "Grid dimensions must be between 1 and 512",
				stageId = stageId,
			})
		end
		if
			type(grid.cellSize) ~= "number"
			or grid.cellSize ~= grid.cellSize
			or grid.cellSize <= 0
			or grid.cellSize > 128
		then
			table.insert(issues, {
				severity = "Error",
				code = "CellSize",
				message = "Grid cell size must be finite and between 0 and 128",
				stageId = stageId,
			})
		end
		for key, cell in grid.cells or {} do
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			local column = tonumber(columnText)
			local row = tonumber(rowText)
			if
				column == nil
				or row == nil
				or column < 1
				or column > grid.columns
				or row < 1
				or row > grid.rows
			then
				table.insert(issues, {
					severity = "Error",
					code = "CellOutOfBounds",
					message = `Cell override {key} is outside the stage grid`,
					stageId = stageId,
					objectId = key,
				})
			end
			if cell.buildPolicy ~= nil and VALID_BUILD_POLICIES[cell.buildPolicy] ~= true then
				table.insert(issues, {
					severity = "Error",
					code = "BuildPolicy",
					message = `Cell {key} has an invalid build policy`,
					stageId = stageId,
					objectId = key,
				})
			end
			if
				cell.enemyTraversalPolicy ~= nil
				and VALID_TRAVERSAL_POLICIES[cell.enemyTraversalPolicy] ~= true
			then
				table.insert(issues, {
					severity = "Error",
					code = "TraversalPolicy",
					message = `Cell {key} has an invalid enemy traversal policy`,
					stageId = stageId,
					objectId = key,
				})
			end
			for role, enabled in cell.roles or {} do
				if enabled == true and VALID_ROLES[role] ~= true then
					table.insert(issues, {
						severity = "Warning",
						code = "UnknownCellRole",
						message = `Cell {key} has unknown role {role}`,
						stageId = stageId,
						objectId = key,
					})
				end
			end
			local roles = cell.roles or {}
			if (roles.EnemySpawn or roles.EnemyGoal) and cell.buildPolicy ~= "Blocked" then
				table.insert(issues, {
					severity = "Error",
					code = "EndpointBuildPolicy",
					message = `Cell {key} spawn/goal role requires Blocked build policy`,
					stageId = stageId,
					objectId = key,
				})
			end
			if roles.AutoPlace and cell.buildPolicy == "Blocked" then
				table.insert(issues, {
					severity = "Error",
					code = "AutoPlaceBlocked",
					message = `Cell {key} cannot be blocked and auto-place`,
					stageId = stageId,
					objectId = key,
				})
			end
			if cell.metadata ~= nil then
				local success, encoded = pcall(StageSchema.encodeCanonical, cell.metadata)
				if not success or #encoded > 4_096 then
					table.insert(issues, {
						severity = "Error",
						code = "CellMetadata",
						message = `Cell {key} metadata is invalid or exceeds 4096 bytes`,
						stageId = stageId,
						objectId = key,
					})
				end
			end
		end
	end
	for graphId, graph in stage.pathGraphs or {} do
		for _, issue in StageGraph.validate(graph) do
			table.insert(issues, {
				severity = issue.severity,
				code = issue.code,
				message = issue.message,
				stageId = stageId,
				graphId = graphId,
				objectId = issue.objectId,
			})
		end
	end
	return issues
end

function StageSchema.hasErrors(issues: { Issue }): boolean
	for _, issue in issues do
		if issue.severity == "Error" then
			return true
		end
	end
	return false
end

return table.freeze(StageSchema)

--!strict

local StageGraph = if script ~= nil then require(script.Parent.StageGraph) else require("./StageGraph")
local StageCell = if script ~= nil then require(script.Parent.StageCell) else require("./StageCell")
local StageHierarchy = if script ~= nil
	then require(script.Parent.StageHierarchy)
	else require("./StageHierarchy")
local StageLanes = if script ~= nil then require(script.Parent.StageLanes) else require("./StageLanes")
local StagePathAssets = if script ~= nil
	then require(script.Parent.StagePathAssets)
	else require("./StagePathAssets")

local StageSchema = {}

StageSchema.AUTHORING_VERSION = 4
StageSchema.RUNTIME_VERSION = 2

export type JsonValue = string | number | boolean | { JsonValue } | { [string]: JsonValue }
export type Issue = {
	severity: "Error" | "Warning",
	code: string,
	message: string,
	mapId: string?,
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

function StageSchema.checksumEncoded(encoded: string): string
	local hash = 2_166_136_261
	for index = 1, #encoded do
		hash = bit32.bxor(hash, string.byte(encoded, index))
		-- 16,777,619 = 2^24 + 403. Split the multiplication so every
		-- intermediate remains exactly representable by Luau's number type.
		hash = (bit32.lshift(hash, 24) + hash * 403) % 4_294_967_296
	end
	return string.format("fnv1a32-%08x", hash)
end

function StageSchema.checksum(value: JsonValue): string
	return StageSchema.checksumEncoded(StageSchema.encodeCanonical(value))
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
			stage.schemaVersion = 2
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
		project.schemaVersion = 2
		version = 2
	end
	if version == 2 then
		local legacyIds: { string } = {}
		for id in project.stages do
			table.insert(legacyIds, id)
		end
		table.sort(legacyIds, function(left, right)
			local leftStage = project.stages[left]
			local rightStage = project.stages[right]
			return if leftStage.displayOrder == rightStage.displayOrder
				then left < right
				else leftStage.displayOrder < rightStage.displayOrder
		end)
		for stageNumber, id in legacyIds do
			local stage = project.stages[id]
			StageHierarchy.assign(stage, `stage_group_legacy_{stageNumber}`, stageNumber, 1)
			stage.schemaVersion = 3
		end
		project.schemaVersion = 3
		version = 3
	end
	if version == 3 then
		if project.maps ~= nil and type(project.maps) ~= "table" then
			error("Stagewright project maps must be a table")
		end
		local maps = project.maps or {}
		project.maps = maps
		local existingMapIds = StageHierarchy.mapIds(maps)
		if #existingMapIds > 0 then
			local onlyMapId = if #existingMapIds == 1 then existingMapIds[1] else nil
			local mapHasLevel: { [string]: boolean } = {}
			for order, existingMapId in existingMapIds do
				local map = maps[existingMapId]
				if type(map) ~= "table" then
					error(`Stagewright legacy Map {existingMapId} must be a table`)
				end
				map.id = map.id or existingMapId
				map.name = map.name or `Map {order}`
				map.displayOrder = map.displayOrder or order
				map.backdropImageId = map.backdropImageId or ""
				map.metadata = map.metadata or {}
				mapHasLevel[existingMapId] = false
			end
			for _, stage in project.stages do
				local assignedMapId = if type(stage.mapId) == "string" and stage.mapId ~= ""
					then stage.mapId
					else onlyMapId
				if assignedMapId == nil or maps[assignedMapId] == nil then
					error("Stagewright legacy Map ownership is incomplete")
				end
				stage.mapId = assignedMapId
				stage.schemaVersion = StageSchema.AUTHORING_VERSION
				mapHasLevel[assignedMapId] = true
			end
			for existingMapId, ownsLevel in mapHasLevel do
				if not ownsLevel then
					error(`Stagewright legacy Map {existingMapId} has no Levels`)
				end
			end
		else
			local mapId = StageHierarchy.LEGACY_MAP_ID
			local agreedBackdrop: string? = nil
			local backdropConflict = false
			local metadata = if type(project.metadata) == "table" then project.metadata else nil
			local legacyBackdrops = if metadata ~= nil
					and type(metadata["stagewright.mapBackdrops"]) == "table"
				then metadata["stagewright.mapBackdrops"]
				else nil
			for _, stage in project.stages do
				local address = StageHierarchy.address(stage)
				local value = if legacyBackdrops ~= nil then legacyBackdrops[address.groupId] else nil
				if type(value) == "string" and value ~= "" then
					if agreedBackdrop == nil then
						agreedBackdrop = value
					elseif agreedBackdrop ~= value then
						backdropConflict = true
					end
				end
			end
			maps[mapId] = {
				id = mapId,
				name = "Map 1",
				displayOrder = 1,
				backdropImageId = if backdropConflict then "" else agreedBackdrop or "",
				metadata = if backdropConflict then { ["stagewright.legacyBackdropConflict"] = true } else {},
			}
			for _, stage in project.stages do
				stage.mapId = mapId
				stage.schemaVersion = StageSchema.AUTHORING_VERSION
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

function StageSchema.validateMap(map: any): { Issue }
	local issues: { Issue } = {}
	if type(map) ~= "table" or type(map.id) ~= "string" or map.id == "" or #map.id > 80 then
		return { { severity = "Error", code = "InvalidMap", message = "Map has no valid stable ID" } }
	end
	local mapId = map.id
	if type(map.name) ~= "string" or map.name == "" or #map.name > 120 then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidMapName",
			message = "Map name must contain between 1 and 120 characters",
			mapId = mapId,
		})
	end
	if
		type(map.displayOrder) ~= "number"
		or map.displayOrder % 1 ~= 0
		or map.displayOrder < 1
		or map.displayOrder > 999
	then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidMapOrder",
			message = "Map order must be an integer between 1 and 999",
			mapId = mapId,
		})
	end
	local backdropImageId = map.backdropImageId
	if
		type(backdropImageId) ~= "string"
		or (
			backdropImageId ~= ""
			and string.match(backdropImageId, "^%d+$") == nil
			and string.match(backdropImageId, "^rbxassetid://%d+$") == nil
		)
	then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidMapBackdrop",
			message = "Map backdrop must be blank, digits, or rbxassetid://digits",
			mapId = mapId,
		})
	end
	if type(map.metadata) ~= "table" then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidMapMetadata",
			message = "Map metadata must be a table",
			mapId = mapId,
		})
	else
		local success, encoded = pcall(StageSchema.encodeCanonical, map.metadata)
		if not success or #encoded > 16_384 then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidMapMetadata",
				message = "Map metadata is invalid or exceeds 16384 bytes",
				mapId = mapId,
			})
		end
	end
	return issues
end

function StageSchema.validateStage(stage: any): { Issue }
	local issues: { Issue } = {}
	if type(stage) ~= "table" or type(stage.id) ~= "string" or stage.id == "" then
		return { { severity = "Error", code = "InvalidStage", message = "Stage has no stable ID" } }
	end
	local stageId = stage.id
	local address = StageHierarchy.address(stage)
	if type(stage.mapId) ~= "string" or stage.mapId == "" or #stage.mapId > 80 then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidMapId",
			message = "Level has no valid stable Map ID",
			stageId = stageId,
		})
	end
	if type(stage.stageGroupId) ~= "string" or stage.stageGroupId == "" or #stage.stageGroupId > 80 then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidStageGroupId",
			message = "Level has no valid stable stage-group ID",
			stageId = stageId,
		})
	end
	if
		type(stage.stageNumber) ~= "number"
		or stage.stageNumber ~= address.stageNumber
		or address.stageNumber > 999
	then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidStageNumber",
			message = "Stage number must be an integer between 1 and 999",
			stageId = stageId,
		})
	end
	if
		type(stage.levelNumber) ~= "number"
		or stage.levelNumber ~= address.levelNumber
		or address.levelNumber > 999
	then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidLevelNumber",
			message = "Level number must be an integer between 1 and 999",
			stageId = stageId,
		})
	end
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
		local defaultCell = if type(grid.defaultCell) == "table" then grid.defaultCell else {}
		if type(grid.defaultCell) ~= "table" then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidDefaultCell",
				message = "Stage grid default cell is missing or invalid",
				stageId = stageId,
			})
		else
			if defaultCell.buildPolicy ~= nil and VALID_BUILD_POLICIES[defaultCell.buildPolicy] ~= true then
				table.insert(issues, {
					severity = "Error",
					code = "DefaultBuildPolicy",
					message = "Stage grid default cell has an invalid build policy",
					stageId = stageId,
				})
			end
			if
				defaultCell.enemyTraversalPolicy ~= nil
				and VALID_TRAVERSAL_POLICIES[defaultCell.enemyTraversalPolicy] ~= true
			then
				table.insert(issues, {
					severity = "Error",
					code = "DefaultTraversalPolicy",
					message = "Stage grid default cell has an invalid enemy traversal policy",
					stageId = stageId,
				})
			end
			if defaultCell.roles ~= nil and type(defaultCell.roles) ~= "table" then
				table.insert(issues, {
					severity = "Error",
					code = "DefaultCellRoles",
					message = "Stage grid default roles must be a table",
					stageId = stageId,
				})
			elseif type(defaultCell.roles) == "table" then
				for _, enabled in defaultCell.roles do
					if enabled == true then
						table.insert(issues, {
							severity = "Error",
							code = "DefaultCellRole",
							message = "Cell roles must be authored on explicit cells, not the level default",
							stageId = stageId,
						})
						break
					end
				end
			end
		end
		local cells = if type(grid.cells) == "table" then grid.cells else {}
		if type(grid.cells) ~= "table" then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidCells",
				message = "Stage grid cell overrides are missing or invalid",
				stageId = stageId,
			})
		end
		for key, cell in cells do
			if type(key) ~= "string" or type(cell) ~= "table" then
				table.insert(issues, {
					severity = "Error",
					code = "InvalidCellOverride",
					message = "Stage grid contains an invalid cell override",
					stageId = stageId,
					objectId = if type(key) == "string" then key else nil,
				})
				continue
			end
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
			local authoredRoles = if type(cell.roles) == "table" then cell.roles else {}
			if cell.roles ~= nil and type(cell.roles) ~= "table" then
				table.insert(issues, {
					severity = "Error",
					code = "CellRoles",
					message = `Cell {key} roles must be a table`,
					stageId = stageId,
					objectId = key,
				})
			end
			for role, enabled in authoredRoles do
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
			local resolvedCell = StageCell.resolve(defaultCell, cell)
			local roles = if type(resolvedCell.roles) == "table" then resolvedCell.roles else {}
			local primaryRoleCount = 0
			for _, primaryRole in { "EnemySpawn", "EnemyGoal", "AutoPlace" } do
				if roles[primaryRole] == true then
					primaryRoleCount += 1
				end
			end
			if primaryRoleCount > 1 then
				table.insert(issues, {
					severity = "Error",
					code = "ConflictingPrimaryRoles",
					message = `Cell {key} can only be a spawn, goal, or auto-place cell`,
					stageId = stageId,
					objectId = key,
				})
			end
			if (roles.EnemySpawn or roles.EnemyGoal) and resolvedCell.buildPolicy ~= "Blocked" then
				table.insert(issues, {
					severity = "Error",
					code = "EndpointBuildPolicy",
					message = `Cell {key} spawn/goal role requires Blocked build policy`,
					stageId = stageId,
					objectId = key,
				})
			end
			if roles.AutoPlace and resolvedCell.buildPolicy == "Blocked" then
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
		if type(graph.laneProfiles) ~= "table" then
			table.insert(issues, {
				severity = "Error",
				code = "MissingLaneProfiles",
				message = `Graph {graphId} has no lane profiles`,
				stageId = stageId,
				graphId = graphId,
			})
		else
			for profileId, profile in graph.laneProfiles do
				local offsets = if type(profile) == "table" then profile.offsets else nil
				if type(profile) ~= "table" or profile.id ~= profileId then
					table.insert(issues, {
						severity = "Error",
						code = "LaneProfileIdMismatch",
						message = `Lane profile {profileId} has an invalid stable ID`,
						stageId = stageId,
						graphId = graphId,
						objectId = profileId,
					})
				end
				if
					type(offsets) ~= "table"
					or #offsets < StageLanes.MIN_COUNT
					or #offsets > StageLanes.MAX_COUNT
				then
					table.insert(issues, {
						severity = "Error",
						code = "LaneCount",
						message = `Lane profile {profileId} must define 1, 2, or 3 lanes`,
						stageId = stageId,
						graphId = graphId,
						objectId = profileId,
					})
				else
					local furthestOffset = 0
					for _, offset in offsets do
						if type(offset) ~= "number" or offset ~= offset or math.abs(offset) == math.huge then
							table.insert(issues, {
								severity = "Error",
								code = "LaneOffset",
								message = `Lane profile {profileId} has a non-finite offset`,
								stageId = stageId,
								graphId = graphId,
								objectId = profileId,
							})
						else
							furthestOffset = math.max(furthestOffset, math.abs(offset))
						end
					end
					if
						type(profile.clearanceRadius) ~= "number"
						or profile.clearanceRadius ~= profile.clearanceRadius
						or profile.clearanceRadius < furthestOffset
						or profile.clearanceRadius == math.huge
					then
						table.insert(issues, {
							severity = "Error",
							code = "LaneClearance",
							message = `Lane profile {profileId} clearance must cover every lane offset`,
							stageId = stageId,
							graphId = graphId,
							objectId = profileId,
						})
					end
				end
			end
			for edgeId, edge in graph.edges or {} do
				if graph.laneProfiles[edge.laneProfileId] == nil then
					table.insert(issues, {
						severity = "Error",
						code = "MissingLaneProfile",
						message = `Edge {edgeId} references a missing lane profile`,
						stageId = stageId,
						graphId = graphId,
						objectId = edgeId,
					})
				end
				local metadata = if type(edge.metadata) == "table" then edge.metadata else nil
				local pathAssetId = if metadata ~= nil then metadata.pathAssetId else nil
				if type(pathAssetId) == "string" and not StagePathAssets.isValid(pathAssetId) then
					table.insert(issues, {
						severity = "Warning",
						code = "UnknownPathAsset",
						message = `Edge {edgeId} references unavailable path asset {pathAssetId}; preview uses {StagePathAssets.DEFAULT_ASSET_ID}`,
						stageId = stageId,
						graphId = graphId,
						objectId = edgeId,
					})
				end
			end
		end
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

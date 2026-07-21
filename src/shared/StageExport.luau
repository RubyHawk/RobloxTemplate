--!strict

local StagePath = if script ~= nil then require(script.Parent.StagePath) else require("./StagePath")
local StageCell = if script ~= nil then require(script.Parent.StageCell) else require("./StageCell")
local StageHierarchy = if script ~= nil
	then require(script.Parent.StageHierarchy)
	else require("./StageHierarchy")
local StageSchema = if script ~= nil then require(script.Parent.StageSchema) else require("./StageSchema")
local StageTypes = if script ~= nil then require(script.Parent.StageTypes) else require("./StageTypes")

local StageExport = {}

export type ExportResult = {
	bundle: StageTypes.RuntimeStageBundle?,
	issues: { StageSchema.Issue },
}

local function clone(value: any, seen: { [table]: table }?): any
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	if visited[value] ~= nil then
		return visited[value]
	end
	local result = {}
	visited[value] = result
	for key, child in value do
		result[clone(key, visited)] = clone(child, visited)
	end
	return result
end

local function copyFields(source: any, fields: { string }): any
	local result = {}
	for _, field in fields do
		if source[field] ~= nil then
			result[field] = clone(source[field])
		end
	end
	return result
end

local function copyArray<T>(source: { T }): { T }
	local result: { T } = {}
	for index = 1, #source do
		result[index] = clone(source[index])
	end
	return result
end

local PREDICATE_FIELDS: { [string]: { string } } = {
	WaveRange = { "kind", "minimum", "maximum" },
	StageFlagEquals = { "kind", "key", "value" },
	EnemyTag = { "kind", "tag" },
	VisitCountBelow = { "kind", "nodeId", "maximum" },
	StageUnlocked = { "kind", "stageId" },
	UpgradeLevelAtLeast = { "kind", "upgradeId", "level" },
	CurrencyAtLeast = { "kind", "currencyId", "amount" },
}

local UNLOCK_REQUIREMENT_FIELDS: { [string]: { string } } = {
	StageUnlocked = PREDICATE_FIELDS.StageUnlocked,
	UpgradeLevelAtLeast = PREDICATE_FIELDS.UpgradeLevelAtLeast,
	CurrencyAtLeast = PREDICATE_FIELDS.CurrencyAtLeast,
}

local function projectPredicate(predicate: any): StageTypes.RoutePredicate
	local fields = PREDICATE_FIELDS[predicate.kind]
	assert(fields ~= nil, `Cannot project unknown Stagewright predicate {tostring(predicate.kind)}`)
	return copyFields(predicate, fields) :: StageTypes.RoutePredicate
end

local function projectUnlockRequirement(requirement: any): StageTypes.StageUnlockPredicate
	local fields = UNLOCK_REQUIREMENT_FIELDS[requirement.kind]
	assert(
		fields ~= nil,
		`Cannot project unknown Stagewright unlock requirement {tostring(requirement.kind)}`
	)
	return copyFields(requirement, fields) :: StageTypes.StageUnlockPredicate
end

local function projectCell(cell: any): StageTypes.CellOverride
	return copyFields(cell, {
		"terrainId",
		"buildPolicy",
		"enemyTraversalPolicy",
		"roles",
		"metadata",
	}) :: StageTypes.CellOverride
end

local function projectGrid(grid: any): StageTypes.GridDefinition
	local cells: { [string]: StageTypes.CellOverride } = {}
	for key, cell in grid.cells do
		cells[key] = projectCell(cell)
	end
	return {
		columns = grid.columns,
		rows = grid.rows,
		cellSize = grid.cellSize,
		defaultCell = projectCell(grid.defaultCell),
		cells = cells,
	}
end

local function projectNode(node: any): StageTypes.PathNode
	return {
		id = node.id,
		name = node.name,
		kind = node.kind,
		position = copyFields(node.position, { "x", "y", "z" }),
		tags = copyArray(node.tags),
	}
end

local function projectEdge(edge: any): StageTypes.PathEdge
	local predicates: { StageTypes.RoutePredicate } = {}
	for index = 1, #edge.predicates do
		predicates[index] = projectPredicate(edge.predicates[index])
	end
	return {
		id = edge.id,
		fromNodeId = edge.fromNodeId,
		toNodeId = edge.toNodeId,
		outHandleOffset = copyFields(edge.outHandleOffset, { "x", "y", "z" }),
		inHandleOffset = copyFields(edge.inHandleOffset, { "x", "y", "z" }),
		laneProfileId = edge.laneProfileId,
		priority = edge.priority,
		predicates = predicates,
		metadata = clone(edge.metadata),
	}
end

local function projectGraph(graph: any): StageTypes.PathGraphDefinition
	local nodes: { [string]: StageTypes.PathNode } = {}
	for nodeId, node in graph.nodes do
		nodes[nodeId] = projectNode(node)
	end
	local edges: { [string]: StageTypes.PathEdge } = {}
	for edgeId, edge in graph.edges do
		edges[edgeId] = projectEdge(edge)
	end
	local laneProfiles: { [string]: StageTypes.LaneProfile } = {}
	for profileId, profile in graph.laneProfiles do
		laneProfiles[profileId] = {
			id = profile.id,
			offsets = copyArray(profile.offsets),
			clearanceRadius = profile.clearanceRadius,
		}
	end
	return {
		id = graph.id,
		name = graph.name,
		nodes = nodes,
		edges = edges,
		laneProfiles = laneProfiles,
		maxNodeVisitsPerEnemy = graph.maxNodeVisitsPerEnemy,
		maxTravelDistance = graph.maxTravelDistance,
	}
end

local function projectMap(map: any): StageTypes.RuntimeMapDefinition
	return {
		id = map.id,
		name = map.name,
		displayOrder = map.displayOrder,
		metadata = clone(map.metadata),
	}
end

local ENEMY_TYPE_FIELDS =
	{ "id", "name", "tags", "health", "speed", "reward", "baseDamage", "modelId", "renderScale", "tint" }
local WAVE_ENTRY_FIELDS = {
	"enemyTypeId",
	"count",
	"spacingSeconds",
	"startDelaySeconds",
	"healthScale",
	"rewardScale",
	"speedScale",
}

local function projectEnemyType(enemyType: any): StageTypes.EnemyTypeDefinition
	return copyFields(enemyType, ENEMY_TYPE_FIELDS) :: StageTypes.EnemyTypeDefinition
end

local function projectWaveSet(waveSet: any): StageTypes.WaveSetDefinition
	local waves: { StageTypes.WaveDefinition } = {}
	for index = 1, #waveSet.waves do
		local wave = waveSet.waves[index]
		local entries: { StageTypes.WaveEntryDefinition } = {}
		for entryIndex = 1, #wave.entries do
			entries[entryIndex] =
				copyFields(wave.entries[entryIndex], WAVE_ENTRY_FIELDS) :: StageTypes.WaveEntryDefinition
		end
		local projected: StageTypes.WaveDefinition = { entries = entries }
		if wave.isBoss ~= nil then
			projected.isBoss = wave.isBoss
		end
		waves[index] = projected
	end
	return {
		id = waveSet.id,
		name = waveSet.name,
		waves = waves,
	}
end

local function sortedIds(registry: { [string]: any }): { string }
	local ids: { string } = {}
	for id in registry do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function projectStage(stage: any): StageTypes.StageDefinition
	local pathGraphs: { [string]: StageTypes.PathGraphDefinition } = {}
	for graphId, graph in stage.pathGraphs do
		pathGraphs[graphId] = projectGraph(graph)
	end
	local unlockRequirements: { StageTypes.StageUnlockPredicate } = {}
	for index = 1, #stage.unlockRequirements do
		unlockRequirements[index] = projectUnlockRequirement(stage.unlockRequirements[index])
	end
	return {
		schemaVersion = StageSchema.RUNTIME_VERSION,
		id = stage.id,
		mapId = stage.mapId,
		stageGroupId = stage.stageGroupId,
		stageNumber = stage.stageNumber,
		levelNumber = stage.levelNumber,
		name = stage.name,
		displayOrder = stage.displayOrder,
		grid = projectGrid(stage.grid),
		pathGraphs = pathGraphs,
		waveSetId = stage.waveSetId,
		themeId = stage.themeId,
		modifierIds = copyArray(stage.modifierIds),
		unlockRequirements = unlockRequirements,
		metadata = clone(stage.metadata),
	}
end

local function add(left: any, right: any): any
	return { x = left.x + right.x, y = left.y + right.y, z = left.z + right.z }
end

local function bakeGraph(graph: any)
	local outgoingEdgeIds: { [string]: { string } } = {}
	for edgeId, edge in graph.edges do
		local fromNode = graph.nodes[edge.fromNodeId]
		local toNode = graph.nodes[edge.toNodeId]
		if fromNode ~= nil and toNode ~= nil then
			local samples, length = StagePath.bake(
				fromNode.position,
				add(fromNode.position, edge.outHandleOffset),
				add(toNode.position, edge.inHandleOffset),
				toNode.position,
				{
					maximumChordError = 0.08,
					maximumSegmentLength = 1.5,
					maximumTurnAngleDegrees = 8,
					maximumDepth = 12,
				}
			)
			edge.samples = samples
			edge.length = length
			local outgoing = outgoingEdgeIds[edge.fromNodeId]
			if outgoing == nil then
				outgoing = {}
				outgoingEdgeIds[edge.fromNodeId] = outgoing
			end
			table.insert(outgoing, edgeId)
		end
	end
	for _, edgeIds in outgoingEdgeIds do
		table.sort(edgeIds, function(leftId, rightId)
			local left = graph.edges[leftId]
			local right = graph.edges[rightId]
			return if left.priority == right.priority
				then leftId < rightId
				else left.priority < right.priority
		end)
	end
	graph.outgoingEdgeIds = outgoingEdgeIds
end

local function routeMask(stage: any): { [string]: boolean }
	local mask: { [string]: boolean } = {}
	local grid = stage.grid
	for _, graph in stage.pathGraphs do
		for _, edge in graph.edges do
			local laneProfile = graph.laneProfiles[edge.laneProfileId]
			local radius = if laneProfile ~= nil then laneProfile.clearanceRadius else 0
			local cellRadius = math.max(math.ceil(radius / grid.cellSize), 0)
			for _, sample in edge.samples or {} do
				local column = math.floor(
					(sample.position.x + grid.columns * grid.cellSize * 0.5) / grid.cellSize
				) + 1
				local row = math.floor((sample.position.z + grid.rows * grid.cellSize * 0.5) / grid.cellSize)
					+ 1
				for offsetColumn = -cellRadius, cellRadius do
					for offsetRow = -cellRadius, cellRadius do
						local nextColumn = column + offsetColumn
						local nextRow = row + offsetRow
						if
							nextColumn >= 1
							and nextColumn <= grid.columns
							and nextRow >= 1
							and nextRow <= grid.rows
						then
							mask[StageSchema.cellKey(nextColumn, nextRow)] = true
						end
					end
				end
			end
		end
	end
	return mask
end

local function validateStageReferences(
	project: any,
	stageId: string,
	stage: any,
	issues: { StageSchema.Issue }
)
	if type(stage.waveSetId) ~= "string" or stage.waveSetId == "" then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidWaveSetId",
			message = "Level wave set ID must be a non-empty string",
			mapId = if type(stage.mapId) == "string" then stage.mapId else nil,
			stageId = stageId,
		})
	elseif type(project.waveSets) ~= "table" or project.waveSets[stage.waveSetId] == nil then
		table.insert(issues, {
			severity = "Error",
			code = "MissingWaveSet",
			message = `Level references missing wave set {stage.waveSetId}`,
			mapId = if type(stage.mapId) == "string" then stage.mapId else nil,
			stageId = stageId,
			objectId = stage.waveSetId,
		})
	end
	if type(stage.unlockRequirements) == "table" then
		for index = 1, #stage.unlockRequirements do
			local requirement = stage.unlockRequirements[index]
			if
				type(requirement) == "table"
				and requirement.kind == "StageUnlocked"
				and type(requirement.stageId) == "string"
				and project.stages[requirement.stageId] == nil
			then
				table.insert(issues, {
					severity = "Error",
					code = "DanglingStageReference",
					message = `Level unlock requirement {index} references missing Level {requirement.stageId}`,
					mapId = if type(stage.mapId) == "string" then stage.mapId else nil,
					stageId = stageId,
					objectId = requirement.stageId,
				})
			end
		end
	end
	if type(stage.pathGraphs) ~= "table" then
		return
	end
	for graphId, graph in stage.pathGraphs do
		if type(graph) == "table" and type(graph.edges) == "table" then
			for edgeId, edge in graph.edges do
				if type(edge) == "table" and type(edge.predicates) == "table" then
					for index = 1, #edge.predicates do
						local predicate = edge.predicates[index]
						if
							type(predicate) == "table"
							and predicate.kind == "StageUnlocked"
							and type(predicate.stageId) == "string"
							and project.stages[predicate.stageId] == nil
						then
							table.insert(issues, {
								severity = "Error",
								code = "DanglingStageReference",
								message = `Edge {tostring(edgeId)} StageUnlocked predicate {index} references missing Level {predicate.stageId}`,
								mapId = if type(stage.mapId) == "string" then stage.mapId else nil,
								stageId = stageId,
								graphId = if type(graphId) == "string" then graphId else nil,
								objectId = if type(edgeId) == "string" then edgeId else nil,
							})
						end
					end
				end
			end
		end
	end
end

-- Builds the exact route data used by runtime export without requiring the
-- entire project to validate. Editor previews must stay available while a
-- designer is fixing invalid cells, predicates, or catalog references.
function StageExport.preview(stage: StageTypes.StageDefinition): StageTypes.StagePreviewDefinition?
	if type(stage) ~= "table" or type(stage.grid) ~= "table" or type(stage.pathGraphs) ~= "table" then
		return nil
	end
	local preview = clone(stage)
	for _, graph in preview.pathGraphs do
		if type(graph) == "table" and type(graph.nodes) == "table" and type(graph.edges) == "table" then
			pcall(bakeGraph, graph)
		end
	end
	preview.routeNoBuildMask = routeMask(preview)
	return preview :: StageTypes.StagePreviewDefinition
end

function StageExport.bake(project: any): ExportResult
	local issues: { StageSchema.Issue } = {}
	if type(project) ~= "table" or type(project.maps) ~= "table" or type(project.stages) ~= "table" then
		return {
			bundle = nil,
			issues = {
				{
					severity = "Error",
					code = "InvalidProject",
					message = "Project has no valid Map or Level registry",
				},
			},
		}
	end
	if type(project.startingStageId) ~= "string" or project.stages[project.startingStageId] == nil then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidStartingStage",
			message = `Starting stage {tostring(project.startingStageId)} does not reference an exported stage`,
		})
	end
	local mapIds = StageHierarchy.mapIds(project.maps)
	local mapOrderKeys: { [number]: string } = {}
	local levelCountByMap: { [string]: number } = {}
	for mapId, map in project.maps do
		if type(mapId) ~= "string" then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidMapKey",
				message = "Every Map registry key must be a string",
			})
		elseif type(map) ~= "table" or map.id ~= mapId then
			table.insert(issues, {
				severity = "Error",
				code = "MapIdMismatch",
				message = `Map registry key {mapId} does not match Map ID {tostring(
					if type(map) == "table" then map.id else nil
				)}`,
				mapId = mapId,
			})
		else
			levelCountByMap[mapId] = 0
			for _, issue in StageSchema.validateMap(map) do
				table.insert(issues, issue)
			end
			if
				type(map.displayOrder) == "number"
				and map.displayOrder == map.displayOrder
				and math.abs(map.displayOrder) < math.huge
				and map.displayOrder % 1 == 0
			then
				local existingMapId = mapOrderKeys[map.displayOrder]
				if existingMapId ~= nil and existingMapId ~= mapId then
					table.insert(issues, {
						severity = "Error",
						code = "DuplicateMapOrder",
						message = `Map order {map.displayOrder} is used by more than one Map`,
						mapId = mapId,
					})
				end
				mapOrderKeys[map.displayOrder] = mapId
			end
			if
				type(map.metadata) == "table"
				and map.metadata["stagewright.legacyBackdropConflict"] == true
			then
				table.insert(issues, {
					severity = "Warning",
					code = "LegacyBackdropConflict",
					message = "Legacy Stages used different backdrop images; choose one backdrop in Map Properties",
					mapId = mapId,
				})
			end
		end
	end
	if #mapIds == 0 then
		table.insert(issues, {
			severity = "Error",
			code = "MissingMap",
			message = "Project must contain at least one Map",
		})
	end

	local enemyTypeIds: { [string]: boolean } = {}
	if type(project.enemyTypes) ~= "table" or next(project.enemyTypes) == nil then
		table.insert(issues, {
			severity = "Error",
			code = "MissingEnemyTypes",
			message = "Project must define at least one enemy type",
		})
	else
		for enemyTypeId, enemyType in project.enemyTypes do
			if type(enemyTypeId) ~= "string" then
				table.insert(issues, {
					severity = "Error",
					code = "InvalidEnemyTypeKey",
					message = "Every enemy type registry key must be a string",
				})
			elseif type(enemyType) ~= "table" or enemyType.id ~= enemyTypeId then
				table.insert(issues, {
					severity = "Error",
					code = "EnemyTypeIdMismatch",
					message = `Enemy type registry key {enemyTypeId} does not match enemy type ID {tostring(
						if type(enemyType) == "table" then enemyType.id else nil
					)}`,
					objectId = enemyTypeId,
				})
			else
				enemyTypeIds[enemyTypeId] = true
				for _, issue in StageSchema.validateEnemyType(enemyType) do
					table.insert(issues, issue)
				end
			end
		end
	end
	if type(project.waveSets) ~= "table" or next(project.waveSets) == nil then
		table.insert(issues, {
			severity = "Error",
			code = "MissingWaveSets",
			message = "Project must define at least one wave set",
		})
	else
		if type(project.waveSets.default) ~= "table" then
			table.insert(issues, {
				severity = "Error",
				code = "MissingDefaultWaveSet",
				message = "Project must define the default wave set",
			})
		end
		for waveSetId, waveSet in project.waveSets do
			if type(waveSetId) ~= "string" then
				table.insert(issues, {
					severity = "Error",
					code = "InvalidWaveSetKey",
					message = "Every wave set registry key must be a string",
				})
			elseif type(waveSet) ~= "table" or waveSet.id ~= waveSetId then
				table.insert(issues, {
					severity = "Error",
					code = "WaveSetIdMismatch",
					message = `Wave set registry key {waveSetId} does not match wave set ID {tostring(
						if type(waveSet) == "table" then waveSet.id else nil
					)}`,
					objectId = waveSetId,
				})
			else
				for _, issue in StageSchema.validateWaveSet(waveSet, enemyTypeIds) do
					table.insert(issues, issue)
				end
			end
		end
	end

	local stageIds: { string } = {}
	local groupByNumber: { [string]: string } = {}
	local numberByGroup: { [string]: string } = {}
	local mapByGroup: { [string]: string } = {}
	local levelKeys: { [string]: string } = {}
	for stageId, stage in project.stages do
		if stage.id ~= stageId then
			table.insert(issues, {
				severity = "Error",
				code = "StageIdMismatch",
				message = `Stage map key {stageId} does not match stage ID {tostring(stage.id)}`,
				stageId = stageId,
			})
		end
		local validationStage = clone(stage)
		for _, graph in validationStage.pathGraphs or {} do
			if type(graph) == "table" then
				graph.outgoingEdgeIds = nil
				for _, edge in graph.edges or {} do
					if type(edge) == "table" and type(edge.predicates) == "table" then
						edge.predicates = copyArray(edge.predicates)
					end
				end
				for _, profile in graph.laneProfiles or {} do
					if type(profile) == "table" and type(profile.offsets) == "table" then
						profile.offsets = copyArray(profile.offsets)
					end
				end
			end
		end
		for _, issue in StageSchema.validateStage(validationStage) do
			table.insert(issues, issue)
		end
		validateStageReferences(project, stageId, stage, issues)
		if type(stage.unlockRequirements) ~= "table" then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidUnlockRequirements",
				message = "Level unlock requirements must be an array",
				stageId = stageId,
			})
		else
			for index = 1, #stage.unlockRequirements do
				local requirement = stage.unlockRequirements[index]
				if type(requirement) ~= "table" or UNLOCK_REQUIREMENT_FIELDS[requirement.kind] == nil then
					table.insert(issues, {
						severity = "Error",
						code = "InvalidUnlockRequirement",
						message = `Level unlock requirement {index} has an unsupported kind`,
						stageId = stageId,
					})
				end
			end
		end
		local address = StageHierarchy.address(stage)
		if project.maps[address.mapId] == nil then
			table.insert(issues, {
				severity = "Error",
				code = "MissingMap",
				message = `Level references missing Map {address.mapId}`,
				mapId = address.mapId,
				stageId = stageId,
			})
		else
			levelCountByMap[address.mapId] = (levelCountByMap[address.mapId] or 0) + 1
		end
		local stageNumberKey = `{address.mapId}:{address.stageNumber}`
		local existingGroup = groupByNumber[stageNumberKey]
		local existingNumber = numberByGroup[address.groupId]
		local existingMap = mapByGroup[address.groupId]
		local levelKey = `{address.groupId}:{address.levelNumber}`
		if existingGroup ~= nil and existingGroup ~= address.groupId then
			table.insert(issues, {
				severity = "Error",
				code = "DuplicateStageNumber",
				message = `Map {address.mapId} Stage number {address.stageNumber} belongs to more than one stable group`,
				mapId = address.mapId,
				stageId = stageId,
			})
		elseif existingMap ~= nil and existingMap ~= address.mapId then
			table.insert(issues, {
				severity = "Error",
				code = "StageSharedAcrossMaps",
				message = `Stage group {address.groupId} belongs to more than one Map`,
				mapId = address.mapId,
				stageId = stageId,
			})
		elseif existingNumber ~= nil and existingNumber ~= stageNumberKey then
			table.insert(issues, {
				severity = "Error",
				code = "StageGroupNumberMismatch",
				message = `Stage group {address.groupId} uses more than one Map or display number`,
				mapId = address.mapId,
				stageId = stageId,
			})
		elseif levelKeys[levelKey] ~= nil then
			table.insert(issues, {
				severity = "Error",
				code = "DuplicateLevelNumber",
				message = `Stage {address.stageNumber} has more than one Level {address.levelNumber}`,
				stageId = stageId,
			})
		end
		groupByNumber[stageNumberKey] = address.groupId
		numberByGroup[address.groupId] = stageNumberKey
		mapByGroup[address.groupId] = address.mapId
		levelKeys[levelKey] = stageId
		table.insert(stageIds, stageId)
	end
	for mapId, levelCount in levelCountByMap do
		if levelCount == 0 then
			table.insert(issues, {
				severity = "Error",
				code = "OrphanMap",
				message = `Map {mapId} must contain at least one Level`,
				mapId = mapId,
			})
		end
	end
	if StageSchema.hasErrors(issues) then
		return { bundle = nil, issues = issues }
	end
	table.sort(stageIds, function(left, right)
		return StageHierarchy.less(project.stages[left], project.stages[right], project.maps)
	end)
	local maps: { [string]: StageTypes.RuntimeMapDefinition } = {}
	for _, mapId in mapIds do
		maps[mapId] = projectMap(project.maps[mapId])
	end
	local stages: { [string]: any } = {}
	for _, stageId in stageIds do
		local stage: any = projectStage(project.stages[stageId])
		for graphId, graph in stage.pathGraphs do
			bakeGraph(graph)
			for edgeId, edge in graph.edges do
				if edge.length < 0.01 then
					table.insert(issues, {
						severity = "Error",
						code = "ZeroLengthEdge",
						message = `Edge {edgeId} has no traversable length`,
						stageId = stageId,
						graphId = graphId,
						objectId = edgeId,
					})
				end
				for _, sample in edge.samples do
					if math.abs(sample.tangent.y) > 0.9 then
						table.insert(issues, {
							severity = "Warning",
							code = "SteepEdge",
							message = `Edge {edgeId} contains a near-vertical segment`,
							stageId = stageId,
							graphId = graphId,
							objectId = edgeId,
						})
						break
					end
				end
			end
		end
		stage.routeNoBuildMask = routeMask(stage)
		for key in stage.routeNoBuildMask do
			local cell = StageCell.resolve(stage.grid.defaultCell, stage.grid.cells[key])
			if cell.enemyTraversalPolicy == "Blocked" then
				table.insert(issues, {
					severity = "Error",
					code = "RouteTraversalConflict",
					message = `Route corridor crosses enemy-blocked cell {key}`,
					stageId = stageId,
					objectId = key,
				})
			end
		end
		stage.checksum = nil
		stage.checksum = StageSchema.checksum(stage)
		stages[stageId] = stage
	end
	local enemyTypeOrder = sortedIds(project.enemyTypes)
	local enemyTypes: { [string]: StageTypes.EnemyTypeDefinition } = {}
	for _, enemyTypeId in enemyTypeOrder do
		enemyTypes[enemyTypeId] = projectEnemyType(project.enemyTypes[enemyTypeId])
	end
	local waveSetOrder = sortedIds(project.waveSets)
	local waveSets: { [string]: StageTypes.WaveSetDefinition } = {}
	for _, waveSetId in waveSetOrder do
		waveSets[waveSetId] = projectWaveSet(project.waveSets[waveSetId])
	end
	local bundle = {
		schemaVersion = StageSchema.RUNTIME_VERSION,
		sourceSchemaVersion = project.schemaVersion,
		startingStageId = project.startingStageId,
		mapOrder = mapIds,
		maps = maps,
		stageOrder = stageIds,
		stages = stages,
		enemyTypeOrder = enemyTypeOrder,
		enemyTypes = enemyTypes,
		waveSetOrder = waveSetOrder,
		waveSets = waveSets,
	}
	bundle.checksum = StageSchema.checksum(bundle)
	return {
		bundle = if StageSchema.hasErrors(issues) then nil else bundle :: StageTypes.RuntimeStageBundle,
		issues = issues,
	}
end

return table.freeze(StageExport)

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
	if type(project) ~= "table" or type(project.stages) ~= "table" then
		return {
			bundle = nil,
			issues = { { severity = "Error", code = "InvalidProject", message = "Project has no stages" } },
		}
	end
	if type(project.startingStageId) ~= "string" or project.stages[project.startingStageId] == nil then
		table.insert(issues, {
			severity = "Error",
			code = "InvalidStartingStage",
			message = `Starting stage {tostring(project.startingStageId)} does not reference an exported stage`,
		})
	end
	local stageIds: { string } = {}
	local groupByNumber: { [number]: string } = {}
	local numberByGroup: { [string]: number } = {}
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
		local existingGroup = groupByNumber[address.stageNumber]
		local existingNumber = numberByGroup[address.groupId]
		local levelKey = `{address.groupId}:{address.levelNumber}`
		if existingGroup ~= nil and existingGroup ~= address.groupId then
			table.insert(issues, {
				severity = "Error",
				code = "DuplicateStageNumber",
				message = `Stage number {address.stageNumber} belongs to more than one stable group`,
				stageId = stageId,
			})
		elseif existingNumber ~= nil and existingNumber ~= address.stageNumber then
			table.insert(issues, {
				severity = "Error",
				code = "StageGroupNumberMismatch",
				message = `Stage group {address.groupId} uses more than one display number`,
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
		groupByNumber[address.stageNumber] = address.groupId
		numberByGroup[address.groupId] = address.stageNumber
		levelKeys[levelKey] = stageId
		table.insert(stageIds, stageId)
	end
	if StageSchema.hasErrors(issues) then
		return { bundle = nil, issues = issues }
	end
	table.sort(stageIds, function(left, right)
		return StageHierarchy.less(project.stages[left], project.stages[right])
	end)
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
	local bundle = {
		schemaVersion = StageSchema.RUNTIME_VERSION,
		sourceSchemaVersion = project.schemaVersion,
		startingStageId = project.startingStageId,
		stageOrder = stageIds,
		stages = stages,
	}
	bundle.checksum = StageSchema.checksum(bundle)
	return {
		bundle = if StageSchema.hasErrors(issues) then nil else bundle :: StageTypes.RuntimeStageBundle,
		issues = issues,
	}
end

return table.freeze(StageExport)

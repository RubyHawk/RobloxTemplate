--!strict

local StagePath = if script ~= nil then require(script.Parent.StagePath) else require("./StagePath")
local StageSchema = if script ~= nil then require(script.Parent.StageSchema) else require("./StageSchema")

local StageExport = {}

export type ExportResult = {
	bundle: any?,
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

function StageExport.bake(project: any): ExportResult
	local issues: { StageSchema.Issue } = {}
	if type(project) ~= "table" or type(project.stages) ~= "table" then
		return {
			bundle = nil,
			issues = { { severity = "Error", code = "InvalidProject", message = "Project has no stages" } },
		}
	end
	local stageIds: { string } = {}
	for stageId, stage in project.stages do
		if stage.id ~= stageId then
			table.insert(issues, {
				severity = "Error",
				code = "StageIdMismatch",
				message = `Stage map key {stageId} does not match stage ID {tostring(stage.id)}`,
				stageId = stageId,
			})
		end
		for _, issue in StageSchema.validateStage(stage) do
			table.insert(issues, issue)
		end
		table.insert(stageIds, stageId)
	end
	if StageSchema.hasErrors(issues) then
		return { bundle = nil, issues = issues }
	end
	table.sort(stageIds, function(left, right)
		local leftStage = project.stages[left]
		local rightStage = project.stages[right]
		return if leftStage.displayOrder == rightStage.displayOrder
			then left < right
			else leftStage.displayOrder < rightStage.displayOrder
	end)
	local stages: { [string]: any } = {}
	for _, stageId in stageIds do
		local stage = clone(project.stages[stageId])
		stage.schemaVersion = StageSchema.RUNTIME_VERSION
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
			local cell = stage.grid.cells[key]
			if cell ~= nil and cell.enemyTraversalPolicy == "Blocked" then
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
	return { bundle = if StageSchema.hasErrors(issues) then nil else bundle, issues = issues }
end

return table.freeze(StageExport)

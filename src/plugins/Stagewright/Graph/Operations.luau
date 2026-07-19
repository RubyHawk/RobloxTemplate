--!strict

local HttpService = if script ~= nil then game:GetService("HttpService") else nil

local StageLanes = if script ~= nil
	then require(script.Parent.Parent.Shared.StageLanes)
	else require("../../../shared/StageLanes")

local Operations = {}

local DEFAULT_LANE_WIDTH = 4
local fallbackGuid = 0

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function finiteNumber(value: any, fallback: number): number
	return if isFiniteNumber(value) then value else fallback
end

local function edgeMetadata(edge: any): any
	local metadata = edge.metadata
	if type(metadata) ~= "table" then
		metadata = {}
		edge.metadata = metadata
	end
	metadata.pathAssetId = if type(metadata.pathAssetId) == "string" then metadata.pathAssetId else "gravel"
	metadata.curveMode = if type(metadata.curveMode) == "string" then metadata.curveMode else "Free"
	metadata.surfaceMode = if type(metadata.surfaceMode) == "string"
		then metadata.surfaceMode
		else "FollowTerrain"
	metadata.laneWidth = math.clamp(finiteNumber(metadata.laneWidth, DEFAULT_LANE_WIDTH), 2, 12)
	return metadata
end

local function cloneValue(source: any, seen: { [any]: any }?): any
	if type(source) ~= "table" then
		return source
	end
	local visited = seen or {}
	local existing = visited[source]
	if existing ~= nil then
		return existing
	end
	local result = {}
	visited[source] = result
	for key, value in source do
		result[cloneValue(key, visited)] = cloneValue(value, visited)
	end
	return result
end

local function cloneDictionary(source: any): any
	return if type(source) == "table" then cloneValue(source) else {}
end

local function clonePredicates(source: any): { any }
	local result: { any } = {}
	if type(source) == "table" then
		for _, predicate in source do
			table.insert(result, cloneDictionary(predicate))
		end
	end
	return result
end

local function add(left: any, right: any): any
	return {
		x = left.x + right.x,
		y = left.y + right.y,
		z = left.z + right.z,
	}
end

local function subtract(left: any, right: any): any
	return {
		x = left.x - right.x,
		y = left.y - right.y,
		z = left.z - right.z,
	}
end

local function midpoint(left: any, right: any): any
	return {
		x = (left.x + right.x) * 0.5,
		y = (left.y + right.y) * 0.5,
		z = (left.z + right.z) * 0.5,
	}
end

local function profileLaneWidth(edge: any): number
	return edgeMetadata(edge).laneWidth
end

local function furthestLaneOffset(profile: any): number
	local furthest = 0
	for _, offset in profile.offsets do
		furthest = math.max(furthest, math.abs(offset))
	end
	return furthest
end

local function authoredShoulder(profile: any, laneWidth: number): number
	local clearance = finiteNumber(profile.clearanceRadius, laneWidth * 0.5)
	return math.max(clearance - furthestLaneOffset(profile), laneWidth * 0.5)
end

local function offsetsEqual(left: { number }, right: { number }): boolean
	if #left ~= #right then
		return false
	end
	for index, value in left do
		if value ~= right[index] then
			return false
		end
	end
	return true
end

local function vectorMagnitude(vector: any): number
	return math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
end

local function oppositeWithLength(vector: any, length: number): any
	local magnitude = vectorMagnitude(vector)
	if magnitude <= 1e-6 or length <= 1e-6 then
		return { x = -vector.x, y = -vector.y, z = -vector.z }
	end
	local scale = -length / magnitude
	return { x = vector.x * scale, y = vector.y * scale, z = vector.z * scale }
end

local function constrainedOpposite(primary: any, counterpart: any, curveMode: string): any
	if curveMode == "Mirrored" then
		return { x = -primary.x, y = -primary.y, z = -primary.z }
	elseif curveMode == "Smooth" then
		return oppositeWithLength(primary, vectorMagnitude(counterpart))
	end
	return counterpart
end

local function guid(prefix: string): string
	if HttpService ~= nil then
		return `{prefix}_{string.lower(HttpService:GenerateGUID(false))}`
	end
	fallbackGuid += 1
	return `{prefix}_test_{fallbackGuid}`
end

local function deltaBetween(from: any, to: any, divisor: number): any
	return {
		x = (to.position.x - from.position.x) / divisor,
		y = (to.position.y - from.position.y) / divisor,
		z = (to.position.z - from.position.z) / divisor,
	}
end

local function independentLaneProfile(graph: any, edge: any): any?
	local profile = graph.laneProfiles[edge.laneProfileId]
	if profile == nil then
		return nil
	end
	local references = 0
	for _, candidate in graph.edges do
		if candidate.laneProfileId == edge.laneProfileId then
			references += 1
		end
	end
	if references <= 1 then
		return profile
	end
	local profileId = guid("lane")
	local clone = cloneDictionary(profile)
	clone.id = profileId
	clone.offsets = table.clone(profile.offsets)
	graph.laneProfiles[profileId] = clone
	edge.laneProfileId = profileId
	return clone
end

function Operations.addNode(graph: any, kind: string, requestedPosition: any?): string
	local id = guid("node")
	local count = 0
	for _ in graph.nodes do
		count += 1
	end
	graph.nodes[id] = {
		id = id,
		name = `{kind} {count + 1}`,
		kind = kind,
		position = requestedPosition or { x = (count - 1) * 8, y = 2, z = 0 },
		tags = {},
	}
	return id
end

function Operations.moveNode(graph: any, nodeId: string, position: any): boolean
	local node = graph.nodes[nodeId]
	if node == nil then
		return false
	end
	node.position = {
		x = position.x,
		y = node.position.y,
		z = position.z,
	}
	return true
end

function Operations.moveHandle(graph: any, edgeId: string, handleId: string, position: any): boolean
	if handleId ~= "Out" and handleId ~= "In" then
		return false
	end
	local edge = graph.edges[edgeId]
	if edge == nil then
		return false
	end
	local anchorNode = graph.nodes[if handleId == "Out" then edge.fromNodeId else edge.toNodeId]
	if anchorNode == nil then
		return false
	end
	local offset = if handleId == "Out" then edge.outHandleOffset else edge.inHandleOffset
	return Operations.setHandleOffset(graph, edgeId, handleId, {
		x = position.x - anchorNode.position.x,
		y = offset.y,
		z = position.z - anchorNode.position.z,
	})
end

function Operations.setHandleOffset(graph: any, edgeId: string, handleId: string, offset: any): boolean
	if handleId ~= "Out" and handleId ~= "In" then
		return false
	end
	local edge = graph.edges[edgeId]
	if
		edge == nil
		or type(offset) ~= "table"
		or not isFiniteNumber(offset.x)
		or not isFiniteNumber(offset.y)
		or not isFiniteNumber(offset.z)
	then
		return false
	end
	local nextOffset = { x = offset.x, y = offset.y, z = offset.z }
	local curveMode = edgeMetadata(edge).curveMode
	if handleId == "Out" then
		edge.outHandleOffset = nextOffset
		edge.inHandleOffset = constrainedOpposite(nextOffset, edge.inHandleOffset, curveMode)
	else
		edge.inHandleOffset = nextOffset
		edge.outHandleOffset = constrainedOpposite(nextOffset, edge.outHandleOffset, curveMode)
	end
	return true
end

function Operations.canConnect(graph: any, fromId: string, toId: string): boolean
	if fromId == toId then
		return false
	end
	local from = graph.nodes[fromId]
	local to = graph.nodes[toId]
	if from == nil or to == nil then
		return false
	end
	if from.kind == "Goal" or to.kind == "Spawn" then
		return false
	end
	return true
end

function Operations.connect(graph: any, fromId: string, toId: string): string?
	if not Operations.canConnect(graph, fromId, toId) then
		return nil
	end
	local from = graph.nodes[fromId]
	local to = graph.nodes[toId]
	local edgeId = guid("edge")
	local laneProfileId = guid("lane")
	local delta = deltaBetween(from, to, 3)
	graph.edges[edgeId] = {
		id = edgeId,
		fromNodeId = fromId,
		toNodeId = toId,
		outHandleOffset = delta,
		inHandleOffset = { x = -delta.x, y = -delta.y, z = -delta.z },
		laneProfileId = laneProfileId,
		metadata = {
			pathAssetId = "gravel",
			curveMode = "Smooth",
			surfaceMode = "FollowTerrain",
			laneWidth = DEFAULT_LANE_WIDTH,
		},
		priority = 1,
		predicates = {},
	}
	local offsets = StageLanes.offsets(1)
	graph.laneProfiles[laneProfileId] = {
		id = laneProfileId,
		offsets = offsets,
		clearanceRadius = StageLanes.clearanceRadius(offsets),
	}
	return edgeId
end

function Operations.splitEdge(graph: any, edgeId: string): string?
	local edge = graph.edges[edgeId]
	if edge == nil then
		return nil
	end
	local from = graph.nodes[edge.fromNodeId]
	local to = graph.nodes[edge.toNodeId]
	if from == nil or to == nil then
		return nil
	end
	local nodeId = guid("node")
	local firstEdgeId = guid("edge")
	local secondEdgeId = guid("edge")
	-- De Casteljau at t=0.5 preserves the authored cubic exactly. A previous
	-- midpoint split replaced both halves with generic handles, visibly changing
	-- the route as soon as the author used Split.
	local firstPoint = from.position
	local secondPoint = add(firstPoint, edge.outHandleOffset)
	local fourthPoint = to.position
	local thirdPoint = add(fourthPoint, edge.inHandleOffset)
	local firstHalf = midpoint(firstPoint, secondPoint)
	local centerHalf = midpoint(secondPoint, thirdPoint)
	local lastHalf = midpoint(thirdPoint, fourthPoint)
	local firstQuarter = midpoint(firstHalf, centerHalf)
	local lastQuarter = midpoint(centerHalf, lastHalf)
	local splitPoint = midpoint(firstQuarter, lastQuarter)
	local metadata = cloneDictionary(edgeMetadata(edge))
	local predicates = clonePredicates(edge.predicates)
	graph.nodes[nodeId] = {
		id = nodeId,
		name = "Junction",
		kind = "Junction",
		position = splitPoint,
		tags = {},
	}
	graph.edges[firstEdgeId] = {
		id = firstEdgeId,
		fromNodeId = edge.fromNodeId,
		toNodeId = nodeId,
		outHandleOffset = subtract(firstHalf, firstPoint),
		inHandleOffset = subtract(firstQuarter, splitPoint),
		laneProfileId = edge.laneProfileId,
		metadata = cloneDictionary(metadata),
		priority = edge.priority,
		predicates = predicates,
	}
	graph.edges[secondEdgeId] = {
		id = secondEdgeId,
		fromNodeId = nodeId,
		toNodeId = edge.toNodeId,
		outHandleOffset = subtract(lastQuarter, splitPoint),
		inHandleOffset = subtract(lastHalf, fourthPoint),
		laneProfileId = edge.laneProfileId,
		metadata = cloneDictionary(metadata),
		priority = edge.priority,
		predicates = {},
	}
	graph.edges[edgeId] = nil
	return nodeId
end

function Operations.setLaneCount(graph: any, edgeId: string, laneCount: number): boolean
	local edge = graph.edges[edgeId]
	if
		edge == nil
		or not isFiniteNumber(laneCount)
		or laneCount % 1 ~= 0
		or laneCount < StageLanes.MIN_COUNT
		or laneCount > StageLanes.MAX_COUNT
	then
		return false
	end
	local currentProfile = graph.laneProfiles[edge.laneProfileId]
	if currentProfile == nil then
		return false
	end
	local laneWidth = profileLaneWidth(edge)
	local nextOffsets = StageLanes.offsets(laneCount, laneWidth)
	if offsetsEqual(currentProfile.offsets, nextOffsets) then
		return true
	end
	local profile = independentLaneProfile(graph, edge)
	if profile == nil then
		return false
	end
	local shoulder = authoredShoulder(profile, laneWidth)
	profile.offsets = nextOffsets
	profile.clearanceRadius = StageLanes.clearanceRadius(profile.offsets, shoulder)
	return true
end

function Operations.setLaneWidth(graph: any, edgeId: string, laneWidth: number): boolean
	local edge = graph.edges[edgeId]
	if edge == nil or not isFiniteNumber(laneWidth) then
		return false
	end
	local resolvedWidth = math.clamp(math.floor(laneWidth + 0.5), 2, 12)
	local previousWidth = profileLaneWidth(edge)
	if resolvedWidth == previousWidth then
		return true
	end
	local profile = independentLaneProfile(graph, edge)
	if profile == nil then
		return false
	end
	local laneCount = math.clamp(#profile.offsets, StageLanes.MIN_COUNT, StageLanes.MAX_COUNT)
	local extraShoulder = math.max(authoredShoulder(profile, previousWidth) - previousWidth * 0.5, 0)
	edgeMetadata(edge).laneWidth = resolvedWidth
	profile.offsets = StageLanes.offsets(laneCount, resolvedWidth)
	profile.clearanceRadius = StageLanes.clearanceRadius(profile.offsets, resolvedWidth * 0.5 + extraShoulder)
	return true
end

function Operations.setPriority(graph: any, edgeId: string, priority: number): boolean
	local edge = graph.edges[edgeId]
	if edge == nil or not isFiniteNumber(priority) then
		return false
	end
	local resolvedPriority = math.clamp(math.floor(priority + 0.5), 0, 99)
	if edge.priority == resolvedPriority then
		return true
	end
	edge.priority = resolvedPriority
	return true
end

function Operations.setCurveMode(graph: any, edgeId: string, curveMode: string): boolean
	local edge = graph.edges[edgeId]
	if edge == nil or (curveMode ~= "Smooth" and curveMode ~= "Mirrored" and curveMode ~= "Free") then
		return false
	end
	edgeMetadata(edge).curveMode = curveMode
	if curveMode ~= "Free" then
		edge.inHandleOffset = constrainedOpposite(edge.outHandleOffset, edge.inHandleOffset, curveMode)
	end
	return true
end

function Operations.deleteEdge(graph: any, edgeId: string): boolean
	local edge = graph.edges[edgeId]
	if edge == nil then
		return false
	end
	graph.edges[edgeId] = nil
	return true
end

function Operations.canDeleteNode(graph: any, nodeId: string): boolean
	if graph.nodes[nodeId] == nil then
		return false
	end
	for _, edge in graph.edges do
		if edge.fromNodeId ~= nodeId and edge.toNodeId ~= nodeId then
			for _, predicate in edge.predicates do
				if predicate.kind == "VisitCountBelow" and predicate.nodeId == nodeId then
					return false
				end
			end
		end
	end
	return true
end

function Operations.deleteNode(graph: any, nodeId: string): boolean
	if not Operations.canDeleteNode(graph, nodeId) then
		return false
	end
	local incidentEdgeIds: { string } = {}
	for edgeId, edge in graph.edges do
		if edge.fromNodeId == nodeId or edge.toNodeId == nodeId then
			table.insert(incidentEdgeIds, edgeId)
		end
	end
	for _, edgeId in incidentEdgeIds do
		Operations.deleteEdge(graph, edgeId)
	end
	graph.nodes[nodeId] = nil
	return true
end

function Operations.cycleLaneCount(graph: any, edgeId: string): number?
	local edge = graph.edges[edgeId]
	local profile = if edge ~= nil then graph.laneProfiles[edge.laneProfileId] else nil
	if profile == nil then
		return nil
	end
	local nextCount = (#profile.offsets % StageLanes.MAX_COUNT) + 1
	if not Operations.setLaneCount(graph, edgeId, nextCount) then
		return nil
	end
	return nextCount
end

return table.freeze(Operations)

--!strict

local HttpService = game:GetService("HttpService")

local StageLanes = require(script.Parent.Parent.Shared.StageLanes)

local Operations = {}

local function guid(prefix: string): string
	return `{prefix}_{string.lower(HttpService:GenerateGUID(false))}`
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
	local clone = {
		id = profileId,
		offsets = table.clone(profile.offsets),
		clearanceRadius = profile.clearanceRadius,
	}
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

function Operations.connect(graph: any, fromId: string, toId: string): string?
	if fromId == toId then
		return nil
	end
	local from = graph.nodes[fromId]
	local to = graph.nodes[toId]
	if from == nil or to == nil then
		return nil
	end
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
	local midpoint = {
		x = (from.position.x + to.position.x) * 0.5,
		y = (from.position.y + to.position.y) * 0.5,
		z = (from.position.z + to.position.z) * 0.5,
	}
	local delta = deltaBetween(from, to, 6)
	graph.nodes[nodeId] = {
		id = nodeId,
		name = "Junction",
		kind = "Junction",
		position = midpoint,
		tags = {},
	}
	graph.edges[firstEdgeId] = {
		id = firstEdgeId,
		fromNodeId = edge.fromNodeId,
		toNodeId = nodeId,
		outHandleOffset = delta,
		inHandleOffset = { x = -delta.x, y = -delta.y, z = -delta.z },
		laneProfileId = edge.laneProfileId,
		priority = edge.priority,
		predicates = table.clone(edge.predicates),
	}
	graph.edges[secondEdgeId] = {
		id = secondEdgeId,
		fromNodeId = nodeId,
		toNodeId = edge.toNodeId,
		outHandleOffset = delta,
		inHandleOffset = { x = -delta.x, y = -delta.y, z = -delta.z },
		laneProfileId = edge.laneProfileId,
		priority = 1,
		predicates = {},
	}
	graph.edges[edgeId] = nil
	return nodeId
end

function Operations.setLaneCount(graph: any, edgeId: string, laneCount: number): boolean
	local edge = graph.edges[edgeId]
	if edge == nil then
		return false
	end
	local profile = independentLaneProfile(graph, edge)
	if profile == nil then
		return false
	end
	profile.offsets = StageLanes.offsets(laneCount)
	profile.clearanceRadius = StageLanes.clearanceRadius(profile.offsets)
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

function Operations.smoothEdge(graph: any, edgeId: string): boolean
	local edge = graph.edges[edgeId]
	local from = if edge ~= nil then graph.nodes[edge.fromNodeId] else nil
	local to = if edge ~= nil then graph.nodes[edge.toNodeId] else nil
	if edge == nil or from == nil or to == nil then
		return false
	end
	local delta = deltaBetween(from, to, 3)
	edge.outHandleOffset = delta
	edge.inHandleOffset = { x = -delta.x, y = -delta.y, z = -delta.z }
	return true
end

return table.freeze(Operations)

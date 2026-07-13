--!strict

local StageGraph = {}

export type Predicate = { [string]: any }
export type Edge = {
	id: string,
	fromNodeId: string,
	toNodeId: string,
	priority: number,
	predicates: { Predicate },
}
export type Node = { id: string, kind: string }
export type Graph = {
	nodes: { [string]: Node },
	edges: { [string]: Edge },
	outgoingEdgeIds: { [string]: { string } }?,
}
export type Context = {
	wave: number,
	stageFlags: { [string]: boolean },
	enemyTags: { [string]: boolean },
	nodeVisits: { [string]: number },
	unlockedStages: { [string]: boolean },
	upgradeLevels: { [string]: number },
	currencies: { [string]: number },
}
export type Issue = {
	severity: "Error" | "Warning",
	code: string,
	message: string,
	objectId: string?,
}

local function predicatePasses(predicate: Predicate, context: Context): boolean
	local kind = predicate.kind
	if kind == "WaveRange" then
		return context.wave >= (predicate.minimum or 1) and context.wave <= (predicate.maximum or math.huge)
	elseif kind == "StageFlagEquals" then
		return context.stageFlags[predicate.key] == predicate.value
	elseif kind == "EnemyTag" then
		return context.enemyTags[predicate.tag] == true
	elseif kind == "VisitCountBelow" then
		return (context.nodeVisits[predicate.nodeId] or 0) < (predicate.maximum or 0)
	elseif kind == "StageUnlocked" then
		return context.unlockedStages[predicate.stageId] == true
	elseif kind == "UpgradeLevelAtLeast" then
		return (context.upgradeLevels[predicate.upgradeId] or 0) >= (predicate.level or math.huge)
	elseif kind == "CurrencyAtLeast" then
		return (context.currencies[predicate.currencyId] or 0) >= (predicate.amount or math.huge)
	end
	return false
end

function StageGraph.predicatesPass(predicates: { Predicate }, context: Context): boolean
	for _, predicate in predicates do
		if not predicatePasses(predicate, context) then
			return false
		end
	end
	return true
end

local function edgeLess(left: Edge, right: Edge): boolean
	if left.priority == right.priority then
		return left.id < right.id
	end
	return left.priority < right.priority
end

function StageGraph.outgoing(graph: Graph, nodeId: string): { Edge }
	local result: { Edge } = {}
	if graph.outgoingEdgeIds ~= nil then
		for _, edgeId in graph.outgoingEdgeIds[nodeId] or {} do
			local edge = graph.edges[edgeId]
			if edge ~= nil then
				table.insert(result, edge)
			end
		end
		return result
	end
	for _, edge in graph.edges do
		if edge.fromNodeId == nodeId then
			table.insert(result, edge)
		end
	end
	table.sort(result, edgeLess)
	return result
end

function StageGraph.chooseEdge(graph: Graph, nodeId: string, context: Context): (Edge?, string?)
	local outgoing = StageGraph.outgoing(graph, nodeId)
	for _, edge in outgoing do
		if StageGraph.predicatesPass(edge.predicates, context) then
			return edge, nil
		end
	end
	return nil, `Node {nodeId} has no eligible outgoing edge`
end

local function hasVisitLimit(edge: Edge): boolean
	for _, predicate in edge.predicates do
		if predicate.kind == "VisitCountBelow" then
			return true
		end
	end
	return false
end

local VALID_PREDICATES = {
	WaveRange = true,
	StageFlagEquals = true,
	EnemyTag = true,
	VisitCountBelow = true,
	StageUnlocked = true,
	UpgradeLevelAtLeast = true,
	CurrencyAtLeast = true,
}

function StageGraph.validate(graph: Graph): { Issue }
	local issues: { Issue } = {}
	local spawnCount = 0
	local goalCount = 0
	for nodeId, node in graph.nodes do
		if node.id ~= nodeId then
			table.insert(issues, {
				severity = "Error",
				code = "NodeIdMismatch",
				message = `Node map key {nodeId} does not match node ID {node.id}`,
				objectId = nodeId,
			})
		end
		if node.kind == "Spawn" then
			spawnCount += 1
		elseif node.kind == "Goal" then
			goalCount += 1
		end
	end
	if spawnCount == 0 then
		table.insert(
			issues,
			{ severity = "Error", code = "MissingSpawn", message = "Graph has no spawn node" }
		)
	end
	if goalCount == 0 then
		table.insert(issues, { severity = "Error", code = "MissingGoal", message = "Graph has no goal node" })
	end

	for edgeId, edge in graph.edges do
		if edge.id ~= edgeId then
			table.insert(issues, {
				severity = "Error",
				code = "EdgeIdMismatch",
				message = `Edge map key {edgeId} does not match edge ID {edge.id}`,
				objectId = edgeId,
			})
		end
		if graph.nodes[edge.fromNodeId] == nil or graph.nodes[edge.toNodeId] == nil then
			table.insert(issues, {
				severity = "Error",
				code = "DanglingEdge",
				message = `Edge {edgeId} references a missing node`,
				objectId = edgeId,
			})
		end
		if type(edge.priority) ~= "number" or edge.priority ~= edge.priority then
			table.insert(issues, {
				severity = "Error",
				code = "InvalidEdgePriority",
				message = `Edge {edgeId} has an invalid priority`,
				objectId = edgeId,
			})
		end
		for _, predicate in edge.predicates or {} do
			if VALID_PREDICATES[predicate.kind] ~= true then
				table.insert(issues, {
					severity = "Error",
					code = "UnknownPredicate",
					message = `Edge {edgeId} uses unknown predicate {tostring(predicate.kind)}`,
					objectId = edgeId,
				})
			elseif predicate.kind == "VisitCountBelow" and graph.nodes[predicate.nodeId] == nil then
				table.insert(issues, {
					severity = "Error",
					code = "PredicateNodeReference",
					message = `Edge {edgeId} visit predicate references a missing node`,
					objectId = edgeId,
				})
			end
		end
	end

	for nodeId, node in graph.nodes do
		local outgoing = StageGraph.outgoing(graph, nodeId)
		if node.kind ~= "Goal" and #outgoing == 0 then
			table.insert(issues, {
				severity = "Error",
				code = "DeadEnd",
				message = `Non-goal node {nodeId} has no outgoing edge`,
				objectId = nodeId,
			})
		elseif #outgoing > 1 then
			local fallbackCount = 0
			for _, edge in outgoing do
				if #edge.predicates == 0 then
					fallbackCount += 1
				end
			end
			if fallbackCount ~= 1 then
				table.insert(issues, {
					severity = "Error",
					code = "BranchFallback",
					message = `Branch node {nodeId} requires exactly one unconditional fallback`,
					objectId = nodeId,
				})
			end
		end
	end

	local reachable: { [string]: boolean } = {}
	local function markReachable(nodeId: string)
		if reachable[nodeId] then
			return
		end
		reachable[nodeId] = true
		for _, edge in StageGraph.outgoing(graph, nodeId) do
			markReachable(edge.toNodeId)
		end
	end
	for nodeId, node in graph.nodes do
		if node.kind == "Spawn" then
			markReachable(nodeId)
		end
	end
	local reachableGoal = false
	for nodeId, node in graph.nodes do
		if reachable[nodeId] and node.kind == "Goal" then
			reachableGoal = true
		elseif not reachable[nodeId] then
			table.insert(issues, {
				severity = "Warning",
				code = "UnreachableNode",
				message = `Node {nodeId} is unreachable from every spawn`,
				objectId = nodeId,
			})
		end
	end
	if spawnCount > 0 and not reachableGoal then
		table.insert(issues, {
			severity = "Error",
			code = "GoalUnreachable",
			message = "No goal is reachable from a spawn",
		})
	end

	local visiting: { [string]: boolean } = {}
	local visited: { [string]: boolean } = {}
	local function visit(nodeId: string, bounded: boolean)
		if visiting[nodeId] then
			if not bounded then
				table.insert(issues, {
					severity = "Error",
					code = "UnboundedCycle",
					message = `Cycle through node {nodeId} has no visit-count predicate`,
					objectId = nodeId,
				})
			end
			return
		end
		if visited[nodeId] then
			return
		end
		visiting[nodeId] = true
		for _, edge in StageGraph.outgoing(graph, nodeId) do
			visit(edge.toNodeId, bounded or hasVisitLimit(edge))
		end
		visiting[nodeId] = nil
		visited[nodeId] = true
	end
	for nodeId, node in graph.nodes do
		if node.kind == "Spawn" then
			visit(nodeId, false)
		end
	end
	return issues
end

return table.freeze(StageGraph)

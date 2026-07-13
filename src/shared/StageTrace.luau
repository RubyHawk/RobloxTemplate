--!strict

local StageGraph = if script ~= nil then require(script.Parent.StageGraph) else require("./StageGraph")

local StageTrace = {}

export type Result = {
	nodeIds: { string },
	edgeIds: { string },
	distanceTraveled: number,
	reachedGoal: boolean,
	stoppedReason: string,
}

local function cloneVisits(source: { [string]: number }): { [string]: number }
	return table.clone(source)
end

local function contextWithVisits(
	context: StageGraph.Context,
	visits: { [string]: number }
): StageGraph.Context
	return {
		wave = context.wave,
		stageFlags = context.stageFlags,
		enemyTags = context.enemyTags,
		nodeVisits = visits,
		unlockedStages = context.unlockedStages,
		upgradeLevels = context.upgradeLevels,
		currencies = context.currencies,
	}
end

function StageTrace.trace(
	graph: any,
	spawnNodeId: string,
	context: StageGraph.Context,
	maximumSteps: number?
): Result
	local limit = math.clamp(math.floor(maximumSteps or graph.maxNodeVisitsPerEnemy or 64), 1, 10_000)
	local visits = cloneVisits(context.nodeVisits)
	local result: Result = {
		nodeIds = { spawnNodeId },
		edgeIds = {},
		distanceTraveled = 0,
		reachedGoal = false,
		stoppedReason = "",
	}
	local currentNodeId = spawnNodeId
	visits[currentNodeId] = (visits[currentNodeId] or 0) + 1
	for _ = 1, limit do
		local node = graph.nodes[currentNodeId]
		if node == nil then
			result.stoppedReason = `Missing node {currentNodeId}`
			return result
		end
		if node.kind == "Goal" then
			result.reachedGoal = true
			result.stoppedReason = "Reached goal"
			return result
		end
		local edge, reason = StageGraph.chooseEdge(graph, currentNodeId, contextWithVisits(context, visits))
		if edge == nil then
			result.stoppedReason = reason or `No eligible edge from {currentNodeId}`
			return result
		end
		table.insert(result.edgeIds, edge.id)
		result.distanceTraveled += edge.length or 0
		if result.distanceTraveled > (graph.maxTravelDistance or math.huge) then
			result.stoppedReason = `Maximum travel distance exceeded at {edge.id}`
			return result
		end
		currentNodeId = edge.toNodeId
		visits[currentNodeId] = (visits[currentNodeId] or 0) + 1
		table.insert(result.nodeIds, currentNodeId)
	end
	result.stoppedReason = `Maximum node visits exceeded at {currentNodeId}`
	return result
end

return table.freeze(StageTrace)

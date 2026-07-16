--!strict

local StageStarterProject = {}

StageStarterProject.REVISION = 1

export type IdFactory = (string) -> string

local function vector(x: number, z: number): { x: number, y: number, z: number }
	return { x = x, y = 0.48, z = z }
end

local function offset(x: number, z: number): { x: number, y: number, z: number }
	return { x = x, y = 0, z = z }
end

local function makeGraph(idFactory: IdFactory): (string, any)
	local graphId = idFactory("graph")
	local nodeIds = {
		northSpawn = idFactory("node"),
		southSpawn = idFactory("node"),
		merge = idFactory("node"),
		waveGate = idFactory("node"),
		fallback = idFactory("node"),
		rejoin = idFactory("node"),
		goal = idFactory("node"),
	}
	local nodes = {
		[nodeIds.northSpawn] = {
			id = nodeIds.northSpawn,
			name = "North Spawn",
			kind = "Spawn",
			position = vector(-52, -32),
			tags = { "North" },
		},
		[nodeIds.southSpawn] = {
			id = nodeIds.southSpawn,
			name = "South Spawn",
			kind = "Spawn",
			position = vector(-52, 32),
			tags = { "South" },
		},
		[nodeIds.merge] = {
			id = nodeIds.merge,
			name = "Merge",
			kind = "Junction",
			position = vector(-18, 0),
			tags = { "Merge" },
		},
		[nodeIds.waveGate] = {
			id = nodeIds.waveGate,
			name = "Wave Gate",
			kind = "Junction",
			position = vector(12, -24),
			tags = { "Conditional" },
		},
		[nodeIds.fallback] = {
			id = nodeIds.fallback,
			name = "Fallback Path",
			kind = "Junction",
			position = vector(12, 24),
			tags = { "Fallback" },
		},
		[nodeIds.rejoin] = {
			id = nodeIds.rejoin,
			name = "Rejoin",
			kind = "Junction",
			position = vector(40, 0),
			tags = { "Merge" },
		},
		[nodeIds.goal] = {
			id = nodeIds.goal,
			name = "Goal",
			kind = "Goal",
			position = vector(56, 0),
			tags = { "Goal" },
		},
	}

	local function edge(
		fromNodeId: string,
		toNodeId: string,
		outHandleOffset: any,
		inHandleOffset: any,
		priority: number,
		predicates: { any }
	): (string, any)
		local edgeId = idFactory("edge")
		return edgeId,
			{
				id = edgeId,
				fromNodeId = fromNodeId,
				toNodeId = toNodeId,
				outHandleOffset = outHandleOffset,
				inHandleOffset = inHandleOffset,
				laneProfileId = "lane_default",
				priority = priority,
				predicates = predicates,
				metadata = {
					pathAssetId = "gravel",
					curveMode = "Smooth",
					surfaceMode = "FollowTerrain",
					laneWidth = 4,
				},
			}
	end

	local edges: { [string]: any } = {}
	for _, definition in
		{
			{ nodeIds.northSpawn, nodeIds.merge, offset(15, 1), offset(-13, -11), 1, {} },
			{ nodeIds.southSpawn, nodeIds.merge, offset(15, -1), offset(-13, 11), 1, {} },
			{
				nodeIds.merge,
				nodeIds.waveGate,
				offset(10, -5),
				offset(-10, 5),
				1,
				{ { kind = "WaveRange", minimum = 5 } },
			},
			{ nodeIds.merge, nodeIds.fallback, offset(10, 5), offset(-10, -5), 2, {} },
			{ nodeIds.waveGate, nodeIds.rejoin, offset(10, 1), offset(-10, -10), 1, {} },
			{ nodeIds.fallback, nodeIds.rejoin, offset(10, -1), offset(-10, 10), 1, {} },
			{ nodeIds.rejoin, nodeIds.goal, offset(6, 0), offset(-6, 0), 1, {} },
		}
	do
		local edgeId, value =
			edge(definition[1], definition[2], definition[3], definition[4], definition[5], definition[6])
		edges[edgeId] = value
	end

	return graphId,
		{
			id = graphId,
			name = "Main Enemy Route",
			nodes = nodes,
			edges = edges,
			laneProfiles = {
				lane_default = {
					id = "lane_default",
					offsets = { -2, 2 },
					clearanceRadius = 5,
				},
			},
			maxNodeVisitsPerEnemy = 64,
			maxTravelDistance = 10_000,
		}
end

local function makeGrid(): any
	return {
		columns = 32,
		rows = 27,
		cellSize = 4,
		defaultCell = {
			terrainId = "ground",
			buildPolicy = "Allowed",
			enemyTraversalPolicy = "Allowed",
		},
		cells = {
			["4:6"] = { buildPolicy = "Blocked", roles = { EnemySpawn = true } },
			["4:22"] = { buildPolicy = "Blocked", roles = { EnemySpawn = true } },
			["31:14"] = { buildPolicy = "Blocked", roles = { EnemyGoal = true } },
			["16:2"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
			["16:26"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
			["24:2"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
			["24:26"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
			["31:2"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
			["31:26"] = { buildPolicy = "Allowed", roles = { AutoPlace = true } },
		},
	}
end

function StageStarterProject.build(
	levelCount: number,
	idFactory: IdFactory,
	firstStageId: string?,
	stageGroupId: string?
): any
	local count = math.clamp(math.floor(levelCount), 1, 100)
	local groupId = stageGroupId or idFactory("stage_group")
	local stages: { [string]: any } = {}
	local previousId: string? = nil
	local startingStageId = firstStageId or idFactory("stage")
	for levelNumber = 1, count do
		local stageId = if levelNumber == 1 then startingStageId else idFactory("stage")
		local graphId, graph = makeGraph(idFactory)
		stages[stageId] = {
			schemaVersion = 3,
			id = stageId,
			name = `Level {levelNumber}`,
			displayOrder = levelNumber,
			stageGroupId = groupId,
			stageNumber = 1,
			levelNumber = levelNumber,
			grid = makeGrid(),
			pathGraphs = { [graphId] = graph },
			waveSetId = "default",
			themeId = "default",
			modifierIds = {},
			unlockRequirements = if previousId == nil
				then {}
				else { { kind = "StageUnlocked", stageId = previousId } },
			metadata = {
				["stagewright.designIntent"] = "Two spawns merge, branch by wave, and rejoin before the goal",
				["stagewright.layoutVersion"] = 3,
			},
		}
		previousId = stageId
	end
	return {
		schemaVersion = 3,
		startingStageId = startingStageId,
		selectedStageId = startingStageId,
		stages = stages,
		metadata = {
			["stagewright.starterLevelCount"] = count,
			["stagewright.starterStageGroupId"] = groupId,
			["stagewright.approvedStarterRevision"] = StageStarterProject.REVISION,
		},
	}
end

function StageStarterProject.isRecognizedLegacyTestProject(project: any): boolean
	if type(project) ~= "table" or type(project.stages) ~= "table" then
		return false
	end
	local metadata = project.metadata
	if type(metadata) == "table" and type(metadata["stagewright.approvedStarterRevision"]) == "number" then
		return false
	end
	local stageCount = 0
	local recognizedStages = 0
	for _, stage in project.stages do
		stageCount += 1
		local legacyControls = 0
		local nodeCount = 0
		local edgeCount = 0
		if type(stage.pathGraphs) == "table" then
			for _, graph in stage.pathGraphs do
				if type(graph.nodes) == "table" then
					for _, node in graph.nodes do
						nodeCount += 1
						if
							type(node.name) == "string"
							and string.match(node.name, "^Legacy Control %d+$") ~= nil
						then
							legacyControls += 1
						end
					end
				end
				if type(graph.edges) == "table" then
					for _ in graph.edges do
						edgeCount += 1
					end
				end
			end
		end
		if legacyControls >= 5 and nodeCount >= 7 and edgeCount >= 6 then
			recognizedStages += 1
		end
	end
	return stageCount == 10 and recognizedStages >= 8
end

return StageStarterProject

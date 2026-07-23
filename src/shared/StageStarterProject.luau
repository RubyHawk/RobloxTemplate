--!strict

local StageWaveDefaults = if script ~= nil
	then require(script.Parent.StageWaveDefaults)
	else require("./StageWaveDefaults")

local StageStarterProject = {}

StageStarterProject.REVISION = 2
StageStarterProject.BASICS_WAVE_SET_ID = "mvp_basics"
StageStarterProject.MIXED_WAVE_SET_ID = "mvp_mixed"
StageStarterProject.BOSS_WAVE_SET_ID = "mvp_boss"

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

local function waveEntry(
	enemyTypeId: string,
	count: number,
	spacingSeconds: number,
	startDelaySeconds: number
): any
	return {
		enemyTypeId = enemyTypeId,
		count = count,
		spacingSeconds = spacingSeconds,
		startDelaySeconds = startDelaySeconds,
	}
end

function StageStarterProject.playtestWaveSets(): { [string]: any }
	return {
		[StageStarterProject.BASICS_WAVE_SET_ID] = {
			id = StageStarterProject.BASICS_WAVE_SET_ID,
			name = "MVP Basics",
			waves = {
				{ entries = { waveEntry("forest_grunt", 6, 0.8, 0) } },
				{
					entries = {
						waveEntry("forest_grunt", 8, 0.65, 0),
						waveEntry("forest_runner", 4, 0.5, 2.5),
					},
				},
				{
					entries = {
						waveEntry("forest_grunt", 8, 0.6, 0),
						waveEntry("bark_bruiser", 2, 1.2, 4),
					},
				},
			},
		},
		[StageStarterProject.MIXED_WAVE_SET_ID] = {
			id = StageStarterProject.MIXED_WAVE_SET_ID,
			name = "MVP Mixed",
			waves = {
				{ entries = { waveEntry("forest_runner", 10, 0.4, 0) } },
				{
					entries = {
						waveEntry("forest_grunt", 6, 0.7, 0),
						waveEntry("sky_wisp", 6, 0.55, 1.5),
					},
				},
				{
					entries = {
						waveEntry("forest_runner", 8, 0.4, 0),
						waveEntry("bark_bruiser", 4, 1, 2),
						waveEntry("sky_wisp", 6, 0.5, 4),
					},
				},
			},
		},
		[StageStarterProject.BOSS_WAVE_SET_ID] = {
			id = StageStarterProject.BOSS_WAVE_SET_ID,
			name = "MVP Boss",
			waves = {
				{
					entries = {
						waveEntry("bark_bruiser", 6, 0.9, 0),
						waveEntry("forest_runner", 8, 0.4, 2),
					},
				},
				{
					entries = {
						waveEntry("sky_wisp", 10, 0.5, 0),
						waveEntry("bark_bruiser", 4, 1, 3),
					},
				},
				{
					isBoss = true,
					entries = {
						waveEntry("forest_grunt", 8, 0.55, 0),
						waveEntry("grove_titan", 1, 1, 2),
						waveEntry("forest_runner", 6, 0.4, 3),
					},
				},
			},
		},
	}
end

local function playtestWaveSetId(levelNumber: number): string
	if levelNumber == 1 then
		return StageStarterProject.BASICS_WAVE_SET_ID
	elseif levelNumber == 2 then
		return StageStarterProject.MIXED_WAVE_SET_ID
	elseif levelNumber == 3 then
		return StageStarterProject.BOSS_WAVE_SET_ID
	end
	return StageWaveDefaults.DEFAULT_WAVE_SET_ID
end

function StageStarterProject.build(
	levelCount: number,
	idFactory: IdFactory,
	firstStageId: string?,
	stageGroupId: string?,
	mapIdValue: string?
): any
	local count = math.clamp(math.floor(levelCount), 1, 100)
	local groupId = stageGroupId or idFactory("stage_group")
	local mapId = mapIdValue or idFactory("map")
	local stages: { [string]: any } = {}
	local previousId: string? = nil
	local startingStageId = firstStageId or idFactory("stage")
	for levelNumber = 1, count do
		local stageId = if levelNumber == 1 then startingStageId else idFactory("stage")
		local graphId, graph = makeGraph(idFactory)
		stages[stageId] = {
			schemaVersion = 5,
			id = stageId,
			mapId = mapId,
			name = `Level {levelNumber}`,
			displayOrder = levelNumber,
			stageGroupId = groupId,
			stageNumber = 1,
			levelNumber = levelNumber,
			grid = makeGrid(),
			pathGraphs = { [graphId] = graph },
			waveSetId = playtestWaveSetId(levelNumber),
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
		schemaVersion = 5,
		startingStageId = startingStageId,
		selectedStageId = startingStageId,
		maps = {
			[mapId] = {
				id = mapId,
				name = "Map 1",
				displayOrder = 1,
				backdropImageId = "",
				metadata = {},
			},
		},
		stages = stages,
		enemyTypes = StageWaveDefaults.enemyTypes(),
		waveSets = (function(): { [string]: any }
			local result = StageStarterProject.playtestWaveSets()
			result[StageWaveDefaults.DEFAULT_WAVE_SET_ID] = StageWaveDefaults.defaultWaveSet()
			return result
		end)(),
		metadata = {
			["stagewright.starterLevelCount"] = count,
			["stagewright.starterMapId"] = mapId,
			["stagewright.starterStageGroupId"] = groupId,
			["stagewright.approvedStarterRevision"] = StageStarterProject.REVISION,
		},
	}
end

-- Revision 1 was the exact ten-level starter layout with every level assigned
-- to the default wave set. Upgrade only that untouched assignment boundary;
-- custom wave sets or custom level assignments are never replaced.
function StageStarterProject.upgradeApprovedStarter(project: any): boolean
	if
		type(project) ~= "table"
		or type(project.metadata) ~= "table"
		or project.metadata["stagewright.approvedStarterRevision"] ~= 1
		or type(project.stages) ~= "table"
		or type(project.waveSets) ~= "table"
	then
		return false
	end
	local starting = project.stages[project.startingStageId]
	if type(starting) ~= "table" then
		return false
	end
	local levelIds: { string } = {}
	for stageId, stage in project.stages do
		if
			type(stage) == "table"
			and stage.mapId == starting.mapId
			and stage.stageGroupId == starting.stageGroupId
			and stage.stageNumber == starting.stageNumber
			and type(stage.levelNumber) == "number"
		then
			table.insert(levelIds, stageId)
		end
	end
	table.sort(levelIds, function(left, right)
		return project.stages[left].levelNumber < project.stages[right].levelNumber
	end)
	if #levelIds ~= 10 or project.metadata["stagewright.starterLevelCount"] ~= 10 then
		return false
	end
	for levelNumber = 1, 3 do
		if project.stages[levelIds[levelNumber]].waveSetId ~= StageWaveDefaults.DEFAULT_WAVE_SET_ID then
			return false
		end
	end
	local fixtureSets = StageStarterProject.playtestWaveSets()
	for waveSetId in fixtureSets do
		if project.waveSets[waveSetId] ~= nil then
			return false
		end
	end
	for waveSetId, waveSet in fixtureSets do
		project.waveSets[waveSetId] = waveSet
	end
	for levelNumber = 1, 3 do
		project.stages[levelIds[levelNumber]].waveSetId = playtestWaveSetId(levelNumber)
	end
	project.metadata["stagewright.approvedStarterRevision"] = StageStarterProject.REVISION
	return true
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

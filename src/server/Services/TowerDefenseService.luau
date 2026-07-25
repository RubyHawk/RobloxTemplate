--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local StageCatalog = require(Shared.StageCatalog)
local StageLanes = require(Shared.StageLanes)
local StageTypes = require(Shared.StageTypes)
local TowerDefenseCatalog = require(Shared.TowerDefenseCatalog)
local TowerDefenseLogic = require(Shared.TowerDefenseLogic)
local TowerDefenseRequest = require(Shared.TowerDefenseRequest)
local TowerDefenseWaves = require(Shared.TowerDefenseWaves)
local Types = require(Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local StageRuntimeService = require(script.Parent.StageRuntimeService)

type TowerDefenseClientState = Types.TowerDefenseClientState
type TowerDefenseEnemyState = Types.TowerDefenseEnemyState
type TowerDefensePlacementState = Types.TowerDefensePlacementState
type TowerDefensePresentationPlacement = Types.TowerDefensePresentationPlacement
type TowerDefenseLevelOption = Types.TowerDefenseLevelOption

type Cell = {
	column: number,
	row: number,
}

type Placement = {
	id: string,
	unitId: string,
	cell: Cell,
	position: Vector3,
	nextAttackAt: number,
}

type Enemy = {
	id: string,
	enemyTypeId: string,
	name: string,
	health: number,
	maxHealth: number,
	speed: number,
	reward: number,
	baseDamage: number,
	armorMultiplier: number,
	isBoss: boolean,
	distance: number,
	edgeId: string,
	edgeDistance: number,
	laneIndex: number,
	laneSequence: number,
	nodeVisits: { [string]: number },
	tags: { string },
}

type MatchState = {
	baseHealth: number,
	wave: number,
	waveRunning: boolean,
	placements: { [string]: Placement },
	placementOrder: { string },
	enemies: { [string]: Enemy },
	enemyOrder: { string },
	nextPlacementId: number,
	nextEnemyId: number,
	spawnStreams: { TowerDefenseWaves.SpawnStream },
	waveIsBoss: boolean,
	waveCount: number,
	stageId: string,
	graphId: string,
	graph: any?,
	stageFlags: { [string]: boolean },
	nextSnapshotAt: number,
	isPlaytest: boolean,
}

type GridData = {
	stage: any,
	cellSize: number,
	columns: number,
	rows: number,
	autoPlaceCells: { Cell },
	portalCells: { Cell },
	goalCells: { Cell },
}

local TowerDefenseService = {}

local TOWER_VERTICAL_OFFSET = 0.7
local rng = Random.new()
local matches: { [Player]: MatchState } = {}
local publishSnapshot: ((player: Player) -> ())? = nil
local publishEnemyCorrection: ((player: Player) -> ())? = nil
local publishPlacementSnapshot: (() -> ())? = nil
local placementRevision = 0
local loopConnected = false

local function readGrid(player: Player): GridData?
	if not StageRuntimeService.hasPlatform(player) then
		return nil
	end
	local stage = StageRuntimeService.activeStage(player)
	if stage == nil then
		return nil
	end
	return {
		stage = stage,
		cellSize = stage.grid.cellSize,
		columns = stage.grid.columns,
		rows = stage.grid.rows,
		autoPlaceCells = StageRuntimeService.cellsWithRole(stage, "AutoPlace"),
		portalCells = StageRuntimeService.cellsWithRole(stage, "EnemySpawn"),
		goalCells = StageRuntimeService.cellsWithRole(stage, "EnemyGoal"),
	}
end

local function cellCode(grid: GridData, cell: Cell): string
	if cell.column < 1 or cell.column > grid.columns or cell.row < 1 or cell.row > grid.rows then
		return "#"
	end
	local authored = StageRuntimeService.cell(grid.stage, cell.column, cell.row)
	local roles = authored.roles or {}
	if roles.EnemySpawn then
		return "P"
	elseif roles.EnemyGoal then
		return "G"
	elseif roles.AutoPlace then
		return "A"
	elseif not StageRuntimeService.isBuildable(grid.stage, cell.column, cell.row) then
		return "#"
	end
	return "."
end

local function cellKey(cell: Cell): string
	return `{cell.column}:{cell.row}`
end

local function cellWorldPosition(player: Player, grid: GridData, cell: Cell, verticalOffset: number): Vector3
	return StageRuntimeService.cellWorldPosition(player, grid.stage, cell.column, cell.row, verticalOffset)
end

local function defaultMatch(): MatchState
	return {
		baseHealth = Config.towerDefense.baseHealth,
		wave = 0,
		waveRunning = false,
		placements = {},
		placementOrder = {},
		enemies = {},
		enemyOrder = {},
		nextPlacementId = 0,
		nextEnemyId = 0,
		spawnStreams = {},
		waveIsBoss = false,
		waveCount = 0,
		stageId = "",
		graphId = "",
		graph = nil,
		stageFlags = {},
		nextSnapshotAt = 0,
		isPlaytest = false,
	}
end

local function matchFor(player: Player): MatchState
	local match = matches[player]
	if match == nil then
		match = defaultMatch()
		matches[player] = match
	end
	return match
end

local function publish(player: Player)
	local callback = publishSnapshot
	if callback ~= nil and player.Parent ~= nil then
		callback(player)
	end
end

local function publishEnemies(player: Player)
	local callback = publishEnemyCorrection
	if callback ~= nil and player.Parent ~= nil then
		callback(player)
	else
		publish(player)
	end
end

local function publishPlacements()
	placementRevision += 1
	local callback = publishPlacementSnapshot
	if callback ~= nil then
		callback()
	end
end

local function profileTowerState(player: Player): Types.TowerDefenseSaveState?
	local profile = ProfileService.get(player)
	return if profile then profile.towerDefense else nil
end

local function unlockedLoadoutSlots(td: Types.TowerDefenseSaveState): number
	return math.clamp(
		math.floor(td.unlockedLoadoutSlots),
		Config.towerDefense.startingLoadoutSlots,
		Config.towerDefense.loadoutSlots
	)
end

local function nextLoadoutSlotCost(td: Types.TowerDefenseSaveState): number?
	local unlocked = unlockedLoadoutSlots(td)
	if unlocked >= Config.towerDefense.loadoutSlots then
		return nil
	end
	local costIndex = unlocked - Config.towerDefense.startingLoadoutSlots + 1
	return Config.towerDefense.loadoutSlotUnlockCosts[costIndex]
end

local function hasUnit(player: Player, unitId: string): boolean
	local td = profileTowerState(player)
	local entry = if td ~= nil then td.ownedUnits[unitId] else nil
	return entry ~= nil and type(entry.count) == "number" and entry.count > 0
end

local function inLoadout(player: Player, unitId: string): boolean
	local td = profileTowerState(player)
	if td == nil then
		return false
	end
	for _, loadoutUnitId in td.loadout do
		if loadoutUnitId == unitId then
			return true
		end
	end
	return false
end

local function placementAt(match: MatchState, cell: Cell): Placement?
	local key = cellKey(cell)
	for _, placement in match.placements do
		if cellKey(placement.cell) == key then
			return placement
		end
	end
	return nil
end

local function setBestLoadout(player: Player): (boolean, string)
	local td = profileTowerState(player)
	if td == nil then
		return false, "Profile is not loaded"
	end
	td.loadout =
		TowerDefenseLogic.bestLoadout(td.ownedUnits, TowerDefenseCatalog.units, unlockedLoadoutSlots(td))
	ProfileService.markDirty(player, "towerDefense:loadoutBest")
	return true, `Equipped {#td.loadout} unit(s)`
end

function TowerDefenseService.rollUnit(player: Player): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	local cost = Config.towerDefense.unitRollCost
	if
		not EconomyService.spendCurrency(
			player,
			Config.economy.primaryCurrencyId,
			cost,
			"towerDefense:rollUnit"
		)
	then
		return false, "Not enough currency"
	end
	local index = TowerDefenseLogic.pickWeightedUnitIndex(TowerDefenseCatalog.units, rng:NextNumber())
	local unit = TowerDefenseCatalog.units[index]
	if unit == nil then
		EconomyService.awardCurrencyRaw(
			player,
			Config.economy.primaryCurrencyId,
			cost,
			"towerDefense:rollRefund"
		)
		return false, "No unit catalog is available"
	end
	local entry = profile.towerDefense.ownedUnits[unit.id]
	local ownedCount = if entry == nil then 1 else math.min(entry.count + 1, 1e9)
	profile.towerDefense.ownedUnits[unit.id] = { count = ownedCount }
	if
		#profile.towerDefense.loadout < unlockedLoadoutSlots(profile.towerDefense)
		and not inLoadout(player, unit.id)
	then
		table.insert(profile.towerDefense.loadout, unit.id)
	end
	ProfileService.markDirty(player, `towerDefense:roll:{unit.id}`)
	return true, `Rolled {unit.name}`
end

function TowerDefenseService.setLoadout(player: Player, unitIds: any): (boolean, string)
	local td = profileTowerState(player)
	if td == nil then
		return false, "Profile is not loaded"
	end
	local parsedUnitIds = TowerDefenseRequest.parseUnitIds(unitIds, unlockedLoadoutSlots(td))
	if parsedUnitIds == nil then
		return false, "Invalid loadout"
	end
	local nextLoadout: { string } = {}
	for _, unitId in parsedUnitIds do
		if TowerDefenseCatalog.unit(unitId) == nil or not hasUnit(player, unitId) then
			return false, "Unit is not owned"
		end
		table.insert(nextLoadout, unitId)
	end
	td.loadout = nextLoadout
	ProfileService.markDirty(player, "towerDefense:setLoadout")
	return true, "Loadout updated"
end

function TowerDefenseService.equipBest(player: Player): (boolean, string)
	return setBestLoadout(player)
end

function TowerDefenseService.unlockLoadoutSlot(player: Player): (boolean, string)
	local td = profileTowerState(player)
	if td == nil then
		return false, "Profile is not loaded"
	end
	local unlocked = unlockedLoadoutSlots(td)
	if unlocked >= Config.towerDefense.loadoutSlots then
		return false, "All unit slots are already unlocked"
	end
	local cost = nextLoadoutSlotCost(td)
	if type(cost) ~= "number" or cost ~= cost or cost <= 0 or cost == math.huge or cost == -math.huge then
		return false, "The next unit slot is not configured"
	end
	if
		not EconomyService.spendCurrency(
			player,
			Config.economy.primaryCurrencyId,
			cost,
			"towerDefense:unlockLoadoutSlot"
		)
	then
		return false, "Not enough currency"
	end
	td.unlockedLoadoutSlots = unlocked + 1
	ProfileService.markDirty(player, "towerDefense:unlockLoadoutSlot")
	return true, `Unlocked unit slot {td.unlockedLoadoutSlots}`
end

local function placeUnitInternal(
	player: Player,
	unitId: string,
	cell: Cell,
	charge: boolean
): (boolean, string)
	local unit = TowerDefenseCatalog.unit(unitId)
	if unit == nil then
		return false, "Unknown unit"
	end
	if not hasUnit(player, unitId) or not inLoadout(player, unitId) then
		return false, "Unit is not in your loadout"
	end
	local grid = readGrid(player)
	if grid == nil then
		return false, "Grid is unavailable"
	end
	local code = cellCode(grid, cell)
	if not TowerDefenseLogic.isBuildableCell(code) then
		return false, "That grid cell cannot hold a unit"
	end
	local match = matchFor(player)
	if placementAt(match, cell) ~= nil then
		return false, "That grid cell is already occupied"
	end
	if
		charge
		and not EconomyService.spendCurrency(
			player,
			Config.economy.primaryCurrencyId,
			unit.deployCost,
			"towerDefense:place"
		)
	then
		return false, "Not enough currency to place unit"
	end

	match.nextPlacementId += 1
	local id = `Tower_{match.nextPlacementId}`
	local placement: Placement = {
		id = id,
		unitId = unitId,
		cell = { column = cell.column, row = cell.row },
		position = cellWorldPosition(player, grid, cell, TOWER_VERTICAL_OFFSET),
		nextAttackAt = 0,
	}
	match.placements[id] = placement
	table.insert(match.placementOrder, id)
	return true, `Placed {unit.name}`
end

function TowerDefenseService.placeUnit(player: Player, unitId: any, column: any, row: any): (boolean, string)
	local placement = TowerDefenseRequest.parsePlacement({
		unitId = unitId,
		column = column,
		row = row,
	})
	if placement == nil then
		return false, "Invalid placement"
	end
	local ok, message = placeUnitInternal(player, placement.unitId, {
		column = placement.column,
		row = placement.row,
	}, true)
	if ok then
		publishPlacements()
	end
	return ok, message
end

function TowerDefenseService.autoPlaceBest(player: Player): (boolean, string)
	local td = profileTowerState(player)
	local grid = readGrid(player)
	if td == nil or grid == nil then
		return false, "Grid is unavailable"
	end
	if #td.loadout == 0 then
		return false, "Select units for your loadout first"
	end
	local placed = 0
	local unitIndex = 1
	for _, cell in grid.autoPlaceCells do
		if placed >= Config.towerDefense.autoPlaceMaxUnits then
			break
		end
		local unitId = td.loadout[unitIndex]
		if unitId == nil then
			break
		end
		local didPlace = placeUnitInternal(player, unitId, cell, true)
		if didPlace then
			placed += 1
			unitIndex += 1
		end
	end
	if placed > 0 then
		publishPlacements()
	end
	return placed > 0,
		if placed > 0 then `Auto-placed {placed} unit(s)` else "No auto-place slots were available"
end

-- Authored Stagewright enemy types are authoritative; the legacy catalog keeps
-- older generated bundles (and the gallery place) playable.
local function enemyDefinitionFor(enemyTypeId: string): StageTypes.EnemyTypeDefinition?
	local authored = StageCatalog.enemyType(enemyTypeId)
	if authored ~= nil then
		return authored
	end
	local legacy = TowerDefenseCatalog.enemy(enemyTypeId)
	if legacy == nil then
		return nil
	end
	return {
		id = legacy.id,
		name = legacy.name,
		tags = legacy.tags,
		health = legacy.health,
		speed = legacy.speed,
		reward = legacy.reward,
		baseDamage = legacy.baseDamage,
		modelId = "",
		renderScale = 1,
	}
end

local function abortWave(match: MatchState)
	match.waveRunning = false
	table.clear(match.spawnStreams)
end

local function spawnEnemy(player: Player, match: MatchState, stream: TowerDefenseWaves.SpawnStream): boolean
	local enemyDefinition = enemyDefinitionFor(stream.enemyTypeId)
	local graph = match.graph
	if enemyDefinition == nil or graph == nil then
		warn(`Tower defense spawn rejected: unknown enemy type {stream.enemyTypeId}`)
		abortWave(match)
		return false
	end
	if #match.enemyOrder >= Config.towerDefense.maximumEnemiesPerPlayer then
		warn(`Tower defense spawn rejected: enemy cap reached for {player.Name}`)
		abortWave(match)
		return false
	end
	local spawnNodes = StageRuntimeService.spawnNodes(graph)
	if #spawnNodes == 0 then
		warn(`Tower defense graph {match.graphId} has no spawn node`)
		abortWave(match)
		return false
	end
	local enemySequence = match.nextEnemyId + 1
	local spawnNode = spawnNodes[StageLanes.index(enemySequence, #spawnNodes)]
	local laneSequence = StageLanes.sequenceForSpawn(enemySequence, #spawnNodes)
	local nodeVisits = { [spawnNode.id] = 1 }
	local tags = table.clone(enemyDefinition.tags)
	local context = StageRuntimeService.context(player, match.wave, tags, nodeVisits, match.stageFlags)
	local firstEdge, reason = StageRuntimeService.chooseEdge(graph, spawnNode.id, context)
	if firstEdge == nil then
		warn(`Tower defense route failed at {spawnNode.id}: {reason or "no eligible edge"}`)
		abortWave(match)
		return false
	end
	local laneProfile = graph.laneProfiles[firstEdge.laneProfileId]
	local laneCount = if laneProfile ~= nil and #laneProfile.offsets > 0 then #laneProfile.offsets else 1
	match.nextEnemyId += 1
	local maxHealth = math.max(math.floor(enemyDefinition.health * stream.healthScale), 1)
	local enemy: Enemy = {
		id = `Enemy_{match.nextEnemyId}`,
		enemyTypeId = enemyDefinition.id,
		name = enemyDefinition.name,
		health = maxHealth,
		maxHealth = maxHealth,
		speed = math.max(enemyDefinition.speed * stream.speedScale, 0.1),
		reward = math.floor(enemyDefinition.reward * stream.rewardScale),
		baseDamage = enemyDefinition.baseDamage,
		armorMultiplier = TowerDefenseWaves.armorMultiplier(
			tags,
			Config.towerDefense.armoredDamageMultiplier
		),
		isBoss = TowerDefenseWaves.hasTag(tags, "Boss"),
		distance = 0,
		edgeId = firstEdge.id,
		edgeDistance = 0,
		laneIndex = StageLanes.index(laneSequence, laneCount),
		laneSequence = laneSequence,
		nodeVisits = nodeVisits,
		tags = tags,
	}
	match.enemies[enemy.id] = enemy
	table.insert(match.enemyOrder, enemy.id)
	return true
end

local function startWaveInternal(
	player: Player,
	requestedWave: number?,
	isPlaytest: boolean
): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	local match = matchFor(player)
	if match.waveRunning then
		return false, "A wave is already running"
	end
	if match.baseHealth <= 0 then
		matches[player] = defaultMatch()
		match = matches[player]
		match.isPlaytest = isPlaytest
		publishPlacements()
	end
	local grid = readGrid(player)
	if grid == nil then
		return false, "Grid is unavailable"
	end
	local graph = StageRuntimeService.firstGraph(grid.stage)
	if graph == nil or #StageRuntimeService.spawnNodes(graph) == 0 then
		return false, "The active stage needs a valid route graph"
	end

	match.wave = requestedWave or (match.wave + 1)
	match.waveRunning = true
	match.isPlaytest = isPlaytest
	match.stageId = grid.stage.id
	match.graphId = graph.id
	match.graph = graph
	local waveSet = StageCatalog.waveSetForStage(grid.stage.id)
	local wave: StageTypes.WaveDefinition
	local waveCount: number
	if waveSet ~= nil then
		wave, waveCount = TowerDefenseWaves.waveForIndex(waveSet, match.wave)
	else
		wave = TowerDefenseWaves.fromCatalogWave(TowerDefenseCatalog.wave(match.wave))
		waveCount = #TowerDefenseCatalog.waves
	end
	local loopScale = TowerDefenseLogic.waveScale(match.wave, waveCount)
	match.spawnStreams = TowerDefenseWaves.buildStreams(wave, os.clock(), loopScale)
	match.waveIsBoss = TowerDefenseWaves.isBossWave(wave)
	match.waveCount = waveCount
	if not match.isPlaytest then
		profile.towerDefense.stats.bestWave = math.max(profile.towerDefense.stats.bestWave, match.wave)
		ProfileService.markDirty(player, "towerDefense:startWave")
	end
	return true, `Started wave {match.wave}`
end

function TowerDefenseService.startWave(player: Player): (boolean, string)
	return startWaveInternal(player, nil, StageRuntimeService.isPlaytesting(player))
end

function TowerDefenseService.runWavePlaytest(
	player: Player,
	stageId: string,
	waveNumber: number
): (boolean, string)
	if not RunService:IsStudio() or StageCatalog.isPlaytestCatalog ~= true then
		return false, "Stagewright playtest is unavailable"
	end
	if not StageRuntimeService.hasPlatform(player) then
		return false, "No tower-defense platform is available"
	end
	local stage = StageCatalog.get(stageId)
	local waveSet = StageCatalog.waveSetForStage(stageId)
	if stage == nil or waveSet == nil or waveNumber < 1 or waveNumber > #waveSet.waves then
		return false, "Unknown playtest level or wave"
	end
	local activated, activationMessage = StageRuntimeService.activateForPlaytest(player, stageId)
	if not activated then
		return false, activationMessage
	end
	local match = defaultMatch()
	match.isPlaytest = true
	matches[player] = match
	publishPlacements()
	local started, message = startWaveInternal(player, waveNumber, true)
	if not started then
		return false, message
	end
	return true, `{activationMessage}; {message}`
end

function TowerDefenseService.resetMatch(player: Player): (boolean, string)
	matches[player] = defaultMatch()
	publishPlacements()
	return true, "Tower defense match reset"
end

function TowerDefenseService.activateStage(player: Player, stageId: any): (boolean, string)
	local activation = TowerDefenseRequest.parseStageActivation({ stageId = stageId })
	if activation == nil then
		return false, "Invalid stage"
	end
	if not StageRuntimeService.hasPlatform(player) then
		return false, "No tower-defense platform is available"
	end
	local match = matches[player]
	if match ~= nil and match.waveRunning then
		return false, "Finish or reset the current wave before changing stages"
	end
	local ok, message = StageRuntimeService.activate(player, activation.stageId)
	if not ok then
		return false, message
	end
	matches[player] = defaultMatch()
	publishPlacements()
	return true, message
end

local function removeEnemy(match: MatchState, enemyId: string)
	match.enemies[enemyId] = nil
	for index, id in match.enemyOrder do
		if id == enemyId then
			table.remove(match.enemyOrder, index)
			break
		end
	end
end

local function tickSpawns(player: Player, match: MatchState, now: number)
	if not match.waveRunning then
		return
	end
	-- Each due stream spawns at most one enemy per pass: advancing nextSpawnAt
	-- past `now` guarantees the loop terminates within one simulation step.
	local dueIndex = TowerDefenseWaves.dueStreamIndex(match.spawnStreams, now)
	while dueIndex ~= nil do
		local stream = match.spawnStreams[dueIndex]
		if not spawnEnemy(player, match, stream) then
			return
		end
		stream.remaining -= 1
		stream.nextSpawnAt = now + stream.spacingSeconds
		if stream.remaining <= 0 then
			table.remove(match.spawnStreams, dueIndex)
		end
		dueIndex = TowerDefenseWaves.dueStreamIndex(match.spawnStreams, now)
	end
end

local function tickEnemies(player: Player, match: MatchState, deltaTime: number)
	local graph = match.graph
	local stage = StageRuntimeService.activeStage(player)
	if graph == nil or stage == nil or stage.id ~= match.stageId then
		return
	end
	local function invalidateRoute(nodeOrEdgeId: string, reason: string)
		warn(`Invalid Stagewright route {match.stageId}/{match.graphId} at {nodeOrEdgeId}: {reason}`)
		abortWave(match)
		for _, id in table.clone(match.enemyOrder) do
			removeEnemy(match, id)
		end
		publishEnemies(player)
	end
	for _, enemyId in table.clone(match.enemyOrder) do
		local enemy = match.enemies[enemyId]
		if enemy == nil then
			continue
		end
		local remaining = enemy.speed * deltaTime
		enemy.distance += remaining
		if enemy.distance > graph.maxTravelDistance then
			invalidateRoute(enemy.edgeId, "maximum travel distance exceeded")
			return
		end
		while remaining > 0 do
			local edge = graph.edges[enemy.edgeId]
			if edge == nil or edge.length <= 0 then
				invalidateRoute(enemy.edgeId, "missing or zero-length edge")
				return
			end
			local available = math.max(edge.length - enemy.edgeDistance, 0)
			if remaining < available then
				enemy.edgeDistance += remaining
				remaining = 0
				break
			end
			remaining -= available
			enemy.edgeDistance = edge.length
			local node = graph.nodes[edge.toNodeId]
			if node == nil then
				invalidateRoute(edge.id, "destination node is missing")
				return
			end
			enemy.nodeVisits[node.id] = (enemy.nodeVisits[node.id] or 0) + 1
			local totalVisits = 0
			for _, count in enemy.nodeVisits do
				totalVisits += count
			end
			if totalVisits > graph.maxNodeVisitsPerEnemy then
				invalidateRoute(node.id, "maximum node visits exceeded")
				return
			end
			if node.kind == "Goal" then
				match.baseHealth = math.max(match.baseHealth - enemy.baseDamage, 0)
				removeEnemy(match, enemyId)
				if match.baseHealth <= 0 then
					local profile = ProfileService.get(player)
					if profile ~= nil and not match.isPlaytest then
						profile.towerDefense.stats.losses += 1
						ProfileService.markDirty(player, "towerDefense:loss")
					end
					abortWave(match)
					for _, id in table.clone(match.enemyOrder) do
						removeEnemy(match, id)
					end
					publish(player)
					return
				end
				break
			end
			local context = StageRuntimeService.context(
				player,
				match.wave,
				enemy.tags,
				enemy.nodeVisits,
				match.stageFlags
			)
			local nextEdge, reason = StageRuntimeService.chooseEdge(graph, node.id, context)
			if nextEdge == nil then
				invalidateRoute(node.id, reason or "no eligible edge")
				return
			end
			enemy.edgeId = nextEdge.id
			enemy.edgeDistance = 0
			local laneProfile = graph.laneProfiles[nextEdge.laneProfileId]
			local laneCount = if laneProfile ~= nil and #laneProfile.offsets > 0
				then #laneProfile.offsets
				else 1
			enemy.laneIndex = StageLanes.index(enemy.laneSequence, laneCount)
		end
	end
end

local function enemyPosition(player: Player, match: MatchState, enemy: Enemy): Vector3?
	local stage = StageRuntimeService.activeStage(player)
	local graph = match.graph
	if stage == nil or graph == nil or stage.id ~= match.stageId then
		return nil
	end
	local frame = StageRuntimeService.sampleEdge(
		player,
		stage,
		graph,
		enemy.edgeId,
		enemy.edgeDistance,
		enemy.laneIndex
	)
	return if frame ~= nil then frame.Position else nil
end

type EnemySpatialIndex = {
	positions: { [string]: Vector3 },
	buckets: { [string]: { Enemy } },
	bucketSize: number,
}

local function spatialKey(position: Vector3, bucketSize: number): string
	return `{math.floor(position.X / bucketSize)}:{math.floor(position.Z / bucketSize)}`
end

local function buildEnemySpatialIndex(player: Player, match: MatchState): EnemySpatialIndex
	local bucketSize = 32
	local index: EnemySpatialIndex = { positions = {}, buckets = {}, bucketSize = bucketSize }
	for enemyId, enemy in match.enemies do
		local position = enemyPosition(player, match, enemy)
		if position ~= nil then
			index.positions[enemyId] = position
			local key = spatialKey(position, bucketSize)
			local bucket = index.buckets[key]
			if bucket == nil then
				bucket = {}
				index.buckets[key] = bucket
			end
			table.insert(bucket, enemy)
		end
	end
	return index
end

local function findTarget(
	placement: Placement,
	unit: TowerDefenseCatalog.UnitDefinition,
	spatial: EnemySpatialIndex
): Enemy?
	local bestEnemy: Enemy? = nil
	local bestScore = -math.huge
	local radius = math.ceil(unit.range / spatial.bucketSize)
	local centerX = math.floor(placement.position.X / spatial.bucketSize)
	local centerZ = math.floor(placement.position.Z / spatial.bucketSize)
	for offsetX = -radius, radius do
		for offsetZ = -radius, radius do
			local bucket = spatial.buckets[`{centerX + offsetX}:{centerZ + offsetZ}`] or {}
			for _, enemy in bucket do
				local position = spatial.positions[enemy.id]
				if position == nil or (position - placement.position).Magnitude > unit.range then
					continue
				end
				local score = if unit.targeting == "Nearest"
					then -(position - placement.position).Magnitude
					else enemy.distance
				if score > bestScore then
					bestScore = score
					bestEnemy = enemy
				end
			end
		end
	end
	return bestEnemy
end

local function tickTowers(player: Player, match: MatchState, now: number)
	local spatial = buildEnemySpatialIndex(player, match)
	for _, placementId in match.placementOrder do
		local placement = match.placements[placementId]
		if placement == nil or now < placement.nextAttackAt then
			continue
		end
		local unit = TowerDefenseCatalog.unit(placement.unitId)
		if unit == nil then
			continue
		end
		local target = findTarget(placement, unit, spatial)
		if target == nil then
			continue
		end
		target.health -= unit.damage * target.armorMultiplier
		placement.nextAttackAt = now + unit.fireRate
		if target.health <= 0 then
			EconomyService.awardCurrencyRaw(
				player,
				Config.economy.primaryCurrencyId,
				target.reward,
				"towerDefense:enemy"
			)
			removeEnemy(match, target.id)
		end
	end
end

local function tickWaveCompletion(player: Player, match: MatchState)
	if
		match.waveRunning
		and #match.spawnStreams == 0
		and next(match.enemies) == nil
		and match.baseHealth > 0
	then
		match.waveRunning = false
		local profile = ProfileService.get(player)
		if profile ~= nil and not match.isPlaytest then
			profile.towerDefense.stats.wins += 1
			profile.towerDefense.stats.bestWave = math.max(profile.towerDefense.stats.bestWave, match.wave)
			local stageProgress = profile.towerDefense.stageProgress[match.stageId]
			if stageProgress == nil then
				stageProgress = { unlocked = true, clears = 0, bestWave = 0 }
				profile.towerDefense.stageProgress[match.stageId] = stageProgress
			end
			stageProgress.unlocked = true
			stageProgress.clears += 1
			stageProgress.bestWave = math.max(stageProgress.bestWave, match.wave)
			local nextLevelId = StageCatalog.nextLevelId(match.stageId)
			if nextLevelId ~= nil then
				local nextProgress = profile.towerDefense.stageProgress[nextLevelId]
				if type(nextProgress) ~= "table" then
					nextProgress = { unlocked = true, clears = 0, bestWave = 0 }
					profile.towerDefense.stageProgress[nextLevelId] = nextProgress
				else
					nextProgress.unlocked = true
				end
			end
			ProfileService.markDirty(player, "towerDefense:waveClear")
		end
		publish(player)
	end
end

local simulationAccumulator = 0

local function tick(deltaTime: number)
	if Config.features.towerDefense ~= true then
		return
	end
	local step = 1 / math.max(Config.towerDefense.simulationHz, 1)
	simulationAccumulator += math.min(deltaTime, step * 4)
	while simulationAccumulator >= step do
		simulationAccumulator -= step
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local match = matches[player]
			if match == nil or not match.waveRunning then
				continue
			end
			tickSpawns(player, match, now)
			tickEnemies(player, match, step)
			tickTowers(player, match, now)
			tickWaveCompletion(player, match)
			if match.waveRunning and now >= match.nextSnapshotAt then
				match.nextSnapshotAt = now + 1 / math.max(Config.towerDefense.networkSnapshotHz, 1)
				publishEnemies(player)
			end
		end
	end
end

function TowerDefenseService.presentationSnapshot(): ({ TowerDefensePresentationPlacement }, number)
	local snapshot: { TowerDefensePresentationPlacement } = {}
	local players = Players:GetPlayers()
	table.sort(players, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, player in players do
		local match = matches[player]
		local slot = player:GetAttribute("TowerDefensePlatformSlot")
		if
			match == nil
			or type(slot) ~= "number"
			or slot % 1 ~= 0
			or slot < 1
			or slot > Config.towerDefense.platformSlotCount
		then
			continue
		end
		for _, placementId in match.placementOrder do
			local placement = match.placements[placementId]
			if placement ~= nil then
				table.insert(snapshot, {
					ownerUserId = player.UserId,
					slot = slot,
					id = placement.id,
					unitId = placement.unitId,
					cell = {
						column = placement.cell.column,
						row = placement.cell.row,
					},
					frame = CFrame.new(placement.position) * CFrame.Angles(0, 0, math.rad(90)),
				})
			end
		end
	end
	return snapshot, placementRevision
end

function TowerDefenseService.snapshotFor(player: Player): TowerDefenseClientState?
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	local match = matchFor(player)
	local grid = readGrid(player)
	local activeStageId = StageRuntimeService.activeStageId(player)
	local activeWaveSet = StageCatalog.waveSetForStage(activeStageId)
	local displayedWaveCount = if match.waveCount > 0
		then match.waveCount
		elseif activeWaveSet ~= nil then #activeWaveSet.waves
		else #TowerDefenseCatalog.waves
	local levelOptions: { TowerDefenseLevelOption } = {}
	for _, stageId in StageCatalog.levelIds(1) do
		if #levelOptions >= Config.towerDefense.levelSelectorSlots then
			break
		end
		local stage = StageCatalog.get(stageId)
		local address = StageCatalog.address(stageId)
		if stage ~= nil and address ~= nil then
			table.insert(levelOptions, {
				id = stageId,
				name = stage.name,
				levelNumber = address.levelNumber,
				unlocked = StageRuntimeService.isUnlocked(player, stageId),
			})
		end
	end
	local placements: { TowerDefensePlacementState } = {}
	for _, placementId in match.placementOrder do
		local placement = match.placements[placementId]
		if placement ~= nil then
			table.insert(placements, {
				id = placement.id,
				unitId = placement.unitId,
				cell = {
					column = placement.cell.column,
					row = placement.cell.row,
				},
			})
		end
	end
	local enemies: { TowerDefenseEnemyState } = {}
	local serverTime = Workspace:GetServerTimeNow()
	for _, enemyId in match.enemyOrder do
		local enemy = match.enemies[enemyId]
		if enemy ~= nil then
			local edge = if match.graph ~= nil then match.graph.edges[enemy.edgeId] else nil
			local edgeLength = if edge ~= nil then edge.length else 1
			table.insert(enemies, {
				id = enemy.id,
				enemyTypeId = enemy.enemyTypeId,
				isBoss = enemy.isBoss,
				health = enemy.health,
				maxHealth = enemy.maxHealth,
				progress = math.clamp(enemy.edgeDistance / math.max(edgeLength, 1), 0, 1),
				stageId = match.stageId,
				graphId = match.graphId,
				edgeId = enemy.edgeId,
				edgeDistance = enemy.edgeDistance,
				edgeLength = edgeLength,
				speed = enemy.speed,
				laneIndex = enemy.laneIndex,
				distanceTraveled = enemy.distance,
				serverTime = serverTime,
			})
		end
	end
	return {
		activeStageId = activeStageId,
		stageOrigin = if grid ~= nil then StageRuntimeService.originFor(player, grid.stage) else CFrame.new(),
		ownedUnits = profile.towerDefense.ownedUnits,
		loadout = profile.towerDefense.loadout,
		rollCost = Config.towerDefense.unitRollCost,
		loadoutSlots = unlockedLoadoutSlots(profile.towerDefense),
		maximumLoadoutSlots = Config.towerDefense.loadoutSlots,
		nextLoadoutSlotCost = nextLoadoutSlotCost(profile.towerDefense),
		baseHealth = match.baseHealth,
		maxBaseHealth = Config.towerDefense.baseHealth,
		wave = match.wave,
		waveRunning = match.waveRunning,
		waveIsBoss = match.waveIsBoss,
		waveCount = displayedWaveCount,
		levelOptions = levelOptions,
		placements = placements,
		enemies = enemies,
		autoPlaceCells = if grid ~= nil then grid.autoPlaceCells else {},
		portalCells = if grid ~= nil then grid.portalCells else {},
		goalCells = if grid ~= nil then grid.goalCells else {},
	}
end

function TowerDefenseService.start(options: {
	publish: (player: Player) -> (),
	publishEnemies: ((player: Player) -> ())?,
	publishPlacements: (() -> ())?,
})
	publishSnapshot = options.publish
	publishEnemyCorrection = options.publishEnemies
	publishPlacementSnapshot = options.publishPlacements
	if loopConnected or Config.features.towerDefense ~= true then
		return
	end
	loopConnected = true
	RunService.Heartbeat:Connect(tick)
end

function TowerDefenseService.forget(player: Player)
	local hadMatch = matches[player] ~= nil
	matches[player] = nil
	if hadMatch then
		publishPlacements()
	end
end

return TowerDefenseService

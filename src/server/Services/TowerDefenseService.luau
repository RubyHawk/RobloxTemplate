--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local StageLanes = require(Shared.StageLanes)
local TowerDefenseCatalog = require(Shared.TowerDefenseCatalog)
local TowerDefenseLogic = require(Shared.TowerDefenseLogic)
local Types = require(Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local StageRuntimeService = require(script.Parent.StageRuntimeService)

type TowerDefenseClientState = Types.TowerDefenseClientState
type TowerDefenseEnemyState = Types.TowerDefenseEnemyState
type TowerDefensePlacementState = Types.TowerDefensePlacementState

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
	part: BasePart?,
}

type Enemy = {
	id: string,
	name: string,
	health: number,
	maxHealth: number,
	speed: number,
	reward: number,
	baseDamage: number,
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
	pendingSpawns: number,
	nextSpawnAt: number,
	spawnSpacing: number,
	spawnEnemyId: string,
	enemyHealthScale: number,
	enemyRewardScale: number,
	stageId: string,
	graphId: string,
	graph: any?,
	stageFlags: { [string]: boolean },
	nextSnapshotAt: number,
	folder: Folder?,
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
local NAMEPLATE_NAME = "DebugNameplate"
local HEALTH_BAR_FILL_NAME = "HealthBarFill"
local HEALTH_TEXT_NAME = "HealthText"
local rng = Random.new()
local matches: { [Player]: MatchState } = {}
local publishSnapshot: ((player: Player) -> ())? = nil
local publishEnemyCorrection: ((player: Player) -> ())? = nil
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

local function ensureRuntimeFolder(player: Player, match: MatchState): Folder
	if match.folder ~= nil and match.folder.Parent ~= nil then
		return match.folder
	end
	local root = Workspace:FindFirstChild(Config.towerDefense.runtimeFolderName)
	if root == nil or not root:IsA("Folder") then
		if root ~= nil then
			root:Destroy()
		end
		root = Instance.new("Folder")
		root.Name = Config.towerDefense.runtimeFolderName
		root.Parent = Workspace
	end
	local folder = root:FindFirstChild(tostring(player.UserId))
	if folder == nil or not folder:IsA("Folder") then
		if folder ~= nil then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = tostring(player.UserId)
		folder.Parent = root
	end
	match.folder = folder
	return folder
end

local function createDebugNameplate(
	part: BasePart,
	title: string,
	subtitle: string,
	fillColor: Color3
): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = NAMEPLATE_NAME
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Size = UDim2.fromOffset(170, 58)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.9, 0)
	billboard.Parent = part

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.fromRGB(12, 18, 16)
	root.BackgroundTransparency = 0.18
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(184, 226, 181)
	stroke.Transparency = 0.22
	stroke.Thickness = 1
	stroke.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameText"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.Position = UDim2.fromOffset(8, 3)
	nameLabel.Size = UDim2.new(1, -16, 0, 20)
	nameLabel.Text = title
	nameLabel.TextColor3 = Color3.fromRGB(242, 255, 237)
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Parent = root

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "SubtitleText"
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.SourceSans
	subtitleLabel.Position = UDim2.fromOffset(8, 23)
	subtitleLabel.Size = UDim2.new(1, -16, 0, 14)
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.fromRGB(190, 214, 188)
	subtitleLabel.TextScaled = true
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	subtitleLabel.Parent = root

	local bar = Instance.new("Frame")
	bar.Name = "HealthBar"
	bar.BackgroundColor3 = Color3.fromRGB(42, 51, 46)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(10, 40)
	bar.Size = UDim2.new(1, -20, 0, 9)
	bar.Parent = root

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = HEALTH_BAR_FILL_NAME
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local healthText = Instance.new("TextLabel")
	healthText.Name = HEALTH_TEXT_NAME
	healthText.BackgroundTransparency = 1
	healthText.Font = Enum.Font.SourceSansBold
	healthText.Position = UDim2.fromOffset(10, 39)
	healthText.Size = UDim2.new(1, -20, 0, 11)
	healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
	healthText.TextScaled = true
	healthText.TextXAlignment = Enum.TextXAlignment.Center
	healthText.Parent = root

	return billboard
end

local function setNameplateBar(part: BasePart?, current: number, maximum: number, label: string?)
	if part == nil then
		return
	end
	local billboard = part:FindFirstChild(NAMEPLATE_NAME)
	if billboard == nil or not billboard:IsA("BillboardGui") then
		return
	end
	local root = billboard:FindFirstChild("Root")
	if root == nil or not root:IsA("Frame") then
		return
	end
	local bar = root:FindFirstChild("HealthBar")
	local healthText = root:FindFirstChild(HEALTH_TEXT_NAME)
	if bar ~= nil and bar:IsA("Frame") then
		local fill = bar:FindFirstChild(HEALTH_BAR_FILL_NAME)
		if fill ~= nil and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(math.clamp(current / math.max(maximum, 1), 0, 1), 1)
		end
	end
	if healthText ~= nil and healthText:IsA("TextLabel") then
		healthText.Text = label or `{math.max(math.ceil(current), 0)}/{math.max(math.ceil(maximum), 1)} HP`
	end
end

local function createTowerPart(player: Player, match: MatchState, placement: Placement): BasePart
	local part = Instance.new("Part")
	part.Name = placement.id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(1.4, 2.6, 2.6)
	part.Color = Color3.fromRGB(78, 151, 73)
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(placement.position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = ensureRuntimeFolder(player, match)
	local unit = TowerDefenseCatalog.unit(placement.unitId)
	createDebugNameplate(
		part,
		if unit ~= nil then unit.name else placement.unitId,
		`Cell {placement.cell.column}, {placement.cell.row}`,
		Color3.fromRGB(82, 196, 104)
	)
	setNameplateBar(part, 1, 1, "1/1 HP")
	return part
end

local function clearRuntime(match: MatchState)
	if match.folder ~= nil then
		match.folder:Destroy()
		match.folder = nil
	end
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
		pendingSpawns = 0,
		nextSpawnAt = 0,
		spawnSpacing = 0,
		spawnEnemyId = "",
		enemyHealthScale = 1,
		enemyRewardScale = 1,
		stageId = "",
		graphId = "",
		graph = nil,
		stageFlags = {},
		nextSnapshotAt = 0,
		folder = nil,
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

local function profileTowerState(player: Player): Types.TowerDefenseSaveState?
	local profile = ProfileService.get(player)
	return if profile then profile.towerDefense else nil
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
	td.loadout = TowerDefenseLogic.bestLoadout(
		td.ownedUnits,
		TowerDefenseCatalog.units,
		Config.towerDefense.loadoutSlots
	)
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
		#profile.towerDefense.loadout < Config.towerDefense.loadoutSlots and not inLoadout(player, unit.id)
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
	if type(unitIds) ~= "table" then
		return false, "Invalid loadout"
	end
	local nextLoadout: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, unitId in unitIds do
		if #nextLoadout >= Config.towerDefense.loadoutSlots then
			break
		end
		if type(unitId) ~= "string" or #unitId > 64 or seen[unitId] then
			return false, "Invalid unit"
		end
		if TowerDefenseCatalog.unit(unitId) == nil or not hasUnit(player, unitId) then
			return false, "Unit is not owned"
		end
		seen[unitId] = true
		table.insert(nextLoadout, unitId)
	end
	td.loadout = nextLoadout
	ProfileService.markDirty(player, "towerDefense:setLoadout")
	return true, "Loadout updated"
end

function TowerDefenseService.equipBest(player: Player): (boolean, string)
	return setBestLoadout(player)
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
		part = nil,
	}
	placement.part = createTowerPart(player, match, placement)
	match.placements[id] = placement
	table.insert(match.placementOrder, id)
	return true, `Placed {unit.name}`
end

function TowerDefenseService.placeUnit(player: Player, unitId: any, column: any, row: any): (boolean, string)
	if type(unitId) ~= "string" or #unitId > 64 or type(column) ~= "number" or type(row) ~= "number" then
		return false, "Invalid placement"
	end
	return placeUnitInternal(player, unitId, {
		column = math.floor(column),
		row = math.floor(row),
	}, true)
end

function TowerDefenseService.autoPlaceBest(player: Player): (boolean, string)
	local ok, message = setBestLoadout(player)
	if not ok then
		return false, message
	end
	local td = profileTowerState(player)
	local grid = readGrid(player)
	if td == nil or grid == nil then
		return false, "Grid is unavailable"
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
	publish(player)
	return placed > 0,
		if placed > 0 then `Auto-placed {placed} unit(s)` else "No auto-place slots were available"
end

local function spawnEnemy(player: Player, match: MatchState)
	local enemyDefinition = TowerDefenseCatalog.enemy(match.spawnEnemyId)
	local graph = match.graph
	if enemyDefinition == nil or graph == nil then
		return
	end
	if #match.enemyOrder >= Config.towerDefense.maximumEnemiesPerPlayer then
		warn(`Tower defense spawn rejected: enemy cap reached for {player.Name}`)
		match.waveRunning = false
		match.pendingSpawns = 0
		return
	end
	local spawnNodes = StageRuntimeService.spawnNodes(graph)
	if #spawnNodes == 0 then
		warn(`Tower defense graph {match.graphId} has no spawn node`)
		match.waveRunning = false
		match.pendingSpawns = 0
		return
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
		match.waveRunning = false
		match.pendingSpawns = 0
		return
	end
	local laneProfile = graph.laneProfiles[firstEdge.laneProfileId]
	local laneCount = if laneProfile ~= nil and #laneProfile.offsets > 0 then #laneProfile.offsets else 1
	match.nextEnemyId += 1
	local maxHealth = math.floor(enemyDefinition.health * match.enemyHealthScale)
	local enemy: Enemy = {
		id = `Enemy_{match.nextEnemyId}`,
		name = enemyDefinition.name,
		health = maxHealth,
		maxHealth = maxHealth,
		speed = enemyDefinition.speed,
		reward = math.floor(enemyDefinition.reward * match.enemyRewardScale),
		baseDamage = enemyDefinition.baseDamage,
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
end

function TowerDefenseService.startWave(player: Player): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	local match = matchFor(player)
	if match.waveRunning then
		return false, "A wave is already running"
	end
	if match.baseHealth <= 0 then
		clearRuntime(match)
		matches[player] = defaultMatch()
		match = matches[player]
	end
	local grid = readGrid(player)
	if grid == nil then
		return false, "Grid is unavailable"
	end
	local graph = StageRuntimeService.firstGraph(grid.stage)
	if graph == nil or #StageRuntimeService.spawnNodes(graph) == 0 then
		return false, "The active stage needs a valid route graph"
	end

	match.wave += 1
	match.waveRunning = true
	match.stageId = grid.stage.id
	match.graphId = graph.id
	match.graph = graph
	local wave = TowerDefenseCatalog.wave(match.wave)
	local loopScale = TowerDefenseLogic.waveScale(match.wave)
	match.pendingSpawns = math.max(wave.count, 1)
	match.nextSpawnAt = os.clock()
	match.spawnSpacing = math.max(wave.spacingSeconds, 0.1)
	match.spawnEnemyId = wave.enemyId
	match.enemyHealthScale = wave.healthScale * loopScale
	match.enemyRewardScale = wave.rewardScale * loopScale
	profile.towerDefense.stats.bestWave = math.max(profile.towerDefense.stats.bestWave, match.wave)
	ProfileService.markDirty(player, "towerDefense:startWave")
	return true, `Started wave {match.wave}`
end

function TowerDefenseService.resetMatch(player: Player): (boolean, string)
	local match = matches[player]
	if match ~= nil then
		clearRuntime(match)
	end
	matches[player] = defaultMatch()
	publish(player)
	return true, "Tower defense match reset"
end

function TowerDefenseService.activateStage(player: Player, stageId: any): (boolean, string)
	if not StageRuntimeService.hasPlatform(player) then
		return false, "No tower-defense platform is available"
	end
	local match = matches[player]
	if match ~= nil and match.waveRunning then
		return false, "Finish or reset the current wave before changing stages"
	end
	local ok, message = StageRuntimeService.activate(player, stageId)
	if not ok then
		return false, message
	end
	if match ~= nil then
		clearRuntime(match)
	end
	matches[player] = defaultMatch()
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

local function clearDeadPart(part: BasePart?)
	if part ~= nil and part.Parent ~= nil then
		part:Destroy()
	end
end

local function tickSpawns(player: Player, match: MatchState, now: number)
	if not match.waveRunning or match.pendingSpawns <= 0 or now < match.nextSpawnAt then
		return
	end
	spawnEnemy(player, match)
	match.pendingSpawns -= 1
	match.nextSpawnAt = now + match.spawnSpacing
end

local function tickEnemies(player: Player, match: MatchState, deltaTime: number)
	local graph = match.graph
	local stage = StageRuntimeService.activeStage(player)
	if graph == nil or stage == nil or stage.id ~= match.stageId then
		return
	end
	local function invalidateRoute(nodeOrEdgeId: string, reason: string)
		warn(`Invalid Stagewright route {match.stageId}/{match.graphId} at {nodeOrEdgeId}: {reason}`)
		match.waveRunning = false
		match.pendingSpawns = 0
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
					if profile ~= nil then
						profile.towerDefense.stats.losses += 1
						ProfileService.markDirty(player, "towerDefense:loss")
					end
					match.waveRunning = false
					match.pendingSpawns = 0
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
		target.health -= unit.damage
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
		and match.pendingSpawns <= 0
		and next(match.enemies) == nil
		and match.baseHealth > 0
	then
		match.waveRunning = false
		local profile = ProfileService.get(player)
		if profile ~= nil then
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

function TowerDefenseService.snapshotFor(player: Player): TowerDefenseClientState?
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	local match = matchFor(player)
	local grid = readGrid(player)
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
		activeStageId = StageRuntimeService.activeStageId(player),
		stageOrigin = if grid ~= nil then StageRuntimeService.originFor(player, grid.stage) else CFrame.new(),
		ownedUnits = profile.towerDefense.ownedUnits,
		loadout = profile.towerDefense.loadout,
		rollCost = Config.towerDefense.unitRollCost,
		loadoutSlots = Config.towerDefense.loadoutSlots,
		baseHealth = match.baseHealth,
		maxBaseHealth = Config.towerDefense.baseHealth,
		wave = match.wave,
		waveRunning = match.waveRunning,
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
})
	publishSnapshot = options.publish
	publishEnemyCorrection = options.publishEnemies
	if loopConnected or Config.features.towerDefense ~= true then
		return
	end
	loopConnected = true
	RunService.Heartbeat:Connect(tick)
end

function TowerDefenseService.forget(player: Player)
	local match = matches[player]
	if match ~= nil then
		for _, placement in match.placements do
			clearDeadPart(placement.part)
		end
		clearRuntime(match)
	end
	matches[player] = nil
end

return TowerDefenseService

--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local TowerDefenseCatalog = require(Shared.TowerDefenseCatalog)
local TowerDefenseLogic = require(Shared.TowerDefenseLogic)
local Types = require(Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)

type TowerDefenseClientState = Types.TowerDefenseClientState
type TowerDefenseEnemyState = Types.TowerDefenseEnemyState
type TowerDefensePlacementState = Types.TowerDefensePlacementState

type Cell = {
	column: number,
	row: number,
}

type SplineSample = {
	position: Vector3,
	distance: number,
}

type SplinePath = {
	samples: { SplineSample },
	length: number,
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
	part: BasePart?,
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
	path: SplinePath?,
	folder: Folder?,
}

type GridData = {
	base: BasePart,
	cellSize: number,
	columns: number,
	rows: number,
	map: { string },
	autoPlaceCells: { Cell },
	portalCells: { Cell },
	goalCells: { Cell },
	pathPoints: { BasePart },
}

local TowerDefenseService = {}

local ISLAND_NAME = "FirstPrivateIsland"
local PLATFORM_NAME = "GamePlatform"
local MAP_NAME = "CellMap"
local PATH_POINTS_NAME = "PathPoints"
local SPLINE_SAMPLES_PER_SEGMENT = 18
local ENEMY_VERTICAL_OFFSET = 1.25
local TOWER_VERTICAL_OFFSET = 1.35
local NAMEPLATE_NAME = "DebugNameplate"
local HEALTH_BAR_FILL_NAME = "HealthBarFill"
local HEALTH_TEXT_NAME = "HealthText"
local rng = Random.new()
local matches: { [Player]: MatchState } = {}
local publishSnapshot: ((player: Player) -> ())? = nil
local loopConnected = false

local function findModel(parent: Instance, name: string): Model?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("Model") then
		return child
	end
	return nil
end

local function findFolder(parent: Instance, name: string): Folder?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("Folder") then
		return child
	end
	return nil
end

local function findInt(parent: Instance, name: string, fallback: number): number
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("IntValue") then
		return child.Value
	end
	return fallback
end

local function platformModel(): Model?
	local island = findModel(Workspace, ISLAND_NAME)
	if island == nil then
		return nil
	end
	return findModel(island, PLATFORM_NAME)
end

local function platformBasePart(platform: Model): BasePart?
	local base = platform:FindFirstChild("PlatformBase")
	if base ~= nil and base:IsA("BasePart") then
		return base
	end
	return nil
end

local function collectPathPoints(platform: Model): { BasePart }
	local folder = findFolder(platform, PATH_POINTS_NAME)
	local points: { BasePart } = {}
	if folder == nil then
		return points
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(left, right)
		return left.Name < right.Name
	end)
	return points
end

local function readGrid(): GridData?
	local platform = platformModel()
	if platform == nil then
		return nil
	end
	local base = platformBasePart(platform)
	local cellMap = findFolder(platform, MAP_NAME)
	if base == nil or cellMap == nil then
		return nil
	end

	local columns = findInt(platform, "Columns", 32)
	local rows = findInt(platform, "Rows", 27)
	local cellSize = findInt(platform, "CellSize", 4)
	local map: { string } = {}
	local autoPlaceCells: { Cell } = {}
	local portalCells: { Cell } = {}
	local goalCells: { Cell } = {}

	for row = 1, rows do
		local rowNode = cellMap:FindFirstChild(`Row_{string.format("%02d", row)}`)
		local rowValue = if rowNode ~= nil and rowNode:IsA("StringValue") then rowNode.Value else ""
		if #rowValue < columns then
			rowValue ..= string.rep(".", columns - #rowValue)
		end
		map[row] = rowValue
		for column = 1, columns do
			local code = TowerDefenseLogic.normalizeCellCode(string.sub(rowValue, column, column))
			if code == "A" then
				table.insert(autoPlaceCells, { column = column, row = row })
			elseif code == "P" then
				table.insert(portalCells, { column = column, row = row })
			elseif code == "G" then
				table.insert(goalCells, { column = column, row = row })
			end
		end
	end

	return {
		base = base,
		cellSize = cellSize,
		columns = columns,
		rows = rows,
		map = map,
		autoPlaceCells = autoPlaceCells,
		portalCells = portalCells,
		goalCells = goalCells,
		pathPoints = collectPathPoints(platform),
	}
end

local function cellCode(grid: GridData, cell: Cell): string
	if cell.column < 1 or cell.column > grid.columns or cell.row < 1 or cell.row > grid.rows then
		return "#"
	end
	return TowerDefenseLogic.normalizeCellCode(string.sub(grid.map[cell.row] or "", cell.column, cell.column))
end

local function cellKey(cell: Cell): string
	return `{cell.column}:{cell.row}`
end

local function cellWorldPosition(grid: GridData, cell: Cell, verticalOffset: number): Vector3
	local localX = -grid.base.Size.X / 2 + (cell.column - 0.5) * grid.cellSize
	local localZ = -grid.base.Size.Z / 2 + (cell.row - 0.5) * grid.cellSize
	return grid.base.CFrame:PointToWorldSpace(
		Vector3.new(localX, grid.base.Size.Y / 2 + verticalOffset, localZ)
	)
end

local function controlPointPosition(points: { Vector3 }, index: number): Vector3
	return points[math.clamp(index, 1, #points)]
end

local function catmullRomPosition(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local alpha2 = alpha * alpha
	local alpha3 = alpha2 * alpha
	return (
		(p1 * 2)
		+ ((p2 - p0) * alpha)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * alpha2)
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * alpha3)
	) * 0.5
end

local function buildSplinePath(positions: { Vector3 }): SplinePath?
	if #positions < 2 then
		return nil
	end
	local samples: { SplineSample } = {}
	local totalDistance = 0
	local function insertSample(position: Vector3)
		if #samples > 0 then
			totalDistance += (position - samples[#samples].position).Magnitude
		end
		table.insert(samples, { position = position, distance = totalDistance })
	end
	for segment = 1, #positions - 1 do
		local p0 = controlPointPosition(positions, segment - 1)
		local p1 = controlPointPosition(positions, segment)
		local p2 = controlPointPosition(positions, segment + 1)
		local p3 = controlPointPosition(positions, segment + 2)
		for step = 0, SPLINE_SAMPLES_PER_SEGMENT do
			if segment > 1 and step == 0 then
				continue
			end
			insertSample(catmullRomPosition(p0, p1, p2, p3, step / SPLINE_SAMPLES_PER_SEGMENT))
		end
	end
	if totalDistance < 0.1 then
		return nil
	end
	return { samples = samples, length = totalDistance }
end

local function sampleSplinePath(path: SplinePath, distance: number): Vector3
	local samples = path.samples
	if distance <= 0 then
		return samples[1].position
	elseif distance >= path.length then
		return samples[#samples].position
	end
	local low = 2
	local high = #samples
	while low < high do
		local middle = math.floor((low + high) / 2)
		if samples[middle].distance < distance then
			low = middle + 1
		else
			high = middle
		end
	end
	local after = samples[low]
	local before = samples[low - 1]
	local span = after.distance - before.distance
	local alpha = if span > 0 then math.clamp((distance - before.distance) / span, 0, 1) else 0
	return before.position:Lerp(after.position, alpha)
end

local function routeForGrid(grid: GridData): SplinePath?
	local positions: { Vector3 } = {}
	if grid.portalCells[1] ~= nil then
		table.insert(positions, cellWorldPosition(grid, grid.portalCells[1], ENEMY_VERTICAL_OFFSET))
	end
	for _, point in grid.pathPoints do
		table.insert(positions, point.Position + Vector3.new(0, ENEMY_VERTICAL_OFFSET, 0))
	end
	if grid.goalCells[1] ~= nil then
		table.insert(positions, cellWorldPosition(grid, grid.goalCells[1], ENEMY_VERTICAL_OFFSET))
	end
	return buildSplinePath(positions)
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

local function createEnemyPart(player: Player, match: MatchState, enemy: Enemy): BasePart?
	local path = match.path
	if path == nil then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = enemy.id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Color = Color3.fromRGB(95, 57, 35)
	part.Material = Enum.Material.SmoothPlastic
	part.Position = sampleSplinePath(path, 0)
	part.Parent = ensureRuntimeFolder(player, match)
	createDebugNameplate(part, enemy.name, enemy.id, Color3.fromRGB(239, 68, 68))
	setNameplateBar(part, enemy.health, enemy.maxHealth, nil)
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
		path = nil,
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
	local grid = readGrid()
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
		position = cellWorldPosition(grid, cell, TOWER_VERTICAL_OFFSET),
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
	local grid = readGrid()
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
	local path = match.path
	if enemyDefinition == nil or path == nil then
		return
	end
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
		part = nil,
	}
	enemy.part = createEnemyPart(player, match, enemy)
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
	local grid = readGrid()
	if grid == nil then
		return false, "Grid is unavailable"
	end
	local path = routeForGrid(grid)
	if path == nil then
		return false, "Portal, spline path, and goal need a valid route"
	end

	match.wave += 1
	match.waveRunning = true
	match.path = path
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

local function removeEnemy(match: MatchState, enemyId: string)
	local enemy = match.enemies[enemyId]
	if enemy ~= nil and enemy.part ~= nil then
		enemy.part:Destroy()
	end
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
	local path = match.path
	if path == nil then
		return
	end
	for _, enemyId in table.clone(match.enemyOrder) do
		local enemy = match.enemies[enemyId]
		if enemy == nil then
			continue
		end
		enemy.distance += enemy.speed * deltaTime
		if enemy.distance >= path.length then
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
		elseif enemy.part ~= nil then
			enemy.part.Position = sampleSplinePath(path, enemy.distance)
		end
	end
end

local function enemyPosition(match: MatchState, enemy: Enemy): Vector3?
	if enemy.part ~= nil then
		return enemy.part.Position
	end
	local path = match.path
	return if path ~= nil then sampleSplinePath(path, enemy.distance) else nil
end

local function findTarget(
	match: MatchState,
	placement: Placement,
	unit: TowerDefenseCatalog.UnitDefinition
): Enemy?
	local bestEnemy: Enemy? = nil
	local bestScore = -math.huge
	for _, enemy in match.enemies do
		local position = enemyPosition(match, enemy)
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
	return bestEnemy
end

local function tickTowers(player: Player, match: MatchState, now: number)
	for _, placementId in match.placementOrder do
		local placement = match.placements[placementId]
		if placement == nil or now < placement.nextAttackAt then
			continue
		end
		local unit = TowerDefenseCatalog.unit(placement.unitId)
		if unit == nil then
			continue
		end
		local target = findTarget(match, placement, unit)
		if target == nil then
			continue
		end
		target.health -= unit.damage
		placement.nextAttackAt = now + unit.fireRate
		setNameplateBar(target.part, target.health, target.maxHealth, nil)
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
			ProfileService.markDirty(player, "towerDefense:waveClear")
		end
		publish(player)
	end
end

local function tick(deltaTime: number)
	if Config.features.towerDefense ~= true then
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local match = matches[player]
		if match == nil or not match.waveRunning then
			continue
		end
		tickSpawns(player, match, now)
		tickEnemies(player, match, deltaTime)
		tickTowers(player, match, now)
		tickWaveCompletion(player, match)
	end
end

function TowerDefenseService.snapshotFor(player: Player): TowerDefenseClientState?
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	local match = matchFor(player)
	local grid = readGrid()
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
	local pathLength = if match.path ~= nil then match.path.length else 1
	for _, enemyId in match.enemyOrder do
		local enemy = match.enemies[enemyId]
		if enemy ~= nil then
			table.insert(enemies, {
				id = enemy.id,
				health = enemy.health,
				maxHealth = enemy.maxHealth,
				progress = math.clamp(enemy.distance / math.max(pathLength, 1), 0, 1),
			})
		end
	end
	return {
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

function TowerDefenseService.start(options: { publish: (player: Player) -> () })
	publishSnapshot = options.publish
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
		for _, enemy in match.enemies do
			clearDeadPart(enemy.part)
		end
		clearRuntime(match)
	end
	matches[player] = nil
end

return TowerDefenseService

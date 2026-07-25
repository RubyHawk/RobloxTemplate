--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("TemplateConfig"))
local StageCatalog = require(Shared:WaitForChild("StageCatalog"))
local StageCell = require(Shared:WaitForChild("StageCell"))
local StageSchema = require(Shared:WaitForChild("StageSchema"))
local TowerDefenseCatalog = require(Shared:WaitForChild("TowerDefenseCatalog"))
local StageGridRenderer = require(script.Parent:WaitForChild("StageGridRenderer"))
local StageTowerRenderer = require(script.Parent:WaitForChild("StageTowerRenderer"))

type Request = (action: string, payload: any, audioCue: string?) -> ()

type SlotView = {
	button: TextButton,
	accent: Frame,
	icon: ImageLabel,
	glyph: TextLabel,
	name: TextLabel,
	cost: TextLabel,
	placedBadge: TextLabel,
	stroke: UIStroke,
}

type InventoryView = {
	button: TextButton,
	accent: Frame,
	icon: ImageLabel,
	glyph: TextLabel,
	name: TextLabel,
	rarity: TextLabel,
	owned: TextLabel,
	equipped: TextLabel,
	stroke: UIStroke,
}

type DetailsView = {
	panel: Frame,
	stroke: UIStroke,
	accent: Frame,
	icon: ImageLabel,
	glyph: TextLabel,
	name: TextLabel,
	rarity: TextLabel,
	status: TextLabel,
	damage: TextLabel,
	range: TextLabel,
	fireRate: TextLabel,
	cost: TextLabel,
	targeting: TextLabel,
	owned: TextLabel,
	placement: TextLabel,
}

type TalentNodeView = {
	targetSlot: number,
	button: TextButton,
	stroke: UIStroke,
}

local TowerDefenseLoadoutController = {}
local initialized = false
local requestServer: Request? = nil
local latestState: any = nil
local selectedSlot: number? = nil
local screenGui: ScreenGui? = nil
local placementHint: TextLabel? = nil
local loadoutBar: Frame? = nil
local dynamicWidthConstraint: UISizeConstraint? = nil
local aimDot: Frame? = nil
local inventoryPanel: Frame? = nil
local talentPanel: Frame? = nil
local slots: { SlotView } = {}
local inventoryViews: { InventoryView } = {}
local detailsView: DetailsView? = nil
local talentNodes: { TalentNodeView } = {}
local currentSlotsLabel: TextLabel? = nil
local nextCostLabel: TextLabel? = nil
local lastInputWasGamepad = false
local detailsUnitId: string? = nil
local detailsSlot: number? = nil
local detailsPlacementId: string? = nil

local EMPTY_COLOR = Color3.fromRGB(23, 33, 43)
local EMPTY_ACCENT = Color3.fromRGB(54, 72, 86)
local SELECTED_COLOR = Color3.fromRGB(255, 214, 76)
local PLACED_COLOR = Color3.fromRGB(48, 54, 60)
local PLACED_ACCENT = Color3.fromRGB(76, 82, 88)
local TALENT_UNLOCKED_COLOR = Color3.fromRGB(34, 128, 91)
local TALENT_AVAILABLE_COLOR = Color3.fromRGB(120, 82, 209)
local TALENT_LOCKED_COLOR = Color3.fromRGB(38, 42, 48)
local BAR_HORIZONTAL_PADDING = 24
local SLOT_WIDTH = 84
local SLOT_GAP = 8
local BAR_HEIGHT = 116

local function catalogColor(value: any, fallback: Color3): Color3
	if type(value) ~= "table" then
		return fallback
	end
	local red = if type(value[1]) == "number" then value[1] else fallback.R * 255
	local green = if type(value[2]) == "number" then value[2] else fallback.G * 255
	local blue = if type(value[3]) == "number" then value[3] else fallback.B * 255
	return Color3.fromRGB(
		math.clamp(math.floor(red), 0, 255),
		math.clamp(math.floor(green), 0, 255),
		math.clamp(math.floor(blue), 0, 255)
	)
end

local function integer(value: any, fallback: number): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		then math.floor(value)
		else fallback
end

local function currentLoadout(): { string }
	local state = latestState
	local result: { string } = {}
	if type(state) ~= "table" or type(state.loadout) ~= "table" then
		return result
	end
	for _, unitId in state.loadout do
		if type(unitId) == "string" and TowerDefenseCatalog.unit(unitId) ~= nil then
			table.insert(result, unitId)
		end
	end
	return result
end

local function unlockedSlots(): number
	local state = latestState
	local value = if type(state) == "table"
		then integer(state.loadoutSlots, Config.towerDefense.startingLoadoutSlots)
		else Config.towerDefense.startingLoadoutSlots
	return math.clamp(value, Config.towerDefense.startingLoadoutSlots, Config.towerDefense.loadoutSlots)
end

local function maximumSlots(): number
	local state = latestState
	local value = if type(state) == "table"
		then integer(state.maximumLoadoutSlots, Config.towerDefense.loadoutSlots)
		else Config.towerDefense.loadoutSlots
	return math.clamp(value, Config.towerDefense.startingLoadoutSlots, Config.towerDefense.loadoutSlots)
end

local function setHint(text: string)
	if placementHint ~= nil then
		placementHint.Text = text
	end
end

local function setImage(icon: ImageLabel, glyph: TextLabel, assetId: any, fallbackGlyph: string)
	local content = if type(assetId) == "string" then assetId else ""
	if content ~= "" then
		icon.Image = if string.find(content, "rbx", 1, true) == 1 then content else `rbxassetid://{content}`
		icon.Visible = true
		glyph.Visible = false
	else
		icon.Image = ""
		icon.Visible = false
		glyph.Visible = true
		glyph.Text = fallbackGlyph
	end
end

local function equippedCount(unitId: string, loadout: { string }): number
	local count = 0
	for _, equippedUnitId in loadout do
		if equippedUnitId == unitId then
			count += 1
		end
	end
	return count
end

local function ownedCount(unitId: string): number
	local state = latestState
	local entry = if type(state) == "table" and type(state.ownedUnits) == "table"
		then state.ownedUnits[unitId]
		else nil
	return if type(entry) == "table" then math.max(integer(entry.count, 0), 0) else 0
end

local function placementById(placementId: string?): any?
	local state = latestState
	if placementId == nil or type(state) ~= "table" or type(state.placements) ~= "table" then
		return nil
	end
	for _, placement in state.placements do
		if type(placement) == "table" and placement.id == placementId then
			return placement
		end
	end
	return nil
end

local function placementForSlot(slotIndex: number, loadout: { string }?): any?
	local resolvedLoadout = loadout or currentLoadout()
	local unitId = resolvedLoadout[slotIndex]
	local state = latestState
	if unitId == nil or type(state) ~= "table" or type(state.placements) ~= "table" then
		return nil
	end
	local slotOccurrence = 0
	for index = 1, slotIndex do
		if resolvedLoadout[index] == unitId then
			slotOccurrence += 1
		end
	end
	local placementOccurrence = 0
	for _, placement in state.placements do
		if type(placement) == "table" and placement.unitId == unitId then
			placementOccurrence += 1
			if placementOccurrence == slotOccurrence then
				return placement
			end
		end
	end
	return nil
end

local function refreshDetails()
	local view = detailsView
	local unitId = detailsUnitId
	if view == nil or unitId == nil then
		return
	end
	local unit = TowerDefenseCatalog.unit(unitId)
	if unit == nil then
		view.panel.Visible = false
		return
	end
	local loadout = currentLoadout()
	if detailsSlot ~= nil and loadout[detailsSlot] ~= unitId then
		detailsSlot = nil
	end
	local placement = placementById(detailsPlacementId)
	if detailsPlacementId ~= nil and placement == nil and detailsSlot == nil then
		view.panel.Visible = false
		return
	end
	if placement == nil and detailsSlot ~= nil then
		placement = placementForSlot(detailsSlot, loadout)
	end
	local rarity = TowerDefenseCatalog.rarity(unit.rarityId)
	local backgroundColor = catalogColor(unit.backgroundColor, EMPTY_COLOR)
	local accentColor = catalogColor(unit.accentColor, EMPTY_ACCENT)
	view.panel.BackgroundColor3 = backgroundColor:Lerp(Color3.fromRGB(7, 11, 15), 0.72)
	view.stroke.Color = accentColor
	view.accent.BackgroundColor3 = accentColor
	view.name.Text = string.upper(unit.name)
	view.rarity.Text = if rarity ~= nil then string.upper(rarity.name) else "UNIT"
	view.rarity.TextColor3 = if rarity ~= nil
		then catalogColor(rarity.color, Color3.fromRGB(150, 180, 170))
		else Color3.fromRGB(150, 180, 170)
	view.status.Text = if placement ~= nil then "PLACED ON GRID" else "READY TO PLACE"
	view.status.TextColor3 = if placement ~= nil
		then Color3.fromRGB(210, 220, 225)
		else Color3.fromRGB(128, 238, 178)
	view.damage.Text = `DAMAGE  {unit.damage}`
	view.range.Text = `RANGE  {unit.range}`
	view.fireRate.Text = `FIRE RATE  {string.format("%.2fs", unit.fireRate)}`
	view.cost.Text = `COST  {unit.deployCost}`
	view.targeting.Text = `TARGETING  {string.upper(unit.targeting)}`
	view.owned.Text = `OWNED x{ownedCount(unitId)}  |  EQUIPPED x{equippedCount(unitId, loadout)}`
	if placement ~= nil and type(placement.cell) == "table" then
		view.placement.Text = `PLACED  |  CELL {placement.cell.column}:{placement.cell.row}`
	elseif detailsSlot ~= nil then
		view.placement.Text = `SLOT {detailsSlot}  |  NOT PLACED`
	else
		view.placement.Text = "UNIT DETAILS"
	end
	setImage(view.icon, view.glyph, unit.iconAssetId, unit.iconGlyph)
end

local function showUnitDetails(unitId: string, slotIndex: number?, placementId: string?)
	detailsUnitId = unitId
	detailsSlot = slotIndex
	detailsPlacementId = placementId
	if detailsView ~= nil then
		detailsView.panel.Visible = true
		refreshDetails()
	end
end

local function refreshBarWidth()
	if dynamicWidthConstraint == nil then
		return
	end
	local count = unlockedSlots()
	local desiredWidth = BAR_HORIZONTAL_PADDING + count * SLOT_WIDTH + math.max(count - 1, 0) * SLOT_GAP
	local camera = Workspace.CurrentCamera
	local availableWidth = if camera ~= nil then math.max(camera.ViewportSize.X * 0.96, 180) else desiredWidth
	local width = math.floor(math.min(desiredWidth, availableWidth))
	dynamicWidthConstraint.MinSize = Vector2.new(width, BAR_HEIGHT)
	dynamicWidthConstraint.MaxSize = Vector2.new(width, BAR_HEIGHT)
end

local function refresh()
	local state = latestState
	if screenGui == nil or type(state) ~= "table" then
		return
	end

	local loadout = currentLoadout()
	local unlocked = unlockedSlots()
	if selectedSlot ~= nil and (selectedSlot > unlocked or loadout[selectedSlot] == nil) then
		selectedSlot = nil
	end
	if selectedSlot ~= nil and placementForSlot(selectedSlot, loadout) ~= nil then
		selectedSlot = nil
	end

	for index, view in slots do
		local visible = index <= unlocked
		view.button.Visible = visible
		if not visible then
			continue
		end
		local unitId = loadout[index]
		local unit = if unitId ~= nil then TowerDefenseCatalog.unit(unitId) else nil
		local placement = placementForSlot(index, loadout)
		local isPlaced = placement ~= nil
		view.stroke.Color = SELECTED_COLOR
		view.stroke.Transparency = if selectedSlot == index then 0 else 1
		view.placedBadge.Visible = isPlaced
		view.icon.ImageColor3 = if isPlaced then Color3.fromRGB(150, 156, 160) else Color3.new(1, 1, 1)
		view.glyph.TextColor3 = if isPlaced then Color3.fromRGB(170, 176, 180) else Color3.new(1, 1, 1)
		if unit == nil then
			view.button.BackgroundColor3 = EMPTY_COLOR
			view.accent.BackgroundColor3 = EMPTY_ACCENT
			view.name.Text = "+ UNIT"
			view.cost.Text = "OPEN INVENTORY"
			setImage(view.icon, view.glyph, "", "+")
		else
			view.button.BackgroundColor3 = if isPlaced
				then PLACED_COLOR
				else catalogColor(unit.backgroundColor, EMPTY_COLOR)
			view.accent.BackgroundColor3 = if isPlaced
				then PLACED_ACCENT
				else catalogColor(unit.accentColor, EMPTY_ACCENT)
			view.name.Text = string.upper(unit.name)
			view.cost.Text = if isPlaced then "CLICK FOR DETAILS" else `{unit.deployCost} COINS`
			setImage(view.icon, view.glyph, unit.iconAssetId, unit.iconGlyph)
		end
	end

	for index, view in inventoryViews do
		local unit = TowerDefenseCatalog.units[index]
		view.button.Visible = unit ~= nil
		if unit == nil then
			continue
		end
		local entry = if type(state.ownedUnits) == "table" then state.ownedUnits[unit.id] else nil
		local copiesOwned = if type(entry) == "table" then math.max(integer(entry.count, 0), 0) else 0
		local rarity = TowerDefenseCatalog.rarity(unit.rarityId)
		local copiesEquipped = equippedCount(unit.id, loadout)
		local owned = copiesOwned > 0
		view.button.Active = owned
		view.button.AutoButtonColor = owned
		view.button.BackgroundColor3 = catalogColor(unit.backgroundColor, EMPTY_COLOR)
		view.accent.BackgroundColor3 = catalogColor(unit.accentColor, EMPTY_ACCENT)
		view.stroke.Color = if rarity ~= nil then catalogColor(rarity.color, EMPTY_ACCENT) else EMPTY_ACCENT
		view.stroke.Transparency = if owned then 0.18 else 0.72
		view.name.Text = string.upper(unit.name)
		view.rarity.Text = if rarity ~= nil then string.upper(rarity.name) else "UNIT"
		view.rarity.TextColor3 = if rarity ~= nil
			then catalogColor(rarity.color, Color3.fromRGB(150, 180, 170))
			else Color3.fromRGB(150, 180, 170)
		view.owned.Text = if owned then `OWNED x{copiesOwned}` else "NOT OWNED - ROLL TO FIND"
		view.equipped.Visible = copiesEquipped > 0
		view.equipped.Text = if copiesEquipped > 0 then `EQUIPPED x{copiesEquipped}` else ""
		setImage(view.icon, view.glyph, unit.iconAssetId, unit.iconGlyph)
	end

	local maximum = maximumSlots()
	local nextCost = state.nextLoadoutSlotCost
	if currentSlotsLabel ~= nil then
		currentSlotsLabel.Text = `UNLOCKED {unlocked} / {maximum}`
	end
	if nextCostLabel ~= nil then
		nextCostLabel.Text = if unlocked >= maximum
			then "ALL UNIT SLOTS UNLOCKED"
			elseif type(nextCost) == "number" then `NEXT SLOT: {math.floor(nextCost)} COINS`
			else "NEXT SLOT UNAVAILABLE"
	end
	for _, node in talentNodes do
		local unlockedNode = node.targetSlot <= unlocked
		local availableNode = node.targetSlot == unlocked + 1
			and node.targetSlot <= maximum
			and type(nextCost) == "number"
		node.button.Active = availableNode
		node.button.AutoButtonColor = availableNode
		node.button.BackgroundColor3 = if unlockedNode
			then TALENT_UNLOCKED_COLOR
			elseif availableNode then TALENT_AVAILABLE_COLOR
			else TALENT_LOCKED_COLOR
		node.stroke.Color = if unlockedNode
			then Color3.fromRGB(80, 235, 164)
			elseif availableNode then SELECTED_COLOR
			else Color3.fromRGB(88, 94, 104)
		node.stroke.Transparency = if unlockedNode or availableNode then 0.04 else 0.4
		if unlockedNode then
			node.button.Text = `SLOT {node.targetSlot}\nUNLOCKED`
		elseif availableNode and type(nextCost) == "number" then
			node.button.Text = `SLOT {node.targetSlot}\n{math.floor(nextCost)} COINS\nTAP TO UNLOCK`
		else
			local costIndex = node.targetSlot - Config.towerDefense.startingLoadoutSlots
			local configuredCost = Config.towerDefense.loadoutSlotUnlockCosts[costIndex]
			local costText = if type(configuredCost) == "number"
				then `{math.floor(configuredCost)} COINS`
				else "UNAVAILABLE"
			node.button.Text = `SLOT {node.targetSlot}\n{costText}\nREQUIRES SLOT {node.targetSlot - 1}`
		end
	end

	local selectedReady = selectedSlot ~= nil
		and loadout[selectedSlot] ~= nil
		and placementForSlot(selectedSlot, loadout) == nil
	if selectedReady and selectedSlot ~= nil then
		local selectedUnit = TowerDefenseCatalog.unit(loadout[selectedSlot])
		setHint(
			if selectedUnit ~= nil
				then `{string.upper(selectedUnit.name)} - GREEN/BLUE PLACE | RED BLOCKED | GOLD OCCUPIED`
				else "SELECT A UNIT SLOT TO PLACE"
		)
	else
		setHint("SELECT A UNIT SLOT TO PLACE")
	end
	if aimDot ~= nil then
		aimDot.Visible = selectedReady and lastInputWasGamepad
	end
	local panelBlocking = inventoryPanel ~= nil and inventoryPanel.Visible
		or talentPanel ~= nil and talentPanel.Visible
	StageGridRenderer.setPlacementMode(selectedReady and not panelBlocking, state)
	refreshDetails()
	refreshBarWidth()
	screenGui.Enabled = true
end

local function sendLoadout(nextLoadout: { string })
	local send = requestServer
	if send == nil then
		return
	end
	send("SetTowerLoadout", { unitIds = nextLoadout })
end

local function selectInventoryUnit(unitIndex: number)
	local state = latestState
	local unit = TowerDefenseCatalog.units[unitIndex]
	if type(state) ~= "table" or unit == nil then
		return
	end
	local entry = if type(state.ownedUnits) == "table" then state.ownedUnits[unit.id] else nil
	local copiesOwned = if type(entry) == "table" then math.max(integer(entry.count, 0), 0) else 0
	if copiesOwned <= 0 then
		setHint("ROLL THIS UNIT BEFORE EQUIPPING IT")
		return
	end

	local nextLoadout = currentLoadout()
	if selectedSlot ~= nil and selectedSlot <= #nextLoadout then
		local currentUnitId = nextLoadout[selectedSlot]
		if currentUnitId == unit.id then
			if equippedCount(unit.id, nextLoadout) >= copiesOwned then
				setHint(`ALL {copiesOwned} OWNED COPIES ARE ALREADY EQUIPPED`)
				return
			end
			if #nextLoadout >= unlockedSlots() then
				setHint("UNLOCK ANOTHER UNIT SLOT FOR THIS COPY")
				return
			end
			table.insert(nextLoadout, unit.id)
			selectedSlot = #nextLoadout
			sendLoadout(nextLoadout)
			return
		end
		local copiesAfterReplace = equippedCount(unit.id, nextLoadout) + 1
		if copiesAfterReplace > copiesOwned then
			setHint(`ALL {copiesOwned} OWNED COPIES ARE ALREADY EQUIPPED`)
			return
		end
		nextLoadout[selectedSlot] = unit.id
	elseif #nextLoadout < unlockedSlots() then
		if equippedCount(unit.id, nextLoadout) >= copiesOwned then
			setHint(`ALL {copiesOwned} OWNED COPIES ARE ALREADY EQUIPPED`)
			return
		end
		table.insert(nextLoadout, unit.id)
		selectedSlot = #nextLoadout
	else
		setHint("SELECT A UNIT SLOT TO REPLACE")
		return
	end
	sendLoadout(nextLoadout)
end

local function moveSelected(direction: number)
	if selectedSlot == nil then
		setHint("SELECT AN EQUIPPED SLOT FIRST")
		return
	end
	local nextLoadout = currentLoadout()
	local target = selectedSlot + direction
	if nextLoadout[selectedSlot] == nil or target < 1 or target > #nextLoadout then
		return
	end
	nextLoadout[selectedSlot], nextLoadout[target] = nextLoadout[target], nextLoadout[selectedSlot]
	selectedSlot = target
	sendLoadout(nextLoadout)
end

local function removeSelected()
	if selectedSlot == nil then
		setHint("SELECT AN EQUIPPED SLOT FIRST")
		return
	end
	local nextLoadout = currentLoadout()
	if nextLoadout[selectedSlot] == nil then
		return
	end
	table.remove(nextLoadout, selectedSlot)
	selectedSlot = nil
	sendLoadout(nextLoadout)
end

local function selectedUnitId(): string?
	if selectedSlot == nil then
		return nil
	end
	local loadout = currentLoadout()
	if placementForSlot(selectedSlot, loadout) ~= nil then
		return nil
	end
	return loadout[selectedSlot]
end

local function isClientBuildable(stage: any, column: number, row: number): boolean
	if
		type(stage) ~= "table"
		or type(stage.grid) ~= "table"
		or column < 1
		or column > stage.grid.columns
		or row < 1
		or row > stage.grid.rows
	then
		return false
	end
	local key = StageSchema.cellKey(column, row)
	if type(stage.routeNoBuildMask) == "table" and stage.routeNoBuildMask[key] == true then
		return false
	end
	local resolved = StageCell.resolve(stage.grid.defaultCell, stage.grid.cells[key])
	local roles = resolved.roles or {}
	if roles.EnemySpawn == true or roles.EnemyGoal == true then
		return false
	end
	return resolved.buildPolicy == nil
		or resolved.buildPolicy == "Allowed"
		or resolved.buildPolicy == "AutoOnly"
end

local function occupied(column: number, row: number): boolean
	local state = latestState
	if type(state) ~= "table" or type(state.placements) ~= "table" then
		return false
	end
	for _, placement in state.placements do
		if
			type(placement) == "table"
			and type(placement.cell) == "table"
			and placement.cell.column == column
			and placement.cell.row == row
		then
			return true
		end
	end
	return false
end

local function cellFromScreenPoint(screenPoint: Vector2, viewportPoint: boolean): (number?, number?)
	local state = latestState
	local camera = Workspace.CurrentCamera
	if
		type(state) ~= "table"
		or typeof(state.stageOrigin) ~= "CFrame"
		or type(state.activeStageId) ~= "string"
		or camera == nil
	then
		return nil, nil
	end
	local stage = StageCatalog.get(state.activeStageId)
	if stage == nil then
		return nil, nil
	end
	local ray = if viewportPoint
		then camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
		else camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
	local normal = state.stageOrigin.UpVector
	local denominator = ray.Direction:Dot(normal)
	if math.abs(denominator) < 1e-5 then
		return nil, nil
	end
	local distance = (state.stageOrigin.Position - ray.Origin):Dot(normal) / denominator
	if distance <= 0 then
		return nil, nil
	end
	local worldPoint = ray.Origin + ray.Direction * distance
	local localPoint = state.stageOrigin:PointToObjectSpace(worldPoint)
	local grid = stage.grid
	local column = math.floor((localPoint.X + (grid.columns * grid.cellSize) / 2) / grid.cellSize) + 1
	local row = math.floor((localPoint.Z + (grid.rows * grid.cellSize) / 2) / grid.cellSize) + 1
	if not isClientBuildable(stage, column, row) or occupied(column, row) then
		return nil, nil
	end
	return column, row
end

local function placeAt(screenPoint: Vector2, viewportPoint: boolean)
	local unitId = selectedUnitId()
	local send = requestServer
	if unitId == nil or send == nil then
		return
	end
	local column, row = cellFromScreenPoint(screenPoint, viewportPoint)
	if column == nil or row == nil then
		setHint("CHOOSE AN EMPTY BUILDABLE CELL")
		return
	end
	send("PlaceUnit", { unitId = unitId, column = column, row = row })
end

local function interactAt(screenPoint: Vector2, viewportPoint: boolean)
	local placementId, unitId = StageTowerRenderer.localPlacementAtScreen(screenPoint, viewportPoint)
	if placementId ~= nil and unitId ~= nil then
		selectedSlot = nil
		showUnitDetails(unitId, nil, placementId)
		return
	end
	placeAt(screenPoint, viewportPoint)
end

local function setPanelVisible(panel: Frame?, visible: boolean)
	if panel ~= nil then
		panel.Visible = visible
	end
end

local function closePanels()
	setPanelVisible(inventoryPanel, false)
	setPanelVisible(talentPanel, false)
end

local function cycleSelection(direction: number)
	local loadout = currentLoadout()
	if #loadout == 0 then
		selectedSlot = nil
		setPanelVisible(inventoryPanel, true)
		refresh()
		return
	end
	local current = selectedSlot or if direction > 0 then 0 else #loadout + 1
	for offset = 1, #loadout do
		local candidate = ((current - 1 + direction * offset) % #loadout) + 1
		if placementForSlot(candidate, loadout) == nil then
			selectedSlot = candidate
			refresh()
			return
		end
	end
	selectedSlot = nil
	setHint("EVERY EQUIPPED COPY IS ALREADY PLACED")
	refresh()
end

local function bindViewportResize()
	local function bindCamera(camera: Camera?)
		if camera == nil then
			return
		end
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshBarWidth)
		refreshBarWidth()
	end
	bindCamera(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
	end)
end

function TowerDefenseLoadoutController.initialize(request: Request)
	if initialized or Config.features.towerDefense ~= true then
		return
	end
	initialized = true
	requestServer = request

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local candidate = playerGui:WaitForChild("TowerDefenseLoadoutHUD", 15)
		if candidate == nil or not candidate:IsA("ScreenGui") then
			warn("TowerDefenseLoadoutHUD is missing from StarterGui")
			return
		end
		screenGui = candidate
		placementHint = candidate:WaitForChild("PlacementHint") :: TextLabel
		loadoutBar = candidate:WaitForChild("LoadoutBar") :: Frame
		dynamicWidthConstraint = loadoutBar:WaitForChild("DynamicWidthConstraint") :: UISizeConstraint
		aimDot = candidate:WaitForChild("AimDot") :: Frame
		inventoryPanel = candidate:WaitForChild("InventoryPanel") :: Frame
		talentPanel = candidate:WaitForChild("TalentPanel") :: Frame
		local detailsPanel = candidate:WaitForChild("UnitDetailsPanel") :: Frame
		detailsView = {
			panel = detailsPanel,
			stroke = detailsPanel:WaitForChild("PanelStroke") :: UIStroke,
			accent = detailsPanel:WaitForChild("Accent") :: Frame,
			icon = detailsPanel:WaitForChild("Icon") :: ImageLabel,
			glyph = detailsPanel:WaitForChild("Glyph") :: TextLabel,
			name = detailsPanel:WaitForChild("UnitName") :: TextLabel,
			rarity = detailsPanel:WaitForChild("Rarity") :: TextLabel,
			status = detailsPanel:WaitForChild("Status") :: TextLabel,
			damage = detailsPanel:WaitForChild("DamageValue") :: TextLabel,
			range = detailsPanel:WaitForChild("RangeValue") :: TextLabel,
			fireRate = detailsPanel:WaitForChild("FireRateValue") :: TextLabel,
			cost = detailsPanel:WaitForChild("CostValue") :: TextLabel,
			targeting = detailsPanel:WaitForChild("TargetingValue") :: TextLabel,
			owned = detailsPanel:WaitForChild("OwnedValue") :: TextLabel,
			placement = detailsPanel:WaitForChild("PlacementValue") :: TextLabel,
		}
		local detailsCloseButton = detailsPanel:WaitForChild("CloseButton") :: TextButton
		detailsCloseButton.Activated:Connect(function()
			detailsPanel.Visible = false
			detailsUnitId = nil
			detailsSlot = nil
			detailsPlacementId = nil
		end)

		local controlRow = candidate:WaitForChild("ControlRow")
		local inventoryButton = controlRow:WaitForChild("InventoryButton") :: TextButton
		local diceButton = controlRow:WaitForChild("DiceButton") :: TextButton
		local upgradeTreeButton = controlRow:WaitForChild("UpgradeTreeButton") :: TextButton
		local slotsRoot = loadoutBar:WaitForChild("Slots")
		for index = 1, Config.towerDefense.loadoutSlots do
			local button = slotsRoot:WaitForChild(`UnitSlot{string.format("%02d", index)}`) :: TextButton
			slots[index] = {
				button = button,
				accent = button:WaitForChild("Accent") :: Frame,
				icon = button:WaitForChild("Icon") :: ImageLabel,
				glyph = button:WaitForChild("Glyph") :: TextLabel,
				name = button:WaitForChild("UnitName") :: TextLabel,
				cost = button:WaitForChild("Cost") :: TextLabel,
				placedBadge = button:WaitForChild("PlacedBadge") :: TextLabel,
				stroke = button:WaitForChild("SelectionStroke") :: UIStroke,
			}
			button.Activated:Connect(function()
				local unitId = currentLoadout()[index]
				if unitId == nil then
					selectedSlot = index
					setPanelVisible(talentPanel, false)
					setPanelVisible(inventoryPanel, true)
				else
					closePanels()
					local placement = placementForSlot(index, currentLoadout())
					local placementId = if type(placement) == "table"
							and type(placement.id) == "string"
						then placement.id
						else nil
					selectedSlot = if placement == nil then index else nil
					showUnitDetails(unitId, index, placementId)
				end
				refresh()
			end)
			button.MouseEnter:Connect(function()
				local unitId = currentLoadout()[index]
				if unitId ~= nil then
					local placement = placementForSlot(index, currentLoadout())
					local placementId = if type(placement) == "table"
							and type(placement.id) == "string"
						then placement.id
						else nil
					showUnitDetails(unitId, index, placementId)
				end
			end)
		end

		local cards = inventoryPanel:WaitForChild("Cards")
		for index = 1, 8 do
			local button = cards:WaitForChild(`InventoryUnit{string.format("%02d", index)}`) :: TextButton
			inventoryViews[index] = {
				button = button,
				accent = button:WaitForChild("Accent") :: Frame,
				icon = button:WaitForChild("Icon") :: ImageLabel,
				glyph = button:WaitForChild("Glyph") :: TextLabel,
				name = button:WaitForChild("UnitName") :: TextLabel,
				rarity = button:WaitForChild("Rarity") :: TextLabel,
				owned = button:WaitForChild("Owned") :: TextLabel,
				equipped = button:WaitForChild("Equipped") :: TextLabel,
				stroke = button:WaitForChild("CardStroke") :: UIStroke,
			}
			button.Activated:Connect(function()
				selectInventoryUnit(index)
			end)
		end
		local reorderRow = inventoryPanel:WaitForChild("ReorderRow")
		local moveLeftButton = reorderRow:WaitForChild("MoveLeftButton") :: TextButton
		local removeButton = reorderRow:WaitForChild("RemoveButton") :: TextButton
		local moveRightButton = reorderRow:WaitForChild("MoveRightButton") :: TextButton
		local inventoryCloseButton = inventoryPanel:WaitForChild("CloseButton") :: TextButton
		moveLeftButton.Activated:Connect(function()
			moveSelected(-1)
		end)
		removeButton.Activated:Connect(removeSelected)
		moveRightButton.Activated:Connect(function()
			moveSelected(1)
		end)
		inventoryCloseButton.Activated:Connect(function()
			setPanelVisible(inventoryPanel, false)
			refresh()
		end)

		local treeCanvas = talentPanel:WaitForChild("TreeCanvas")
		currentSlotsLabel = treeCanvas:WaitForChild("CurrentSlots") :: TextLabel
		nextCostLabel = treeCanvas:WaitForChild("NextCost") :: TextLabel
		for targetSlot = Config.towerDefense.startingLoadoutSlots + 1, Config.towerDefense.loadoutSlots do
			local nodeSlot = targetSlot
			local button = treeCanvas:WaitForChild(`SlotNode{string.format("%02d", nodeSlot)}`) :: TextButton
			table.insert(talentNodes, {
				targetSlot = nodeSlot,
				button = button,
				stroke = button:WaitForChild("NodeStroke") :: UIStroke,
			})
			button.Activated:Connect(function()
				if nodeSlot == unlockedSlots() + 1 then
					request("UnlockTowerLoadoutSlot", {})
				end
			end)
		end
		local talentCloseButton = talentPanel:WaitForChild("CloseButton") :: TextButton
		talentCloseButton.Activated:Connect(function()
			setPanelVisible(talentPanel, false)
			refresh()
		end)

		inventoryButton.Activated:Connect(function()
			setPanelVisible(talentPanel, false)
			setPanelVisible(inventoryPanel, not inventoryPanel.Visible)
			refresh()
		end)
		diceButton.Activated:Connect(function()
			closePanels()
			refresh()
			request("RollUnit", {})
		end)
		upgradeTreeButton.Activated:Connect(function()
			setPanelVisible(inventoryPanel, false)
			setPanelVisible(talentPanel, not talentPanel.Visible)
			refresh()
		end)

		local templateGui = playerGui:FindFirstChild("TemplateUI")
		local templateRoot = if templateGui and templateGui:IsA("ScreenGui")
			then templateGui:FindFirstChild("Root")
			else nil
		local navigation = if templateRoot then templateRoot:FindFirstChild("Navigation") else nil
		if navigation and navigation:IsA("GuiObject") then
			navigation.Visible = false
		end

		bindViewportResize()
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		lastInputWasGamepad = string.find(input.UserInputType.Name, "Gamepad", 1, true) == 1
		if processed then
			refresh()
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if
				inventoryPanel ~= nil and inventoryPanel.Visible
				or talentPanel ~= nil and talentPanel.Visible
			then
				closePanels()
			elseif detailsView ~= nil and detailsView.panel.Visible then
				detailsView.panel.Visible = false
				detailsUnitId = nil
				detailsSlot = nil
				detailsPlacementId = nil
			else
				selectedSlot = nil
			end
			refresh()
			return
		end
		local numberKeys = {
			[Enum.KeyCode.One] = 1,
			[Enum.KeyCode.Two] = 2,
			[Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5,
			[Enum.KeyCode.Six] = 6,
		}
		local slotIndex = numberKeys[input.KeyCode]
		if slotIndex ~= nil and slotIndex <= unlockedSlots() then
			local loadout = currentLoadout()
			local unitId = loadout[slotIndex]
			local placement = placementForSlot(slotIndex, loadout)
			selectedSlot = if unitId ~= nil and placement == nil then slotIndex else nil
			if unitId ~= nil then
				local placementId = if type(placement) == "table" and type(placement.id) == "string"
					then placement.id
					else nil
				showUnitDetails(unitId, slotIndex, placementId)
			end
			refresh()
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycleSelection(-1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycleSelection(1)
		elseif
			input.KeyCode == Enum.KeyCode.ButtonA
			and (inventoryPanel == nil or not inventoryPanel.Visible)
			and (talentPanel == nil or not talentPanel.Visible)
		then
			local camera = Workspace.CurrentCamera
			if camera ~= nil then
				interactAt(camera.ViewportSize / 2, true)
			end
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			and (inventoryPanel == nil or not inventoryPanel.Visible)
			and (talentPanel == nil or not talentPanel.Visible)
		then
			interactAt(Vector2.new(input.Position.X, input.Position.Y), false)
		end
		refresh()
	end)

	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		lastInputWasGamepad = false
		if
			not processedByUI
			and (inventoryPanel == nil or not inventoryPanel.Visible)
			and (talentPanel == nil or not talentPanel.Visible)
		then
			interactAt(position, false)
		end
		refresh()
	end)
end

function TowerDefenseLoadoutController.apply(state: any)
	latestState = state
	refresh()
end

return table.freeze(TowerDefenseLoadoutController)

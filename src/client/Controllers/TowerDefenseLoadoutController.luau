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

type Request = (action: string, payload: any, audioCue: string?) -> ()

type SlotView = {
	button: TextButton,
	accent: Frame,
	icon: ImageLabel,
	glyph: TextLabel,
	name: TextLabel,
	cost: TextLabel,
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
local currentSlotsLabel: TextLabel? = nil
local nextCostLabel: TextLabel? = nil
local unlockButton: TextButton? = nil
local lastInputWasGamepad = false

local EMPTY_COLOR = Color3.fromRGB(23, 33, 43)
local EMPTY_ACCENT = Color3.fromRGB(54, 72, 86)
local LOCKED_ACTION_COLOR = Color3.fromRGB(63, 73, 84)
local SELECTED_COLOR = Color3.fromRGB(255, 214, 76)
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

local function equippedSlot(unitId: string, loadout: { string }): number?
	for index, equippedUnitId in loadout do
		if equippedUnitId == unitId then
			return index
		end
	end
	return nil
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

	for index, view in slots do
		local visible = index <= unlocked
		view.button.Visible = visible
		if not visible then
			continue
		end
		local unitId = loadout[index]
		local unit = if unitId ~= nil then TowerDefenseCatalog.unit(unitId) else nil
		view.stroke.Color = SELECTED_COLOR
		view.stroke.Transparency = if selectedSlot == index then 0 else 1
		if unit == nil then
			view.button.BackgroundColor3 = EMPTY_COLOR
			view.accent.BackgroundColor3 = EMPTY_ACCENT
			view.name.Text = "+ UNIT"
			view.cost.Text = "OPEN INVENTORY"
			setImage(view.icon, view.glyph, "", "+")
		else
			view.button.BackgroundColor3 = catalogColor(unit.backgroundColor, EMPTY_COLOR)
			view.accent.BackgroundColor3 = catalogColor(unit.accentColor, EMPTY_ACCENT)
			view.name.Text = string.upper(unit.name)
			view.cost.Text = `{unit.deployCost} COINS`
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
		local ownedCount = if type(entry) == "table" then math.max(integer(entry.count, 0), 0) else 0
		local rarity = TowerDefenseCatalog.rarity(unit.rarityId)
		local slotIndex = equippedSlot(unit.id, loadout)
		local owned = ownedCount > 0
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
		view.owned.Text = if owned then `OWNED x{ownedCount}` else "NOT OWNED - ROLL TO FIND"
		view.equipped.Visible = slotIndex ~= nil
		view.equipped.Text = if slotIndex ~= nil then `SLOT {slotIndex}` else ""
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
	if unlockButton ~= nil then
		local canUnlock = unlocked < maximum and type(nextCost) == "number"
		unlockButton.Active = canUnlock
		unlockButton.AutoButtonColor = canUnlock
		unlockButton.BackgroundColor3 = if canUnlock
			then Color3.fromRGB(120, 82, 209)
			else LOCKED_ACTION_COLOR
		unlockButton.Text = if unlocked >= maximum then "MAXIMUM SLOTS" else "UNLOCK SLOT"
	end

	if selectedSlot ~= nil and loadout[selectedSlot] ~= nil then
		local selectedUnit = TowerDefenseCatalog.unit(loadout[selectedSlot])
		setHint(
			if selectedUnit ~= nil
				then `{string.upper(selectedUnit.name)} SELECTED - TAP A BUILDABLE CELL`
				else "SELECT A UNIT SLOT TO PLACE"
		)
	else
		setHint("SELECT A UNIT SLOT TO PLACE")
	end
	if aimDot ~= nil then
		aimDot.Visible = selectedSlot ~= nil and lastInputWasGamepad
	end
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
	if type(entry) ~= "table" or integer(entry.count, 0) <= 0 then
		setHint("ROLL THIS UNIT BEFORE EQUIPPING IT")
		return
	end

	local nextLoadout = currentLoadout()
	local alreadyEquipped = equippedSlot(unit.id, nextLoadout)
	if alreadyEquipped ~= nil then
		table.remove(nextLoadout, alreadyEquipped)
		if selectedSlot == alreadyEquipped then
			selectedSlot = nil
		end
		sendLoadout(nextLoadout)
		return
	end

	if selectedSlot ~= nil and selectedSlot <= #nextLoadout then
		nextLoadout[selectedSlot] = unit.id
	elseif #nextLoadout < unlockedSlots() then
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
	return currentLoadout()[selectedSlot]
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
	selectedSlot = ((current - 1 + direction) % #loadout) + 1
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
				stroke = button:WaitForChild("SelectionStroke") :: UIStroke,
			}
			button.Activated:Connect(function()
				local unitId = currentLoadout()[index]
				if unitId == nil then
					selectedSlot = index
					setPanelVisible(talentPanel, false)
					setPanelVisible(inventoryPanel, true)
				else
					selectedSlot = index
					closePanels()
				end
				refresh()
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
		end)

		local slotNode = talentPanel:WaitForChild("SlotUpgradeNode")
		currentSlotsLabel = slotNode:WaitForChild("CurrentSlots") :: TextLabel
		nextCostLabel = slotNode:WaitForChild("NextCost") :: TextLabel
		unlockButton = slotNode:WaitForChild("UnlockButton") :: TextButton
		local talentCloseButton = talentPanel:WaitForChild("CloseButton") :: TextButton
		unlockButton.Activated:Connect(function()
			request("UnlockTowerLoadoutSlot", {})
		end)
		talentCloseButton.Activated:Connect(function()
			setPanelVisible(talentPanel, false)
		end)

		inventoryButton.Activated:Connect(function()
			setPanelVisible(talentPanel, false)
			setPanelVisible(inventoryPanel, not inventoryPanel.Visible)
		end)
		diceButton.Activated:Connect(function()
			closePanels()
			request("RollUnit", {})
		end)
		upgradeTreeButton.Activated:Connect(function()
			setPanelVisible(inventoryPanel, false)
			setPanelVisible(talentPanel, not talentPanel.Visible)
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
			selectedSlot = if currentLoadout()[slotIndex] ~= nil then slotIndex else nil
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
				placeAt(camera.ViewportSize / 2, true)
			end
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			and (inventoryPanel == nil or not inventoryPanel.Visible)
			and (talentPanel == nil or not talentPanel.Visible)
		then
			placeAt(Vector2.new(input.Position.X, input.Position.Y), false)
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
			placeAt(position, false)
		end
		refresh()
	end)
end

function TowerDefenseLoadoutController.apply(state: any)
	latestState = state
	refresh()
end

return table.freeze(TowerDefenseLoadoutController)

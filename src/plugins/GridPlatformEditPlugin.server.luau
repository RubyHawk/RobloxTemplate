--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local ISLAND_NAME = "FirstPrivateIsland"
local PLATFORM_NAME = "GamePlatform"
local MAP_NAME = "CellMap"
local PATH_POINTS_NAME = "PathPoints"
local PATH_TILES_NAME = "PathTiles"

local LEGAL_COLOR = Color3.fromRGB(38, 217, 97)
local ILLEGAL_COLOR = Color3.fromRGB(255, 66, 41)
local PATH_COLOR = Color3.fromRGB(255, 199, 36)
local CONTROL_POINT_COLOR = Color3.fromRGB(255, 46, 31)
local PANEL_BG = Color3.fromRGB(28, 30, 36)
local PANEL_SECTION = Color3.fromRGB(38, 41, 49)
local BUTTON_BG = Color3.fromRGB(58, 63, 74)
local BUTTON_ACTIVE = Color3.fromRGB(0, 162, 255)
local TEXT = Color3.fromRGB(242, 245, 250)
local MUTED = Color3.fromRGB(166, 174, 187)

local LEGAL_TRANSPARENCY = 0.55
local ILLEGAL_TRANSPARENCY = 0.22
local PLATFORM_TRANSPARENCY = 0.18
local PATH_TILE_TRANSPARENCY = 0.06
local CONTROL_POINT_TRANSPARENCY = 0.18
local PATH_TILE_SURFACE_OFFSET = 0.18
local CONTROL_POINT_SURFACE_OFFSET = 0.65
local PATH_TILE_SPACING = 2.15
local PATH_TILE_DIAMETER = 4.45
local PATH_GRID_RADIUS = 4.35
local PATH_GRID_SAMPLE_STEP = 0.8
local SPLINE_SAMPLES_PER_SEGMENT = 24

type PaintMode = "Toggle" | "Legal" | "Illegal"

type SplineSample = {
	position: Vector3,
	tangent: Vector3,
	distance: number,
}

type SplinePath = {
	samples: { SplineSample },
	length: number,
}

local toolbar = plugin:CreateToolbar("Grid Platform")
local openButton =
	toolbar:CreateButton("GridPlatformEditor", "Open the grid platform editor", "", "Grid Editor")
openButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 520, 280, 360)
local widget = plugin:CreateDockWidgetPluginGuiAsync("GridPlatformEditorPanel", widgetInfo)
widget.Title = "Grid Platform Editor"

local activeMode: PaintMode? = nil
local mouse = plugin:GetMouse()
local statusLabel: TextLabel
local modeButtons: { [PaintMode]: TextButton } = {} :: any
local splineAddActive = false
local splineAddButton: TextButton
local gridButton: TextButton
local platformButton: TextButton

local function setStatus(message: string)
	statusLabel.Text = message
	print(`Grid Platform Editor: {message}`)
end

local function createLabel(
	parent: Instance,
	name: string,
	text: string,
	height: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, height)
	label.Parent = parent
	return label
end

local function createButton(parent: Instance, name: string, text: string, height: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = BUTTON_BG
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSansBold
	button.Text = text
	button.TextColor3 = TEXT
	button.TextSize = 16
	button.TextWrapped = true
	button.Size = UDim2.new(1, 0, 0, height)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

local function createSection(parent: Instance, name: string): Frame
	local section = Instance.new("Frame")
	section.Name = name
	section.BackgroundColor3 = PANEL_SECTION
	section.BorderSizePixel = 0
	section.Size = UDim2.fromScale(1, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = section

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = section

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = section

	return section
end

local function createButtonRow(parent: Instance, name: string, buttons: { { string } }): { TextButton }
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local created: { TextButton } = {}
	for _, info in buttons do
		local button = createButton(row, info[1], info[2], 34)
		button.Size = UDim2.new(1 / #buttons, -4, 1, 0)
		table.insert(created, button)
	end

	return created
end

local function buildWidget()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = PANEL_BG
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = widget

	local rootPadding = Instance.new("UIPadding")
	rootPadding.PaddingTop = UDim.new(0, 12)
	rootPadding.PaddingBottom = UDim.new(0, 12)
	rootPadding.PaddingLeft = UDim.new(0, 12)
	rootPadding.PaddingRight = UDim.new(0, 12)
	rootPadding.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Active = true
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	createLabel(scroll, "Title", "Grid Platform Editor", 28, TEXT)
	createLabel(
		scroll,
		"Subtitle",
		"Paint 4x4 grid cells in edit mode. Select GamePlatform when moving or rotating.",
		44,
		MUTED
	)

	local modeSection = createSection(scroll, "PaintMode")
	createLabel(modeSection, "ModeTitle", "Paint Mode", 24, TEXT)
	local modeRow = createButtonRow(modeSection, "Modes", {
		{ "Toggle", "Toggle" },
		{ "Legal", "Legal" },
		{ "Illegal", "Illegal" },
	})
	modeButtons.Toggle = modeRow[1]
	modeButtons.Legal = modeRow[2]
	modeButtons.Illegal = modeRow[3]

	local placementSection = createSection(scroll, "Placement")
	createLabel(placementSection, "PlacementTitle", "Placement", 24, TEXT)
	local selectRow = createButtonRow(placementSection, "SelectRow", {
		{ "Select", "Select Platform" },
		{ "Origin", "Fix Origin" },
	})

	local resetSnapRow = createButtonRow(placementSection, "ResetSnapRow", {
		{ "Reset", "Reset Flat" },
		{ "Snap", "Snap to Selection" },
	})

	local splineSection = createSection(scroll, "SplinePath")
	createLabel(splineSection, "SplineTitle", "Spline Path", 24, TEXT)
	local splineSelectRow = createButtonRow(splineSection, "SplineSelectRow", {
		{ "SelectSpline", "Select Points" },
		{ "RebuildSpline", "Rebuild Curve" },
	})
	local splineEditRow = createButtonRow(splineSection, "SplineEditRow", {
		{ "AddSplinePoint", "Add Point" },
		{ "DeleteSplinePoint", "Delete Selected" },
	})
	local splineUtilityRow = createButtonRow(splineSection, "SplineUtilityRow", {
		{ "SnapSplinePoints", "Snap Points" },
		{ "ExportSpline", "Export Spline" },
	})
	splineAddButton = splineEditRow[1]
	createLabel(
		splineSection,
		"SplineHelp",
		"Move red control points with Studio tools, then rebuild. Add Point inserts after the selected point.",
		64,
		MUTED
	)

	local visibilitySection = createSection(scroll, "Visibility")
	createLabel(visibilitySection, "VisibilityTitle", "Visibility", 24, TEXT)
	local visibilityRow = createButtonRow(visibilitySection, "VisibilityRow", {
		{ "Grid", "Toggle Grid" },
		{ "Platform", "Toggle Platform" },
	})
	gridButton = visibilityRow[1]
	platformButton = visibilityRow[2]

	local exportSection = createSection(scroll, "Export")
	createLabel(exportSection, "ExportTitle", "Export", 24, TEXT)
	local exportLayoutButton = createButton(exportSection, "ExportLayout", "Print Layout to Output", 36)
	createLabel(
		exportSection,
		"ExportHelp",
		"After painting, export and send the Output text so the layout can be baked into source.",
		54,
		MUTED
	)

	statusLabel = createLabel(
		scroll,
		"Status",
		"Ready. Open the panel, pick a mode, then click the platform.",
		58,
		MUTED
	)

	return {
		selectButton = selectRow[1],
		originButton = selectRow[2],
		resetButton = resetSnapRow[1],
		snapButton = resetSnapRow[2],
		selectSplineButton = splineSelectRow[1],
		rebuildSplineButton = splineSelectRow[2],
		addSplineButton = splineEditRow[1],
		deleteSplineButton = splineEditRow[2],
		snapSplineButton = splineUtilityRow[1],
		exportSplineButton = splineUtilityRow[2],
		exportButton = exportLayoutButton,
	}
end

local widgetButtons = buildWidget()

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

local function boolValue(parent: Instance, name: string): BoolValue?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("BoolValue") then
		return child
	end
	return nil
end

local function intValue(parent: Instance, name: string): IntValue?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("IntValue") then
		return child
	end
	return nil
end

local function stringValue(parent: Instance, name: string): StringValue?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("StringValue") then
		return child
	end
	return nil
end

local function islandModel(): Model?
	return findModel(Workspace, ISLAND_NAME)
end

local function platformModel(): Model?
	local island = islandModel()
	if island == nil then
		return nil
	end
	return findModel(island, PLATFORM_NAME)
end

local function pathParent(): Instance?
	local platform = platformModel()
	if platform ~= nil then
		return platform
	end
	return islandModel()
end

local function pathPointsFolder(): Folder?
	local parent = pathParent()
	if parent ~= nil then
		local folder = findFolder(parent, PATH_POINTS_NAME)
		if folder ~= nil then
			return folder
		end
	end

	local island = islandModel()
	if island ~= nil then
		return findFolder(island, PATH_POINTS_NAME)
	end

	return nil
end

local function pathTilesFolder(): Folder?
	local parent = pathParent()
	if parent ~= nil then
		local folder = findFolder(parent, PATH_TILES_NAME)
		if folder ~= nil then
			return folder
		end
	end

	local island = islandModel()
	if island ~= nil then
		return findFolder(island, PATH_TILES_NAME)
	end

	return nil
end

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = findFolder(parent, name)
	if folder ~= nil then
		return folder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

local function ensurePathPointsFolder(): Folder?
	local existing = pathPointsFolder()
	if existing ~= nil then
		return existing
	end

	local parent = pathParent()
	if parent == nil then
		return nil
	end
	return ensureFolder(parent, PATH_POINTS_NAME)
end

local function ensurePathTilesFolder(): Folder?
	local existing = pathTilesFolder()
	if existing ~= nil then
		return existing
	end

	local parent = pathParent()
	if parent == nil then
		return nil
	end
	return ensureFolder(parent, PATH_TILES_NAME)
end

local function platformBasePart(platform: Model): BasePart?
	local platformBase = platform:FindFirstChild("PlatformBase")
	if platformBase ~= nil and platformBase:IsA("BasePart") then
		return platformBase
	end
	return nil
end

local function mapFolder(platform: Model): Folder?
	return findFolder(platform, MAP_NAME)
end

local function platformEnabled(platform: Model): boolean
	local value = boolValue(platform, "PlatformEnabled")
	return value == nil or value.Value
end

local function gridVisible(platform: Model): boolean
	local value = boolValue(platform, "GridVisible")
	return value == nil or value.Value
end

local function cellSize(platform: Model): number
	local value = intValue(platform, "CellSize")
	return if value ~= nil then value.Value else 4
end

local function columns(platform: Model): number
	local value = intValue(platform, "Columns")
	return if value ~= nil then value.Value else 32
end

local function rows(platform: Model): number
	local value = intValue(platform, "Rows")
	return if value ~= nil then value.Value else 27
end

local function rowName(row: number): string
	return `Row_{string.format("%02d", row)}`
end

local function cellName(column: number, row: number): string
	return `Cell_{string.format("%02d", column)}_{string.format("%02d", row)}`
end

local function rowString(platform: Model, row: number): StringValue?
	local folder = mapFolder(platform)
	if folder == nil then
		return nil
	end
	return stringValue(folder, rowName(row))
end

local function cellFrame(platform: Model, column: number, row: number): Frame?
	local platformBase = platformBasePart(platform)
	if platformBase == nil then
		return nil
	end

	local overlay = platformBase:FindFirstChild("GridOverlay")
	if overlay == nil or not overlay:IsA("SurfaceGui") then
		return nil
	end

	local cells = overlay:FindFirstChild("Cells")
	if cells == nil or not cells:IsA("Frame") then
		return nil
	end

	local frame = cells:FindFirstChild(cellName(column, row))
	if frame ~= nil and frame:IsA("Frame") then
		return frame
	end
	return nil
end

local function isCellBuildable(platform: Model, column: number, row: number): boolean
	local rowValue = rowString(platform, row)
	if rowValue == nil then
		return true
	end
	return string.sub(rowValue.Value, column, column) ~= "#"
end

local function updateCellVisual(platform: Model, column: number, row: number)
	local frame = cellFrame(platform, column, row)
	if frame == nil then
		return
	end

	local buildable = isCellBuildable(platform, column, row)
	frame.BackgroundColor3 = if buildable then LEGAL_COLOR else ILLEGAL_COLOR
	frame.BackgroundTransparency = if buildable then LEGAL_TRANSPARENCY else ILLEGAL_TRANSPARENCY
end

local function updateAllCellVisuals(platform: Model)
	for row = 1, rows(platform) do
		for column = 1, columns(platform) do
			updateCellVisual(platform, column, row)
		end
	end
end

local function setBoolChild(parent: Instance, childName: string, value: boolean)
	local child = boolValue(parent, childName)
	if child ~= nil then
		child.Value = value
	end
end

local function applyPlatformVisual()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return
	end

	local enabled = platformEnabled(platform)
	local visible = gridVisible(platform)
	base.Transparency = if enabled then PLATFORM_TRANSPARENCY else 1
	base.CanCollide = enabled
	base.CanQuery = enabled

	local overlay = base:FindFirstChild("GridOverlay")
	if overlay ~= nil and overlay:IsA("SurfaceGui") then
		overlay.Enabled = enabled and visible
	end

	local pathTiles = pathTilesFolder()
	if pathTiles ~= nil then
		for _, child in pathTiles:GetChildren() do
			if child:IsA("BasePart") then
				child.Transparency = if enabled then PATH_TILE_TRANSPARENCY else 1
			end
		end
	end

	gridButton.Text = if visible then "Hide Grid" else "Show Grid"
	platformButton.Text = if enabled then "Disable Platform" else "Enable Platform"
	updateAllCellVisuals(platform)
end

local function preparePlatformOrigin(platform: Model): boolean
	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return false
	end

	base.PivotOffset = CFrame.new()
	platform.PrimaryPart = base

	local island = islandModel()
	if island ~= nil then
		island.PrimaryPart = base
	end

	local origin = platform:FindFirstChild("PlatformOrigin")
	if origin ~= nil and origin:IsA("BasePart") then
		origin.CFrame = base.CFrame * CFrame.new(0, 0.77, 0)
	end

	pcall(function()
		platform.WorldPivot = base.CFrame
	end)
	pcall(function()
		if island ~= nil then
			island.WorldPivot = base.CFrame
		end
	end)

	return true
end

local function beginRecording(name: string): string?
	local recording = ChangeHistoryService:TryBeginRecording(name)
	if recording == nil then
		setStatus("Could not start undo recording. Try again after the current edit finishes.")
	end
	return recording
end

local function finishRecording(recording: string?)
	if recording ~= nil then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
end

local function updateModeButtons()
	for mode, button in modeButtons do
		button.BackgroundColor3 = if activeMode == mode then BUTTON_ACTIVE else BUTTON_BG
	end
end

local function setMode(mode: PaintMode?, skipPluginDeactivate: boolean?)
	local shouldDeactivate = activeMode ~= nil and mode == nil
	if mode ~= nil and splineAddActive then
		splineAddActive = false
		splineAddButton.BackgroundColor3 = BUTTON_BG
	end

	activeMode = mode
	updateModeButtons()

	if activeMode ~= nil then
		plugin:Activate(false)
		setStatus(`Paint mode: {activeMode}. Click the platform surface.`)
	else
		if shouldDeactivate and not skipPluginDeactivate then
			plugin:Deactivate()
		end
		setStatus("Paint mode off.")
	end
end

local function setSplineAddMode(enabled: boolean, skipPluginDeactivate: boolean?)
	if enabled then
		setMode(nil)
	end

	splineAddActive = enabled
	splineAddButton.BackgroundColor3 = if splineAddActive then BUTTON_ACTIVE else BUTTON_BG

	if splineAddActive then
		plugin:Activate(false)
		setStatus("Add Point mode: click the platform to insert a red spline control point.")
	else
		if not skipPluginDeactivate then
			plugin:Deactivate()
		end
		setStatus("Add Point mode off.")
	end
end

local function cellAtWorldPosition(platform: Model, worldPosition: Vector3): (number?, number?)
	local base = platformBasePart(platform)
	if base == nil then
		return nil, nil
	end

	local localPosition = base.CFrame:PointToObjectSpace(worldPosition)
	local size = cellSize(platform)
	local column = math.floor((localPosition.X + base.Size.X / 2) / size) + 1
	local row = math.floor((localPosition.Z + base.Size.Z / 2) / size) + 1

	if column < 1 or column > columns(platform) or row < 1 or row > rows(platform) then
		return nil, nil
	end

	return column, row
end

local function setCellBuildable(platform: Model, column: number, row: number, buildable: boolean)
	local rowValue = rowString(platform, row)
	if rowValue == nil then
		return
	end

	local old = rowValue.Value
	local marker = if buildable then "." else "#"
	rowValue.Value = string.sub(old, 1, column - 1) .. marker .. string.sub(old, column + 1)
	updateCellVisual(platform, column, row)
end

local function numberedName(prefix: string, index: number): string
	return `{prefix}_{string.format("%03d", index)}`
end

local function distanceXZ(left: Vector3, right: Vector3): number
	local deltaX = left.X - right.X
	local deltaZ = left.Z - right.Z
	return math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
end

local function collectSplineControls(): { BasePart }
	local folder = pathPointsFolder()
	local controls: { BasePart } = {}
	if folder == nil then
		return controls
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(controls, child)
		end
	end

	table.sort(controls, function(left, right)
		return left.Name < right.Name
	end)

	return controls
end

local function selectedSplineControls(): { BasePart }
	local folder = pathPointsFolder()
	local selectedControls: { BasePart } = {}
	if folder == nil then
		return selectedControls
	end

	local seen: { [Instance]: boolean } = {}
	local function addControl(instance: Instance)
		if instance:IsA("BasePart") and instance.Parent == folder and not seen[instance] then
			seen[instance] = true
			table.insert(selectedControls, instance)
		end
	end

	for _, selected in Selection:Get() do
		if selected == folder then
			for _, child in folder:GetChildren() do
				addControl(child)
			end
		elseif selected:IsDescendantOf(folder) then
			addControl(selected)
			for _, descendant in selected:GetDescendants() do
				addControl(descendant)
			end
		end
	end

	table.sort(selectedControls, function(left, right)
		return left.Name < right.Name
	end)

	return selectedControls
end

local function renameSplineControls(controls: { BasePart })
	for index, control in controls do
		control.Name = numberedName("ControlPending", index)
	end

	for index, control in controls do
		control.Name = numberedName("Control", index)
	end
end

local function splineControlIndex(controls: { BasePart }, control: BasePart): number?
	for index, candidate in controls do
		if candidate == control then
			return index
		end
	end
	return nil
end

local function pointOnPlatform(worldPosition: Vector3, surfaceOffset: number): Vector3?
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return nil
	end

	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return nil
	end

	local localPosition = base.CFrame:PointToObjectSpace(worldPosition)
	if
		localPosition.X < -base.Size.X / 2
		or localPosition.X > base.Size.X / 2
		or localPosition.Z < -base.Size.Z / 2
		or localPosition.Z > base.Size.Z / 2
	then
		setStatus("Click inside the platform rectangle to place a spline point.")
		return nil
	end

	return base.CFrame:PointToWorldSpace(
		Vector3.new(localPosition.X, base.Size.Y / 2 + surfaceOffset, localPosition.Z)
	)
end

local function controlPositionAt(points: { Vector3 }, index: number): Vector3
	local clampedIndex = math.clamp(index, 1, #points)
	return points[clampedIndex]
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

local function catmullRomTangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local alpha2 = alpha * alpha

	return (
		(p2 - p0)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * (2 * alpha))
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * (3 * alpha2))
	) * 0.5
end

local function buildSplinePath(positions: { Vector3 }): SplinePath
	local samples: { SplineSample } = {}
	local totalDistance = 0

	local function insertSample(position: Vector3, tangent: Vector3)
		if #samples > 0 then
			totalDistance += (position - samples[#samples].position).Magnitude
			if tangent.Magnitude < 0.001 then
				tangent = position - samples[#samples].position
			end
		end

		table.insert(samples, {
			position = position,
			tangent = tangent,
			distance = totalDistance,
		})
	end

	for segment = 1, #positions - 1 do
		local p0 = controlPositionAt(positions, segment - 1)
		local p1 = controlPositionAt(positions, segment)
		local p2 = controlPositionAt(positions, segment + 1)
		local p3 = controlPositionAt(positions, segment + 2)

		for step = 0, SPLINE_SAMPLES_PER_SEGMENT do
			if segment > 1 and step == 0 then
				continue
			end

			local alpha = step / SPLINE_SAMPLES_PER_SEGMENT
			insertSample(catmullRomPosition(p0, p1, p2, p3, alpha), catmullRomTangent(p0, p1, p2, p3, alpha))
		end
	end

	return {
		samples = samples,
		length = totalDistance,
	}
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

local function createPathTile(parent: Instance, name: string, position: Vector3): BasePart
	local tile = Instance.new("Part")
	tile.Name = name
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = false
	tile.CanTouch = false
	tile.Color = PATH_COLOR
	tile.Material = Enum.Material.Neon
	tile.Position = position
	tile.Shape = Enum.PartType.Cylinder
	tile.Size = Vector3.new(PATH_TILE_DIAMETER, 0.12, PATH_TILE_DIAMETER)
	tile.Transparency = PATH_TILE_TRANSPARENCY
	tile.Parent = parent
	return tile
end

local function createSplineControl(parent: Instance, position: Vector3): BasePart
	local control = Instance.new("Part")
	control.Name = "ControlPending"
	control.Anchored = true
	control.CanCollide = false
	control.CanQuery = true
	control.CanTouch = false
	control.Color = CONTROL_POINT_COLOR
	control.Material = Enum.Material.Neon
	control.Position = position
	control.Shape = Enum.PartType.Ball
	control.Size = Vector3.new(0.85, 0.85, 0.85)
	control.Transparency = CONTROL_POINT_TRANSPARENCY
	control.Parent = parent
	return control
end

local function rebuildPathTiles(path: SplinePath): number
	local folder = ensurePathTilesFolder()
	if folder == nil then
		setStatus("PathTiles folder is missing.")
		return 0
	end

	for _, child in folder:GetChildren() do
		child:Destroy()
	end

	local platform = platformModel()
	local base = if platform ~= nil then platformBasePart(platform) else nil
	local tileOffset = if base ~= nil then base.Size.Y / 2 + PATH_TILE_SURFACE_OFFSET else 0
	local tileCount = 0
	local distance = 0

	while distance <= path.length do
		tileCount += 1
		local sampledPosition = sampleSplinePath(path, distance)
		local tilePosition = sampledPosition
		if base ~= nil then
			local localPosition = base.CFrame:PointToObjectSpace(sampledPosition)
			tilePosition =
				base.CFrame:PointToWorldSpace(Vector3.new(localPosition.X, tileOffset, localPosition.Z))
		end

		createPathTile(folder, numberedName("PathCurve", tileCount), tilePosition)
		distance += PATH_TILE_SPACING
	end

	return tileCount
end

local function rebuildPathGrid(platform: Model, path: SplinePath)
	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return
	end

	local sampledPath: { Vector3 } = {}
	local distance = 0
	while distance <= path.length do
		table.insert(sampledPath, sampleSplinePath(path, distance))
		distance += PATH_GRID_SAMPLE_STEP
	end
	table.insert(sampledPath, sampleSplinePath(path, path.length))

	local size = cellSize(platform)
	for row = 1, rows(platform) do
		local rowValue = rowString(platform, row)
		if rowValue == nil then
			continue
		end

		local nextValue = ""
		for column = 1, columns(platform) do
			local localX = -base.Size.X / 2 + (column - 0.5) * size
			local localZ = -base.Size.Z / 2 + (row - 0.5) * size
			local cellPosition = base.CFrame:PointToWorldSpace(Vector3.new(localX, base.Size.Y / 2, localZ))
			local blocked = false

			for _, pathPosition in sampledPath do
				if distanceXZ(cellPosition, pathPosition) <= PATH_GRID_RADIUS then
					blocked = true
					break
				end
			end

			nextValue ..= if blocked then "#" else "."
		end

		rowValue.Value = nextValue
	end

	updateAllCellVisuals(platform)
end

local function rebuildSplineFromControls(): boolean
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return false
	end

	local controls = collectSplineControls()
	if #controls < 2 then
		setStatus("PathPoints needs at least two red control points.")
		return false
	end

	renameSplineControls(controls)

	local positions: { Vector3 } = {}
	for _, control in controls do
		table.insert(positions, control.Position)
	end

	local path = buildSplinePath(positions)
	if path.length < 0.1 then
		setStatus("Spline path is too short.")
		return false
	end

	local tileCount = rebuildPathTiles(path)
	rebuildPathGrid(platform, path)
	applyPlatformVisual()
	setStatus(`Rebuilt spline from {#controls} points into {tileCount} curve markers.`)
	return true
end

local function selectSplinePoints()
	setMode(nil)
	setSplineAddMode(false, true)

	local controls = collectSplineControls()
	if #controls == 0 then
		setStatus("No spline control points found.")
		return
	end

	Selection:Set(controls)
	setStatus("Selected red spline controls. Move individual points, then click Rebuild Curve.")
end

local function rebuildSplineButtonClicked()
	setMode(nil)
	setSplineAddMode(false, true)

	local recording = beginRecording("Rebuild spline path")
	if recording == nil then
		return
	end

	rebuildSplineFromControls()
	finishRecording(recording)
end

local function addSplinePointAt(worldPosition: Vector3)
	local folder = ensurePathPointsFolder()
	if folder == nil then
		setStatus("PathPoints folder is missing.")
		return
	end

	local pointPosition = pointOnPlatform(worldPosition, CONTROL_POINT_SURFACE_OFFSET)
	if pointPosition == nil then
		return
	end

	local recording = beginRecording("Add spline control point")
	if recording == nil then
		return
	end

	local controls = collectSplineControls()
	local selectedControls = selectedSplineControls()
	local insertIndex = #controls + 1
	local selectedIndex = if selectedControls[1] ~= nil
		then splineControlIndex(controls, selectedControls[1])
		else nil
	if selectedIndex ~= nil then
		insertIndex = selectedIndex + 1
	end

	local newControl = createSplineControl(folder, pointPosition)
	table.insert(controls, insertIndex, newControl)
	renameSplineControls(controls)
	rebuildSplineFromControls()
	Selection:Set({ newControl })
	finishRecording(recording)
	setStatus(`Added {newControl.Name}. Move it if needed, then rebuild.`)
end

local function deleteSelectedSplinePoints()
	setMode(nil)
	setSplineAddMode(false, true)

	local controls = collectSplineControls()
	local selectedControls = selectedSplineControls()
	if #selectedControls == 0 then
		setStatus("Select one or more red spline control points first.")
		return
	end

	if #controls - #selectedControls < 2 then
		setStatus("Keep at least two spline control points.")
		return
	end

	local recording = beginRecording("Delete spline control points")
	if recording == nil then
		return
	end

	local selectedLookup: { [Instance]: boolean } = {}
	for _, control in selectedControls do
		selectedLookup[control] = true
		control:Destroy()
	end

	local remainingControls: { BasePart } = {}
	for _, control in controls do
		if not selectedLookup[control] then
			table.insert(remainingControls, control)
		end
	end

	renameSplineControls(remainingControls)
	rebuildSplineFromControls()
	Selection:Set(remainingControls)
	finishRecording(recording)
	setStatus(`Deleted {#selectedControls} spline control point(s).`)
end

local function snapSplinePointsToPlatform()
	setMode(nil)
	setSplineAddMode(false, true)

	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return
	end

	local controls = selectedSplineControls()
	if #controls == 0 then
		controls = collectSplineControls()
	end

	if #controls == 0 then
		setStatus("No spline control points found.")
		return
	end

	local recording = beginRecording("Snap spline control points")
	if recording == nil then
		return
	end

	local controlOffset = base.Size.Y / 2 + CONTROL_POINT_SURFACE_OFFSET
	for _, control in controls do
		local localPosition = base.CFrame:PointToObjectSpace(control.Position)
		control.Position =
			base.CFrame:PointToWorldSpace(Vector3.new(localPosition.X, controlOffset, localPosition.Z))
	end

	rebuildSplineFromControls()
	Selection:Set(controls)
	finishRecording(recording)
	setStatus(`Snapped {#controls} spline point(s) to the platform surface.`)
end

local function exportSpline()
	local controls = collectSplineControls()
	if #controls == 0 then
		setStatus("No spline control points found.")
		return
	end

	local lines = {
		"-- Spline control point export",
		"-- Paste these positions into the authored path generator if you want to bake them.",
		"return {",
	}

	for _, control in controls do
		local position = control.Position
		table.insert(
			lines,
			string.format("\tVector3.new(%.3f, %.3f, %.3f),", position.X, position.Y, position.Z)
		)
	end

	table.insert(lines, "}")
	print(table.concat(lines, "\n"))
	setStatus("Spline control points printed to Output.")
end

local function paintCellAt(worldPosition: Vector3, mode: PaintMode)
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local column, row = cellAtWorldPosition(platform, worldPosition)
	if column == nil or row == nil then
		setStatus("Click inside the platform rectangle.")
		return
	end

	local recording = beginRecording(`Paint cell {mode}`)
	if recording == nil then
		return
	end

	if mode == "Legal" then
		setCellBuildable(platform, column, row, true)
	elseif mode == "Illegal" then
		setCellBuildable(platform, column, row, false)
	else
		setCellBuildable(platform, column, row, not isCellBuildable(platform, column, row))
	end

	finishRecording(recording)
	setStatus(
		`Painted cell {column}, {row} as {if isCellBuildable(platform, column, row)
			then "legal"
			else "illegal"}.`
	)
end

local function selectPlatform()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	setMode(nil)
	setSplineAddMode(false, true)
	preparePlatformOrigin(platform)
	Selection:Set({ platform })
	setStatus("Selected GamePlatform. Press F to focus; move/rotate this model only.")
end

local function fixOrigin()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	setMode(nil)
	setSplineAddMode(false, true)
	local recording = beginRecording("Fix grid platform origin")
	if recording == nil then
		return
	end

	if preparePlatformOrigin(platform) then
		Selection:Set({ platform })
		setStatus("Origin fixed at PlatformBase center.")
	end

	finishRecording(recording)
end

local function resetFlat()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	setMode(nil)
	setSplineAddMode(false, true)
	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return
	end

	local recording = beginRecording("Reset grid platform flat")
	if recording == nil then
		return
	end

	preparePlatformOrigin(platform)
	platform:PivotTo(CFrame.new(base.Position))
	preparePlatformOrigin(platform)
	Selection:Set({ platform })
	finishRecording(recording)
	setStatus("Platform reset flat with centered handles.")
end

local function selectedTargetPartOutsidePlatform(): BasePart?
	local platform = platformModel()
	for _, selected in Selection:Get() do
		if selected:IsA("BasePart") and (platform == nil or not selected:IsDescendantOf(platform)) then
			return selected
		end
		for _, descendant in selected:GetDescendants() do
			if
				descendant:IsA("BasePart") and (platform == nil or not descendant:IsDescendantOf(platform))
			then
				return descendant
			end
		end
	end
	return nil
end

local function snapToSelection()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	setMode(nil)
	setSplineAddMode(false, true)
	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return
	end

	local target = selectedTargetPartOutsidePlatform()
	if target == nil then
		setStatus("Select the island surface part first, then click Snap.")
		return
	end

	local recording = beginRecording("Snap grid platform to selection")
	if recording == nil then
		return
	end

	preparePlatformOrigin(platform)
	local verticalOffset = target.Size.Y / 2 + base.Size.Y / 2 + 0.08
	platform:PivotTo(target.CFrame * CFrame.new(0, verticalOffset, 0))
	preparePlatformOrigin(platform)
	Selection:Set({ platform })
	finishRecording(recording)
	setStatus(`Snapped to {target.Name}. Rotate Y if the island edge needs a finer angle.`)
end

local function toggleGrid()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local recording = beginRecording("Toggle grid overlay")
	if recording == nil then
		return
	end

	setBoolChild(platform, "GridVisible", not gridVisible(platform))
	applyPlatformVisual()
	finishRecording(recording)
	setStatus("Grid visibility toggled.")
end

local function togglePlatform()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local recording = beginRecording("Toggle grid platform")
	if recording == nil then
		return
	end

	setBoolChild(platform, "PlatformEnabled", not platformEnabled(platform))
	applyPlatformVisual()
	finishRecording(recording)
	setStatus("Platform visibility/collision toggled.")
end

local function exportLayout()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return
	end

	local folder = mapFolder(platform)
	if folder == nil then
		setStatus("CellMap is missing.")
		return
	end

	local lines = {
		"-- GamePlatform layout export",
		"-- . = legal/buildable, # = illegal/blocked",
		"return {",
		`\tcellSize = {cellSize(platform)},`,
		`\tcolumns = {columns(platform)},`,
		`\trows = {rows(platform)},`,
		"\tmap = {",
	}

	for row = 1, rows(platform) do
		local value = rowString(platform, row)
		table.insert(lines, `\t\t"{if value ~= nil then value.Value else ""}",`)
	end

	table.insert(lines, "\t},")
	table.insert(lines, "}")
	print(table.concat(lines, "\n"))
	setStatus("Layout printed to Output.")
end

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	openButton:SetActive(widget.Enabled)
	if widget.Enabled then
		applyPlatformVisual()
	end
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
end)

modeButtons.Toggle.MouseButton1Click:Connect(function()
	setMode(if activeMode == "Toggle" then nil else "Toggle")
end)
modeButtons.Legal.MouseButton1Click:Connect(function()
	setMode(if activeMode == "Legal" then nil else "Legal")
end)
modeButtons.Illegal.MouseButton1Click:Connect(function()
	setMode(if activeMode == "Illegal" then nil else "Illegal")
end)

widgetButtons.selectButton.MouseButton1Click:Connect(selectPlatform)
widgetButtons.originButton.MouseButton1Click:Connect(fixOrigin)
widgetButtons.resetButton.MouseButton1Click:Connect(resetFlat)
widgetButtons.snapButton.MouseButton1Click:Connect(snapToSelection)
widgetButtons.selectSplineButton.MouseButton1Click:Connect(selectSplinePoints)
widgetButtons.rebuildSplineButton.MouseButton1Click:Connect(rebuildSplineButtonClicked)
widgetButtons.addSplineButton.MouseButton1Click:Connect(function()
	setSplineAddMode(not splineAddActive)
end)
widgetButtons.deleteSplineButton.MouseButton1Click:Connect(deleteSelectedSplinePoints)
widgetButtons.snapSplineButton.MouseButton1Click:Connect(snapSplinePointsToPlatform)
widgetButtons.exportSplineButton.MouseButton1Click:Connect(exportSpline)
gridButton.MouseButton1Click:Connect(toggleGrid)
platformButton.MouseButton1Click:Connect(togglePlatform)
widgetButtons.exportButton.MouseButton1Click:Connect(exportLayout)

mouse.Button1Down:Connect(function()
	if splineAddActive then
		addSplinePointAt(mouse.Hit.Position)
		return
	end

	if activeMode == nil then
		return
	end
	paintCellAt(mouse.Hit.Position, activeMode)
end)

plugin.Deactivation:Connect(function()
	setMode(nil, true)
	setSplineAddMode(false, true)
end)

applyPlatformVisual()
print("Grid Platform Editor plugin loaded.")

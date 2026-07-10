--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ISLAND_NAME = "FirstPrivateIsland"
local PLATFORM_NAME = "GamePlatform"
local MAP_NAME = "CellMap"
local PATH_POINTS_NAME = "PathPoints"
local PATH_TILES_NAME = "PathTiles"

local LEGAL_COLOR = Color3.fromRGB(38, 217, 97)
local ILLEGAL_COLOR = Color3.fromRGB(255, 66, 41)
local PATH_COLOR = Color3.fromRGB(255, 199, 36)
local PORTAL_COLOR = Color3.fromRGB(99, 102, 241)
local GOAL_COLOR = Color3.fromRGB(255, 147, 51)
local AUTOPLACE_COLOR = Color3.fromRGB(14, 165, 233)
local CONTROL_POINT_COLOR = Color3.fromRGB(255, 46, 31)
local HOVER_COLOR = Color3.fromRGB(255, 255, 255)
local PANEL_BG = Color3.fromRGB(11, 14, 19)
local PANEL_HEADER = Color3.fromRGB(22, 27, 35)
local PANEL_SECTION = Color3.fromRGB(15, 20, 27)
local PANEL_STATUS = Color3.fromRGB(14, 18, 24)
local BUTTON_BG = Color3.fromRGB(25, 31, 40)
local BUTTON_ACTIVE = Color3.fromRGB(45, 212, 191)
local BUTTON_HOVER = Color3.fromRGB(36, 44, 56)
local BORDER = Color3.fromRGB(62, 73, 91)
local BORDER_ACTIVE = Color3.fromRGB(125, 211, 252)
local TEXT = Color3.fromRGB(242, 245, 250)
local TEXT_ACTIVE = Color3.fromRGB(4, 17, 19)
local MUTED = Color3.fromRGB(166, 174, 187)
local SUBTLE = Color3.fromRGB(109, 120, 138)

local LEGAL_TRANSPARENCY = 0.55
local ILLEGAL_TRANSPARENCY = 0.22
local SPECIAL_TRANSPARENCY = 0.18
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
local HOVER_PREVIEW_NAME = "GridHoverPreview"
local CELL_VISUAL_INSET_STUDS = 0.04
local GRID_PIXELS_PER_STUD = 8

type PaintMode = "Toggle" | "Legal" | "Illegal" | "Portal" | "Goal" | "AutoPlace"
type ToolTab = "Paint" | "Path" | "Stage" | "Data"
type CellCode = "." | "#" | "P" | "G" | "A"

type SplineSample = {
	position: Vector3,
	tangent: Vector3,
	distance: number,
}

type SplinePath = {
	samples: { SplineSample },
	length: number,
}

type PlatformRayHit = {
	platform: Model,
	base: BasePart,
	localPosition: Vector3,
	worldPosition: Vector3,
}

local toolbar = plugin:CreateToolbar("Grid Platform")
local openButton =
	toolbar:CreateButton("GridPlatformEditor", "Open the grid platform editor", "", "Grid Editor")
openButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 620, 320, 420)
local widget = plugin:CreateDockWidgetPluginGuiAsync("GridPlatformEditorPanel", widgetInfo)
widget.Title = "Grid Platform Editor"

local activeMode: PaintMode? = "Legal"
local mouse = plugin:GetMouse()
local statusLabel: TextLabel
local modeHintLabel: TextLabel
local targetInfoLabel: TextLabel
local inspectorStageLabel: TextLabel
local inspectorCellLabel: TextLabel
local inspectorTypeLabel: TextLabel
local inspectorWorldLabel: TextLabel
local inspectorBrushLabel: TextLabel
local inspectorGridLabel: TextLabel
local modeButtons: { [PaintMode]: TextButton } = {} :: any
local toolTabButtons: { [ToolTab]: TextButton } = {} :: any
local toolTabAnchors: { [ToolTab]: GuiObject } = {} :: any
local stageProfileButtons: { TextButton } = {}
local mainScrollFrame: ScrollingFrame? = nil
local activeToolTab: ToolTab = "Paint"
local activeStageProfile = "First Private Island"
local splineAddActive = false
local splineAddButton: TextButton
local gridButton: TextButton
local platformButton: TextButton
local calibrateButton: TextButton
local hoverPreviewFrame: Frame? = nil
local hoverPlatform: Model? = nil
local hoverColumn: number? = nil
local hoverRow: number? = nil
local hoverCellKey: string? = nil
local dragPainting = false
local dragPaintRecording: string? = nil
local dragPaintedCells: { [string]: boolean } = {}
local canvasPreviewFrame: Frame? = nil
local canvasHoverFrame: Frame? = nil
local canvasPreviewCells: { [string]: TextButton } = {}
local handleCanvasCellHover: ((number, number) -> ())? = nil
local handleCanvasCellPaintStart: ((number, number) -> ())? = nil
local handleCanvasCellPaintDrag: ((number, number) -> ())? = nil
local handleCanvasPaintEnd: (() -> ())? = nil

local function setStatus(message: string, quiet: boolean?)
	statusLabel.Text = message
	if quiet ~= true then
		print(`Grid Platform Editor: {message}`)
	end
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
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
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
	button.Font = Enum.Font.GothamMedium
	button.Text = text
	button.TextColor3 = TEXT
	button.TextSize = 13
	button.TextWrapped = true
	button.Size = UDim2.new(1, 0, 0, height)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "ButtonStroke"
	stroke.Color = BORDER
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		if button.BackgroundColor3 ~= BUTTON_ACTIVE then
			button.BackgroundColor3 = BUTTON_HOVER
		end
	end)
	button.MouseLeave:Connect(function()
		if button.BackgroundColor3 ~= BUTTON_ACTIVE then
			button.BackgroundColor3 = BUTTON_BG
		end
	end)

	return button
end

local function createSection(parent: Instance, name: string, title: string, subtitle: string?): Frame
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

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.68
	stroke.Thickness = 1
	stroke.Parent = section

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = section

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = section

	local titleLabel = createLabel(section, `{name}Title`, title, 16, TEXT)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 12
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	if subtitle ~= nil and subtitle ~= "" then
		local subtitleLabel = createLabel(section, `{name}Subtitle`, subtitle, 18, MUTED)
		subtitleLabel.TextSize = 10
		subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	end

	return section
end

local function createButtonRow(parent: Instance, name: string, buttons: { { string } }): { TextButton }
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 32)
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local created: { TextButton } = {}
	for _, info in buttons do
		local button = createButton(row, info[1], info[2], 32)
		button.Size = UDim2.new(1 / #buttons, -5, 1, 0)
		table.insert(created, button)
	end

	return created
end

local function setButtonActive(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then BUTTON_ACTIVE else BUTTON_BG
	button.TextColor3 = if active then TEXT_ACTIVE else TEXT
	local stroke = button:FindFirstChild("ButtonStroke")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = if active then BORDER_ACTIVE else BORDER
		stroke.Transparency = if active then 0.05 else 0.55
		stroke.Thickness = if active then 1.5 else 1
	end
end

local function createChip(parent: Instance, name: string, text: string, color: Color3): Frame
	local chip = Instance.new("Frame")
	chip.Name = name
	chip.BackgroundColor3 = Color3.fromRGB(31, 36, 46)
	chip.BorderSizePixel = 0
	chip.Size = UDim2.new(1, 0, 0, 20)
	chip.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = chip

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.65
	stroke.Thickness = 1
	stroke.Parent = chip

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.Position = UDim2.fromOffset(6, 6)
	swatch.Size = UDim2.fromOffset(8, 8)
	swatch.Parent = chip

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = MUTED
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(18, 0)
	label.Size = UDim2.new(1, -21, 1, 0)
	label.Parent = chip

	return chip
end

local function createLegendRow(parent: Instance)
	local legend = Instance.new("Frame")
	legend.Name = "ModeLegend"
	legend.BackgroundTransparency = 1
	legend.Size = UDim2.new(1, 0, 0, 44)
	legend.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(5, 4)
	grid.CellSize = UDim2.new(0.333, -5, 0, 20)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = legend

	createChip(legend, "BuildableChip", ". Build", LEGAL_COLOR)
	createChip(legend, "BlockedChip", "# Block", ILLEGAL_COLOR)
	createChip(legend, "PortalChip", "P Portal", PORTAL_COLOR)
	createChip(legend, "GoalChip", "G Goal", GOAL_COLOR)
	createChip(legend, "AutoChip", "A Auto", AUTOPLACE_COLOR)
end

local function createInlineLabel(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function createPropertyField(
	parent: Instance,
	name: string,
	labelText: string,
	valueText: string
): TextLabel
	local field = Instance.new("Frame")
	field.Name = name
	field.BackgroundColor3 = Color3.fromRGB(16, 21, 28)
	field.BorderSizePixel = 0
	field.Size = UDim2.new(0.5, -4, 0, 46)
	field.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = field

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = field

	local label = createInlineLabel(field, "Label", labelText, MUTED)
	label.Position = UDim2.fromOffset(9, 5)
	label.Size = UDim2.new(1, -18, 0, 14)
	label.TextSize = 10

	local value = createInlineLabel(field, "Value", valueText, TEXT)
	value.Font = Enum.Font.GothamBold
	value.Position = UDim2.fromOffset(9, 20)
	value.Size = UDim2.new(1, -18, 0, 18)
	value.TextSize = 12
	return value
end

local function createStageProfileButton(
	parent: Instance,
	name: string,
	title: string,
	detail: string
): TextButton
	local button = createButton(parent, name, "", 36)
	button.Text = ""
	button.AutoButtonColor = true

	local titleLabel = createInlineLabel(button, "Title", title, TEXT)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Position = UDim2.fromOffset(7, 4)
	titleLabel.Size = UDim2.new(1, -14, 0, 14)
	titleLabel.TextSize = 10
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local detailLabel = createInlineLabel(button, "Detail", detail, MUTED)
	detailLabel.Position = UDim2.fromOffset(7, 19)
	detailLabel.Size = UDim2.new(1, -14, 0, 13)
	detailLabel.TextSize = 9
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd

	return button
end

local function createCanvasPreview(parent: Instance): Frame
	local canvas = Instance.new("Frame")
	canvas.Name = "CanvasGrid"
	canvas.BackgroundColor3 = Color3.fromRGB(10, 16, 23)
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.Size = UDim2.new(1, 0, 0, 246)
	canvas.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = canvas

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(49, 64, 80)
	stroke.Transparency = 0.1
	stroke.Thickness = 1
	stroke.Parent = canvas

	local gridTexture = Instance.new("Frame")
	gridTexture.Name = "CanvasBackdrop"
	gridTexture.BackgroundColor3 = Color3.fromRGB(12, 19, 27)
	gridTexture.BackgroundTransparency = 0.18
	gridTexture.BorderSizePixel = 0
	gridTexture.Size = UDim2.fromScale(1, 1)
	gridTexture.ZIndex = 0
	gridTexture.Parent = canvas

	local hover = Instance.new("Frame")
	hover.Name = "CanvasHover"
	hover.BackgroundColor3 = HOVER_COLOR
	hover.BackgroundTransparency = 0.55
	hover.BorderSizePixel = 0
	hover.Visible = false
	hover.ZIndex = 5
	hover.Parent = canvas

	local hoverStroke = Instance.new("UIStroke")
	hoverStroke.Name = "CanvasHoverStroke"
	hoverStroke.Color = Color3.fromRGB(255, 255, 255)
	hoverStroke.Thickness = 2
	hoverStroke.Transparency = 0
	hoverStroke.Parent = hover

	canvasHoverFrame = hover
	canvasPreviewFrame = canvas
	return canvas
end

local function createLayerRow(parent: Instance, name: string, labelText: string, countText: string): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundColor3 = Color3.fromRGB(16, 21, 28)
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.62
	stroke.Thickness = 1
	stroke.Parent = row

	local visibleBox = Instance.new("Frame")
	visibleBox.Name = "Visible"
	visibleBox.BackgroundColor3 = Color3.fromRGB(28, 36, 47)
	visibleBox.BorderSizePixel = 0
	visibleBox.Position = UDim2.fromOffset(9, 9)
	visibleBox.Size = UDim2.fromOffset(11, 11)
	visibleBox.Parent = row

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 3)
	boxCorner.Parent = visibleBox

	local label = createInlineLabel(row, "Label", labelText, TEXT)
	label.Position = UDim2.fromOffset(28, 0)
	label.Size = UDim2.new(1, -78, 1, 0)
	label.TextSize = 12

	local count = createInlineLabel(row, "Count", countText, MUTED)
	count.Position = UDim2.new(1, -46, 0, 0)
	count.Size = UDim2.fromOffset(38, 30)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextSize = 11

	return row
end

local function createHeaderPanel(parent: Instance)
	local header = Instance.new("Frame")
	header.Name = "ToolHeader"
	header.BackgroundColor3 = PANEL_HEADER
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 48)
	header.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = header

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = header

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = BORDER
	accent.BorderSizePixel = 0
	accent.Position = UDim2.fromOffset(0, 0)
	accent.Size = UDim2.new(1, 0, 0, 1)
	accent.Parent = header

	local title = createLabel(header, "Title", "Grid Platform Editor", 18, TEXT)
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 18)
	title.TextSize = 14
	title.TextYAlignment = Enum.TextYAlignment.Center

	targetInfoLabel = createLabel(header, "TargetInfo", "Target: not connected", 15, MUTED)
	targetInfoLabel.Position = UDim2.fromOffset(12, 24)
	targetInfoLabel.Size = UDim2.new(1, -24, 0, 15)
	targetInfoLabel.TextSize = 10
	targetInfoLabel.TextYAlignment = Enum.TextYAlignment.Center

	modeHintLabel = createLabel(header, "ModeHint", "Brush: Legal", 11, SUBTLE)
	modeHintLabel.Position = UDim2.fromOffset(12, 37)
	modeHintLabel.Size = UDim2.new(1, -24, 0, 11)
	modeHintLabel.TextSize = 9
	modeHintLabel.TextYAlignment = Enum.TextYAlignment.Center
end

local function createStatusDock(parent: Instance)
	local dock = Instance.new("Frame")
	dock.Name = "StatusDock"
	dock.BackgroundColor3 = PANEL_STATUS
	dock.BorderSizePixel = 0
	dock.Position = UDim2.new(0, 0, 1, -38)
	dock.Size = UDim2.new(1, 0, 0, 38)
	dock.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = dock

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.62
	stroke.Thickness = 1
	stroke.Parent = dock

	local label = createLabel(dock, "StatusTitle", "STATUS", 10, SUBTLE)
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromOffset(10, 5)
	label.Size = UDim2.new(1, -20, 0, 10)
	label.TextSize = 9

	statusLabel =
		createLabel(dock, "StatusText", "Ready. Paint on the canvas or switch brushes above.", 18, MUTED)
	statusLabel.Position = UDim2.fromOffset(10, 16)
	statusLabel.Size = UDim2.new(1, -20, 0, 18)
	statusLabel.TextSize = 11
end

local function buildWidget()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = PANEL_BG
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = widget

	local rootPadding = Instance.new("UIPadding")
	rootPadding.PaddingTop = UDim.new(0, 8)
	rootPadding.PaddingBottom = UDim.new(0, 8)
	rootPadding.PaddingLeft = UDim.new(0, 8)
	rootPadding.PaddingRight = UDim.new(0, 8)
	rootPadding.Parent = root

	createHeaderPanel(root)
	createStatusDock(root)

	local commandTabRow = createButtonRow(root, "CommandTabs", {
		{ "PaintTab", "Paint" },
		{ "PathTab", "Path" },
		{ "StageTab", "Stage" },
		{ "DataTab", "Data" },
	})
	local commandTabFrame = commandTabRow[1].Parent
	if commandTabFrame ~= nil and commandTabFrame:IsA("Frame") then
		commandTabFrame.Position = UDim2.fromOffset(0, 56)
		commandTabFrame.Size = UDim2.new(1, 0, 0, 32)
	end
	toolTabButtons.Paint = commandTabRow[1]
	toolTabButtons.Path = commandTabRow[2]
	toolTabButtons.Stage = commandTabRow[3]
	toolTabButtons.Data = commandTabRow[4]
	setButtonActive(toolTabButtons.Paint, true)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Active = true
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = BORDER
	scroll.Position = UDim2.fromOffset(0, 96)
	scroll.Size = UDim2.new(1, 0, 1, -142)
	scroll.Parent = root
	mainScrollFrame = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local canvasSection = createSection(
		scroll,
		"CanvasFirst",
		"Canvas",
		"Pick a stage profile, then paint cells directly on the canvas or in the 3D viewport."
	)
	local stageRow = Instance.new("Frame")
	stageRow.Name = "StageProfiles"
	stageRow.BackgroundTransparency = 1
	stageRow.Size = UDim2.new(1, 0, 0, 36)
	stageRow.Parent = canvasSection

	local stageRowLayout = Instance.new("UIListLayout")
	stageRowLayout.FillDirection = Enum.FillDirection.Horizontal
	stageRowLayout.Padding = UDim.new(0, 6)
	stageRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stageRowLayout.Parent = stageRow

	stageProfileButtons = {
		createStageProfileButton(stageRow, "StageFirstPrivateIsland", "First Island", "active"),
		createStageProfileButton(stageRow, "StageForestBend", "Forest Bend", "draft"),
		createStageProfileButton(stageRow, "StageTestPad", "Test Pad", "safe"),
	}
	for _, stageButton in stageProfileButtons do
		stageButton.Size = UDim2.new(1 / #stageProfileButtons, -4, 1, 0)
	end
	setButtonActive(stageProfileButtons[1], true)

	createCanvasPreview(canvasSection)
	createLegendRow(canvasSection)

	local modeSection = createSection(
		scroll,
		"PaintMode",
		"Brush Palette",
		"Pick what the next click paints. The strong hover square is the cell that commits."
	)
	local modeRow = createButtonRow(modeSection, "Modes", {
		{ "Toggle", "Toggle" },
		{ "Legal", "Legal" },
		{ "Illegal", "Illegal" },
	})
	local specialModeRow = createButtonRow(modeSection, "SpecialModes", {
		{ "Portal", "Portal" },
		{ "Goal", "Goal" },
		{ "AutoPlace", "Auto Place" },
	})
	modeButtons.Toggle = modeRow[1]
	modeButtons.Legal = modeRow[2]
	modeButtons.Illegal = modeRow[3]
	modeButtons.Portal = specialModeRow[1]
	modeButtons.Goal = specialModeRow[2]
	modeButtons.AutoPlace = specialModeRow[3]
	setButtonActive(modeButtons.Legal, true)

	local inspectorSection = createSection(
		scroll,
		"InspectorPanel",
		"Inspector",
		"Selected and hovered cell information stays visible while painting."
	)
	local propertyGrid = Instance.new("Frame")
	propertyGrid.Name = "InspectorProperties"
	propertyGrid.BackgroundTransparency = 1
	propertyGrid.Size = UDim2.new(1, 0, 0, 154)
	propertyGrid.Parent = inspectorSection

	local propertyLayout = Instance.new("UIGridLayout")
	propertyLayout.CellPadding = UDim2.fromOffset(8, 8)
	propertyLayout.CellSize = UDim2.new(0.5, -4, 0, 46)
	propertyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	propertyLayout.Parent = propertyGrid

	inspectorStageLabel = createPropertyField(propertyGrid, "StageField", "Stage", activeStageProfile)
	inspectorCellLabel = createPropertyField(propertyGrid, "CellField", "Cell", "-")
	inspectorTypeLabel = createPropertyField(propertyGrid, "TypeField", "Type", "-")
	inspectorBrushLabel = createPropertyField(propertyGrid, "BrushField", "Brush", "None")
	inspectorWorldLabel = createPropertyField(propertyGrid, "WorldField", "World", "-")
	inspectorGridLabel = createPropertyField(propertyGrid, "GridField", "Grid", "32 x 27")

	local layerSection =
		createSection(scroll, "LayerTree", "Layer Tree", "Quick readout for the main editable systems.")
	createLayerRow(layerSection, "GridCellsLayer", "Grid cells", "864")
	createLayerRow(layerSection, "PathSplineLayer", "Path spline", "curve")
	createLayerRow(layerSection, "PortalLayer", "Portal spawns", "P")
	createLayerRow(layerSection, "GoalLayer", "Goal zones", "G")
	createLayerRow(layerSection, "AutoPlaceLayer", "Auto-place slots", "A")

	local placementSection = createSection(
		scroll,
		"Placement",
		"Platform",
		"Fix handles, flatten rotation, or snap to the island surface."
	)
	local selectRow = createButtonRow(placementSection, "SelectRow", {
		{ "Select", "Select Platform" },
		{ "Origin", "Fix Origin" },
	})

	local resetSnapRow = createButtonRow(placementSection, "ResetSnapRow", {
		{ "Reset", "Reset Flat" },
		{ "Snap", "Snap to Selection" },
	})
	calibrateButton = createButton(placementSection, "CalibrateGrid", "Calibrate Grid to 32 x 27", 38)
	local visibilityRow = createButtonRow(placementSection, "VisibilityRow", {
		{ "Grid", "Toggle Grid" },
		{ "Platform", "Toggle Platform" },
	})
	gridButton = visibilityRow[1]
	platformButton = visibilityRow[2]

	local splineSection =
		createSection(scroll, "SplinePath", "Spline Path", "Use red control points for smoother enemy turns.")
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
		"Move red points with Studio tools, then rebuild. Add Point inserts after the selected point.",
		46,
		MUTED
	)

	local exportSection = createSection(
		scroll,
		"Export",
		"Export",
		"Print the current grid map when you want to bake source data."
	)
	local exportLayoutButton = createButton(exportSection, "ExportLayout", "Print Layout to Output", 36)
	createLabel(
		exportSection,
		"ExportHelp",
		"Export uses . buildable, # blocked/path, P portal spawn, G goal, A auto-place slot.",
		54,
		MUTED
	)
	toolTabAnchors.Paint = canvasSection
	toolTabAnchors.Path = splineSection
	toolTabAnchors.Stage = canvasSection
	toolTabAnchors.Data = inspectorSection

	return {
		selectButton = selectRow[1],
		originButton = selectRow[2],
		resetButton = resetSnapRow[1],
		snapButton = resetSnapRow[2],
		calibrateButton = calibrateButton,
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

local function gridFootprint(platform: Model): (number, number)
	local size = cellSize(platform)
	return columns(platform) * size, rows(platform) * size
end

local function gridLocalBounds(platform: Model): (number, number, number, number)
	local width, depth = gridFootprint(platform)
	return -width / 2, width / 2, -depth / 2, depth / 2
end

local function rowName(row: number): string
	return `Row_{string.format("%02d", row)}`
end

local function cellName(column: number, row: number): string
	return `Cell_{string.format("%02d", column)}_{string.format("%02d", row)}`
end

local function gridCellKey(column: number, row: number): string
	return `{column}:{row}`
end

local function rowString(platform: Model, row: number): StringValue?
	local folder = mapFolder(platform)
	if folder == nil then
		return nil
	end
	return stringValue(folder, rowName(row))
end

local function gridCellsFrame(platform: Model): Frame?
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

	return cells
end

local function cellFrame(platform: Model, column: number, row: number): Frame?
	local cells = gridCellsFrame(platform)
	if cells == nil then
		return nil
	end

	local frame = cells:FindFirstChild(cellName(column, row))
	if frame ~= nil and frame:IsA("Frame") then
		return frame
	end
	return nil
end

local function normalizeCellCode(code: string?): CellCode
	if code == "." or code == "#" or code == "P" or code == "G" or code == "A" then
		return code
	end
	return "."
end

local function cellCode(platform: Model, column: number, row: number): CellCode
	local rowValue = rowString(platform, row)
	if rowValue == nil then
		return "."
	end
	return normalizeCellCode(string.sub(rowValue.Value, column, column))
end

local function isCellBuildable(platform: Model, column: number, row: number): boolean
	local code = cellCode(platform, column, row)
	return code == "." or code == "A"
end

local function colorForCellCode(code: CellCode): Color3
	if code == "P" then
		return PORTAL_COLOR
	elseif code == "G" then
		return GOAL_COLOR
	elseif code == "A" then
		return AUTOPLACE_COLOR
	elseif code == "#" then
		return ILLEGAL_COLOR
	end
	return LEGAL_COLOR
end

local function labelForCellCode(code: CellCode): string
	if code == "P" then
		return "Portal spawn"
	elseif code == "G" then
		return "Goal zone"
	elseif code == "A" then
		return "Auto-place slot"
	elseif code == "#" then
		return "Blocked / path"
	end
	return "Legal build"
end

local function syncCanvasPreview(platform: Model)
	local canvas = canvasPreviewFrame
	if canvas == nil then
		return
	end

	local expectedColumns = columns(platform)
	local expectedRows = rows(platform)
	local expectedCells = expectedColumns * expectedRows
	local currentCells = 0
	for _, child in canvas:GetChildren() do
		if child:IsA("TextButton") and string.sub(child.Name, 1, 12) == "PreviewCell_" then
			currentCells += 1
		end
	end

	if currentCells ~= expectedCells then
		canvasPreviewCells = {}
		for _, child in canvas:GetChildren() do
			if child:IsA("GuiObject") and string.sub(child.Name, 1, 12) == "PreviewCell_" then
				child:Destroy()
			end
		end
	end

	local inset = 0.003
	for row = 1, expectedRows do
		for column = 1, expectedColumns do
			local key = gridCellKey(column, row)
			local previewCell = canvasPreviewCells[key]
			if previewCell == nil or previewCell.Parent ~= canvas then
				previewCell = Instance.new("TextButton")
				previewCell.Name = `PreviewCell_{string.format("%02d", column)}_{string.format("%02d", row)}`
				previewCell.AutoButtonColor = false
				previewCell.BorderSizePixel = 0
				previewCell.Text = ""
				previewCell.Selectable = false
				previewCell.ZIndex = 2
				previewCell.Parent = canvas
				canvasPreviewCells[key] = previewCell

				local cellColumn = column
				local cellRow = row
				previewCell.MouseEnter:Connect(function()
					if handleCanvasCellHover ~= nil then
						handleCanvasCellHover(cellColumn, cellRow)
					end
					if dragPainting and handleCanvasCellPaintDrag ~= nil then
						handleCanvasCellPaintDrag(cellColumn, cellRow)
					end
				end)
				previewCell.MouseButton1Down:Connect(function()
					if handleCanvasCellPaintStart ~= nil then
						handleCanvasCellPaintStart(cellColumn, cellRow)
					end
				end)
				previewCell.MouseButton1Up:Connect(function()
					if handleCanvasPaintEnd ~= nil then
						handleCanvasPaintEnd()
					end
				end)
			end

			previewCell.Position =
				UDim2.fromScale((column - 1) / expectedColumns + inset, (row - 1) / expectedRows + inset)
			previewCell.Size =
				UDim2.fromScale((1 / expectedColumns) - inset * 2, (1 / expectedRows) - inset * 2)
		end
	end
end

local function updateCanvasCellVisual(platform: Model, column: number, row: number)
	local previewCell = canvasPreviewCells[gridCellKey(column, row)]
	if previewCell == nil then
		return
	end

	local code = cellCode(platform, column, row)
	previewCell.BackgroundColor3 = colorForCellCode(code)
	previewCell.BackgroundTransparency = if code == "." then 0.68 elseif code == "#" then 0.42 else 0.22
end

local function updateInspectorCell(platform: Model?, column: number?, row: number?, worldPosition: Vector3?)
	if inspectorStageLabel ~= nil then
		inspectorStageLabel.Text = activeStageProfile
	end
	if inspectorBrushLabel ~= nil then
		inspectorBrushLabel.Text = if activeMode ~= nil
			then activeMode
			else if splineAddActive then "Spline point" else "None"
	end

	if platform == nil or column == nil or row == nil then
		if inspectorCellLabel ~= nil then
			inspectorCellLabel.Text = "-"
		end
		if inspectorTypeLabel ~= nil then
			inspectorTypeLabel.Text = "-"
		end
		if inspectorWorldLabel ~= nil then
			inspectorWorldLabel.Text = "-"
		end
		return
	end

	local code = cellCode(platform, column, row)
	if inspectorCellLabel ~= nil then
		inspectorCellLabel.Text = `{column}, {row}`
	end
	if inspectorTypeLabel ~= nil then
		inspectorTypeLabel.Text = labelForCellCode(code)
	end
	if inspectorWorldLabel ~= nil then
		if worldPosition ~= nil then
			inspectorWorldLabel.Text =
				`{math.floor(worldPosition.X)}, {math.floor(worldPosition.Y)}, {math.floor(worldPosition.Z)}`
		else
			inspectorWorldLabel.Text = "viewport"
		end
	end
end

local function updateCellVisual(platform: Model, column: number, row: number)
	local frame = cellFrame(platform, column, row)
	if frame == nil then
		updateCanvasCellVisual(platform, column, row)
		return
	end

	local code = cellCode(platform, column, row)
	frame.BackgroundColor3 = colorForCellCode(code)
	frame.BackgroundTransparency = if code == "P" or code == "G"
		then SPECIAL_TRANSPARENCY
		elseif code == "#" then ILLEGAL_TRANSPARENCY
		else LEGAL_TRANSPARENCY
	updateCanvasCellVisual(platform, column, row)
end

local function updateAllCellVisuals(platform: Model)
	syncCanvasPreview(platform)
	for row = 1, rows(platform) do
		for column = 1, columns(platform) do
			updateCellVisual(platform, column, row)
		end
	end
end

local function syncGridTemplate(platform: Model)
	local base = platformBasePart(platform)
	if base == nil then
		setStatus("PlatformBase is missing.")
		return false
	end

	local width, depth = gridFootprint(platform)
	if math.abs(base.Size.X - width) > 0.001 or math.abs(base.Size.Z - depth) > 0.001 then
		base.Size = Vector3.new(width, base.Size.Y, depth)
	end

	local overlay = base:FindFirstChild("GridOverlay")
	if overlay == nil or not overlay:IsA("SurfaceGui") then
		if overlay ~= nil then
			overlay:Destroy()
		end
		overlay = Instance.new("SurfaceGui")
		overlay.Name = "GridOverlay"
		overlay.Parent = base
	end
	overlay.Face = Enum.NormalId.Top
	overlay.AlwaysOnTop = true
	overlay.LightInfluence = 0
	overlay.PixelsPerStud = GRID_PIXELS_PER_STUD
	overlay.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud

	local cells = overlay:FindFirstChild("Cells")
	if cells == nil or not cells:IsA("Frame") then
		if cells ~= nil then
			cells:Destroy()
		end
		cells = Instance.new("Frame")
		cells.Name = "Cells"
		cells.Parent = overlay
	end
	cells.BackgroundTransparency = 1
	cells.BorderSizePixel = 0
	cells.Size = UDim2.fromScale(1, 1)

	local cell = cellSize(platform)
	local inset = math.min(CELL_VISUAL_INSET_STUDS, cell * 0.1)
	for row = 1, rows(platform) do
		for column = 1, columns(platform) do
			local frame = cells:FindFirstChild(cellName(column, row))
			if frame == nil or not frame:IsA("Frame") then
				if frame ~= nil then
					frame:Destroy()
				end
				frame = Instance.new("Frame")
				frame.Name = cellName(column, row)
				frame.Parent = cells
			end
			frame.BorderSizePixel = 0
			frame.Position =
				UDim2.fromScale(((column - 1) * cell + inset) / width, ((row - 1) * cell + inset) / depth)
			frame.Size = UDim2.fromScale((cell - inset * 2) / width, (cell - inset * 2) / depth)
		end
	end

	updateAllCellVisuals(platform)
	return true
end

local function updateTargetInfo(platform: Model?)
	if platform == nil then
		targetInfoLabel.Text = "Target: not connected"
		if inspectorGridLabel ~= nil then
			inspectorGridLabel.Text = "-"
		end
		return
	end
	local base = platformBasePart(platform)
	local width, depth = gridFootprint(platform)
	local aligned = if base ~= nil
		then math.abs(base.Size.X - width) < 0.01 and math.abs(base.Size.Z - depth) < 0.01
		else false
	targetInfoLabel.Text =
		`{columns(platform)} x {rows(platform)} cells | {cellSize(platform)} studs | {width} x {depth} footprint | {if aligned
			then "aligned"
			else "needs calibration"}`
	if inspectorGridLabel ~= nil then
		inspectorGridLabel.Text = `{columns(platform)} x {rows(platform)}`
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
	updateTargetInfo(platform)
	updateAllCellVisuals(platform)
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
	calibrateButton.Text = `Calibrate Grid to {columns(platform)} x {rows(platform)}`
	setButtonActive(gridButton, visible)
	setButtonActive(platformButton, enabled)
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

local function finishPaintDrag()
	if dragPainting then
		finishRecording(dragPaintRecording)
	end
	dragPainting = false
	dragPaintRecording = nil
	dragPaintedCells = {}
end

local function clearHoverPreview()
	hoverPlatform = nil
	hoverColumn = nil
	hoverRow = nil
	hoverCellKey = nil
	updateInspectorCell(nil, nil, nil, nil)
	if hoverPreviewFrame ~= nil then
		hoverPreviewFrame.Visible = false
	end
	if canvasHoverFrame ~= nil then
		canvasHoverFrame.Visible = false
	end
end

local function ensureHoverPreview(platform: Model): Frame?
	local cells = gridCellsFrame(platform)
	if cells == nil then
		return nil
	end

	if hoverPreviewFrame ~= nil and hoverPreviewFrame.Parent == cells then
		return hoverPreviewFrame
	end

	local existing = cells:FindFirstChild(HOVER_PREVIEW_NAME)
	if existing ~= nil then
		if existing:IsA("Frame") then
			hoverPreviewFrame = existing
			return existing
		end
		existing:Destroy()
	end

	local preview = Instance.new("Frame")
	preview.Name = HOVER_PREVIEW_NAME
	preview.BackgroundColor3 = HOVER_COLOR
	preview.BackgroundTransparency = 0.82
	preview.BorderSizePixel = 0
	preview.Visible = false
	preview.ZIndex = 40
	preview.Parent = cells

	local stroke = Instance.new("UIStroke")
	stroke.Name = "HoverStroke"
	stroke.Color = BORDER_ACTIVE
	stroke.Thickness = 4
	stroke.Transparency = 0
	stroke.Parent = preview

	hoverPreviewFrame = preview
	return preview
end

local function updateModeButtons()
	for mode, button in modeButtons do
		setButtonActive(button, activeMode == mode)
	end
end

local function setMode(mode: PaintMode?, skipPluginDeactivate: boolean?)
	finishPaintDrag()
	clearHoverPreview()
	local shouldDeactivate = activeMode ~= nil and mode == nil
	if mode ~= nil and splineAddActive then
		splineAddActive = false
		setButtonActive(splineAddButton, false)
	end

	activeMode = mode
	updateModeButtons()
	updateInspectorCell(hoverPlatform, hoverColumn, hoverRow, nil)

	if activeMode ~= nil then
		plugin:Activate(false)
		modeHintLabel.Text = `Painting: {activeMode}`
		setStatus(`Paint mode: {activeMode}. Click the platform surface.`)
	else
		if shouldDeactivate and not skipPluginDeactivate then
			plugin:Deactivate()
		end
		modeHintLabel.Text = "Pick a paint mode or edit the spline path."
		setStatus("Paint mode off.")
	end
end

local function setSplineAddMode(enabled: boolean, skipPluginDeactivate: boolean?)
	finishPaintDrag()
	clearHoverPreview()
	if enabled then
		setMode(nil)
	end

	splineAddActive = enabled
	setButtonActive(splineAddButton, splineAddActive)
	updateInspectorCell(hoverPlatform, hoverColumn, hoverRow, nil)

	if splineAddActive then
		plugin:Activate(false)
		modeHintLabel.Text = "Spline: adding control points"
		setStatus("Add Point mode: click the platform to insert a red spline control point.")
	else
		if not skipPluginDeactivate then
			plugin:Deactivate()
		end
		modeHintLabel.Text = "Pick a paint mode or edit the spline path."
		setStatus("Add Point mode off.")
	end
end

local function setToolTab(tab: ToolTab)
	activeToolTab = tab
	for tabName, button in toolTabButtons do
		setButtonActive(button, tabName == activeToolTab)
	end

	local scroll = mainScrollFrame
	local anchor = toolTabAnchors[tab]
	if scroll ~= nil and anchor ~= nil then
		local y = anchor.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 8))
	end

	if tab == "Paint" then
		setStatus("Paint tab selected. Pick a brush, then hover and drag on the 3D platform.")
	elseif tab == "Path" then
		setStatus("Path tab selected. Use spline controls, then rebuild the curve.")
	elseif tab == "Stage" then
		setStatus("Stage tab selected. Profiles are ready for future stage data wiring.")
	else
		setStatus("Data tab selected. Export prints the current layout to Output.")
	end
end

local function setStageProfile(profileName: string, selectedIndex: number)
	activeStageProfile = profileName
	for index, button in stageProfileButtons do
		setButtonActive(button, index == selectedIndex)
	end
	updateInspectorCell(hoverPlatform, hoverColumn, hoverRow, nil)
	setStatus(`Stage profile selected: {profileName}. Current tool still edits the connected GamePlatform.`)
end

local function cellAtWorldPosition(platform: Model, worldPosition: Vector3): (number?, number?)
	local base = platformBasePart(platform)
	if base == nil then
		return nil, nil
	end

	local localPosition = base.CFrame:PointToObjectSpace(worldPosition)
	local size = cellSize(platform)
	local minX, maxX, minZ, maxZ = gridLocalBounds(platform)
	local column = math.floor((localPosition.X - minX) / size) + 1
	local row = math.floor((localPosition.Z - minZ) / size) + 1

	if
		localPosition.X < minX
		or localPosition.X > maxX
		or localPosition.Z < minZ
		or localPosition.Z > maxZ
		or column < 1
		or column > columns(platform)
		or row < 1
		or row > rows(platform)
	then
		return nil, nil
	end

	return column, row
end

local function mousePlatformHit(surfaceOffset: number, quiet: boolean?): PlatformRayHit?
	local platform = platformModel()
	if platform == nil then
		if quiet ~= true then
			setStatus("GamePlatform is missing. Connect Rojo first.")
		end
		return nil
	end

	local base = platformBasePart(platform)
	if base == nil then
		if quiet ~= true then
			setStatus("PlatformBase is missing.")
		end
		return nil
	end

	local ray = mouse.UnitRay
	local localOrigin = base.CFrame:PointToObjectSpace(ray.Origin)
	local localDirection = base.CFrame:VectorToObjectSpace(ray.Direction)
	if math.abs(localDirection.Y) < 0.0001 then
		if quiet ~= true then
			setStatus("Move the camera so the mouse ray crosses the platform.")
		end
		return nil
	end

	local topY = base.Size.Y / 2
	local distance = (topY - localOrigin.Y) / localDirection.Y
	if distance < 0 then
		if quiet ~= true then
			setStatus("Mouse is not aimed at the platform plane.")
		end
		return nil
	end

	local localPosition = localOrigin + localDirection * distance
	local minX, maxX, minZ, maxZ = gridLocalBounds(platform)
	if
		localPosition.X < minX
		or localPosition.X > maxX
		or localPosition.Z < minZ
		or localPosition.Z > maxZ
	then
		if quiet ~= true then
			setStatus("Aim inside the calibrated grid footprint.")
		end
		return nil
	end

	local projected = Vector3.new(localPosition.X, topY + surfaceOffset, localPosition.Z)
	return {
		platform = platform,
		base = base,
		localPosition = projected,
		worldPosition = base.CFrame:PointToWorldSpace(projected),
	}
end

local function setCellCode(platform: Model, column: number, row: number, code: CellCode)
	local rowValue = rowString(platform, row)
	if rowValue == nil then
		return
	end

	local old = rowValue.Value
	rowValue.Value = string.sub(old, 1, column - 1) .. code .. string.sub(old, column + 1)
	updateCellVisual(platform, column, row)
end

local function nextCodeForPaintMode(platform: Model, column: number, row: number, mode: PaintMode): CellCode
	if mode == "Legal" then
		return "."
	elseif mode == "Illegal" then
		return "#"
	elseif mode == "Portal" then
		return "P"
	elseif mode == "Goal" then
		return "G"
	elseif mode == "AutoPlace" then
		return "A"
	end
	return if isCellBuildable(platform, column, row) then "#" else "."
end

local function mouseGridCell(quiet: boolean?): (Model?, number?, number?, Vector3?)
	local hit = mousePlatformHit(0, quiet)
	if hit == nil then
		return nil, nil, nil, nil
	end

	local column, row = cellAtWorldPosition(hit.platform, hit.worldPosition)
	if column == nil or row == nil then
		if quiet ~= true then
			setStatus("Aim inside a calibrated grid square.")
		end
		return nil, nil, nil, nil
	end

	return hit.platform, column, row, hit.worldPosition
end

local function updateHoverPreview()
	if activeMode == nil and not splineAddActive then
		clearHoverPreview()
		return
	end

	local platform, column, row, worldPosition = mouseGridCell(true)
	if platform == nil or column == nil or row == nil then
		clearHoverPreview()
		return
	end

	local targetFrame = cellFrame(platform, column, row)
	local preview = ensureHoverPreview(platform)
	if targetFrame == nil or preview == nil then
		clearHoverPreview()
		return
	end

	local previewColor = if activeMode ~= nil
		then colorForCellCode(nextCodeForPaintMode(platform, column, row, activeMode))
		else CONTROL_POINT_COLOR
	preview.Position = targetFrame.Position
	preview.Size = targetFrame.Size
	preview.BackgroundColor3 = previewColor
	preview.BackgroundTransparency = if activeMode ~= nil then 0.48 else 0.58
	local stroke = preview:FindFirstChild("HoverStroke")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = previewColor
	end
	preview.Visible = true
	hoverPlatform = platform
	hoverColumn = column
	hoverRow = row
	updateInspectorCell(platform, column, row, worldPosition)
	local canvasCell = canvasPreviewCells[gridCellKey(column, row)]
	if canvasCell ~= nil and canvasHoverFrame ~= nil then
		canvasHoverFrame.Position = canvasCell.Position
		canvasHoverFrame.Size = canvasCell.Size
		canvasHoverFrame.BackgroundColor3 = previewColor
		canvasHoverFrame.Visible = true
	end

	local nextHoverCellKey = gridCellKey(column, row)
	if nextHoverCellKey ~= hoverCellKey then
		hoverCellKey = nextHoverCellKey
		if activeMode ~= nil then
			local currentCode = cellCode(platform, column, row)
			local nextCode = nextCodeForPaintMode(platform, column, row, activeMode)
			setStatus(
				`Hover cell {column}, {row}: {currentCode} -> {nextCode}. Hold click and drag to paint.`,
				true
			)
		else
			setStatus(`Hover cell {column}, {row}: click to add a spline point.`, true)
		end
	end
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
	local minX, maxX, minZ, maxZ = gridLocalBounds(platform)
	if
		localPosition.X < minX
		or localPosition.X > maxX
		or localPosition.Z < minZ
		or localPosition.Z > maxZ
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
	local minX, _, minZ = gridLocalBounds(platform)
	for row = 1, rows(platform) do
		local rowValue = rowString(platform, row)
		if rowValue == nil then
			continue
		end

		local nextValue = ""
		for column = 1, columns(platform) do
			local previousCode = cellCode(platform, column, row)
			local localX = minX + (column - 0.5) * size
			local localZ = minZ + (row - 0.5) * size
			local cellPosition = base.CFrame:PointToWorldSpace(Vector3.new(localX, base.Size.Y / 2, localZ))
			local blocked = false

			for _, pathPosition in sampledPath do
				if distanceXZ(cellPosition, pathPosition) <= PATH_GRID_RADIUS then
					blocked = true
					break
				end
			end

			if previousCode == "P" or previousCode == "G" then
				nextValue ..= previousCode
			elseif blocked then
				nextValue ..= "#"
			elseif previousCode == "A" then
				nextValue ..= "A"
			else
				nextValue ..= "."
			end
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

local function paintCell(
	platform: Model,
	column: number,
	row: number,
	mode: PaintMode,
	skipViewportHoverUpdate: boolean?
)
	local paintedKey = gridCellKey(column, row)
	if dragPaintedCells[paintedKey] == true then
		return false
	end
	dragPaintedCells[paintedKey] = true

	local nextCode = nextCodeForPaintMode(platform, column, row, mode)
	setCellCode(platform, column, row, nextCode)

	setStatus(`Painted cell {column}, {row} as {nextCode}.`)
	if skipViewportHoverUpdate ~= true then
		updateHoverPreview()
	end
	return true
end

local function paintHoveredCell(mode: PaintMode)
	updateHoverPreview()
	local platform = hoverPlatform
	local column = hoverColumn
	local row = hoverRow
	if platform == nil or column == nil or row == nil then
		setStatus("Hover a visible grid square before painting.")
		return false
	end

	return paintCell(platform, column, row, mode)
end

local function showCanvasHover(platform: Model, column: number, row: number)
	local canvasCell = canvasPreviewCells[gridCellKey(column, row)]
	if canvasCell == nil then
		return
	end

	local previewColor = if activeMode ~= nil
		then colorForCellCode(nextCodeForPaintMode(platform, column, row, activeMode))
		else colorForCellCode(cellCode(platform, column, row))

	if canvasHoverFrame ~= nil then
		canvasHoverFrame.Position = canvasCell.Position
		canvasHoverFrame.Size = canvasCell.Size
		canvasHoverFrame.BackgroundColor3 = previewColor
		canvasHoverFrame.Visible = true
	end

	hoverPlatform = platform
	hoverColumn = column
	hoverRow = row
	hoverCellKey = gridCellKey(column, row)
	updateInspectorCell(platform, column, row, nil)
	setStatus(`Canvas cell {column}, {row}: {labelForCellCode(cellCode(platform, column, row))}.`, true)
end

local function canvasPlatform(): Model?
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		return nil
	end
	return platform
end

local function beginCanvasPaint(column: number, row: number)
	local platform = canvasPlatform()
	if platform == nil then
		return
	end
	showCanvasHover(platform, column, row)

	if activeMode == nil then
		setStatus("Pick a brush before painting on the canvas.")
		return
	end

	local recording = beginRecording(`Paint canvas cells {activeMode}`)
	if recording == nil then
		return
	end
	dragPainting = true
	dragPaintRecording = recording
	dragPaintedCells = {}
	paintCell(platform, column, row, activeMode, true)
	showCanvasHover(platform, column, row)
end

local function dragCanvasPaint(column: number, row: number)
	local platform = canvasPlatform()
	if platform == nil then
		return
	end
	showCanvasHover(platform, column, row)

	if not dragPainting or activeMode == nil then
		return
	end
	paintCell(platform, column, row, activeMode, true)
	showCanvasHover(platform, column, row)
end

handleCanvasCellHover = function(column: number, row: number)
	local platform = canvasPlatform()
	if platform ~= nil then
		showCanvasHover(platform, column, row)
	end
end

handleCanvasCellPaintStart = beginCanvasPaint
handleCanvasCellPaintDrag = dragCanvasPaint
handleCanvasPaintEnd = finishPaintDrag

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

local function calibrateGridTemplate()
	local platform = platformModel()
	if platform == nil then
		setStatus("GamePlatform is missing. Connect Rojo first.")
		updateTargetInfo(nil)
		return
	end

	setMode(nil)
	setSplineAddMode(false, true)
	local recording = beginRecording("Calibrate grid template")
	if recording == nil then
		return
	end

	local ok = syncGridTemplate(platform)
	if ok then
		preparePlatformOrigin(platform)
		Selection:Set({ platform })
		applyPlatformVisual()
		setStatus(
			`Calibrated grid to {columns(platform)} x {rows(platform)} cells at {cellSize(platform)} studs.`
		)
	end

	finishRecording(recording)
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
		"-- . = buildable, # = blocked/path, P = portal spawn, G = goal, A = auto-place slot",
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

toolTabButtons.Paint.MouseButton1Click:Connect(function()
	setToolTab("Paint")
end)
toolTabButtons.Path.MouseButton1Click:Connect(function()
	setToolTab("Path")
end)
toolTabButtons.Stage.MouseButton1Click:Connect(function()
	setToolTab("Stage")
end)
toolTabButtons.Data.MouseButton1Click:Connect(function()
	setToolTab("Data")
end)

stageProfileButtons[1].MouseButton1Click:Connect(function()
	setStageProfile("First Private Island", 1)
end)
stageProfileButtons[2].MouseButton1Click:Connect(function()
	setStageProfile("Forest Bend", 2)
end)
stageProfileButtons[3].MouseButton1Click:Connect(function()
	setStageProfile("Secluded Test Pad", 3)
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
modeButtons.Portal.MouseButton1Click:Connect(function()
	setMode(if activeMode == "Portal" then nil else "Portal")
end)
modeButtons.Goal.MouseButton1Click:Connect(function()
	setMode(if activeMode == "Goal" then nil else "Goal")
end)
modeButtons.AutoPlace.MouseButton1Click:Connect(function()
	setMode(if activeMode == "AutoPlace" then nil else "AutoPlace")
end)

widgetButtons.selectButton.MouseButton1Click:Connect(selectPlatform)
widgetButtons.originButton.MouseButton1Click:Connect(fixOrigin)
widgetButtons.resetButton.MouseButton1Click:Connect(resetFlat)
widgetButtons.snapButton.MouseButton1Click:Connect(snapToSelection)
widgetButtons.calibrateButton.MouseButton1Click:Connect(calibrateGridTemplate)
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
	updateHoverPreview()

	if splineAddActive then
		local _, _, _, worldPosition = mouseGridCell(false)
		if worldPosition ~= nil then
			addSplinePointAt(worldPosition)
		end
		return
	end

	if activeMode == nil then
		return
	end

	local recording = beginRecording(`Paint grid cells {activeMode}`)
	if recording == nil then
		return
	end
	dragPainting = true
	dragPaintRecording = recording
	dragPaintedCells = {}
	if not paintHoveredCell(activeMode) then
		finishPaintDrag()
	end
end)

mouse.Move:Connect(function()
	updateHoverPreview()
	if dragPainting and activeMode ~= nil then
		local platform = hoverPlatform
		local column = hoverColumn
		local row = hoverRow
		if platform ~= nil and column ~= nil and row ~= nil then
			paintCell(platform, column, row, activeMode)
		end
	end
end)

mouse.Button1Up:Connect(function()
	finishPaintDrag()
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		finishPaintDrag()
	end
end)

plugin.Deactivation:Connect(function()
	finishPaintDrag()
	clearHoverPreview()
	setMode(nil, true)
	setSplineAddMode(false, true)
end)

applyPlatformVisual()
print("Grid Platform Editor plugin loaded.")

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
local PLUGIN_NAME = "Stagewright"
local PLUGIN_SUBTITLE = "Tower defense stage workbench"
local PLUGIN_TOOLBAR_NAME = "Stagewright"
local PLUGIN_BUTTON_ID = "StagewrightEditor"
local PLUGIN_WIDGET_ID = "StagewrightPanel"
local PLUGIN_ICON = "rbxasset://textures/StudioSharedUI/grid@2x.png"

local LEGAL_COLOR = Color3.fromRGB(74, 145, 98)
local ILLEGAL_COLOR = Color3.fromRGB(156, 74, 74)
local PATH_COLOR = Color3.fromRGB(178, 151, 58)
local PORTAL_COLOR = Color3.fromRGB(111, 99, 166)
local GOAL_COLOR = Color3.fromRGB(184, 116, 70)
local AUTOPLACE_COLOR = Color3.fromRGB(74, 137, 155)
local CONTROL_POINT_COLOR = Color3.fromRGB(255, 46, 31)
local HOVER_COLOR = Color3.fromRGB(255, 255, 255)
local PANEL_BG = Color3.fromRGB(17, 18, 20)
local PANEL_HEADER = Color3.fromRGB(23, 24, 27)
local PANEL_SECTION = Color3.fromRGB(13, 14, 16)
local PANEL_STATUS = Color3.fromRGB(12, 13, 15)
local PANEL_FIELD = Color3.fromRGB(10, 12, 14)
local BUTTON_BG = Color3.fromRGB(15, 16, 18)
local BUTTON_ACTIVE = Color3.fromRGB(86, 128, 184)
local BUTTON_HOVER = Color3.fromRGB(30, 33, 38)
local BORDER = Color3.fromRGB(50, 54, 60)
local BORDER_SOFT = Color3.fromRGB(36, 40, 46)
local GRID_MINOR = Color3.fromRGB(28, 31, 36)
local GRID_MAJOR = Color3.fromRGB(58, 63, 68)
local TEXT = Color3.fromRGB(229, 232, 237)
local TEXT_ACTIVE = Color3.fromRGB(245, 247, 250)
local MUTED = Color3.fromRGB(151, 158, 169)
local SUBTLE = Color3.fromRGB(99, 106, 118)
local AMBER = Color3.fromRGB(193, 155, 62)
local CYAN = AUTOPLACE_COLOR
local VIOLET = PORTAL_COLOR

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

type StageProfileDefinition = {
	id: string,
	title: string,
	detail: string,
}

local DEFAULT_STAGE_PROFILES: { StageProfileDefinition } = {
	{
		id = "Template",
		title = "Template",
		detail = "empty",
	},
	{
		id = "Stage1",
		title = "Stage 1",
		detail = "unassigned",
	},
	{
		id = "Stage2",
		title = "Stage 2",
		detail = "unassigned",
	},
}

local toolbar = plugin:CreateToolbar(PLUGIN_TOOLBAR_NAME)
local openButton = toolbar:CreateButton(PLUGIN_BUTTON_ID, `Open {PLUGIN_NAME}`, PLUGIN_ICON, PLUGIN_NAME)
openButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, false, 410, 790, 360, 560)
local widget = plugin:CreateDockWidgetPluginGuiAsync(PLUGIN_WIDGET_ID, widgetInfo)
widget.Title = PLUGIN_NAME

local activeMode: PaintMode? = "Legal"
local mouse = plugin:GetMouse()
local statusLabel: TextLabel
local modeHintLabel: TextLabel
local modeHintPill: Frame
local targetInfoLabel: TextLabel
local inspectorStageLabel: TextLabel
local inspectorCellLabel: TextLabel
local inspectorTypeLabel: TextLabel
local inspectorWorldLabel: TextLabel
local inspectorBrushLabel: TextLabel
local inspectorGridLabel: TextLabel
local modeButtons: { [PaintMode]: TextButton } = {} :: any
local toolTabButtons: { [ToolTab]: TextButton } = {} :: any
local tabSections: { [ToolTab]: { GuiObject } } = {} :: any
local stageProfileButtons: { TextButton } = {}
local mainScrollFrame: ScrollingFrame? = nil
local activeToolTab: ToolTab = "Paint"
local activeStageProfile = DEFAULT_STAGE_PROFILES[1].title
local stageTitleLabel: TextLabel? = nil
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
local canvasRouteState: any = {}
local handleCanvasCellHover: ((number, number) -> ())? = nil
local handleCanvasCellPaintStart: ((number, number) -> ())? = nil
local handleCanvasCellPaintDrag: ((number, number) -> ())? = nil
local handleCanvasPaintEnd: (() -> ())? = nil
local watchedCellMap: Folder? = nil
local cellMapConnections: { RBXScriptConnection } = {}
local cellMapRefreshQueued = false
local widgetButtons: any = nil
local buttonAccents: { [TextButton]: Color3 } = {}

local function setStatus(message: string, quiet: boolean?)
	statusLabel.Text = message
	if quiet ~= true then
		print(`{PLUGIN_NAME}: {message}`)
	end
end

local function setButtonAccent(button: TextButton, accentColor: Color3)
	buttonAccents[button] = accentColor
end

local function setButtonActive(button: TextButton, active: boolean)
	local accentColor = buttonAccents[button] or BUTTON_ACTIVE
	local materialAccent = button:FindFirstChild("MaterialAccent")
	if materialAccent ~= nil and materialAccent:IsA("Frame") then
		button.BackgroundColor3 = if active then BUTTON_HOVER else BUTTON_BG
		local stroke = button:FindFirstChild("ButtonStroke")
		if stroke ~= nil and stroke:IsA("UIStroke") then
			stroke.Color = if active then BUTTON_ACTIVE else BORDER_SOFT
			stroke.Transparency = if active then 0 else 0.2
			stroke.Thickness = if active then 2 else 1
		end
		local title = button:FindFirstChild("Title")
		if title ~= nil and title:IsA("TextLabel") then
			title.TextColor3 = if active then TEXT_ACTIVE else TEXT
		end
		return
	end

	button.BackgroundColor3 = if active then BUTTON_ACTIVE else BUTTON_BG
	button.TextColor3 = if active then TEXT_ACTIVE else MUTED
	local stroke = button:FindFirstChild("ButtonStroke")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = if active then accentColor else BORDER_SOFT
		stroke.Transparency = if active then 0 else 0.2
		stroke.Thickness = if active then 1.5 else 1
	end
	local marker = button:FindFirstChild("ActiveMarker")
	if marker ~= nil and marker:IsA("Frame") then
		marker.BackgroundColor3 = accentColor
		marker.Visible = active
	end
end

local function applyTabContent(tab: ToolTab)
	for _, sections in tabSections do
		for _, section in sections do
			section.Visible = false
		end
	end

	for _, section in tabSections[tab] or {} do
		section.Visible = true
	end

	local scroll = mainScrollFrame
	if scroll ~= nil then
		scroll.CanvasPosition = Vector2.new(0, 0)
	end
end

do
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
		label.TextSize = 14
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
		button.AutoButtonColor = false
		button.BackgroundColor3 = BUTTON_BG
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamMedium
		button.Text = text
		button.TextColor3 = TEXT
		button.TextSize = 14
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.TextWrapped = false
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

		local marker = Instance.new("Frame")
		marker.Name = "ActiveMarker"
		marker.AnchorPoint = Vector2.new(0, 1)
		marker.BackgroundColor3 = BUTTON_ACTIVE
		marker.BorderSizePixel = 0
		marker.Position = UDim2.new(0, 8, 1, -4)
		marker.Size = UDim2.new(1, -16, 0, 2)
		marker.Visible = false
		marker.ZIndex = button.ZIndex + 1
		marker.Parent = button

		local markerCorner = Instance.new("UICorner")
		markerCorner.CornerRadius = UDim.new(1, 0)
		markerCorner.Parent = marker

		button.MouseEnter:Connect(function()
			local activeMarker = button:FindFirstChild("ActiveMarker")
			local active = activeMarker ~= nil and activeMarker:IsA("Frame") and activeMarker.Visible
			if not active then
				button.BackgroundColor3 = BUTTON_HOVER
			end
		end)
		button.MouseLeave:Connect(function()
			local activeMarker = button:FindFirstChild("ActiveMarker")
			local active = activeMarker ~= nil and activeMarker:IsA("Frame") and activeMarker.Visible
			if not active then
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
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = section

		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER
		stroke.Transparency = 0.48
		stroke.Thickness = 1
		stroke.Parent = section

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

		local titleLabel = createLabel(section, `{name}Title`, title, 16, TEXT)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 14
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		if subtitle ~= nil and subtitle ~= "" then
			local subtitleLabel = createLabel(section, `{name}Subtitle`, subtitle, 18, MUTED)
			subtitleLabel.TextSize = 12
			subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end

		return section
	end

	local function createButtonRow(parent: Instance, name: string, buttons: { { string } }): { TextButton }
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 36)
		row.Parent = parent

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row

		local created: { TextButton } = {}
		for _, info in buttons do
			local button = createButton(row, info[1], info[2], 36)
			button.Size = UDim2.new(1 / #buttons, -5, 1, 0)
			table.insert(created, button)
		end

		return created
	end

	local function createChip(parent: Instance, name: string, text: string, color: Color3): Frame
		local chip = Instance.new("Frame")
		chip.Name = name
		chip.BackgroundColor3 = PANEL_FIELD
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
		label.TextSize = 11
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
		label.TextSize = 12
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
		field.BackgroundColor3 = PANEL_FIELD
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
		label.TextSize = 11

		local value = createInlineLabel(field, "Value", valueText, TEXT)
		value.Font = Enum.Font.GothamBold
		value.Position = UDim2.fromOffset(9, 20)
		value.Size = UDim2.new(1, -18, 0, 18)
		value.TextSize = 14
		return value
	end

	local function createStageProfileButton(
		parent: Instance,
		name: string,
		title: string,
		detail: string
	): TextButton
		local button = createButton(parent, name, "", 44)
		button.Text = ""
		button.AutoButtonColor = true

		local titleLabel = createInlineLabel(button, "Title", title, TEXT)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.Position = UDim2.fromOffset(9, 5)
		titleLabel.Size = UDim2.new(1, -18, 0, 18)
		titleLabel.TextSize = 13
		titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local detailLabel = createInlineLabel(button, "Detail", detail, MUTED)
		detailLabel.Position = UDim2.fromOffset(9, 25)
		detailLabel.Size = UDim2.new(1, -18, 0, 14)
		detailLabel.TextSize = 11
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd

		return button
	end

	local function createCanvasPreview(parent: Instance): Frame
		local canvas = Instance.new("Frame")
		canvas.Name = "CanvasGrid"
		canvas.BackgroundColor3 = Color3.fromRGB(4, 11, 16)
		canvas.BorderSizePixel = 0
		canvas.ClipsDescendants = true
		canvas.Size = UDim2.new(1, 0, 0, 270)
		canvas.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = canvas

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(64, 82, 105)
		stroke.Transparency = 0.1
		stroke.Thickness = 1
		stroke.Parent = canvas

		local gridTexture = Instance.new("Frame")
		gridTexture.Name = "CanvasBackdrop"
		gridTexture.BackgroundColor3 = Color3.fromRGB(7, 16, 23)
		gridTexture.BackgroundTransparency = 0
		gridTexture.BorderSizePixel = 0
		gridTexture.Size = UDim2.fromScale(1, 1)
		gridTexture.ZIndex = 0
		gridTexture.Parent = canvas

		local backdropGradient = Instance.new("UIGradient")
		backdropGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 13, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 22, 30)),
		})
		backdropGradient.Rotation = 90
		backdropGradient.Parent = gridTexture

		local routeLayer = Instance.new("Frame")
		routeLayer.Name = "CanvasRouteLayer"
		routeLayer.Active = false
		routeLayer.BackgroundTransparency = 1
		routeLayer.BorderSizePixel = 0
		routeLayer.Size = UDim2.fromScale(1, 1)
		routeLayer.ZIndex = 6
		routeLayer.Parent = canvas
		canvasRouteState.layer = routeLayer

		canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if canvasRouteState.refresh ~= nil then
				canvasRouteState.refresh()
			end
		end)

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
		row.BackgroundColor3 = PANEL_FIELD
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
		visibleBox.BackgroundColor3 = Color3.fromRGB(25, 36, 50)
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

	local function createBrandMark(parent: Instance)
		local mark = Instance.new("Frame")
		mark.Name = "StagewrightMark"
		mark.BackgroundColor3 = Color3.fromRGB(5, 12, 19)
		mark.BorderSizePixel = 0
		mark.Position = UDim2.fromOffset(10, 10)
		mark.Size = UDim2.fromOffset(36, 36)
		mark.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = mark

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(74, 91, 112)
		stroke.Transparency = 0.2
		stroke.Thickness = 1
		stroke.Parent = mark

		local cells = {
			LEGAL_COLOR,
			LEGAL_COLOR,
			ILLEGAL_COLOR,
			LEGAL_COLOR,
			PATH_COLOR,
			PATH_COLOR,
			PORTAL_COLOR,
			LEGAL_COLOR,
			GOAL_COLOR,
		}
		for index, color in cells do
			local cell = Instance.new("Frame")
			cell.Name = `Cell{index}`
			cell.BackgroundColor3 = color
			cell.BackgroundTransparency = if color == LEGAL_COLOR then 0.25 else 0
			cell.BorderSizePixel = 0
			cell.Position = UDim2.fromOffset(7 + ((index - 1) % 3) * 8, 7 + math.floor((index - 1) / 3) * 8)
			cell.Size = UDim2.fromOffset(6, 6)
			cell.Parent = mark

			local cellCorner = Instance.new("UICorner")
			cellCorner.CornerRadius = UDim.new(0, 2)
			cellCorner.Parent = cell
		end
	end

	local function createHeaderPanel(parent: Instance)
		local header = Instance.new("Frame")
		header.Name = "ToolHeader"
		header.BackgroundColor3 = PANEL_HEADER
		header.BorderSizePixel = 0
		header.Size = UDim2.new(1, 0, 0, 64)
		header.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = header

		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER
		stroke.Transparency = 0.35
		stroke.Thickness = 1
		stroke.Parent = header

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 27, 38)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 17, 25)),
		})
		gradient.Rotation = 90
		gradient.Parent = header

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BackgroundColor3 = BUTTON_ACTIVE
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(0, 0)
		accent.Size = UDim2.new(1, 0, 0, 2)
		accent.Parent = header

		createBrandMark(header)

		local title = createLabel(header, "Title", PLUGIN_NAME, 20, TEXT)
		title.Font = Enum.Font.GothamBold
		title.Position = UDim2.fromOffset(54, 8)
		title.Size = UDim2.new(1, -162, 0, 20)
		title.TextSize = 16
		title.TextYAlignment = Enum.TextYAlignment.Center

		local subtitle = createLabel(header, "Subtitle", PLUGIN_SUBTITLE, 14, MUTED)
		subtitle.Position = UDim2.fromOffset(54, 27)
		subtitle.Size = UDim2.new(1, -66, 0, 14)
		subtitle.TextSize = 10
		subtitle.TextYAlignment = Enum.TextYAlignment.Center

		targetInfoLabel = createLabel(header, "TargetInfo", "Target: not connected", 15, SUBTLE)
		targetInfoLabel.Position = UDim2.fromOffset(54, 43)
		targetInfoLabel.Size = UDim2.new(1, -66, 0, 15)
		targetInfoLabel.TextSize = 10
		targetInfoLabel.TextYAlignment = Enum.TextYAlignment.Center

		local localPill = Instance.new("Frame")
		localPill.Name = "LocalPill"
		localPill.BackgroundColor3 = Color3.fromRGB(255, 207, 33)
		localPill.BorderSizePixel = 0
		localPill.Position = UDim2.new(1, -82, 0, 11)
		localPill.Size = UDim2.fromOffset(70, 22)
		localPill.Parent = header
		modeHintPill = localPill

		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(1, 0)
		pillCorner.Parent = localPill

		modeHintLabel = createLabel(localPill, "ModeHint", "Legal", 22, TEXT_ACTIVE)
		modeHintLabel.Font = Enum.Font.GothamBold
		modeHintLabel.Size = UDim2.fromScale(1, 1)
		modeHintLabel.TextSize = 10
		modeHintLabel.TextTruncate = Enum.TextTruncate.AtEnd
		modeHintLabel.TextWrapped = false
		modeHintLabel.TextXAlignment = Enum.TextXAlignment.Center
		modeHintLabel.TextYAlignment = Enum.TextYAlignment.Center
	end

	local function createStatusDock(parent: Instance)
		local dock = Instance.new("Frame")
		dock.Name = "StatusDock"
		dock.BackgroundColor3 = PANEL_STATUS
		dock.BorderSizePixel = 0
		dock.Position = UDim2.new(0, 0, 1, -42)
		dock.Size = UDim2.new(1, 0, 0, 42)
		dock.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = dock

		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER
		stroke.Transparency = 0.45
		stroke.Thickness = 1
		stroke.Parent = dock

		local statusDot = Instance.new("Frame")
		statusDot.Name = "StatusDot"
		statusDot.BackgroundColor3 = BUTTON_ACTIVE
		statusDot.BorderSizePixel = 0
		statusDot.Position = UDim2.fromOffset(10, 8)
		statusDot.Size = UDim2.fromOffset(8, 8)
		statusDot.Parent = dock

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = statusDot

		local label = createLabel(dock, "StatusTitle", "STATUS", 10, SUBTLE)
		label.Font = Enum.Font.GothamBold
		label.Position = UDim2.fromOffset(24, 6)
		label.Size = UDim2.new(1, -34, 0, 10)
		label.TextSize = 10

		statusLabel =
			createLabel(dock, "StatusText", "Ready. Paint on the canvas or switch brushes above.", 18, MUTED)
		statusLabel.Position = UDim2.fromOffset(10, 19)
		statusLabel.Size = UDim2.new(1, -20, 0, 18)
		statusLabel.TextSize = 11
	end

	local function createWorkbenchPanel(parent: Instance, name: string, height: number): Frame
		local panel = Instance.new("Frame")
		panel.Name = name
		panel.BackgroundColor3 = PANEL_SECTION
		panel.BorderSizePixel = 0
		panel.Size = UDim2.new(1, 0, 0, height)
		panel.Parent = parent

		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER_SOFT
		stroke.Transparency = 0.08
		stroke.Thickness = 1
		stroke.Parent = panel

		return panel
	end

	local function createPanelCaption(parent: Instance, text: string, x: number, y: number): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Code
		label.Text = text
		label.TextColor3 = SUBTLE
		label.TextSize = 11
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Position = UDim2.fromOffset(x, y)
		label.Size = UDim2.new(1, -x * 2, 0, 14)
		label.Parent = parent
		return label
	end

	local function createMaterialButton(
		parent: Instance,
		name: string,
		title: string,
		keyText: string,
		color: Color3,
		detailText: string?
	): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.BackgroundColor3 = BUTTON_BG
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamMedium
		button.Text = ""
		button.Size = UDim2.fromOffset(100, 40)
		button.Parent = parent
		setButtonAccent(button, color)

		local stroke = Instance.new("UIStroke")
		stroke.Name = "ButtonStroke"
		stroke.Color = BORDER_SOFT
		stroke.Transparency = 0.2
		stroke.Thickness = 1
		stroke.Parent = button

		local accent = Instance.new("Frame")
		accent.Name = "MaterialAccent"
		accent.BackgroundColor3 = color
		accent.BorderSizePixel = 0
		accent.Size = UDim2.new(0, 4, 1, 0)
		accent.Parent = button

		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.BackgroundColor3 = PANEL_FIELD
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromOffset(10, 8)
		swatch.Size = UDim2.fromOffset(20, 20)
		swatch.Parent = button

		local swatchStroke = Instance.new("UIStroke")
		swatchStroke.Color = GRID_MINOR
		swatchStroke.Transparency = 0.1
		swatchStroke.Thickness = 1
		swatchStroke.Parent = swatch

		for row = 0, 1 do
			for column = 0, 1 do
				local dot = Instance.new("Frame")
				dot.Name = `Dot{row}{column}`
				dot.BackgroundColor3 = if title == "Block" and column == 0
					then Color3.fromRGB(18, 30, 27)
					else color
				dot.BorderSizePixel = 0
				dot.Position = UDim2.fromOffset(4 + column * 7, 4 + row * 7)
				dot.Size = UDim2.fromOffset(5, 5)
				dot.Parent = swatch
			end
		end

		local titleLabel = createInlineLabel(button, "Title", title, TEXT)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.Position = UDim2.fromOffset(38, 6)
		titleLabel.Size = UDim2.new(1, -64, 0, 15)
		titleLabel.TextSize = 12

		local detailLabel = createInlineLabel(button, "Detail", detailText or "cell", SUBTLE)
		detailLabel.Font = Enum.Font.Code
		detailLabel.Position = UDim2.fromOffset(38, 22)
		detailLabel.Size = UDim2.new(1, -64, 0, 12)
		detailLabel.TextSize = 11

		local keyBadge = Instance.new("Frame")
		keyBadge.Name = "Key"
		keyBadge.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
		keyBadge.BorderSizePixel = 0
		keyBadge.Position = UDim2.new(1, -24, 0, 8)
		keyBadge.Size = UDim2.fromOffset(16, 16)
		keyBadge.Parent = button

		local keyStroke = Instance.new("UIStroke")
		keyStroke.Color = GRID_MINOR
		keyStroke.Transparency = 0.2
		keyStroke.Thickness = 1
		keyStroke.Parent = keyBadge

		local keyLabel = createInlineLabel(keyBadge, "Label", keyText, SUBTLE)
		keyLabel.Font = Enum.Font.Code
		keyLabel.Size = UDim2.fromScale(1, 1)
		keyLabel.TextSize = 11
		keyLabel.TextXAlignment = Enum.TextXAlignment.Center

		button.MouseEnter:Connect(function()
			local active = stroke.Color == BUTTON_ACTIVE and stroke.Thickness > 1
			if not active then
				button.BackgroundColor3 = BUTTON_HOVER
			end
		end)
		button.MouseLeave:Connect(function()
			local active = stroke.Color == BUTTON_ACTIVE and stroke.Thickness > 1
			if not active then
				button.BackgroundColor3 = BUTTON_BG
			end
		end)

		return button
	end

	local function createMaterialPicker(parent: Instance): TextButton
		local panel = createWorkbenchPanel(parent, "MaterialPicker", 148)
		createPanelCaption(panel, "materials", 12, 10)

		local keyHint = createInlineLabel(panel, "KeyHint", "keys 1-6", SUBTLE)
		keyHint.Font = Enum.Font.Code
		keyHint.Position = UDim2.new(1, -94, 0, 10)
		keyHint.Size = UDim2.fromOffset(82, 14)
		keyHint.TextSize = 11
		keyHint.TextXAlignment = Enum.TextXAlignment.Right

		local grid = Instance.new("Frame")
		grid.Name = "MaterialGrid"
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(12, 36)
		grid.Size = UDim2.new(1, -24, 0, 102)
		grid.Parent = panel

		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(8, 10)
		layout.CellSize = UDim2.new(0.333, -6, 0, 45)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid

		modeButtons.Legal = createMaterialButton(grid, "BuildMaterial", "Build", "1", LEGAL_COLOR)
		modeButtons.Illegal = createMaterialButton(grid, "BlockMaterial", "Block", "2", ILLEGAL_COLOR)
		local pathButton = createMaterialButton(grid, "PathMaterial", "Route", "3", PATH_COLOR, "edit")
		modeButtons.Portal = createMaterialButton(grid, "PortalMaterial", "Portal", "4", PORTAL_COLOR)
		modeButtons.Goal = createMaterialButton(grid, "GoalMaterial", "Goal", "5", GOAL_COLOR)
		modeButtons.AutoPlace = createMaterialButton(grid, "AutoMaterial", "Auto", "6", AUTOPLACE_COLOR)
		setButtonActive(modeButtons.Legal, true)

		return pathButton
	end

	local function createStageHeader(parent: Instance): (TextButton, TextButton)
		local panel = createWorkbenchPanel(parent, "StageHeader", 68)
		local title = createInlineLabel(panel, "StageName", activeStageProfile, TEXT_ACTIVE)
		stageTitleLabel = title
		title.Font = Enum.Font.GothamBold
		title.Position = UDim2.fromOffset(12, 12)
		title.Size = UDim2.new(1, -134, 0, 20)
		title.TextSize = 15

		targetInfoLabel =
			createInlineLabel(panel, "TargetInfo", "single route / stage_01 / local unsynced", MUTED)
		targetInfoLabel.Font = Enum.Font.Code
		targetInfoLabel.Position = UDim2.fromOffset(12, 36)
		targetInfoLabel.Size = UDim2.new(1, -134, 0, 16)
		targetInfoLabel.TextSize = 11

		local saveButton = createButton(panel, "SaveStage", "Export Layout", 30)
		saveButton.Position = UDim2.new(1, -120, 0, 19)
		saveButton.Size = UDim2.fromOffset(108, 30)
		setButtonAccent(saveButton, BUTTON_ACTIVE)
		setButtonActive(saveButton, true)

		local stagesButton = createButton(panel, "StageDrawer", "", 1)
		stagesButton.Visible = false
		stagesButton.Position = UDim2.new(1, -1, 0, 0)
		stagesButton.Size = UDim2.fromOffset(1, 1)

		return saveButton, stagesButton
	end

	local function createStageSelector(parent: Instance): { TextButton }
		local panel = createWorkbenchPanel(parent, "StageSelector", 76)
		createPanelCaption(panel, "stage tabs", 12, 8)

		local row = Instance.new("Frame")
		row.Name = "StageProfileRow"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(12, 26)
		row.Size = UDim2.new(1, -24, 0, 44)
		row.Parent = panel

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row

		local buttons: { TextButton } = {}
		for _, profile in DEFAULT_STAGE_PROFILES do
			table.insert(
				buttons,
				createStageProfileButton(row, `StageProfile_{profile.id}`, profile.title, profile.detail)
			)
		end
		for _, stageButton in buttons do
			stageButton.Size = UDim2.new(1 / #buttons, -6, 1, 0)
		end

		return buttons
	end

	local function createTemplateDrawer(parent: Instance): TextButton
		local panel = createWorkbenchPanel(parent, "TemplateDrawer", 52)
		createPanelCaption(panel, "template drawer", 12, 10)

		local preview = Instance.new("Frame")
		preview.Name = "EmptyTemplatePreview"
		preview.BackgroundColor3 = PANEL_FIELD
		preview.BorderSizePixel = 0
		preview.Position = UDim2.fromOffset(12, 28)
		preview.Size = UDim2.fromOffset(46, 16)
		preview.Parent = panel

		local previewStroke = Instance.new("UIStroke")
		previewStroke.Color = BORDER_SOFT
		previewStroke.Transparency = 0.1
		previewStroke.Thickness = 1
		previewStroke.Parent = preview

		local templateTitle = createInlineLabel(panel, "TemplateName", "Blank Template", TEXT_ACTIVE)
		templateTitle.Font = Enum.Font.GothamBold
		templateTitle.Position = UDim2.fromOffset(70, 27)
		templateTitle.Size = UDim2.new(1, -154, 0, 12)
		templateTitle.TextSize = 12

		local templateDetail = createInlineLabel(panel, "TemplateDetail", "Empty map and route", MUTED)
		templateDetail.Position = UDim2.fromOffset(70, 39)
		templateDetail.Size = UDim2.new(1, -154, 0, 10)
		templateDetail.TextSize = 11

		local newButton = createButton(panel, "NewFromTemplate", "New", 24)
		newButton.Position = UDim2.new(1, -78, 0, 20)
		newButton.Size = UDim2.fromOffset(64, 24)
		return newButton
	end

	local function createSelectionChecks(parent: Instance)
		local panel = createWorkbenchPanel(parent, "SelectionChecks", 126)
		createPanelCaption(panel, "selection", 12, 10)
		createPanelCaption(panel, "checks", 206, 10)

		local function createReadout(labelText: string, valueText: string, y: number): TextLabel
			local label = createInlineLabel(panel, `{labelText}Label`, labelText, MUTED)
			label.Font = Enum.Font.Code
			label.Position = UDim2.fromOffset(12, y)
			label.Size = UDim2.new(0.5, -28, 0, 14)
			label.TextSize = 11

			local value = createInlineLabel(panel, `{labelText}Value`, valueText, TEXT_ACTIVE)
			value.Font = Enum.Font.Code
			value.Position = UDim2.new(0.5, -92, 0, y)
			value.Size = UDim2.fromOffset(78, 14)
			value.TextSize = 11
			value.TextXAlignment = Enum.TextXAlignment.Right
			return value
		end

		inspectorCellLabel = createReadout("cell", "-", 36)
		inspectorBrushLabel = createReadout("material", "Build", 63)
		inspectorWorldLabel = createReadout("world", "-", 90)
		inspectorStageLabel = createInlineLabel(panel, "StageValue", activeStageProfile, TEXT)
		inspectorStageLabel.Visible = false
		inspectorTypeLabel = createInlineLabel(panel, "TypeValue", "-", TEXT)
		inspectorTypeLabel.Visible = false
		inspectorGridLabel = createInlineLabel(panel, "GridValue", "32 x 27", TEXT)
		inspectorGridLabel.Visible = false

		local checks = {
			{ "Grid calibrated", "ok", LEGAL_COLOR },
			{ "Path reaches goal", "ok", LEGAL_COLOR },
			{ "Auto near path", "warn", AMBER },
		}
		for index, check in checks do
			local y = 36 + (index - 1) * 27
			local dot = Instance.new("Frame")
			dot.Name = `CheckDot{index}`
			dot.BackgroundColor3 = check[3] :: Color3
			dot.BorderSizePixel = 0
			dot.Position = UDim2.new(0.5, 10, 0, y + 4)
			dot.Size = UDim2.fromOffset(8, 8)
			dot.Parent = panel

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			local checkLabel = createInlineLabel(panel, `CheckLabel{index}`, check[1] :: string, MUTED)
			checkLabel.Position = UDim2.new(0.5, 28, 0, y)
			checkLabel.Size = UDim2.new(0.5, -74, 0, 14)
			checkLabel.TextSize = 10

			local checkState =
				createInlineLabel(panel, `CheckState{index}`, check[2] :: string, check[3] :: Color3)
			checkState.Font = Enum.Font.GothamBold
			checkState.Position = UDim2.new(1, -50, 0, y)
			checkState.Size = UDim2.fromOffset(36, 14)
			checkState.TextSize = 10
			checkState.TextXAlignment = Enum.TextXAlignment.Right
		end
	end

	local function buildWidget()
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundColor3 = PANEL_BG
		root.BorderSizePixel = 0
		root.Size = UDim2.fromScale(1, 1)
		root.Parent = widget

		local rootGradient = Instance.new("UIGradient")
		rootGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 15, 23)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 8, 13)),
		})
		rootGradient.Rotation = 90
		rootGradient.Parent = root

		local rootPadding = Instance.new("UIPadding")
		rootPadding.PaddingTop = UDim.new(0, 10)
		rootPadding.PaddingBottom = UDim.new(0, 10)
		rootPadding.PaddingLeft = UDim.new(0, 10)
		rootPadding.PaddingRight = UDim.new(0, 10)
		rootPadding.Parent = root

		do
			local topBar = Instance.new("Frame")
			topBar.Name = "TopBar"
			topBar.BackgroundColor3 = PANEL_HEADER
			topBar.BorderSizePixel = 0
			topBar.Size = UDim2.new(1, 0, 0, 38)
			topBar.Parent = root

			local title = createInlineLabel(topBar, "Title", PLUGIN_NAME, TEXT_ACTIVE)
			title.Font = Enum.Font.GothamBold
			title.Position = UDim2.fromOffset(2, 8)
			title.Size = UDim2.new(1, -112, 0, 18)
			title.TextSize = 16

			local dockLabel = createInlineLabel(topBar, "DockLabel", "Studio dock", SUBTLE)
			dockLabel.Position = UDim2.new(1, -94, 0, 9)
			dockLabel.Size = UDim2.fromOffset(76, 16)
			dockLabel.TextSize = 10
			dockLabel.TextXAlignment = Enum.TextXAlignment.Right

			modeHintPill = Instance.new("Frame")
			modeHintPill.Name = "ActiveMaterial"
			modeHintPill.BackgroundColor3 = LEGAL_COLOR
			modeHintPill.BorderSizePixel = 0
			modeHintPill.Position = UDim2.new(1, -12, 0, 10)
			modeHintPill.Size = UDim2.fromOffset(4, 18)
			modeHintPill.Parent = topBar

			modeHintLabel = createInlineLabel(topBar, "ModeHint", "Build", TEXT_ACTIVE)
			modeHintLabel.Visible = false

			local statusDock = Instance.new("Frame")
			statusDock.Name = "StatusDock"
			statusDock.BackgroundColor3 = PANEL_STATUS
			statusDock.BorderSizePixel = 0
			statusDock.Position = UDim2.new(0, 0, 1, -32)
			statusDock.Size = UDim2.new(1, 0, 0, 32)
			statusDock.Parent = root

			local statusStroke = Instance.new("UIStroke")
			statusStroke.Color = BORDER_SOFT
			statusStroke.Transparency = 0.08
			statusStroke.Thickness = 1
			statusStroke.Parent = statusDock

			statusLabel = createInlineLabel(
				statusDock,
				"StatusText",
				"Ready. Paint cells, edit paths, or export the layout.",
				MUTED
			)
			statusLabel.Font = Enum.Font.Code
			statusLabel.Position = UDim2.fromOffset(8, 7)
			statusLabel.Size = UDim2.new(1, -122, 0, 17)
			statusLabel.TextSize = 11

			local saveHint = createInlineLabel(statusDock, "SaveHint", "Undo sync on", TEXT_ACTIVE)
			saveHint.Font = Enum.Font.GothamBold
			saveHint.Position = UDim2.new(1, -108, 0, 7)
			saveHint.Size = UDim2.fromOffset(100, 17)
			saveHint.TextSize = 11
			saveHint.TextXAlignment = Enum.TextXAlignment.Right

			local saveStageButton, stageDrawerButton = createStageHeader(root)
			local stageHeader = saveStageButton.Parent
			if stageHeader ~= nil and stageHeader:IsA("Frame") then
				stageHeader.Position = UDim2.fromOffset(0, 50)
				stageHeader.Size = UDim2.new(1, 0, 0, 68)
			end

			local profileButtons = createStageSelector(root)
			local profileRow = profileButtons[1].Parent
			local stageSelector = if profileRow ~= nil then profileRow.Parent else nil
			if stageSelector ~= nil and stageSelector:IsA("Frame") then
				stageSelector.Position = UDim2.fromOffset(0, 126)
				stageSelector.Size = UDim2.new(1, 0, 0, 76)
			end

			local scroll = Instance.new("ScrollingFrame")
			scroll.Name = "Scroll"
			scroll.Active = true
			scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
			scroll.BackgroundTransparency = 1
			scroll.BorderSizePixel = 0
			scroll.CanvasSize = UDim2.new()
			scroll.Position = UDim2.fromOffset(0, 214)
			scroll.ScrollBarImageColor3 = BORDER
			scroll.ScrollBarThickness = 5
			scroll.Size = UDim2.new(1, 0, 1, -256)
			scroll.Parent = root
			mainScrollFrame = scroll

			local scrollPadding = Instance.new("UIPadding")
			scrollPadding.PaddingRight = UDim.new(0, 2)
			scrollPadding.Parent = scroll

			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 16)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = scroll

			local canvasPanel = createWorkbenchPanel(scroll, "CanvasPanel", 308)
			local canvas = createCanvasPreview(canvasPanel)
			canvas.Position = UDim2.fromOffset(10, 10)
			canvas.Size = UDim2.new(1, -20, 0, 288)

			splineAddButton = createMaterialPicker(scroll)
			local newTemplateButton = createTemplateDrawer(scroll)
			createSelectionChecks(scroll)

			local routePanel = createWorkbenchPanel(scroll, "RouteTools", 104)
			createPanelCaption(routePanel, "route tools", 12, 10)
			local routeRow = Instance.new("Frame")
			routeRow.Name = "RouteRow"
			routeRow.BackgroundTransparency = 1
			routeRow.Position = UDim2.fromOffset(12, 34)
			routeRow.Size = UDim2.new(1, -24, 0, 62)
			routeRow.Parent = routePanel

			local routeLayout = Instance.new("UIGridLayout")
			routeLayout.CellPadding = UDim2.fromOffset(7, 8)
			routeLayout.CellSize = UDim2.new(0.333, -5, 0, 27)
			routeLayout.SortOrder = Enum.SortOrder.LayoutOrder
			routeLayout.Parent = routeRow

			local selectSplineButton = createButton(routeRow, "SelectSpline", "Select", 27)
			local rebuildSplineButton = createButton(routeRow, "RebuildSpline", "Rebuild", 27)
			local deleteSplineButton = createButton(routeRow, "DeleteSplinePoint", "Delete", 27)
			local snapSplineButton = createButton(routeRow, "SnapSplinePoints", "Snap", 27)
			local clearSplineButton = createButton(routeRow, "ClearSpline", "Clear", 27)
			local exportSplineButton = createButton(routeRow, "ExportSpline", "Export", 27)

			local platformPanel = createWorkbenchPanel(scroll, "StageTools", 142)
			createPanelCaption(platformPanel, "stage tools", 12, 10)
			local stageToolGrid = Instance.new("Frame")
			stageToolGrid.Name = "StageToolGrid"
			stageToolGrid.BackgroundTransparency = 1
			stageToolGrid.Position = UDim2.fromOffset(12, 34)
			stageToolGrid.Size = UDim2.new(1, -24, 0, 100)
			stageToolGrid.Parent = platformPanel

			local stageToolLayout = Instance.new("UIGridLayout")
			stageToolLayout.CellPadding = UDim2.fromOffset(7, 8)
			stageToolLayout.CellSize = UDim2.new(0.333, -5, 0, 27)
			stageToolLayout.SortOrder = Enum.SortOrder.LayoutOrder
			stageToolLayout.Parent = stageToolGrid

			local selectButton = createButton(stageToolGrid, "Select", "Select", 27)
			local originButton = createButton(stageToolGrid, "Origin", "Origin", 27)
			local resetButton = createButton(stageToolGrid, "Reset", "Reset", 27)
			local snapButton = createButton(stageToolGrid, "Snap", "Snap", 27)
			calibrateButton = createButton(stageToolGrid, "CalibrateGrid", "Calibrate", 27)
			gridButton = createButton(stageToolGrid, "Grid", "Grid", 27)
			platformButton = createButton(stageToolGrid, "Platform", "Platform", 27)
			local exportLayoutButton = createButton(stageToolGrid, "ExportLayout", "Export", 27)

			stageProfileButtons = profileButtons
			setButtonAccent(stageDrawerButton, BUTTON_ACTIVE)
			setButtonAccent(stageProfileButtons[1], BUTTON_ACTIVE)
			setButtonAccent(stageProfileButtons[2], CYAN)
			setButtonAccent(stageProfileButtons[3], AMBER)
			setButtonActive(stageProfileButtons[1], true)
			setButtonAccent(newTemplateButton, BUTTON_ACTIVE)
			setButtonAccent(saveStageButton, BUTTON_ACTIVE)
			setButtonAccent(gridButton, CYAN)
			setButtonAccent(platformButton, LEGAL_COLOR)

			tabSections.Paint = { canvasPanel }
			tabSections.Path = { routePanel }
			tabSections.Stage = { platformPanel }
			tabSections.Data = {}

			return {
				selectButton = selectButton,
				originButton = originButton,
				resetButton = resetButton,
				snapButton = snapButton,
				calibrateButton = calibrateButton,
				selectSplineButton = selectSplineButton,
				rebuildSplineButton = rebuildSplineButton,
				addSplineButton = splineAddButton,
				deleteSplineButton = deleteSplineButton,
				snapSplineButton = snapSplineButton,
				clearSplineButton = clearSplineButton,
				exportSplineButton = exportSplineButton,
				exportButton = exportLayoutButton,
				saveStageButton = saveStageButton,
				stageDrawerButton = stageDrawerButton,
				newTemplateButton = newTemplateButton,
			}
		end

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
			commandTabFrame.Position = UDim2.fromOffset(0, 74)
			commandTabFrame.Size = UDim2.new(1, 0, 0, 32)
		end
		toolTabButtons.Paint = commandTabRow[1]
		toolTabButtons.Path = commandTabRow[2]
		toolTabButtons.Stage = commandTabRow[3]
		toolTabButtons.Data = commandTabRow[4]
		setButtonAccent(toolTabButtons.Paint, AMBER)
		setButtonAccent(toolTabButtons.Path, VIOLET)
		setButtonAccent(toolTabButtons.Stage, CYAN)
		setButtonAccent(toolTabButtons.Data, BUTTON_ACTIVE)
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
		scroll.Position = UDim2.fromOffset(0, 114)
		scroll.Size = UDim2.new(1, 0, 1, -166)
		scroll.Parent = root
		mainScrollFrame = scroll

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroll

		local stageSection = createSection(
			scroll,
			"StageProfiles",
			"Stages",
			"Pick the editing profile. Real map swapping can wire into these profiles next."
		)
		local stageRow = Instance.new("Frame")
		stageRow.Name = "StageProfileRow"
		stageRow.BackgroundTransparency = 1
		stageRow.Size = UDim2.new(1, 0, 0, 36)
		stageRow.Parent = stageSection

		local stageRowLayout = Instance.new("UIListLayout")
		stageRowLayout.FillDirection = Enum.FillDirection.Horizontal
		stageRowLayout.Padding = UDim.new(0, 6)
		stageRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		stageRowLayout.Parent = stageRow

		stageProfileButtons = {}
		for _, profile in DEFAULT_STAGE_PROFILES do
			table.insert(
				stageProfileButtons,
				createStageProfileButton(stageRow, `StageProfile_{profile.id}`, profile.title, profile.detail)
			)
		end
		for _, stageButton in stageProfileButtons do
			stageButton.Size = UDim2.new(1 / #stageProfileButtons, -4, 1, 0)
		end
		setButtonAccent(stageProfileButtons[1], BUTTON_ACTIVE)
		setButtonAccent(stageProfileButtons[2], CYAN)
		setButtonAccent(stageProfileButtons[3], AMBER)
		setButtonActive(stageProfileButtons[1], true)

		local canvasSection = createSection(
			scroll,
			"CanvasFirst",
			"Paint Canvas",
			"Click or drag cells here. The canvas writes to the same CellMap as viewport painting."
		)
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
		setButtonAccent(modeButtons.Toggle, TEXT)
		setButtonAccent(modeButtons.Legal, BUTTON_ACTIVE)
		setButtonAccent(modeButtons.Illegal, ILLEGAL_COLOR)
		setButtonAccent(modeButtons.Portal, PORTAL_COLOR)
		setButtonAccent(modeButtons.Goal, GOAL_COLOR)
		setButtonAccent(modeButtons.AutoPlace, AUTOPLACE_COLOR)
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
		setButtonAccent(gridButton, CYAN)
		setButtonAccent(platformButton, BUTTON_ACTIVE)

		local splineSection = createSection(
			scroll,
			"SplinePath",
			"Spline Path",
			"Use red control points for smoother enemy turns."
		)
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
			{ "ClearSpline", "Clear Route" },
			{ "ExportSpline", "Export Spline" },
		})
		splineAddButton = splineEditRow[1]
		setButtonAccent(splineAddButton, CONTROL_POINT_COLOR)
		createLabel(
			splineSection,
			"SplineHelp",
			"Use the Path tab canvas to add or drag route handles. Release a handle to rebuild.",
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
		tabSections.Paint = { canvasSection, modeSection, inspectorSection }
		tabSections.Path = { splineSection }
		tabSections.Stage = { stageSection, placementSection }
		tabSections.Data = { inspectorSection, layerSection, exportSection }
		applyTabContent("Paint")

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
			clearSplineButton = splineUtilityRow[2],
			exportSplineButton = splineUtilityRow[3],
			exportButton = exportLayoutButton,
		}
	end

	widgetButtons = buildWidget()
end

local Runtime: any = {}

do
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

	local function colorForPaintMode(mode: PaintMode?): Color3
		if mode == "Illegal" then
			return ILLEGAL_COLOR
		elseif mode == "Portal" then
			return PORTAL_COLOR
		elseif mode == "Goal" then
			return GOAL_COLOR
		elseif mode == "AutoPlace" then
			return AUTOPLACE_COLOR
		elseif mode == "Toggle" then
			return TEXT
		elseif mode == "Legal" then
			return LEGAL_COLOR
		end
		return AMBER
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
				if
					child:IsA("GuiObject")
					and (
						string.sub(child.Name, 1, 12) == "PreviewCell_"
						or string.sub(child.Name, 1, 12) == "CanvasGuide_"
						or string.sub(child.Name, 1, 12) == "CanvasRuler_"
					)
				then
					child:Destroy()
				end
			end
		end

		local inset = 0.001
		for row = 1, expectedRows do
			for column = 1, expectedColumns do
				local key = gridCellKey(column, row)
				local previewCell = canvasPreviewCells[key]
				if previewCell == nil or previewCell.Parent ~= canvas then
					previewCell = Instance.new("TextButton")
					previewCell.Name =
						`PreviewCell_{string.format("%02d", column)}_{string.format("%02d", row)}`
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

		for column = 0, expectedColumns do
			local guideName = `CanvasGuide_V_{column}`
			local guide = canvas:FindFirstChild(guideName)
			if guide == nil or not guide:IsA("Frame") then
				if guide ~= nil then
					guide:Destroy()
				end
				guide = Instance.new("Frame")
				guide.Name = guideName
				guide.BorderSizePixel = 0
				guide.ZIndex = 3
				guide.Parent = canvas
			end
			local major = column % 4 == 0
			guide.BackgroundColor3 = if major then GRID_MAJOR else GRID_MINOR
			guide.BackgroundTransparency = if major then 0.04 else 0.22
			guide.Position = UDim2.fromScale(column / expectedColumns, 0)
			guide.Size = UDim2.new(0, if major then 2 else 1, 1, 0)
		end

		for row = 0, expectedRows do
			local guideName = `CanvasGuide_H_{row}`
			local guide = canvas:FindFirstChild(guideName)
			if guide == nil or not guide:IsA("Frame") then
				if guide ~= nil then
					guide:Destroy()
				end
				guide = Instance.new("Frame")
				guide.Name = guideName
				guide.BorderSizePixel = 0
				guide.ZIndex = 3
				guide.Parent = canvas
			end
			local major = row % 4 == 0
			guide.BackgroundColor3 = if major then GRID_MAJOR else GRID_MINOR
			guide.BackgroundTransparency = if major then 0.04 else 0.22
			guide.Position = UDim2.fromScale(0, row / expectedRows)
			guide.Size = UDim2.new(1, 0, 0, if major then 2 else 1)
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

	local function updateInspectorCell(
		platform: Model?,
		column: number?,
		row: number?,
		worldPosition: Vector3?
	)
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
					`{math.floor(worldPosition.X)}, {math.floor(worldPosition.Y)}, {math.floor(
						worldPosition.Z
					)}`
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
		if canvasRouteState.refresh ~= nil then
			canvasRouteState.refresh(platform)
		end
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
		stroke.Color = BUTTON_ACTIVE
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
			modeHintLabel.Text = activeMode
			modeHintPill.BackgroundColor3 = colorForPaintMode(activeMode)
			setStatus(`Paint mode: {activeMode}. Click the platform surface.`)
		else
			if shouldDeactivate and not skipPluginDeactivate then
				plugin:Deactivate()
			end
			modeHintLabel.Text = "Idle"
			modeHintPill.BackgroundColor3 = AMBER
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
			modeHintLabel.Text = "Spline"
			modeHintPill.BackgroundColor3 = PATH_COLOR
			setStatus("Add Point mode: click the canvas or platform to insert a spline control point.")
		else
			if not skipPluginDeactivate then
				plugin:Deactivate()
			end
			modeHintLabel.Text = "Idle"
			modeHintPill.BackgroundColor3 = AMBER
			setStatus("Add Point mode off.")
		end
	end

	local function _setToolTab(tab: ToolTab)
		activeToolTab = tab
		for tabName, button in toolTabButtons do
			setButtonActive(button, tabName == activeToolTab)
		end
		applyTabContent(tab)

		if tab == "Paint" then
			if activeMode == nil then
				setMode("Legal", true)
			end
			setStatus("Paint tab selected. Click or drag on the canvas, or paint in the 3D viewport.")
		elseif tab == "Path" then
			if activeMode ~= nil then
				setMode(nil, true)
			end
			setSplineAddMode(true, true)
			setStatus("Path tab selected. Drag canvas dots to reshape the route; release to rebuild.")
		elseif tab == "Stage" then
			if activeMode ~= nil then
				setMode(nil, true)
			end
			if splineAddActive then
				setSplineAddMode(false, true)
			end
			setStatus("Stage tab selected. Profiles are ready for future stage data wiring.")
		else
			if activeMode ~= nil then
				setMode(nil, true)
			end
			if splineAddActive then
				setSplineAddMode(false, true)
			end
			setStatus("Data tab selected. Export prints the current layout to Output.")
		end
	end

	local function setStageProfile(profileName: string, selectedIndex: number)
		activeStageProfile = profileName
		if stageTitleLabel ~= nil then
			stageTitleLabel.Text = profileName
		end
		for index, button in stageProfileButtons do
			setButtonActive(button, index == selectedIndex)
		end
		updateInspectorCell(hoverPlatform, hoverColumn, hoverRow, nil)
		setStatus(
			`Stage profile selected: {profileName}. Current tool still edits the connected GamePlatform.`
		)
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

	local function nextCodeForPaintMode(
		platform: Model,
		column: number,
		row: number,
		mode: PaintMode
	): CellCode
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

	local function catmullRomPosition(
		p0: Vector3,
		p1: Vector3,
		p2: Vector3,
		p3: Vector3,
		alpha: number
	): Vector3
		local alpha2 = alpha * alpha
		local alpha3 = alpha2 * alpha

		return (
			(p1 * 2)
			+ ((p2 - p0) * alpha)
			+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * alpha2)
			+ ((p1 * 3 - p0 - p2 * 3 + p3) * alpha3)
		) * 0.5
	end

	local function catmullRomTangent(
		p0: Vector3,
		p1: Vector3,
		p2: Vector3,
		p3: Vector3,
		alpha: number
	): Vector3
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
				insertSample(
					catmullRomPosition(p0, p1, p2, p3, alpha),
					catmullRomTangent(p0, p1, p2, p3, alpha)
				)
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
				local cellPosition =
					base.CFrame:PointToWorldSpace(Vector3.new(localX, base.Size.Y / 2, localZ))
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

	local function clearPathFolders()
		local points = ensurePathPointsFolder()
		if points ~= nil then
			for _, child in points:GetChildren() do
				child:Destroy()
			end
		end

		local tiles = ensurePathTilesFolder()
		if tiles ~= nil then
			for _, child in tiles:GetChildren() do
				child:Destroy()
			end
		end
	end

	local function resetCellMap(platform: Model, fullReset: boolean)
		local blankRow = string.rep(".", columns(platform))
		for row = 1, rows(platform) do
			local value = rowString(platform, row)
			if value == nil then
				continue
			end

			if fullReset then
				value.Value = blankRow
			else
				value.Value = string.gsub(value.Value, "#", ".")
			end
		end
	end

	local function clearSplineRoute()
		local platform = platformModel()
		if platform == nil then
			setStatus("GamePlatform is missing. Connect Rojo first.")
			return
		end

		setMode(nil)
		setSplineAddMode(false, true)
		local recording = beginRecording("Clear spline route")
		if recording == nil then
			return
		end

		clearPathFolders()
		resetCellMap(platform, false)
		Selection:Set({})
		applyPlatformVisual()
		finishRecording(recording)
		setSplineAddMode(true, true)
		setStatus("Route cleared. Click the canvas to place the first route handle.")
	end

	local function resetEmptyTemplate()
		local platform = platformModel()
		if platform == nil then
			setStatus("GamePlatform is missing. Connect Rojo first.")
			return
		end

		setMode(nil)
		setSplineAddMode(false, true)
		local recording = beginRecording("Reset empty stage template")
		if recording == nil then
			return
		end

		clearPathFolders()
		resetCellMap(platform, true)
		Selection:Set({})
		setStageProfile(DEFAULT_STAGE_PROFILES[1].title, 1)
		applyPlatformVisual()
		finishRecording(recording)
		setSplineAddMode(true, true)
		setStatus("Empty template ready. Click the canvas to draw the route for this stage.")
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

	Runtime.addSplinePointAt = addSplinePointAt
	Runtime.applyPlatformVisual = applyPlatformVisual
	Runtime.beginRecording = beginRecording
	Runtime.buildSplinePath = buildSplinePath
	Runtime.cellCode = cellCode
	Runtime.cellSize = cellSize
	Runtime.clearSplineRoute = clearSplineRoute
	Runtime.clearHoverPreview = clearHoverPreview
	Runtime.collectSplineControls = collectSplineControls
	Runtime.colorForCellCode = colorForCellCode
	Runtime.columns = columns
	Runtime.deleteSelectedSplinePoints = deleteSelectedSplinePoints
	Runtime.finishPaintDrag = finishPaintDrag
	Runtime.finishRecording = finishRecording
	Runtime.gridCellKey = gridCellKey
	Runtime.gridLocalBounds = gridLocalBounds
	Runtime.gridVisible = gridVisible
	Runtime.labelForCellCode = labelForCellCode
	Runtime.mapFolder = mapFolder
	Runtime.mouseGridCell = mouseGridCell
	Runtime.nextCodeForPaintMode = nextCodeForPaintMode
	Runtime.platformBasePart = platformBasePart
	Runtime.platformEnabled = platformEnabled
	Runtime.platformModel = platformModel
	Runtime.preparePlatformOrigin = preparePlatformOrigin
	Runtime.rebuildSplineButtonClicked = rebuildSplineButtonClicked
	Runtime.rebuildSplineFromControls = rebuildSplineFromControls
	Runtime.resetEmptyTemplate = resetEmptyTemplate
	Runtime.rows = rows
	Runtime.rowString = rowString
	Runtime.sampleSplinePath = sampleSplinePath
	Runtime.selectSplinePoints = selectSplinePoints
	Runtime.setBoolChild = setBoolChild
	Runtime.setCellCode = setCellCode
	Runtime.setMode = setMode
	Runtime.setSplineAddMode = setSplineAddMode
	Runtime.setStageProfile = setStageProfile
	Runtime.snapSplinePointsToPlatform = snapSplinePointsToPlatform
	Runtime.syncGridTemplate = syncGridTemplate
	Runtime.updateAllCellVisuals = updateAllCellVisuals
	Runtime.updateHoverPreview = updateHoverPreview
	Runtime.updateInspectorCell = updateInspectorCell
	Runtime.updateTargetInfo = updateTargetInfo
end

do
	local collectSplineControls = Runtime.collectSplineControls

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

	Runtime.exportSpline = exportSpline
end

do
	local gridCellKey = Runtime.gridCellKey
	local nextCodeForPaintMode = Runtime.nextCodeForPaintMode
	local setCellCode = Runtime.setCellCode
	local updateHoverPreview = Runtime.updateHoverPreview

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

	Runtime.paintCell = paintCell
	Runtime.paintHoveredCell = paintHoveredCell
end

do
	local addSplinePointAt = Runtime.addSplinePointAt
	local beginRecording = Runtime.beginRecording
	local buildSplinePath = Runtime.buildSplinePath
	local collectSplineControls = Runtime.collectSplineControls
	local finishRecording = Runtime.finishRecording
	local gridLocalBounds = Runtime.gridLocalBounds
	local platformBasePart = Runtime.platformBasePart
	local platformModel = Runtime.platformModel
	local rebuildSplineFromControls = Runtime.rebuildSplineFromControls
	local sampleSplinePath = Runtime.sampleSplinePath
	local setMode = Runtime.setMode
	local setSplineAddMode = Runtime.setSplineAddMode

	local startControlDrag: ((BasePart) -> ())? = nil

	local function routeLayer(): Frame?
		local layer = canvasRouteState.layer
		if layer ~= nil and layer:IsA("Frame") then
			return layer
		end
		return nil
	end

	local function routeDots(): { [BasePart]: TextButton }
		if canvasRouteState.dots == nil then
			canvasRouteState.dots = {}
		end
		return canvasRouteState.dots
	end

	local function routeSegments(): { Frame }
		if canvasRouteState.segments == nil then
			canvasRouteState.segments = {}
		end
		return canvasRouteState.segments
	end

	local function clearRouteOverlay()
		for _, segment in routeSegments() do
			segment:Destroy()
		end
		table.clear(routeSegments())

		for _, dot in routeDots() do
			dot:Destroy()
		end
		table.clear(routeDots())
	end

	local function canvasScaleFromInput(input: InputObject): (number?, number?)
		local canvas = canvasPreviewFrame
		if canvas == nil or canvas.AbsoluteSize.X < 1 or canvas.AbsoluteSize.Y < 1 then
			return nil, nil
		end

		local position = input.Position
		local scaleX = (position.X - canvas.AbsolutePosition.X) / canvas.AbsoluteSize.X
		local scaleY = (position.Y - canvas.AbsolutePosition.Y) / canvas.AbsoluteSize.Y
		return math.clamp(scaleX, 0, 1), math.clamp(scaleY, 0, 1)
	end

	local function worldFromCanvasScale(platform: Model, scaleX: number, scaleY: number): Vector3?
		local base = platformBasePart(platform)
		if base == nil then
			return nil
		end

		local minX, maxX, minZ, maxZ = gridLocalBounds(platform)
		local localX = minX + (maxX - minX) * math.clamp(scaleX, 0, 1)
		local localZ = minZ + (maxZ - minZ) * math.clamp(scaleY, 0, 1)
		return base.CFrame:PointToWorldSpace(
			Vector3.new(localX, base.Size.Y / 2 + CONTROL_POINT_SURFACE_OFFSET, localZ)
		)
	end

	local function worldToCanvasPoint(platform: Model, worldPosition: Vector3): Vector2?
		local canvas = canvasPreviewFrame
		local base = platformBasePart(platform)
		if canvas == nil or base == nil or canvas.AbsoluteSize.X < 1 or canvas.AbsoluteSize.Y < 1 then
			return nil
		end

		local localPosition = base.CFrame:PointToObjectSpace(worldPosition)
		local minX, maxX, minZ, maxZ = gridLocalBounds(platform)
		local scaleX = (localPosition.X - minX) / (maxX - minX)
		local scaleY = (localPosition.Z - minZ) / (maxZ - minZ)
		return Vector2.new(
			math.clamp(scaleX, 0, 1) * canvas.AbsoluteSize.X,
			math.clamp(scaleY, 0, 1) * canvas.AbsoluteSize.Y
		)
	end

	local function drawRouteSegment(layer: Frame, index: number, fromPoint: Vector2, toPoint: Vector2)
		local segments = routeSegments()
		local segment = segments[index]
		if segment == nil or segment.Parent ~= layer then
			segment = Instance.new("Frame")
			segment.Name = `CanvasRouteSegment_{string.format("%03d", index)}`
			segment.AnchorPoint = Vector2.new(0.5, 0.5)
			segment.BackgroundColor3 = PATH_COLOR
			segment.BorderSizePixel = 0
			segment.ZIndex = 7
			segment.Parent = layer
			segments[index] = segment

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = segment
		end

		local delta = toPoint - fromPoint
		local length = delta.Magnitude
		segment.Visible = length >= 1
		segment.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) / 2, (fromPoint.Y + toPoint.Y) / 2)
		segment.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		segment.Size = UDim2.fromOffset(length, 6)
	end

	local function trimRouteSegments(firstUnusedIndex: number)
		local segments = routeSegments()
		for index = #segments, firstUnusedIndex, -1 do
			segments[index]:Destroy()
			segments[index] = nil
		end
	end

	local function selectedControlLookup(): { [Instance]: boolean }
		local selected: { [Instance]: boolean } = {}
		for _, instance in Selection:Get() do
			selected[instance] = true
		end
		return selected
	end

	local function createRouteDot(layer: Frame, control: BasePart): TextButton
		local dot = Instance.new("TextButton")
		dot.Name = `CanvasRouteDot_{control.Name}`
		dot.AutoButtonColor = false
		dot.BackgroundColor3 = Color3.fromRGB(12, 15, 19)
		dot.BorderSizePixel = 0
		dot.Font = Enum.Font.GothamBold
		dot.Selectable = false
		dot.Size = UDim2.fromOffset(24, 24)
		dot.Text = ""
		dot.TextColor3 = TEXT_ACTIVE
		dot.TextSize = 10
		dot.ZIndex = 10
		dot.Parent = layer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot

		local stroke = Instance.new("UIStroke")
		stroke.Name = "DotStroke"
		stroke.Color = PATH_COLOR
		stroke.Thickness = 2
		stroke.Transparency = 0
		stroke.Parent = dot

		dot.MouseButton1Down:Connect(function()
			local beginDrag = startControlDrag
			if beginDrag ~= nil then
				beginDrag(control)
			end
		end)

		return dot
	end

	local function syncRouteDots(layer: Frame, platform: Model, controls: { BasePart })
		local dots = routeDots()
		local seen: { [BasePart]: boolean } = {}
		local selected = selectedControlLookup()

		for _, control in controls do
			seen[control] = true
			local dot = dots[control]
			if dot == nil or dot.Parent ~= layer then
				dot = createRouteDot(layer, control)
				dots[control] = dot
			end

			local point = worldToCanvasPoint(platform, control.Position)
			dot.Visible = point ~= nil
			dot.Name = `CanvasRouteDot_{control.Name}`
			if point ~= nil then
				dot.Position = UDim2.fromOffset(point.X - 12, point.Y - 12)
			end

			local stroke = dot:FindFirstChild("DotStroke")
			if stroke ~= nil and stroke:IsA("UIStroke") then
				local isSelected = selected[control] == true or canvasRouteState.dragControl == control
				stroke.Color = if isSelected then TEXT_ACTIVE else PATH_COLOR
				stroke.Thickness = if isSelected then 3 else 2
			end
		end

		for control, dot in dots do
			if seen[control] ~= true then
				dot:Destroy()
				dots[control] = nil
			end
		end
	end

	local function syncRouteSegments(layer: Frame, platform: Model, controls: { BasePart })
		if #controls < 2 then
			trimRouteSegments(1)
			return
		end

		local positions: { Vector3 } = {}
		for _, control in controls do
			table.insert(positions, control.Position)
		end

		local path = buildSplinePath(positions)
		if path.length < 0.1 then
			trimRouteSegments(1)
			return
		end

		local sampleCount = math.clamp(math.ceil(path.length / 4), 16, 120)
		local previousPoint: Vector2? = nil
		local segmentIndex = 0
		for step = 0, sampleCount do
			local worldPosition = sampleSplinePath(path, path.length * (step / sampleCount))
			local point = worldToCanvasPoint(platform, worldPosition)
			if point ~= nil then
				if previousPoint ~= nil then
					segmentIndex += 1
					drawRouteSegment(layer, segmentIndex, previousPoint, point)
				end
				previousPoint = point
			else
				previousPoint = nil
			end
		end

		trimRouteSegments(segmentIndex + 1)
	end

	canvasRouteState.refresh = function(platform: Model?)
		local layer = routeLayer()
		local targetPlatform = platform or platformModel()
		if layer == nil or targetPlatform == nil or platformBasePart(targetPlatform) == nil then
			clearRouteOverlay()
			return
		end

		local controls = collectSplineControls()
		syncRouteSegments(layer, targetPlatform, controls)
		syncRouteDots(layer, targetPlatform, controls)
	end

	canvasRouteState.addPointAtCell = function(platform: Model, column: number, row: number)
		local scaleX = (column - 0.5) / Runtime.columns(platform)
		local scaleY = (row - 0.5) / Runtime.rows(platform)
		local worldPosition = worldFromCanvasScale(platform, scaleX, scaleY)
		if worldPosition ~= nil then
			addSplinePointAt(worldPosition)
		end
	end

	startControlDrag = function(control: BasePart)
		if control.Parent == nil then
			return
		end

		setMode(nil, true)
		setSplineAddMode(false, true)
		Selection:Set({ control })

		local recording = beginRecording("Move canvas spline point")
		if recording == nil then
			return
		end

		canvasRouteState.dragControl = control
		canvasRouteState.dragRecording = recording
		canvasRouteState.dragDirty = false
		if canvasRouteState.refresh ~= nil then
			canvasRouteState.refresh()
		end
		setStatus(`Dragging {control.Name}. Release to rebuild the path.`)
	end

	local function updateDrag(input: InputObject)
		local control = canvasRouteState.dragControl
		if control == nil or not control:IsA("BasePart") or control.Parent == nil then
			return
		end

		local platform = platformModel()
		if platform == nil then
			return
		end

		local scaleX, scaleY = canvasScaleFromInput(input)
		if scaleX == nil or scaleY == nil then
			return
		end

		local worldPosition = worldFromCanvasScale(platform, scaleX, scaleY)
		if worldPosition == nil then
			return
		end

		control.Position = worldPosition
		canvasRouteState.dragDirty = true
		if canvasRouteState.refresh ~= nil then
			canvasRouteState.refresh(platform)
		end
		setStatus(`Dragging {control.Name}. Release to rebuild the path.`, true)
	end

	local function finishDrag()
		local control = canvasRouteState.dragControl
		local recording = canvasRouteState.dragRecording
		local dirty = canvasRouteState.dragDirty == true

		canvasRouteState.dragControl = nil
		canvasRouteState.dragRecording = nil
		canvasRouteState.dragDirty = false

		if dirty then
			rebuildSplineFromControls()
			if control ~= nil and control:IsA("BasePart") and control.Parent ~= nil then
				Selection:Set({ control })
			end
			setStatus("Moved spline point and rebuilt the route.")
		elseif control ~= nil and control:IsA("BasePart") then
			setStatus(`Selected {control.Name}. Drag to reshape the route.`)
		end

		finishRecording(recording)
		if canvasRouteState.refresh ~= nil then
			canvasRouteState.refresh()
		end
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			canvasRouteState.dragControl ~= nil
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateDrag(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			canvasRouteState.dragControl ~= nil
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			finishDrag()
		end
	end)

	Selection.SelectionChanged:Connect(function()
		if canvasRouteState.refresh ~= nil then
			canvasRouteState.refresh()
		end
	end)
end

do
	local beginRecording = Runtime.beginRecording
	local cellCode = Runtime.cellCode
	local colorForCellCode = Runtime.colorForCellCode
	local finishPaintDrag = Runtime.finishPaintDrag
	local gridCellKey = Runtime.gridCellKey
	local labelForCellCode = Runtime.labelForCellCode
	local nextCodeForPaintMode = Runtime.nextCodeForPaintMode
	local paintCell = Runtime.paintCell
	local platformModel = Runtime.platformModel
	local updateInspectorCell = Runtime.updateInspectorCell

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
			if splineAddActive and canvasRouteState.addPointAtCell ~= nil then
				canvasRouteState.addPointAtCell(platform, column, row)
				showCanvasHover(platform, column, row)
				return
			end

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
end

do
	local function disconnectCellMapWatch()
		for _, connection in cellMapConnections do
			connection:Disconnect()
		end
		table.clear(cellMapConnections)
		watchedCellMap = nil
		cellMapRefreshQueued = false
	end

	local function queueCellMapRefresh(platform: Model)
		if cellMapRefreshQueued then
			return
		end
		cellMapRefreshQueued = true
		task.defer(function()
			cellMapRefreshQueued = false
			if platform.Parent == nil then
				return
			end
			Runtime.updateTargetInfo(platform)
			Runtime.updateAllCellVisuals(platform)
		end)
	end

	local function watchCellMap(platform: Model)
		local folder = Runtime.mapFolder(platform)
		if folder == watchedCellMap then
			return
		end

		disconnectCellMapWatch()
		if folder == nil then
			return
		end
		watchedCellMap = folder

		local function connectRow(child: Instance)
			if child:IsA("StringValue") then
				table.insert(
					cellMapConnections,
					child.Changed:Connect(function()
						queueCellMapRefresh(platform)
					end)
				)
			end
		end

		for _, child in folder:GetChildren() do
			connectRow(child)
		end
		table.insert(
			cellMapConnections,
			folder.ChildAdded:Connect(function(child: Instance)
				connectRow(child)
				queueCellMapRefresh(platform)
			end)
		)
		table.insert(
			cellMapConnections,
			folder.ChildRemoved:Connect(function()
				queueCellMapRefresh(platform)
			end)
		)
	end

	local applyPlatformVisual = Runtime.applyPlatformVisual
	Runtime.applyPlatformVisual = function()
		applyPlatformVisual()
		local platform = Runtime.platformModel()
		if platform ~= nil then
			watchCellMap(platform)
		end
	end
end

do
	local addSplinePointAt = Runtime.addSplinePointAt
	local applyPlatformVisual = Runtime.applyPlatformVisual
	local beginRecording = Runtime.beginRecording
	local cellSize = Runtime.cellSize
	local clearSplineRoute = Runtime.clearSplineRoute
	local clearHoverPreview = Runtime.clearHoverPreview
	local columns = Runtime.columns
	local deleteSelectedSplinePoints = Runtime.deleteSelectedSplinePoints
	local exportSpline = Runtime.exportSpline
	local finishPaintDrag = Runtime.finishPaintDrag
	local finishRecording = Runtime.finishRecording
	local gridVisible = Runtime.gridVisible
	local mapFolder = Runtime.mapFolder
	local mouseGridCell = Runtime.mouseGridCell
	local paintCell = Runtime.paintCell
	local paintHoveredCell = Runtime.paintHoveredCell
	local platformBasePart = Runtime.platformBasePart
	local platformEnabled = Runtime.platformEnabled
	local platformModel = Runtime.platformModel
	local preparePlatformOrigin = Runtime.preparePlatformOrigin
	local rebuildSplineButtonClicked = Runtime.rebuildSplineButtonClicked
	local resetEmptyTemplate = Runtime.resetEmptyTemplate
	local rows = Runtime.rows
	local rowString = Runtime.rowString
	local selectSplinePoints = Runtime.selectSplinePoints
	local setBoolChild = Runtime.setBoolChild
	local setMode = Runtime.setMode
	local setSplineAddMode = Runtime.setSplineAddMode
	local setStageProfile = Runtime.setStageProfile
	local snapSplinePointsToPlatform = Runtime.snapSplinePointsToPlatform
	local syncGridTemplate = Runtime.syncGridTemplate
	local updateHoverPreview = Runtime.updateHoverPreview
	local updateTargetInfo = Runtime.updateTargetInfo

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
					descendant:IsA("BasePart")
					and (platform == nil or not descendant:IsDescendantOf(platform))
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

	for index, stageButton in stageProfileButtons do
		local profile = DEFAULT_STAGE_PROFILES[index]
		local profileName = if profile ~= nil then profile.title else stageButton.Name
		stageButton.MouseButton1Click:Connect(function()
			setStageProfile(profileName, index)
		end)
	end

	widgetButtons.stageDrawerButton.MouseButton1Click:Connect(function()
		setStageProfile(DEFAULT_STAGE_PROFILES[1].title, 1)
		setStatus("Stage tabs are visible above the canvas.")
	end)
	widgetButtons.newTemplateButton.MouseButton1Click:Connect(function()
		resetEmptyTemplate()
	end)
	widgetButtons.saveStageButton.MouseButton1Click:Connect(function()
		exportLayout()
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
	widgetButtons.clearSplineButton.MouseButton1Click:Connect(clearSplineRoute)
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

	local function openAndRefreshIfReady(): boolean
		widget.Enabled = true
		openButton:SetActive(true)

		local platform = platformModel()
		if platform == nil or platformBasePart(platform) == nil then
			return false
		end

		applyPlatformVisual()
		return true
	end

	task.defer(function()
		for _ = 1, 10 do
			if openAndRefreshIfReady() then
				return
			end
			task.wait(0.5)
		end

		applyPlatformVisual()
	end)

	print(`{PLUGIN_NAME} plugin loaded.`)
end

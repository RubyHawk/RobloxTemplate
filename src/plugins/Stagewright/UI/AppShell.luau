--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local create = Factory.create

export type Mode = "Paint" | "Graph" | "Stage" | "Waves" | "Validate"

export type Controller = {
	root: Frame,
	header: Frame,
	title: TextLabel,
	status: TextLabel,
	modes: Frame,
	footerStage: TextLabel,
	mapPlayable: TextButton,
	mapAdmin: TextButton,
	headerValidation: TextButton,
	popupLayer: Frame,
	leftSidebar: Frame,
	workspace: Frame,
	rightSidebar: Frame,
	sidebarTitle: TextLabel,
	inspectorTitle: TextLabel,
	applyResponsive: (self: Controller, mode: Mode) -> (),
	closeCompactPanel: (self: Controller) -> (),
	isWorkspaceInputAllowed: (self: Controller, position: Vector2) -> boolean,
}

local AppShell = {}
local FOOTER_HEIGHT = 56
local COMPACT_PANEL_BUTTON_WIDTH = 76
local COMPACT_DRAWER_INSET = 8
local COMPACT_LEFT_DRAWER_WIDTH = 248
local COMPACT_RIGHT_DRAWER_WIDTH = 268
local PAINT_MEDIUM_LEFT_WIDTH = 176
local PAINT_DESKTOP_SIDEBAR_MIN_WIDTH = 1_350

type CompactPanel = "Left" | "Right"

function AppShell.new(widget: DockWidgetPluginGui): Controller
	local root = create("Frame", {
		Name = "Root",
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, widget) :: Frame
	local header = create("Frame", {
		Name = "ToolHeader",
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.new(1, 0, 0, Theme.metrics.headerHeight),
	}, root) :: Frame
	create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.border,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
	}, header)
	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.fromOffset(104, Theme.metrics.headerHeight),
		Text = "Stagewright",
		TextColor3 = COLORS.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, header) :: TextLabel
	local modes = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Name = "WorkspaceNavigation",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(436, Theme.metrics.headerControlHeight),
		ZIndex = 1,
	}, header) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, modes)
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLORS.borderStrong,
		Thickness = 1,
	}, modes)
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(2, 0),
		-- Five workspace modes share one row. The offset accounts for the four
		-- two-pixel gaps so the final button cannot wrap below the clipped frame.
		CellSize = UDim2.new(0.2, -1.6, 1, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, modes)
	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Theme.metrics.headerHeight),
		Size = UDim2.new(1, 0, 1, -(Theme.metrics.headerHeight + FOOTER_HEIGHT)),
		ZIndex = 1,
	}, root) :: Frame
	local footer = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		ZIndex = 2,
	}, root) :: Frame
	local footerStage = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.34, -14, 1, 0),
		Text = "Stage 1 / Level 1",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, footer) :: TextLabel
	local status = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromScale(0.34, 0),
		Size = UDim2.new(0.66, -220, 1, 0),
		Text = "Loading your versioned stage project...",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, footer) :: TextLabel
	local mapPanel = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Name = "MapNavigation",
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(204, 48),
		ZIndex = 4,
	}, footer) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.cornerRadius) }, mapPanel)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, mapPanel)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 0, 14),
		Text = "MAP",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, mapPanel)
	local mapPlayable = Factory.button(mapPanel, "PLAYABLE", 92, nil)
	mapPlayable.Name = "MapPlayable"
	mapPlayable.Position = UDim2.fromOffset(6, 18)
	mapPlayable.Size = UDim2.fromOffset(92, 24)
	mapPlayable.TextSize = 10
	mapPlayable.ZIndex = 5
	local mapAdmin = Factory.button(mapPanel, "ADMIN", 92, nil)
	mapAdmin.Name = "MapAdmin"
	mapAdmin.Position = UDim2.fromOffset(106, 18)
	mapAdmin.Size = UDim2.fromOffset(92, 24)
	mapAdmin.TextSize = 10
	mapAdmin.ZIndex = 5
	local headerValidation = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(45, 35, 18),
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold,
		Name = "HeaderValidation",
		Position = UDim2.new(1, -90, 0, 5),
		Size = UDim2.fromOffset(188, Theme.metrics.headerControlHeight),
		Text = "Checking project...",
		TextColor3 = COLORS.muted,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 102,
	}, header) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, headerValidation)
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLORS.border,
		Name = "Outline",
		Thickness = 1,
	}, headerValidation)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.metrics.iconButtonTextPaddingLeft),
		PaddingRight = UDim.new(0, Theme.metrics.iconButtonTextPaddingRight),
	}, headerValidation)

	-- Header dropdowns must sit above every editor surface without turning the
	-- entire window into an input blocker. Only the visible popup children are
	-- Active; this transparent layer itself never consumes pointer input.
	local popupLayer = create("Frame", {
		Active = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Name = "PopupLayer",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 300,
	}, root) :: Frame

	local leftSidebar = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 184, 1, 0),
	}, body) :: Frame
	local workspace = create("Frame", {
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(190, 0),
		Size = UDim2.new(1, -380, 1, 0),
	}, body) :: Frame
	local rightSidebar = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 184, 1, 0),
	}, body) :: Frame
	local sidebarTitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "STAGES & LEVELS",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, leftSidebar) :: TextLabel
	local inspectorTitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "INSPECTOR",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, rightSidebar) :: TextLabel
	local leftCorner = create("UICorner", { CornerRadius = UDim.new(0, 0) }, leftSidebar) :: UICorner
	local rightCorner = create("UICorner", { CornerRadius = UDim.new(0, 0) }, rightSidebar) :: UICorner
	local leftOutline = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLORS.borderStrong,
		Enabled = false,
		Thickness = 1,
	}, leftSidebar) :: UIStroke
	local rightOutline = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLORS.borderStrong,
		Enabled = false,
		Thickness = 1,
	}, rightSidebar) :: UIStroke

	-- Compact layouts keep the editor canvas at full width. These controls reveal
	-- the existing authored sidebars as mutually-exclusive drawers, so Paint,
	-- Stages, and Validate never lose their tools or inspector at the 880 px
	-- supported minimum. The drawer contains the original controls and state;
	-- there is no second compact implementation to drift out of sync.
	local compactDismiss = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(3, 7, 12),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Name = "CompactPanelDismiss",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Visible = false,
		ZIndex = 110,
	}, body) :: TextButton

	local controller: Controller = {} :: any
	local responsiveMode: Mode = "Graph"
	local compactPanel: CompactPanel? = nil
	local compactToolsButton: TextButton
	local compactInspectorButton: TextButton
	compactToolsButton = Factory.button(header, "Tools", COMPACT_PANEL_BUTTON_WIDTH, function()
		compactPanel = if compactPanel == "Left" then nil else "Left"
		controller:applyResponsive(responsiveMode)
	end)
	compactToolsButton.Name = "CompactToolsButton"
	compactToolsButton.AnchorPoint = Vector2.new(1, 0)
	compactToolsButton.Size = UDim2.fromOffset(COMPACT_PANEL_BUTTON_WIDTH, Theme.metrics.headerControlHeight)
	compactToolsButton.Visible = false
	compactToolsButton.ZIndex = 203
	compactInspectorButton = Factory.button(header, "Inspect", COMPACT_PANEL_BUTTON_WIDTH, function()
		compactPanel = if compactPanel == "Right" then nil else "Right"
		controller:applyResponsive(responsiveMode)
	end)
	compactInspectorButton.Name = "CompactInspectorButton"
	compactInspectorButton.AnchorPoint = Vector2.new(1, 0)
	compactInspectorButton.Size =
		UDim2.fromOffset(COMPACT_PANEL_BUTTON_WIDTH, Theme.metrics.headerControlHeight)
	compactInspectorButton.Visible = false
	compactInspectorButton.ZIndex = 203
	compactDismiss.Activated:Connect(function()
		controller:closeCompactPanel()
	end)

	controller.root = root
	controller.header = header
	controller.title = title
	controller.status = status
	controller.modes = modes
	controller.footerStage = footerStage
	controller.mapPlayable = mapPlayable
	controller.mapAdmin = mapAdmin
	controller.headerValidation = headerValidation
	controller.popupLayer = popupLayer
	controller.leftSidebar = leftSidebar
	controller.workspace = workspace
	controller.rightSidebar = rightSidebar
	controller.sidebarTitle = sidebarTitle
	controller.inspectorTitle = inspectorTitle
	controller.closeCompactPanel = function(self: Controller)
		if compactPanel == nil then
			return
		end
		compactPanel = nil
		self:applyResponsive(responsiveMode)
	end
	controller.isWorkspaceInputAllowed = function(_self: Controller, position: Vector2): boolean
		if compactDismiss.Visible then
			return false
		end
		for _, child in popupLayer:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local childPosition = child.AbsolutePosition
				local childSize = child.AbsoluteSize
				if
					position.X >= childPosition.X
					and position.Y >= childPosition.Y
					and position.X < childPosition.X + childSize.X
					and position.Y < childPosition.Y + childSize.Y
				then
					return false
				end
			end
		end
		return true
	end
	controller.applyResponsive = function(self: Controller, mode: Mode)
		local width = self.root.AbsoluteSize.X
		local headerLayout = Theme.resolveHeaderLayout(width)
		local wantsInspector = mode ~= "Validate"
		local usesFullWorkspace = mode == "Graph" or mode == "Waves"
		local isCompact = headerLayout.density == "compact"
		local usesPaintMediumLayout = mode == "Paint"
			and width >= 1_050
			and width < PAINT_DESKTOP_SIDEBAR_MIN_WIDTH
		if responsiveMode ~= mode then
			compactPanel = nil
		end
		responsiveMode = mode
		local leftWidth = if width >= 1_500
			then if mode == "Paint" then 232 elseif mode == "Validate" then 196 else 240
			else if width >= 1_050 then 208 else 172
		local inspectorWidth = if width >= 1_500
			then if mode == "Graph" then 300 elseif mode == "Stage" then 310 else 260
			else 236

		self.title.Visible = headerLayout.showTitle
		self.modes.AnchorPoint = Vector2.new(0.5, 0.5)
		self.modes.Position = UDim2.fromScale(0.5, 0.5)
		self.modes.Size = UDim2.fromOffset(headerLayout.navWidth, Theme.metrics.headerControlHeight)
		for _, child in self.modes:GetChildren() do
			if child:IsA("TextButton") then
				child.TextSize = headerLayout.modeTextSize
			end
		end

		local hidesValidationForDrawerButtons = usesPaintMediumLayout
		self.headerValidation.Visible = not hidesValidationForDrawerButtons
		local validationRight = Theme.metrics.headerOuterPadding
			+ headerLayout.menuWidth
			+ Theme.metrics.headerControlGap
		local inspectorButtonRight = if hidesValidationForDrawerButtons
			then validationRight
			else validationRight + headerLayout.validationWidth + Theme.metrics.headerControlGap
		local controlY = math.floor((Theme.metrics.headerHeight - Theme.metrics.headerControlHeight) * 0.5)
		compactInspectorButton.Position = UDim2.new(1, -inspectorButtonRight, 0, controlY)
		compactToolsButton.Position = UDim2.new(
			1,
			-(inspectorButtonRight + COMPACT_PANEL_BUTTON_WIDTH + Theme.metrics.headerControlGap),
			0,
			controlY
		)

		if usesFullWorkspace then
			compactPanel = nil
			compactToolsButton.Visible = false
			compactInspectorButton.Visible = false
			compactDismiss.Visible = false
			self.leftSidebar.Visible = false
			self.rightSidebar.Visible = false
			self.workspace.Position = UDim2.fromOffset(0, 0)
			self.workspace.Size = UDim2.fromScale(1, 1)
		elseif isCompact then
			if not wantsInspector and compactPanel == "Right" then
				compactPanel = nil
			end
			compactToolsButton.Text = if mode == "Stage"
				then "Levels"
				elseif mode == "Validate" then "Issues"
				else "Tools"
			compactToolsButton.Visible = true
			compactInspectorButton.Visible = wantsInspector
			compactDismiss.Visible = compactPanel ~= nil
			Factory.setSelected(compactToolsButton, compactPanel == "Left")
			Factory.setSelected(compactInspectorButton, compactPanel == "Right")

			self.workspace.Position = UDim2.fromOffset(0, 0)
			self.workspace.Size = UDim2.fromScale(1, 1)
			self.leftSidebar.AnchorPoint = Vector2.new(0, 0)
			self.leftSidebar.Position = UDim2.fromOffset(COMPACT_DRAWER_INSET, COMPACT_DRAWER_INSET)
			self.leftSidebar.Size = UDim2.new(
				0,
				math.min(COMPACT_LEFT_DRAWER_WIDTH, width - COMPACT_DRAWER_INSET * 2),
				1,
				-COMPACT_DRAWER_INSET * 2
			)
			self.leftSidebar.Visible = compactPanel == "Left"
			self.leftSidebar.ZIndex = 120
			self.rightSidebar.AnchorPoint = Vector2.new(1, 0)
			self.rightSidebar.Position = UDim2.new(1, -COMPACT_DRAWER_INSET, 0, COMPACT_DRAWER_INSET)
			self.rightSidebar.Size = UDim2.new(
				0,
				math.min(COMPACT_RIGHT_DRAWER_WIDTH, width - COMPACT_DRAWER_INSET * 2),
				1,
				-COMPACT_DRAWER_INSET * 2
			)
			self.rightSidebar.Visible = compactPanel == "Right" and wantsInspector
			self.rightSidebar.ZIndex = 120
			leftCorner.CornerRadius = UDim.new(0, 8)
			rightCorner.CornerRadius = UDim.new(0, 8)
			leftOutline.Enabled = true
			rightOutline.Enabled = true
		elseif usesPaintMediumLayout then
			-- Keep the frequently-used brush rail visible at medium Paint widths,
			-- while the less frequently-used inspector remains an overlay drawer.
			-- This preserves at least 873 px of canvas at the 1,050 px breakpoint.
			if compactPanel == "Left" then
				compactPanel = nil
			end
			compactToolsButton.Visible = false
			compactInspectorButton.Visible = wantsInspector
			compactDismiss.Visible = compactPanel == "Right"
			Factory.setSelected(compactToolsButton, false)
			Factory.setSelected(compactInspectorButton, compactPanel == "Right")

			self.leftSidebar.Visible = true
			self.leftSidebar.AnchorPoint = Vector2.new(0, 0)
			self.leftSidebar.Position = UDim2.fromOffset(0, 0)
			self.leftSidebar.Size = UDim2.new(0, PAINT_MEDIUM_LEFT_WIDTH, 1, 0)
			self.leftSidebar.ZIndex = 1
			self.workspace.Position = UDim2.fromOffset(PAINT_MEDIUM_LEFT_WIDTH + 1, 0)
			self.workspace.Size = UDim2.new(1, -(PAINT_MEDIUM_LEFT_WIDTH + 1), 1, 0)

			self.rightSidebar.AnchorPoint = Vector2.new(1, 0)
			self.rightSidebar.Position = UDim2.new(1, -COMPACT_DRAWER_INSET, 0, COMPACT_DRAWER_INSET)
			self.rightSidebar.Size = UDim2.new(
				0,
				math.min(COMPACT_RIGHT_DRAWER_WIDTH, width - COMPACT_DRAWER_INSET * 2),
				1,
				-COMPACT_DRAWER_INSET * 2
			)
			self.rightSidebar.Visible = compactPanel == "Right" and wantsInspector
			self.rightSidebar.ZIndex = 120

			leftCorner.CornerRadius = UDim.new(0, 0)
			rightCorner.CornerRadius = UDim.new(0, 8)
			leftOutline.Enabled = false
			rightOutline.Enabled = true
		else
			compactPanel = nil
			compactToolsButton.Visible = false
			compactInspectorButton.Visible = false
			compactDismiss.Visible = false
			Factory.setSelected(compactToolsButton, false)
			Factory.setSelected(compactInspectorButton, false)
			leftCorner.CornerRadius = UDim.new(0, 0)
			rightCorner.CornerRadius = UDim.new(0, 0)
			leftOutline.Enabled = false
			rightOutline.Enabled = false
			self.leftSidebar.Visible = true
			self.leftSidebar.AnchorPoint = Vector2.new(0, 0)
			self.leftSidebar.Position = UDim2.fromOffset(0, 0)
			self.rightSidebar.Visible = wantsInspector
			self.leftSidebar.Size = UDim2.new(0, leftWidth, 1, 0)
			self.leftSidebar.ZIndex = 1
			self.workspace.Position = UDim2.fromOffset(leftWidth + 1, 0)
			self.workspace.Size = UDim2.new(
				1,
				if wantsInspector then -(leftWidth + inspectorWidth + 2) else -(leftWidth + 1),
				1,
				0
			)
			self.rightSidebar.AnchorPoint = Vector2.new(1, 0)
			self.rightSidebar.Position = UDim2.fromScale(1, 0)
			self.rightSidebar.Size = UDim2.new(0, inspectorWidth, 1, 0)
			self.rightSidebar.ZIndex = 1
		end
	end
	return controller
end

return table.freeze(AppShell)

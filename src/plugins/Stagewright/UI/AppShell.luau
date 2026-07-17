--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local create = Factory.create

export type Mode = "Paint" | "Graph" | "Stage" | "Validate"

export type Controller = {
	root: Frame,
	header: Frame,
	title: TextLabel,
	status: TextLabel,
	modes: Frame,
	body: Frame,
	footer: Frame,
	footerStage: TextLabel,
	headerValidation: TextButton,
	popupLayer: Frame,
	leftSidebar: Frame,
	workspace: Frame,
	rightSidebar: Frame,
	sidebarTitle: TextLabel,
	inspectorTitle: TextLabel,
	applyResponsive: (self: Controller, mode: Mode) -> (),
}

local AppShell = {}

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
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.fromOffset(128, Theme.metrics.headerHeight),
		Text = "Stagewright",
		TextColor3 = COLORS.text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header) :: TextLabel
	local status = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(1, 1),
		Text = "Loading your versioned stage project...",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, header) :: TextLabel
	local modes = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -96, 0.5, 0),
		Size = UDim2.fromOffset(500, 34),
	}, header) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 0),
		CellSize = UDim2.new(0.25, -6, 1, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, modes)
	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Theme.metrics.headerHeight),
		Size = UDim2.new(1, 0, 1, -Theme.metrics.headerHeight),
		ZIndex = 1,
	}, root) :: Frame
	local footer = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Visible = false,
		ZIndex = 2,
	}, root) :: Frame
	local footerStage = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.65, -14, 1, 0),
		Text = "Stage 1 / Level 1",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, footer) :: TextLabel
	create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(180, 34),
		Text = "Stagewright 2.4 - Edit mode only",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, footer)
	local headerValidation = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(45, 35, 18),
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.new(1, -598, 0, 9),
		Size = UDim2.fromOffset(174, 34),
		Text = "Checking project...",
		TextColor3 = COLORS.muted,
		TextSize = 12,
	}, header) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, headerValidation)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, headerValidation)

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

	local controller: Controller = {} :: any
	controller.root = root
	controller.header = header
	controller.title = title
	controller.status = status
	controller.modes = modes
	controller.body = body
	controller.footer = footer
	controller.footerStage = footerStage
	controller.headerValidation = headerValidation
	controller.popupLayer = popupLayer
	controller.leftSidebar = leftSidebar
	controller.workspace = workspace
	controller.rightSidebar = rightSidebar
	controller.sidebarTitle = sidebarTitle
	controller.inspectorTitle = inspectorTitle
	controller.applyResponsive = function(self: Controller, mode: Mode)
		local width = self.root.AbsoluteSize.X
		local wantsInspector = mode ~= "Validate"
		local leftWidth = if width >= 1_500
			then if mode == "Paint" then 232 elseif mode == "Validate" then 196 else 240
			else if width >= 1_100 then 208 else 172
		local inspectorWidth = if width >= 1_500
			then if mode == "Graph" then 300 elseif mode == "Stage" then 310 else 260
			else 236
		if mode == "Graph" then
			self.leftSidebar.Visible = false
			self.rightSidebar.Visible = false
			self.workspace.Position = UDim2.fromOffset(0, 0)
			self.workspace.Size = UDim2.fromScale(1, 1)
			self.title.Visible = true
			self.status.Visible = false
			self.modes.AnchorPoint = Vector2.new(1, 0.5)
			self.modes.Position = UDim2.new(1, -96, 0.5, 0)
			self.modes.Size = UDim2.fromOffset(500, 34)
			self.headerValidation.Visible = true
		elseif width >= 760 then
			self.leftSidebar.Visible = true
			self.rightSidebar.Visible = wantsInspector
			self.leftSidebar.Size = UDim2.new(0, leftWidth, 1, 0)
			self.workspace.Position = UDim2.fromOffset(leftWidth + 1, 0)
			self.workspace.Size = UDim2.new(
				1,
				if wantsInspector then -(leftWidth + inspectorWidth + 2) else -(leftWidth + 1),
				1,
				0
			)
			self.rightSidebar.Size = UDim2.new(0, inspectorWidth, 1, 0)
			self.title.Visible = true
			self.status.Visible = false
			self.modes.AnchorPoint = Vector2.new(1, 0.5)
			self.modes.Position = UDim2.new(1, -96, 0.5, 0)
			self.modes.Size = UDim2.fromOffset(500, 34)
			self.headerValidation.Visible = true
		else
			self.leftSidebar.Visible = false
			self.rightSidebar.Visible = false
			self.workspace.Position = UDim2.fromOffset(0, 0)
			self.workspace.Size = UDim2.fromScale(1, 1)
			self.title.Visible = false
			self.status.Visible = false
			self.modes.AnchorPoint = Vector2.new(0, 0.5)
			self.modes.Position = UDim2.new(0, 10, 0.5, 0)
			self.modes.Size = UDim2.new(1, -20, 0, 30)
			self.headerValidation.Visible = false
		end
	end
	return controller
end

return table.freeze(AppShell)

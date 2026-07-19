--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)
local Toolbar = require(script.Parent.Toolbar)

local COLORS = Theme.colors
local button = Factory.button
local create = Factory.create

export type StageOption = {
	id: string,
	label: string,
	selected: boolean,
}

export type Config = {
	header: Frame,
	popupLayer: Frame,
	headerValidation: TextButton,
	status: TextLabel,
	widget: DockWidgetPluginGui,
	stageOptions: () -> { StageOption },
	onSelectStage: (stageId: string) -> (),
	onRender: () -> (),
	onSave: () -> string,
	onOpenValidation: () -> (),
	onFocusAuthoring: () -> (),
	canMutate: () -> boolean,
	onBlocked: (action: string) -> (),
}

export type Controller = {
	refreshStageSelector: (self: Controller) -> (),
}

local HeaderController = {}

local function addLogo(header: Frame): Frame
	local logo = create("Frame", {
		BackgroundTransparency = 1,
		Name = "StagewrightLogo",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 4,
	}, header) :: Frame
	for _, rotation in { 0, 45, 90, 135 } do
		local petal = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.accent,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rotation,
			Size = UDim2.fromOffset(24, 7),
			ZIndex = 4,
		}, logo) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 3) }, petal)
	end
	local core = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.text,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		ZIndex = 5,
	}, logo) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 3) }, core)
	return logo
end

function HeaderController.new(config: Config): Controller
	local header = config.header
	config.headerValidation.TextXAlignment = Enum.TextXAlignment.Left
	local validationPadding = config.headerValidation:FindFirstChildOfClass("UIPadding")
	if validationPadding == nil then
		validationPadding = create("UIPadding", {}, config.headerValidation) :: UIPadding
	end
	validationPadding.PaddingLeft = UDim.new(0, Theme.metrics.iconButtonTextPaddingLeft)
	validationPadding.PaddingRight = UDim.new(0, Theme.metrics.iconButtonTextPaddingRight)
	Toolbar.addVectorIcon(config.headerValidation, "warning", COLORS.warning, 12)
	local logo = addLogo(header)

	local stageSelector = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Name = "StageSelector",
		Position = UDim2.fromOffset(158, 5),
		Size = UDim2.fromOffset(208, Theme.metrics.headerControlHeight),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 202,
	}, header) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, stageSelector)
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLORS.borderStrong,
		Thickness = 1,
	}, stageSelector)
	stageSelector.MouseEnter:Connect(function()
		if stageSelector.BackgroundColor3 == COLORS.surface then
			stageSelector.BackgroundColor3 = COLORS.hover
		end
	end)
	stageSelector.MouseLeave:Connect(function()
		if stageSelector.BackgroundColor3 == COLORS.hover then
			stageSelector.BackgroundColor3 = COLORS.surface
		end
	end)
	local stageSelectorLabel = create("TextLabel", {
		Active = false,
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -38, 1, 0),
		Text = "Stage 1 / Level 1",
		TextColor3 = COLORS.text,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 203,
	}, stageSelector) :: TextLabel
	local stageChevron = Toolbar.addVectorIcon(stageSelector, "chevron", COLORS.muted, 0)
	stageChevron.AnchorPoint = Vector2.new(1, 0.5)
	stageChevron.Position = UDim2.new(1, -10, 0.5, 0)

	local stageDropdown = create("Frame", {
		Active = true,
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Name = "StageDropdown",
		Position = UDim2.fromOffset(158, Theme.metrics.headerHeight + 4),
		Size = UDim2.fromOffset(208, 294),
		Visible = false,
		ZIndex = 310,
	}, config.popupLayer) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, stageDropdown)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, stageDropdown)
	local stageDropdownList = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		Position = UDim2.fromOffset(7, 7),
		ScrollBarImageColor3 = COLORS.borderStrong,
		ScrollBarThickness = 4,
		Size = UDim2.new(1, -14, 1, -14),
		ZIndex = 311,
	}, stageDropdown) :: ScrollingFrame
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, stageDropdownList)

	local controller: Controller = {} :: any
	local function canRunMutation(action: string): boolean
		if config.canMutate() then
			return true
		end
		config.onBlocked(action)
		return false
	end

	controller.refreshStageSelector = function(_self: Controller)
		local options = config.stageOptions()
		for _, option in options do
			if option.selected then
				stageSelectorLabel.Text = option.label
				break
			end
		end
		for _, child in stageDropdownList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for order, option in options do
			local item = button(stageDropdownList, option.label, 198, function()
				stageDropdown.Visible = false
				config.onSelectStage(option.id)
			end)
			item.LayoutOrder = order
			item.Size = UDim2.new(1, -2, 0, 34)
			item.TextXAlignment = Enum.TextXAlignment.Left
			item.TextSize = 13
			item.ZIndex = 312
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}, item)
			if option.selected then
				item.BackgroundColor3 = COLORS.accentMuted
				item.TextColor3 = Color3.fromRGB(70, 187, 255)
				local outline = item:FindFirstChild("Outline")
				if outline ~= nil and outline:IsA("UIStroke") then
					outline.Color = Color3.fromRGB(0, 100, 158)
				end
			end
		end
	end
	local menuPopup: Frame
	stageSelector.Activated:Connect(function()
		menuPopup.Visible = false
		controller:refreshStageSelector()
		stageDropdown.Visible = not stageDropdown.Visible
	end)

	menuPopup = create("Frame", {
		Active = true,
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Name = "MenuPopup",
		Position = UDim2.new(1, -8, 0, Theme.metrics.headerHeight + 4),
		Size = UDim2.fromOffset(190, 190),
		Visible = false,
		ZIndex = 310,
	}, config.popupLayer) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, menuPopup)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, menuPopup)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 20),
		Text = "PROJECT MENU",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 311,
	}, menuPopup)
	local function menuItem(label: string, order: number, callback: () -> ())
		local item = button(menuPopup, label, 170, function()
			menuPopup.Visible = false
			callback()
		end)
		item.Position = UDim2.fromOffset(10, 32 + (order - 1) * 38)
		item.Size = UDim2.new(1, -20, 0, 32)
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.ZIndex = 311
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, item)
	end
	menuItem("Save changes", 1, function()
		if not canRunMutation("Save changes") then
			return
		end
		config.status.Text = `Saved working copy - {config.onSave()}`
		config.status.TextColor3 = COLORS.success
	end)
	menuItem("Open validation", 2, config.onOpenValidation)
	menuItem("Focus authoring area", 3, function()
		if not canRunMutation("Focus authoring area") then
			return
		end
		config.onFocusAuthoring()
		config.status.Text = "Focused the Stagewright authoring area below the shared map."
		config.status.TextColor3 = COLORS.text
	end)
	menuItem("Hide editor", 4, function()
		config.widget.Enabled = false
	end)

	local undo = button(header, "Undo", 82, function()
		if not canRunMutation("Undo") then
			return
		end
		pcall(function()
			ChangeHistoryService:Undo()
		end)
		config.onRender()
	end)
	undo.Name = "UndoButton"
	undo.Position = UDim2.fromOffset(374, 5)
	undo.Size = UDim2.fromOffset(74, Theme.metrics.headerControlHeight)
	undo.ZIndex = 102
	Toolbar.styleIconButton(undo, "Undo", "undo", COLORS.muted)
	local redo = button(header, "Redo", 82, function()
		if not canRunMutation("Redo") then
			return
		end
		pcall(function()
			ChangeHistoryService:Redo()
		end)
		config.onRender()
	end)
	redo.Name = "RedoButton"
	redo.Position = UDim2.fromOffset(454, 5)
	redo.Size = UDim2.fromOffset(74, Theme.metrics.headerControlHeight)
	redo.ZIndex = 102
	Toolbar.styleIconButton(redo, "Redo", "redo", COLORS.muted)
	local menu = button(header, "Menu", 76, function()
		stageDropdown.Visible = false
		menuPopup.Visible = not menuPopup.Visible
	end)
	menu.Name = "MenuButton"
	menu.AnchorPoint = Vector2.new(1, 0)
	menu.Position = UDim2.new(1, -8, 0, 5)
	menu.Size = UDim2.fromOffset(76, Theme.metrics.headerControlHeight)
	menu.ZIndex = 102
	Toolbar.styleIconButton(menu, "Menu", "menu", COLORS.muted)

	local lastDensity = ""
	local function applyHeaderLayout()
		local layout = Theme.resolveHeaderLayout(header.AbsoluteSize.X)
		local controlY = math.floor((Theme.metrics.headerHeight - Theme.metrics.headerControlHeight) * 0.5)
		local undoX = layout.stageX + layout.stageWidth + Theme.metrics.headerOuterPadding
		local redoX = undoX + layout.historyWidth + Theme.metrics.headerControlGap
		local validationRight = Theme.metrics.headerOuterPadding
			+ layout.menuWidth
			+ Theme.metrics.headerControlGap

		logo.Position = UDim2.fromOffset(10, 8)
		stageSelector.Position = UDim2.fromOffset(layout.stageX, controlY)
		stageSelector.Size = UDim2.fromOffset(layout.stageWidth, Theme.metrics.headerControlHeight)
		stageSelectorLabel.TextSize = if layout.density == "compact" then 12 else 13
		stageDropdown.Position = UDim2.fromOffset(layout.stageX, Theme.metrics.headerHeight + 4)
		stageDropdown.Size = UDim2.fromOffset(layout.stageWidth, 294)

		undo.Position = UDim2.fromOffset(undoX, controlY)
		undo.Size = UDim2.fromOffset(layout.historyWidth, Theme.metrics.headerControlHeight)
		redo.Position = UDim2.fromOffset(redoX, controlY)
		redo.Size = UDim2.fromOffset(layout.historyWidth, Theme.metrics.headerControlHeight)
		menu.Position = UDim2.new(1, -Theme.metrics.headerOuterPadding, 0, controlY)
		menu.Size = UDim2.fromOffset(layout.menuWidth, Theme.metrics.headerControlHeight)
		menuPopup.Position =
			UDim2.new(1, -Theme.metrics.headerOuterPadding, 0, Theme.metrics.headerHeight + 4)

		config.headerValidation.Position = UDim2.new(1, -validationRight, 0, controlY)
		config.headerValidation.Size =
			UDim2.fromOffset(layout.validationWidth, Theme.metrics.headerControlHeight)
		config.headerValidation.TextTransparency = if layout.showValidationLabel then 0 else 1
		config.headerValidation:SetAttribute("StagewrightIconOnly", not layout.showValidationLabel)
		validationPadding.PaddingLeft =
			UDim.new(0, if layout.showValidationLabel then Theme.metrics.iconButtonTextPaddingLeft else 0)
		validationPadding.PaddingRight =
			UDim.new(0, if layout.showValidationLabel then Theme.metrics.iconButtonTextPaddingRight else 0)
		local validationIcon = config.headerValidation:FindFirstChild("VectorIcon")
		if validationIcon ~= nil and validationIcon:IsA("GuiObject") then
			if layout.showValidationLabel then
				validationIcon.AnchorPoint = Vector2.new(0, 0.5)
				validationIcon.Position =
					UDim2.new(0, Theme.metrics.iconInset - Theme.metrics.iconButtonTextPaddingLeft, 0.5, 0)
			else
				validationIcon.AnchorPoint = Vector2.new(0.5, 0.5)
				validationIcon.Position = UDim2.fromScale(0.5, 0.5)
			end
		end

		if lastDensity ~= layout.density then
			if layout.showHistoryLabels then
				Toolbar.styleIconButton(undo, "Undo", "undo", COLORS.muted)
				Toolbar.styleIconButton(redo, "Redo", "redo", COLORS.muted)
			else
				Toolbar.styleIconOnlyButton(undo, "Undo", "undo", COLORS.muted)
				Toolbar.styleIconOnlyButton(redo, "Redo", "redo", COLORS.muted)
			end
			if layout.showMenuLabel then
				Toolbar.styleIconButton(menu, "Menu", "menu", COLORS.muted)
			else
				Toolbar.styleIconOnlyButton(menu, "Menu", "menu", COLORS.muted)
			end
			lastDensity = layout.density
		end
	end

	header:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyHeaderLayout)
	applyHeaderLayout()

	return controller
end

return table.freeze(HeaderController)

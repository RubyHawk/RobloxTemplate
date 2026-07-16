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
	headerValidation: TextButton,
	status: TextLabel,
	widget: DockWidgetPluginGui,
	stageOptions: () -> { StageOption },
	onSelectStage: (stageId: string) -> (),
	onRender: () -> (),
	onSave: () -> string,
	onOpenValidation: () -> (),
	onFocusAuthoring: () -> (),
}

export type Controller = {
	refreshStageSelector: (self: Controller) -> (),
}

local HeaderController = {}

local function addLogo(header: Frame)
	local logo = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(13, 10),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 4,
	}, header) :: Frame
	for _, rotation in { 0, 45, 90, 135 } do
		local petal = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.accent,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rotation,
			Size = UDim2.fromOffset(27, 8),
			ZIndex = 4,
		}, logo) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 3) }, petal)
	end
	local core = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.text,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		ZIndex = 5,
	}, logo) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 3) }, core)
end

function HeaderController.new(config: Config): Controller
	local header = config.header
	config.headerValidation.TextXAlignment = Enum.TextXAlignment.Left
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 40),
		PaddingRight = UDim.new(0, 12),
	}, config.headerValidation)
	Toolbar.addVectorIcon(config.headerValidation, "warning", COLORS.warning, 12)
	addLogo(header)

	local stageSelector = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Name = "StageSelector",
		Position = UDim2.fromOffset(198, 7),
		Size = UDim2.fromOffset(224, 38),
		Text = "Stage 1 / Level 1",
		TextColor3 = COLORS.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 202,
	}, header) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, stageSelector)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, stageSelector)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 38),
	}, stageSelector)
	local stageChevron = Toolbar.addVectorIcon(stageSelector, "chevron", COLORS.muted, 0)
	stageChevron.AnchorPoint = Vector2.new(1, 0.5)
	stageChevron.Position = UDim2.new(1, -10, 0.5, 0)

	local stageDropdown = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Name = "StageDropdown",
		Position = UDim2.fromOffset(198, 51),
		Size = UDim2.fromOffset(224, 294),
		Visible = false,
		ZIndex = 210,
	}, header) :: Frame
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
		ZIndex = 211,
	}, stageDropdown) :: ScrollingFrame
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, stageDropdownList)

	local controller: Controller = {} :: any
	controller.refreshStageSelector = function(_self: Controller)
		local options = config.stageOptions()
		for _, option in options do
			if option.selected then
				stageSelector.Text = option.label
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
			item.ZIndex = 212
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
	stageSelector.Activated:Connect(function()
		controller:refreshStageSelector()
		stageDropdown.Visible = not stageDropdown.Visible
	end)

	local menuPopup = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -8, 1, 6),
		Size = UDim2.fromOffset(190, 190),
		Visible = false,
		ZIndex = 100,
	}, header) :: Frame
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
		ZIndex = 101,
	}, menuPopup)
	local function menuItem(label: string, order: number, callback: () -> ())
		local item = button(menuPopup, label, 170, function()
			menuPopup.Visible = false
			callback()
		end)
		item.Position = UDim2.fromOffset(10, 32 + (order - 1) * 38)
		item.Size = UDim2.new(1, -20, 0, 32)
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.ZIndex = 101
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, item)
	end
	menuItem("Save changes", 1, function()
		config.status.Text = `Saved working copy - {config.onSave()}`
		config.status.TextColor3 = COLORS.success
	end)
	menuItem("Open validation", 2, config.onOpenValidation)
	menuItem("Focus authoring area", 3, function()
		config.onFocusAuthoring()
		config.status.Text = "Focused the Stagewright authoring area below the shared map."
		config.status.TextColor3 = COLORS.text
	end)
	menuItem("Hide editor", 4, function()
		config.widget.Enabled = false
	end)

	local undo = button(header, "Undo", 82, function()
		pcall(function()
			ChangeHistoryService:Undo()
		end)
		config.onRender()
	end)
	undo.Position = UDim2.fromOffset(452, 9)
	undo.Size = UDim2.fromOffset(82, 34)
	Toolbar.styleIconButton(undo, "Undo", "undo", COLORS.muted)
	local redo = button(header, "Redo", 82, function()
		pcall(function()
			ChangeHistoryService:Redo()
		end)
		config.onRender()
	end)
	redo.Position = UDim2.fromOffset(540, 9)
	redo.Size = UDim2.fromOffset(82, 34)
	Toolbar.styleIconButton(redo, "Redo", "redo", COLORS.muted)
	local menu = button(header, "Menu", 76, function()
		menuPopup.Visible = not menuPopup.Visible
	end)
	menu.AnchorPoint = Vector2.new(1, 0)
	menu.Position = UDim2.new(1, -8, 0, 9)
	menu.Size = UDim2.fromOffset(76, 34)
	menu.ZIndex = 102
	Toolbar.styleIconButton(menu, "Menu", "menu", COLORS.muted)

	return controller
end

return table.freeze(HeaderController)

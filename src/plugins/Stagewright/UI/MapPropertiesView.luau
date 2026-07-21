--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local button = Factory.button
local create = Factory.create

local MapPropertiesView = {}

export type Config = {
	parent: Instance,
	onApply: (name: string, backdropImageId: string) -> (),
}

export type Controller = {
	root: Frame,
	setMap: (self: Controller, map: any?, mapNumber: number?) -> (),
}

local function textField(parent: Instance, label: string, order: number): TextBox
	local group = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Size = UDim2.new(1, 0, 0, 13),
		Text = label,
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group)
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, field)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, field)
	return field
end

function MapPropertiesView.new(config: Config): Controller
	local root = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 1, -48),
		Visible = false,
		ZIndex = 3,
	}, config.parent) :: Frame
	local contextLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLORS.accentMuted,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(122, 26),
		Text = "MAP --",
		TextColor3 = Color3.fromRGB(151, 194, 255),
		TextSize = 10,
		ZIndex = 4,
	}, root) :: TextLabel
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, contextLabel)
	local form = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 90),
		ZIndex = 4,
	}, root) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(0, 7),
		CellSize = UDim2.new(1, 0, 0, 41),
		FillDirectionMaxCells = 1,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, form)
	local nameField = textField(form, "MAP NAME", 1)
	local backdropField = textField(form, "BACKDROP IMAGE ASSET ID", 2)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(0, 138),
		Size = UDim2.new(1, 0, 0, 50),
		Text = "Shared by every Stage and Level on this Map. The image is visual only; live splines remain the route truth.",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	}, root)
	local apply = button(root, "Apply map changes", 144, function()
		config.onApply(nameField.Text, backdropField.Text)
	end)
	apply.AnchorPoint = Vector2.new(1, 0)
	apply.Position = UDim2.new(1, 0, 0, 196)
	apply.Size = UDim2.fromOffset(144, 32)
	apply.ZIndex = 4

	local controller: Controller = {} :: any
	controller.root = root
	controller.setMap = function(_self: Controller, map: any?, mapNumber: number?)
		local number = mapNumber or 1
		contextLabel.Text = if map ~= nil then `MAP {number}` else "MAP --"
		if not nameField:IsFocused() then
			nameField.Text = if type(map) == "table" and type(map.name) == "string" then map.name else ""
		end
		if not backdropField:IsFocused() then
			backdropField.Text = if type(map) == "table" and type(map.backdropImageId) == "string"
				then map.backdropImageId
				else ""
		end
	end
	return controller
end

return table.freeze(MapPropertiesView)

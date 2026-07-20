--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local create = Factory.create
local button = Factory.button

export type Config = {
	onBrushSize: (number) -> (),
}

export type CellState = {
	label: string,
	surface: string,
	towers: string,
	route: string,
	roles: string,
}

export type Controller = {
	root: ScrollingFrame,
	setBrush: (self: Controller, propertyName: string, name: string, help: string) -> (),
	setBrushSize: (self: Controller, size: number) -> (),
	setCell: (self: Controller, state: CellState?) -> (),
}

type LegendEntry = {
	label: string,
	color: Color3,
}

local LEGEND: { LegendEntry } = {
	{ label = "Surface: Ground", color = COLORS.ground },
	{ label = "Surface: Void", color = COLORS.void },
	{ label = "Towers: Allowed", color = COLORS.allowed },
	{ label = "Towers: Blocked", color = COLORS.blocked },
	{ label = "Towers: Auto", color = COLORS.auto },
	{ label = "Route: Allowed", color = Color3.fromRGB(51, 116, 164) },
	{ label = "Route: Blocked", color = COLORS.blocked },
	{ label = "Roles: Optional", color = COLORS.accent },
}

local PaintInspector = {}

local function label(parent: Instance, properties: { [string]: any }): TextLabel
	properties.BackgroundTransparency = 1
	return create("TextLabel", properties, parent) :: TextLabel
end

local function stateRow(parent: Instance, y: number, title: string): TextLabel
	label(parent, {
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.fromOffset(72, 18),
		Text = title,
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return label(parent, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(86, y),
		Size = UDim2.new(1, -98, 0, 18),
		Text = "--",
		TextColor3 = COLORS.text,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

function PaintInspector.create(parent: Instance, config: Config): Controller
	local root = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 668),
		Name = "PaintInspector",
		Position = UDim2.fromOffset(0, 38),
		ScrollBarImageColor3 = COLORS.borderStrong,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, 0, 1, -38),
		Visible = false,
	}, parent) :: ScrollingFrame

	local brushCard = create("Frame", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 126),
	}, root) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, brushCard)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, brushCard)
	local brushLayer = label(brushCard, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "ACTIVE PROPERTY - SURFACE",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local brushName = label(brushCard, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "Ground",
		TextColor3 = COLORS.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local brushHelp = label(brushCard, {
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 54),
		Text = "Set Surface to Ground. Other cell properties stay unchanged.",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	label(root, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 144),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "BRUSH SIZE",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local sizeChoices: { [number]: TextButton } = {}
	for order, size in { 1, 3, 5 } do
		local brushSize = size
		local sizeChoice = button(root, `{brushSize} x {brushSize}`, 70, function()
			config.onBrushSize(brushSize)
		end)
		sizeChoice.Position = UDim2.new((order - 1) / 3, 10 + (order - 1) * 3, 0, 168)
		sizeChoice.Size = UDim2.new(1 / 3, -9, 0, 32)
		sizeChoice.Name = `PaintSizeChoice{brushSize}`
		sizeChoices[brushSize] = sizeChoice
	end

	local stateCard = create("Frame", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 216),
		Size = UDim2.new(1, -20, 0, 176),
	}, root) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, stateCard)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, stateCard)
	local cellLabel = label(stateCard, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "CELL STATE - SELECT OR HOVER",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(stateCard, {
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 34),
		Text = "Each cell has one Surface, one Tower rule, one Route rule, plus optional roles.",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local surfaceValue = stateRow(stateCard, 66, "Surface")
	local towersValue = stateRow(stateCard, 86, "Towers")
	local routeValue = stateRow(stateCard, 106, "Route")
	local rolesValue = stateRow(stateCard, 126, "Roles")
	rolesValue.Size = UDim2.new(1, -98, 0, 38)
	rolesValue.TextTruncate = Enum.TextTruncate.None
	rolesValue.TextWrapped = true
	rolesValue.TextYAlignment = Enum.TextYAlignment.Top

	label(root, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 408),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "SAFE PAINTING",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(root, {
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 432),
		Size = UDim2.new(1, -24, 0, 74),
		Text = "Choose a layer value and tool. Hold Shift before pressing a cell, keep it held while dragging, then release. Select inspects; middle mouse pans.",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	label(root, {
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 518),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "PROPERTY KEY",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for order, definition in LEGEND do
		local column = (order - 1) % 2
		local row = math.floor((order - 1) / 2)
		local entry = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(column * 0.5, 10 + column * 3, 0, 542 + row * 27),
			Size = UDim2.new(0.5, -13, 0, 22),
		}, root) :: Frame
		local swatch = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = definition.color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(11, 11),
		}, entry) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 3) }, swatch)
		label(entry, {
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(17, 0),
			Size = UDim2.new(1, -17, 1, 0),
			Text = definition.label,
			TextColor3 = COLORS.text,
			TextSize = 9,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	local controller: Controller = {} :: any
	controller.root = root
	controller.setBrush = function(_self: Controller, propertyName: string, name: string, help: string)
		brushLayer.Text = `ACTIVE PROPERTY - {string.upper(propertyName)}`
		brushName.Text = name
		brushHelp.Text = help
	end
	controller.setBrushSize = function(_self: Controller, size: number)
		for value, choice in sizeChoices do
			local selected = value == size
			choice.BackgroundColor3 = if selected then COLORS.accent else COLORS.surface
			choice.TextColor3 = if selected then Color3.fromRGB(255, 255, 255) else COLORS.text
		end
	end
	controller.setCell = function(_self: Controller, state: CellState?)
		cellLabel.Text = if state ~= nil then string.upper(state.label) else "CELL STATE - SELECT OR HOVER"
		surfaceValue.Text = if state ~= nil then state.surface else "--"
		towersValue.Text = if state ~= nil then state.towers else "--"
		routeValue.Text = if state ~= nil then state.route else "--"
		rolesValue.Text = if state ~= nil then state.roles else "--"
	end
	controller:setBrushSize(1)
	return controller
end

return table.freeze(PaintInspector)

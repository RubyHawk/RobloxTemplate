--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local create = Factory.create

local Toolbar = {}

local function paddingFor(result: TextButton): UIPadding
	local padding = result:FindFirstChildOfClass("UIPadding")
	if padding == nil then
		padding = create("UIPadding", {}, result) :: UIPadding
	end
	return padding
end

function Toolbar.iconLine(
	parent: Instance,
	x: number,
	y: number,
	width: number,
	height: number,
	rotation: number,
	color: Color3,
	zIndex: number
): Frame
	local line = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Rotation = rotation,
		Size = UDim2.fromOffset(width, height),
		ZIndex = zIndex,
	}, parent) :: Frame
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, line)
	return line
end

function Toolbar.iconDot(
	parent: Instance,
	x: number,
	y: number,
	size: number,
	color: Color3,
	zIndex: number,
	hollow: boolean?
): Frame
	local dot = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = if hollow then 1 else 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
	}, parent) :: Frame
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	if hollow then
		create("UIStroke", { Color = color, Thickness = 1.6 }, dot)
	end
	return dot
end

function Toolbar.addVectorIcon(parent: GuiObject, kind: string, color: Color3, offsetX: number?): Frame
	local existing = parent:FindFirstChild("VectorIcon")
	if existing ~= nil then
		existing:Destroy()
	end
	-- UIPadding changes the coordinate space of every child, including decorative
	-- icons. Compensate for its left inset so offsetX always means pixels from the
	-- visible edge of the button instead of pixels from the padded text area.
	local resolvedOffsetX = offsetX or 12
	local padding = parent:FindFirstChildOfClass("UIPadding")
	if padding ~= nil then
		resolvedOffsetX -= padding.PaddingLeft.Offset
	end
	local icon = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Name = "VectorIcon",
		Position = UDim2.new(0, resolvedOffsetX, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = parent.ZIndex + 1,
	}, parent) :: Frame
	if parent:GetAttribute("StagewrightIconOnly") == true then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end
	local zIndex = icon.ZIndex + 1
	if kind == "menu" then
		for _, y in { 5, 10, 15 } do
			Toolbar.iconLine(icon, 10, y, 16, 2, 0, color, zIndex)
		end
	elseif kind == "chevron" then
		Toolbar.iconLine(icon, 7.5, 9, 7, 2, 45, color, zIndex)
		Toolbar.iconLine(icon, 12.5, 9, 7, 2, -45, color, zIndex)
	elseif kind == "undo" or kind == "redo" then
		local mirrored = kind == "redo"
		local direction = if mirrored then -1 else 1
		local headX = if mirrored then 15 else 5
		Toolbar.iconLine(icon, headX, 7, 7, 2, 45 * direction, color, zIndex)
		Toolbar.iconLine(icon, headX, 7, 7, 2, -45 * direction, color, zIndex)
		Toolbar.iconLine(icon, 10, 7, 10, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, if mirrored then 4 else 16, 11, 8, 2, 90, color, zIndex)
		Toolbar.iconLine(icon, 10, 15, 10, 2, 0, color, zIndex)
	elseif kind == "select" then
		Toolbar.iconLine(icon, 7, 8, 15, 2, 63, color, zIndex)
		Toolbar.iconLine(icon, 10, 5, 10, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, 5, 10, 10, 2, 90, color, zIndex)
		Toolbar.iconLine(icon, 13, 14, 7, 2, 48, color, zIndex)
	elseif kind == "pan" then
		local palm = create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.fromOffset(9, 9),
			ZIndex = zIndex,
		}, icon) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 3) }, palm)
		for x = 6, 12, 2 do
			Toolbar.iconLine(icon, x, 6, 2, 9, 0, color, zIndex)
		end
		Toolbar.iconLine(icon, 4, 11, 7, 2, 55, color, zIndex)
	elseif kind == "spawn" or kind == "junction" or kind == "goal" then
		Toolbar.iconDot(icon, 10, 10, 15, color, zIndex, true)
		Toolbar.iconDot(icon, 10, 10, if kind == "goal" then 5 else 4, color, zIndex, false)
		if kind == "spawn" then
			Toolbar.iconLine(icon, 10, 2, 5, 2, 90, color, zIndex)
			Toolbar.iconLine(icon, 18, 10, 5, 2, 0, color, zIndex)
			Toolbar.iconLine(icon, 10, 18, 5, 2, 90, color, zIndex)
			Toolbar.iconLine(icon, 2, 10, 5, 2, 0, color, zIndex)
		end
	elseif kind == "connect" then
		Toolbar.iconLine(icon, 10, 10, 15, 2, -42, color, zIndex)
		Toolbar.iconDot(icon, 4, 16, 4, color, zIndex, true)
		Toolbar.iconDot(icon, 16, 4, 4, color, zIndex, true)
	elseif kind == "split" then
		Toolbar.iconLine(icon, 5, 15, 9, 2, -45, color, zIndex)
		Toolbar.iconLine(icon, 12, 8, 9, 2, -45, color, zIndex)
		Toolbar.iconLine(icon, 12, 8, 9, 2, 45, color, zIndex)
		Toolbar.iconDot(icon, 4, 16, 3, color, zIndex, false)
		Toolbar.iconDot(icon, 16, 4, 3, color, zIndex, false)
		Toolbar.iconDot(icon, 16, 12, 3, color, zIndex, false)
	elseif kind == "world" then
		Toolbar.iconDot(icon, 10, 10, 15, color, zIndex, true)
		Toolbar.iconLine(icon, 10, 10, 14, 1, 0, color, zIndex)
		Toolbar.iconLine(icon, 10, 10, 14, 1, 90, color, zIndex)
		Toolbar.iconDot(icon, 10, 10, 3, color, zIndex, false)
	elseif kind == "logic" then
		for _, point in { Vector2.new(4, 5), Vector2.new(15, 5), Vector2.new(10, 15) } do
			local box = create("Frame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(point.X - 2, point.Y - 2),
				Size = UDim2.fromOffset(5, 5),
				ZIndex = zIndex,
			}, icon) :: Frame
			create("UIStroke", { Color = color, Thickness = 1.3 }, box)
		end
		Toolbar.iconLine(icon, 9, 6, 8, 1, 0, color, zIndex)
		Toolbar.iconLine(icon, 7, 10, 9, 1, 55, color, zIndex)
		Toolbar.iconLine(icon, 13, 10, 9, 1, -55, color, zIndex)
	elseif kind == "fit" then
		Toolbar.iconLine(icon, 4, 4, 7, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, 4, 4, 7, 2, 90, color, zIndex)
		Toolbar.iconLine(icon, 16, 4, 7, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, 16, 4, 7, 2, 90, color, zIndex)
		Toolbar.iconLine(icon, 4, 16, 7, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, 4, 16, 7, 2, 90, color, zIndex)
		Toolbar.iconLine(icon, 16, 16, 7, 2, 0, color, zIndex)
		Toolbar.iconLine(icon, 16, 16, 7, 2, 90, color, zIndex)
	elseif kind == "warning" then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Size = UDim2.fromScale(1, 1),
			Text = "!",
			TextColor3 = color,
			TextSize = 18,
			ZIndex = zIndex,
		}, icon)
		create("UIStroke", { Color = color, Thickness = 1.2 }, icon)
		create("UICorner", { CornerRadius = UDim.new(0, 5) }, icon)
	elseif kind == "check" then
		Toolbar.iconLine(icon, 7, 12, 7, 2, 45, color, zIndex)
		Toolbar.iconLine(icon, 13, 9, 11, 2, -48, color, zIndex)
	end
	return icon
end

function Toolbar.styleIconButton(result: TextButton, label: string, iconKind: string, iconColor: Color3?)
	result:SetAttribute("StagewrightIconOnly", false)
	result.Text = label
	result.Font = Enum.Font.BuilderSansMedium
	result.TextColor3 = COLORS.text
	result.TextSize = 13
	result.TextXAlignment = Enum.TextXAlignment.Left
	local padding = paddingFor(result)
	padding.PaddingLeft = UDim.new(0, Theme.metrics.iconButtonTextPaddingLeft)
	padding.PaddingRight = UDim.new(0, Theme.metrics.iconButtonTextPaddingRight)
	Toolbar.addVectorIcon(result, iconKind, iconColor or COLORS.muted, Theme.metrics.iconInset)
end

function Toolbar.styleIconOnlyButton(result: TextButton, label: string, iconKind: string, iconColor: Color3?)
	result:SetAttribute("StagewrightIconOnly", true)
	result.Name = if result.Name == "TextButton" then `{label}Button` else result.Name
	result.Text = ""
	result.TextXAlignment = Enum.TextXAlignment.Center
	local padding = paddingFor(result)
	padding.PaddingLeft = UDim.new(0, 0)
	padding.PaddingRight = UDim.new(0, 0)
	local icon = Toolbar.addVectorIcon(result, iconKind, iconColor or COLORS.muted, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
end

function Toolbar.setNavigationSelected(result: TextButton, selected: boolean)
	result.BackgroundColor3 = if selected then COLORS.accentMuted else COLORS.panel
	result.TextColor3 = if selected then Color3.fromRGB(45, 181, 255) else COLORS.text
	local stroke = result:FindFirstChild("Outline")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = if selected then Color3.fromRGB(0, 91, 145) else COLORS.border
	end
end

return table.freeze(Toolbar)

--!strict

local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors

local Factory = {}

function Factory.create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

function Factory.button(parent: Instance, text: string, width: number?, callback: (() -> ())?): TextButton
	local result = Factory.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		LayoutOrder = #parent:GetChildren() + 1,
		Size = UDim2.fromOffset(width or 110, 30),
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent) :: TextButton
	Factory.create("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.cornerRadius) }, result)
	local stroke = Factory.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Name = "Outline",
		Color = COLORS.border,
		Thickness = 1,
	}, result) :: UIStroke
	local restingBackground: Color3? = nil
	local restingStroke: Color3? = nil
	result.MouseEnter:Connect(function()
		local background = result.BackgroundColor3
		if
			result.Active
			and (background == COLORS.field or background == COLORS.surface or background == COLORS.panel)
		then
			restingBackground = background
			restingStroke = stroke.Color
			result.BackgroundColor3 = COLORS.hover
			stroke.Color = COLORS.borderStrong
		end
	end)
	result.MouseLeave:Connect(function()
		if result.BackgroundColor3 == COLORS.hover and restingBackground ~= nil then
			result.BackgroundColor3 = restingBackground
			stroke.Color = restingStroke or COLORS.border
		end
		restingBackground = nil
		restingStroke = nil
	end)
	if callback ~= nil then
		result.Activated:Connect(callback)
	end
	return result
end

function Factory.sectionLabel(parent: Instance, text: string, order: number?): TextLabel
	return Factory.create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		LayoutOrder = order or 0,
		Size = UDim2.new(1, -8, 0, 22),
		Text = string.upper(text),
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
end

function Factory.setSelected(result: TextButton, selected: boolean)
	result.BackgroundColor3 = if selected then COLORS.accent else COLORS.field
	local stroke = result:FindFirstChild("Outline")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = if selected then Color3.fromRGB(123, 174, 245) else COLORS.border
	end
end

return table.freeze(Factory)

--!strict

local TweenService = game:GetService("TweenService")

local Theme =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").Theme)

local UIFactory = {}

local function corner(parent: Instance, radius: UDim?)
	local object = Instance.new("UICorner")
	object.CornerRadius = radius or Theme.radius.medium
	object.Parent = parent
end

local function stroke(parent: Instance, transparency: number?)
	local object = Instance.new("UIStroke")
	object.Color = Theme.colors.stroke
	object.Transparency = transparency or 0.45
	object.Thickness = 1.5
	object.Parent = parent
end

local function padding(parent: Instance, value: number)
	local object = Instance.new("UIPadding")
	object.PaddingTop = UDim.new(0, value)
	object.PaddingBottom = UDim.new(0, value)
	object.PaddingLeft = UDim.new(0, value)
	object.PaddingRight = UDim.new(0, value)
	object.Parent = parent
end

function UIFactory.frame(parent: Instance, name: string, properties: any?): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundColor3 = Theme.colors.surface
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	object.Parent = parent
	return object
end

function UIFactory.card(parent: Instance, name: string, properties: any?): Frame
	local object = UIFactory.frame(parent, name, properties)
	corner(object)
	stroke(object)
	return object
end

function UIFactory.label(parent: Instance, text: string, properties: any?): TextLabel
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.FontFace = Theme.font
	object.Text = text
	object.TextColor3 = Theme.colors.text
	object.TextSize = 18
	object.TextWrapped = true
	object.TextXAlignment = Enum.TextXAlignment.Left
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	object.Parent = parent
	return object
end

function UIFactory.button(
	parent: Instance,
	text: string,
	onActivated: (() -> ())?,
	properties: any?
): TextButton
	local object = Instance.new("TextButton")
	object.AutoButtonColor = false
	object.BackgroundColor3 = Theme.colors.primary
	object.BorderSizePixel = 0
	object.FontFace = Theme.fontBold
	object.Text = text
	object.TextColor3 = Theme.colors.text
	object.TextSize = 16
	object.TextWrapped = true
	object.Selectable = true
	object.Size = UDim2.new(1, 0, 0, Theme.touchTarget)
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	corner(object, Theme.radius.small)
	stroke(object, 0.7)
	object.MouseEnter:Connect(function()
		TweenService:Create(object, TweenInfo.new(0.12), { BackgroundColor3 = Theme.colors.secondary }):Play()
	end)
	object.MouseLeave:Connect(function()
		TweenService:Create(object, TweenInfo.new(0.12), { BackgroundColor3 = Theme.colors.primary }):Play()
	end)
	if onActivated then
		object.Activated:Connect(onActivated)
	end
	object.Parent = parent
	return object
end

function UIFactory.textBox(parent: Instance, placeholder: string, properties: any?): TextBox
	local object = Instance.new("TextBox")
	object.BackgroundColor3 = Theme.colors.background
	object.BorderSizePixel = 0
	object.ClearTextOnFocus = false
	object.FontFace = Theme.font
	object.PlaceholderText = placeholder
	object.PlaceholderColor3 = Theme.colors.textMuted
	object.Text = ""
	object.TextColor3 = Theme.colors.text
	object.TextSize = 16
	object.TextWrapped = true
	object.Size = UDim2.new(1, 0, 0, Theme.touchTarget)
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	corner(object, Theme.radius.small)
	stroke(object)
	padding(object, Theme.spacing.sm)
	object.Parent = parent
	return object
end

function UIFactory.list(parent: Instance, paddingPixels: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, paddingPixels or Theme.spacing.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

function UIFactory.scroll(parent: Instance, name: string, properties: any?): ScrollingFrame
	local object = Instance.new("ScrollingFrame")
	object.Name = name
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.AutomaticCanvasSize = Enum.AutomaticSize.Y
	object.CanvasSize = UDim2.new()
	object.ScrollBarThickness = 6
	object.ScrollBarImageColor3 = Theme.colors.primary
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	object.Parent = parent
	return object
end

function UIFactory.addPadding(parent: Instance, value: number)
	padding(parent, value)
end

function UIFactory.addCorner(parent: Instance, radius: UDim?)
	corner(parent, radius)
end

function UIFactory.formatNumber(value: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local absolute = math.abs(value)
	local index = 1
	while absolute >= 1000 and index < #suffixes do
		absolute /= 1000
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	return `{string.format("%.1f", value)}{suffixes[index]}`
end

return UIFactory

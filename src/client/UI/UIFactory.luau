--!strict

local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").Theme)

local UIFactory = {}

local function hoverTweenInfo(): TweenInfo
	return TweenInfo.new(if GuiService.ReducedMotionEnabled then 0 else 0.12)
end

local function authoredTemplate(parent: Instance, name: string): Instance?
	local screenGui = parent:FindFirstAncestorWhichIsA("ScreenGui")
	if not screenGui then
		return nil
	end
	local root = screenGui:FindFirstChild("Root")
	local templates = if root then root:FindFirstChild("ComponentTemplates") else nil
	return if templates then templates:FindFirstChild(name) else nil
end

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
	local template = authoredTemplate(parent, "LabelTemplate")
	local object = if template and template:IsA("TextLabel")
		then template:Clone()
		else Instance.new("TextLabel")
	if not template then
		object.BackgroundTransparency = 1
		object.BorderSizePixel = 0
		object.FontFace = Theme.font
		object.TextColor3 = Theme.colors.text
		object.TextSize = 18
		object.TextWrapped = true
		object.TextXAlignment = Enum.TextXAlignment.Left
	end
	object.Visible = true
	object.Text = text
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
	local template = authoredTemplate(parent, "ButtonTemplate")
	local object = if template and template:IsA("TextButton")
		then template:Clone()
		else Instance.new("TextButton")
	if not template then
		object.AutoButtonColor = false
		object.BackgroundColor3 = Theme.colors.primary
		object.BorderSizePixel = 0
		object.FontFace = Theme.fontBold
		object.TextColor3 = Theme.colors.text
		object.TextSize = 16
		object.TextWrapped = true
		object.Selectable = true
		object.Size = UDim2.new(1, 0, 0, Theme.touchTarget)
		corner(object, Theme.radius.small)
		stroke(object, 0.7)
	end
	object.Visible = true
	object.Text = text
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
	local restingColor = object.BackgroundColor3
	object.MouseEnter:Connect(function()
		TweenService:Create(object, hoverTweenInfo(), { BackgroundColor3 = Theme.colors.secondary }):Play()
	end)
	object.MouseLeave:Connect(function()
		TweenService:Create(object, hoverTweenInfo(), { BackgroundColor3 = restingColor }):Play()
	end)
	if onActivated then
		object.Activated:Connect(onActivated)
	end
	object.Parent = parent
	return object
end

function UIFactory.textBox(parent: Instance, placeholder: string, properties: any?): TextBox
	local template = authoredTemplate(parent, "TextBoxTemplate")
	local object = if template and template:IsA("TextBox") then template:Clone() else Instance.new("TextBox")
	if not template then
		object.BackgroundColor3 = Theme.colors.background
		object.BorderSizePixel = 0
		object.ClearTextOnFocus = false
		object.FontFace = Theme.font
		object.PlaceholderColor3 = Theme.colors.textMuted
		object.TextColor3 = Theme.colors.text
		object.TextSize = 16
		object.TextWrapped = true
		object.Size = UDim2.new(1, 0, 0, Theme.touchTarget)
		corner(object, Theme.radius.small)
		stroke(object)
		padding(object, Theme.spacing.sm)
	end
	object.Visible = true
	object.PlaceholderText = placeholder
	object.Text = ""
	if properties then
		for key, value in properties do
			(object :: any)[key] = value
		end
	end
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

--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "TemplateLoading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.BackgroundColor3 = Color3.fromRGB(22, 25, 42)
background.BorderSizePixel = 0
background.Size = UDim2.fromScale(1, 1)
background.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.BackgroundTransparency = 1
title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
title.Position = UDim2.fromScale(0.5, 0.43)
title.Size = UDim2.new(0.9, 0, 0, 60)
title.Text = "ROBLOX TEMPLATE"
title.TextColor3 = Color3.fromRGB(248, 249, 255)
title.TextScaled = true
title.Parent = background

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0)
status.BackgroundTransparency = 1
status.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
status.Position = UDim2.fromScale(0.5, 0.52)
status.Size = UDim2.new(0.8, 0, 0, 30)
status.Text = "Loading systems…"
status.TextColor3 = Color3.fromRGB(180, 187, 218)
status.TextSize = 18
status.Parent = background

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.BackgroundColor3 = Color3.fromRGB(41, 45, 73)
bar.BorderSizePixel = 0
bar.Position = UDim2.fromScale(0.5, 0.59)
bar.Size = UDim2.new(0.7, 0, 0, 12)
bar.Parent = background
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar
local fill = Instance.new("Frame")
fill.BackgroundColor3 = Color3.fromRGB(80, 135, 255)
fill.BorderSizePixel = 0
fill.Size = UDim2.fromScale(0.08, 1)
fill.Parent = bar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

TweenService:Create(fill, TweenInfo.new(1.2), { Size = UDim2.fromScale(0.75, 1) }):Play()
local deadline = os.clock() + 10
while
	(not game:IsLoaded() or ReplicatedStorage:FindFirstChild("TemplateRemotes") == nil)
	and os.clock() < deadline
do
	task.wait(0.1)
end
status.Text = "Ready"
TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 1) }):Play()
task.wait(0.25)
TweenService:Create(background, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
for _, descendant in background:GetDescendants() do
	if descendant:IsA("TextLabel") then
		TweenService:Create(descendant, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
	elseif descendant:IsA("Frame") then
		TweenService:Create(descendant, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.35)
gui:Destroy()

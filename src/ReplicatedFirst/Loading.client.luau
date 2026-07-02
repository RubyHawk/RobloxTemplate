--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
-- A place without the authored loading pack keeps Roblox's default loading
-- screen; never park this thread forever on a missing ScreenGui.
local gui = playerGui:WaitForChild("TemplateLoading", 15)
if gui == nil or not gui:IsA("ScreenGui") then
	return
end

local background = gui:WaitForChild("Background") :: Frame
local card = background:WaitForChild("Card") :: Frame
local status = card:WaitForChild("Status") :: TextLabel
local bar = card:WaitForChild("ProgressTrack") :: Frame
local fill = bar:WaitForChild("Fill") :: Frame

ReplicatedFirst:RemoveDefaultLoadingScreen()
gui.Enabled = true

TweenService:Create(fill, TweenInfo.new(1.2), { Size = UDim2.fromScale(0.75, 1) }):Play()
local minimumVisibleUntil = os.clock() + 1.4
local deadline = os.clock() + 10
while
	(
		os.clock() < minimumVisibleUntil
		or not game:IsLoaded()
		or ReplicatedStorage:FindFirstChild("TemplateRemotes") == nil
	) and os.clock() < deadline
do
	task.wait(0.1)
end
status.Text = "READY!"
TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 1) }):Play()
task.wait(0.25)

for _, descendant in background:GetDescendants() do
	if descendant:IsA("TextLabel") then
		TweenService:Create(descendant, TweenInfo.new(0.25), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	elseif descendant:IsA("Frame") then
		TweenService:Create(descendant, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	elseif descendant:IsA("UIStroke") then
		TweenService:Create(descendant, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end
end
TweenService:Create(background, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
task.wait(0.35)
gui.Enabled = false

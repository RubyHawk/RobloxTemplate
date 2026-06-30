--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EconomyService = require(ServerScriptService:WaitForChild("TemplateServer").Services.EconomyService)

local pad = Instance.new("Part")
pad.Name = "ExampleEarningPad"
pad.Anchored = true
pad.CanCollide = true
pad.Color = Color3.fromRGB(80, 135, 255)
pad.Material = Enum.Material.Neon
pad.Position = Vector3.new(0, 1, -18)
pad.Size = Vector3.new(12, 1, 12)
pad.Parent = Workspace

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Earn 10 Coins"
prompt.ObjectText = "Template Demo"
prompt.HoldDuration = 0.25
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Parent = pad

local billboard = Instance.new("BillboardGui")
billboard.Name = "StarterSign"
billboard.AlwaysOnTop = true
billboard.Size = UDim2.fromOffset(320, 80)
billboard.StudsOffset = Vector3.new(0, 5, 0)
billboard.Parent = pad

local label = Instance.new("TextLabel")
label.BackgroundColor3 = Color3.fromRGB(22, 25, 42)
label.BackgroundTransparency = 0.1
label.BorderSizePixel = 0
label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
label.Size = UDim2.fromScale(1, 1)
label.Text = "PLAYABLE STARTER\nUse the prompt to exercise the template economy"
label.TextColor3 = Color3.fromRGB(248, 249, 255)
label.TextScaled = true
label.TextWrapped = true
label.Parent = billboard
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = label

local lastAwardAt: { [Player]: number } = {}
prompt.Triggered:Connect(function(player)
	local now = os.clock()
	if now - (lastAwardAt[player] or 0) < 1 then
		return
	end
	lastAwardAt[player] = now
	EconomyService.award(player, 10, "starter:earning-pad")
end)

Players.PlayerRemoving:Connect(function(player)
	lastAwardAt[player] = nil
end)

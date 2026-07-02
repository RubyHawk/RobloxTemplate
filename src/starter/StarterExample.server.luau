--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)
local EconomyService = require(ServerScriptService:WaitForChild("TemplateServer").Services.EconomyService)

local pad = Workspace:WaitForChild("ExampleEarningPad")
assert(pad:IsA("BasePart"), "Workspace.ExampleEarningPad must be an authored BasePart")
local prompt = pad:WaitForChild("EarnPrompt")
assert(prompt:IsA("ProximityPrompt"), "ExampleEarningPad.EarnPrompt must be an authored ProximityPrompt")
prompt.ActionText = `Earn 10 {Config.economy.primaryCurrency}`
prompt.ObjectText = `{Config.economy.primaryCurrency} Trainer`

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

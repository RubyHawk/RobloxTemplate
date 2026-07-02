--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)
local EconomyService = require(ServerScriptService:WaitForChild("TemplateServer").Services.EconomyService)

local lastAwardAt: { [Player]: { [string]: number } } = {}

local function findPad(padName: string, promptName: string): (BasePart?, ProximityPrompt?)
	local pad = Workspace:WaitForChild(padName, 10)
	if pad == nil or not pad:IsA("BasePart") then
		return nil, nil
	end
	local prompt = pad:WaitForChild(promptName, 10)
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		return nil, nil
	end
	return pad, prompt
end

local function allowAward(player: Player, padKey: string): boolean
	local now = os.clock()
	local perPad = lastAwardAt[player]
	if perPad == nil then
		perPad = {}
		lastAwardAt[player] = perPad
	end
	if now - (perPad[padKey] or 0) < 1 then
		return false
	end
	perPad[padKey] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastAwardAt[player] = nil
end)

local _, earnPrompt = findPad("ExampleEarningPad", "EarnPrompt")
if earnPrompt then
	earnPrompt.ActionText = `Earn 10 {Config.economy.primaryCurrency}`
	earnPrompt.ObjectText = `{Config.economy.primaryCurrency} Trainer`
	earnPrompt.Triggered:Connect(function(player)
		if allowAward(player, "primary") then
			EconomyService.award(player, 10, "starter:earning-pad")
		end
	end)
else
	warn("Workspace.ExampleEarningPad is missing; rebuild the playable place to restore its demo")
end

local bonusPad, bonusPrompt = findPad("BonusEarningPad", "BonusPrompt")
if bonusPad == nil or bonusPrompt == nil then
	warn("Workspace.BonusEarningPad is missing; rebuild the playable place to demo a second currency")
elseif #Config.economy.currencies >= 2 then
	local bonusCurrency = Config.economy.currencies[2]
	bonusPrompt.ActionText = `Earn 5 {bonusCurrency.name}`
	bonusPrompt.ObjectText = `{bonusCurrency.name} Trainer`
	bonusPrompt.Triggered:Connect(function(player)
		if allowAward(player, "bonus") then
			EconomyService.awardCurrencyRaw(player, bonusCurrency.id, 5, "starter:bonus-pad")
		end
	end)
else
	bonusPrompt.Enabled = false
	bonusPad.Transparency = 1
	bonusPad.CanCollide = false
	bonusPad.CanQuery = false
	bonusPad.CanTouch = false
end

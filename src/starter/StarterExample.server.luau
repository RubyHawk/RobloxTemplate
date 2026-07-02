--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)
local EconomyService = require(ServerScriptService:WaitForChild("TemplateServer").Services.EconomyService)

local lastAwardAt: { [Player]: { [string]: number } } = {}

local function bindPad(padName: string, promptName: string): (BasePart, ProximityPrompt)
	local pad = Workspace:WaitForChild(padName)
	assert(pad:IsA("BasePart"), `Workspace.{padName} must be an authored BasePart`)
	local prompt = pad:WaitForChild(promptName)
	assert(prompt:IsA("ProximityPrompt"), `{padName}.{promptName} must be an authored ProximityPrompt`)
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

local _, earnPrompt = bindPad("ExampleEarningPad", "EarnPrompt")
earnPrompt.ActionText = `Earn 10 {Config.economy.primaryCurrency}`
earnPrompt.ObjectText = `{Config.economy.primaryCurrency} Trainer`
earnPrompt.Triggered:Connect(function(player)
	if allowAward(player, "primary") then
		EconomyService.award(player, 10, "starter:earning-pad")
	end
end)

-- The bonus pad makes a multi-currency recipe provable in Play mode: it pays
-- the second configured currency directly (no earnings multiplier; that bonus
-- only applies to the primary currency). Single-currency recipes hide it.
local bonusPad, bonusPrompt = bindPad("BonusEarningPad", "BonusPrompt")
if #Config.economy.currencies >= 2 then
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

Players.PlayerRemoving:Connect(function(player)
	lastAwardAt[player] = nil
end)

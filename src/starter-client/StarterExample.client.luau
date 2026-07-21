--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Config = require(Template:WaitForChild("Shared").TemplateConfig)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- The earning trainer is lobby-only. Stop before its unbounded world wait so a
-- streamed reserved dungeon never carries an unrelated sign/controller.
if Template:GetAttribute("RuntimeMode") == "dungeon" then
	local function disableStarterSign(instance: Instance)
		if instance.Name == "StarterSignUI" and instance:IsA("BillboardGui") then
			instance.Enabled = false
		end
	end
	for _, instance in playerGui:GetChildren() do
		disableStarterSign(instance)
	end
	playerGui.ChildAdded:Connect(disableStarterSign)
	return
end

local sign = playerGui:WaitForChild("StarterSignUI", 10)
if sign == nil or not sign:IsA("BillboardGui") then
	warn(
		"StarterGui.StarterSignUI is missing; rebuild the place from bootstrap.project.json to show the pad sign"
	)
	return
end

local pad = Workspace:WaitForChild("ExampleEarningPad")
assert(pad:IsA("BasePart"), "Workspace.ExampleEarningPad must be an authored BasePart")

sign.Adornee = pad
sign.Enabled = true

local card = sign:WaitForChild("Card") :: Frame
local header = card:WaitForChild("Header") :: Frame
local title = header:WaitForChild("Title") :: TextLabel
local reward = card:WaitForChild("Reward") :: Frame
local amount = reward:WaitForChild("Amount") :: TextLabel
title.Text = string.upper(`{Config.economy.primaryCurrency} TRAINER`)
amount.Text = string.upper(`+10 {Config.economy.primaryCurrency}`)

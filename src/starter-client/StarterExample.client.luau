--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
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

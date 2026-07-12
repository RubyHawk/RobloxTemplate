--!strict

-- Map-side wiring for the rune altar demo: hands the authored circle part to
-- the reusable RuneService. All roll decisions stay inside the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)
local RuneService = require(ServerScriptService:WaitForChild("TemplateServer").Services.RuneService)

if Config.features.runes ~= true then
	return
end

local circleModel = Workspace:WaitForChild("RuneCircle", 10)
if circleModel == nil then
	warn("Workspace.RuneCircle is missing; rebuild the playable place to restore the rune altar")
	return
end

local platform = circleModel:WaitForChild("Platform", 10)
if platform == nil or not platform:IsA("BasePart") then
	warn("Workspace.RuneCircle.Platform must be an authored BasePart")
	return
end

RuneService.registerCircle(platform)

--!strict

-- Map-side wiring for the dungeon portal: hands the authored pad platform to the
-- reusable PortalService. All occupancy, party, and teleport authority stays in
-- the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)
local PortalService = require(ServerScriptService:WaitForChild("TemplateServer").Services.PortalService)

if Config.features.dungeon ~= true then
	return
end

local padModel = Workspace:WaitForChild("PortalPad", 10)
if padModel == nil then
	warn("Workspace.PortalPad is missing; rebuild the playable place to restore the dungeon portal")
	return
end

local platform = padModel:WaitForChild("Platform", 10)
if platform == nil or not platform:IsA("BasePart") then
	warn("Workspace.PortalPad.Platform must be an authored BasePart")
	return
end

PortalService.registerPad(platform)

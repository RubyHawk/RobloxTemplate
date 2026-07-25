--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local LegacyGalleryCleanup = {}

local CLEANUP_ATTRIBUTE = "StagewrightGalleryCleanupVersion"
local CLEANUP_VERSION = 1
local started = false

local function designerConfig(): any?
	local template = ReplicatedStorage:FindFirstChild("Template")
	local shared = if template ~= nil then template:FindFirstChild("Shared") else nil
	local source = if shared ~= nil then shared:FindFirstChild("DesignerConfig") else nil
	if source == nil or not source:IsA("ModuleScript") then
		return nil
	end
	local clone = source:Clone()
	clone.Name = "DesignerConfigCleanupProbe"
	clone.Parent = script
	local success, result = pcall(require, clone)
	clone:Destroy()
	return if success and type(result) == "table" then result else nil
end

local function optedIn(config: any): boolean
	local identity = if type(config) == "table" then config.identity else nil
	return type(identity) == "table"
		and type(identity.placeId) == "number"
		and identity.placeId > 0
		and identity.placeId == game.PlaceId
		and config.cleanupLegacyGalleryArtifacts == true
end

local function closeEnough(left: number, right: number): boolean
	return math.abs(left - right) <= 0.05
end

local function isGalleryGridPlatform(candidate: Instance?): boolean
	if candidate == nil or not candidate:IsA("Model") or candidate.Name ~= "GamePlatform" then
		return false
	end
	local base = candidate:FindFirstChild("PlatformBase")
	local origin = candidate:FindFirstChild("PlatformOrigin")
	local columns = candidate:FindFirstChild("Columns")
	local rows = candidate:FindFirstChild("Rows")
	local cellSize = candidate:FindFirstChild("CellSize")
	local cellMap = candidate:FindFirstChild("CellMap")
	return base ~= nil
		and base:IsA("BasePart")
		and closeEnough(base.Size.X, 128)
		and closeEnough(base.Size.Y, 0.24)
		and closeEnough(base.Size.Z, 108)
		and origin ~= nil
		and origin:IsA("BasePart")
		and columns ~= nil
		and columns:IsA("IntValue")
		and columns.Value == 32
		and rows ~= nil
		and rows:IsA("IntValue")
		and rows.Value == 27
		and cellSize ~= nil
		and cellSize:IsA("IntValue")
		and cellSize.Value == 4
		and cellMap ~= nil
		and cellMap:IsA("Folder")
end

local function addExact(candidates: { Instance }, parent: Instance?, name: string)
	local candidate = if parent ~= nil then parent:FindFirstChild(name) else nil
	if candidate ~= nil then
		table.insert(candidates, candidate)
	end
end

local function cleanup(): boolean
	local config = designerConfig()
	if not optedIn(config) then
		return false
	end

	local candidates: { Instance } = {}
	addExact(candidates, ServerScriptService, "PlayableStarter")
	addExact(candidates, StarterPlayer.StarterPlayerScripts, "PlayableStarterClient")
	addExact(candidates, ReplicatedFirst, "Loading")
	for _, name in
		{
			"GalleryMenu",
			"GalleryBackdrop",
			"ZxglyV5Showroom",
			"NotificationV2Showroom",
		}
	do
		addExact(candidates, StarterGui, name)
	end
	for _, name in
		{
			"TemplateSpawn",
			"GalleryFloor",
			"ExampleEarningPad",
			"BonusEarningPad",
		}
	do
		addExact(candidates, Workspace, name)
	end

	-- AuthoringArea.ensure moves the only useful legacy grid to the remote admin
	-- island first. Delete a second, exact demo-shaped copy only when that
	-- preserved authoring source already exists.
	local adminArea = Workspace:FindFirstChild("StagewrightAdminArea")
	local adminPlatform = if adminArea ~= nil then adminArea:FindFirstChild("GamePlatform") else nil
	local firstIsland = Workspace:FindFirstChild("FirstPrivateIsland")
	local islandPlatform = if firstIsland ~= nil then firstIsland:FindFirstChild("GamePlatform") else nil
	if adminPlatform ~= nil and adminPlatform:IsA("Model") and isGalleryGridPlatform(islandPlatform) then
		table.insert(candidates, islandPlatform :: Instance)
	end

	if #candidates == 0 then
		Workspace:SetAttribute(CLEANUP_ATTRIBUTE, CLEANUP_VERSION)
		return true
	end
	local recording = ChangeHistoryService:TryBeginRecording(
		"Clean RNG Defender gallery artifacts",
		"Remove objects left by an accidental gallery Rojo sync"
	)
	if recording == nil then
		warn("Stagewright could not begin the gallery cleanup undo recording")
		return true
	end
	for _, candidate in candidates do
		if candidate.Parent ~= nil then
			candidate:Destroy()
		end
	end
	Workspace:SetAttribute(CLEANUP_ATTRIBUTE, CLEANUP_VERSION)
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	print(`Stagewright removed {#candidates} gallery demo root(s) from this place.`)
	return true
end

function LegacyGalleryCleanup.start()
	if started or RunService:IsRunning() then
		return
	end
	started = true
	if cleanup() then
		return
	end
	task.spawn(function()
		-- The local plugin commonly starts before the guarded Rojo patch finishes
		-- attaching. Retry until the exact-place DesignerConfig arrives.
		for _ = 1, 240 do
			task.wait(0.5)
			if RunService:IsRunning() or cleanup() then
				return
			end
		end
	end)
end

return table.freeze(LegacyGalleryCleanup)

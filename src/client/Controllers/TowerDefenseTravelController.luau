--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("TemplateConfig"))
local StageCatalog = require(Shared:WaitForChild("StageCatalog"))

type Request = (action: string, payload: any, audioCue: string?) -> ()

local TowerDefenseTravelController = {}
local initialized = false
local DUNGEON_PRESENTATION_ATTRIBUTE = "DungeonPresentationActive"
local TOWER_PLATFORM_PRESENTATION_ATTRIBUTE = "TowerPlatformPresentationActive"
local REFRESH_INTERVAL = 0.25

local function setTowerPlatformPresentationActive(player: Player, active: boolean)
	if player:GetAttribute(TOWER_PLATFORM_PRESENTATION_ATTRIBUTE) ~= active then
		player:SetAttribute(TOWER_PLATFORM_PRESENTATION_ATTRIBUTE, active)
	end
end

local function platformSlot(player: Player): number?
	local value = player:GetAttribute("TowerDefensePlatformSlot")
	if
		type(value) == "number"
		and value % 1 == 0
		and value >= 1
		and value <= Config.towerDefense.platformSlotCount
	then
		return value
	end
	return nil
end

local function platformOrigin(slot: number): CFrameValue?
	local origins = Template:FindFirstChild(Config.towerDefense.platformOriginsFolderName)
	if origins == nil or not origins:IsA("Folder") then
		return nil
	end
	local value = origins:FindFirstChild(`Slot_{string.format("%02d", slot)}`)
	return if value ~= nil and value:IsA("CFrameValue") then value else nil
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function isOnOwnPlayableIsland(player: Player, slot: number): boolean?
	local origin = platformOrigin(slot)
	local root = characterRoot(player)
	if origin == nil or root == nil then
		return nil
	end
	local activeStageId = origin:GetAttribute("ActiveStageId")
	local stage = if type(activeStageId) == "string" then StageCatalog.get(activeStageId) else nil
	stage = stage or StageCatalog.get(StageCatalog.defaultStageId())
	if stage == nil then
		return nil
	end
	local grid = stage.grid
	local margin = Config.towerDefense.platformTravelPromptMargin
	if type(margin) ~= "number" or margin < 0 or margin > 100 then
		margin = 12
	end
	local localPosition = origin.Value:PointToObjectSpace(root.Position)
	local halfWidth = grid.columns * grid.cellSize * 0.5 + margin
	local halfDepth = grid.rows * grid.cellSize * 0.5 + margin
	return math.abs(localPosition.X) <= halfWidth and math.abs(localPosition.Z) <= halfDepth
end

function TowerDefenseTravelController.initialize(request: Request)
	if initialized or Config.features.towerDefense ~= true then
		return
	end
	initialized = true

	local player = Players.LocalPlayer
	setTowerPlatformPresentationActive(player, false)
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local instance = playerGui:WaitForChild("TowerDefenseTravelHUD", 15)
		if instance == nil or not instance:IsA("ScreenGui") then
			warn("TowerDefenseTravelHUD is missing from StarterGui")
			return
		end
		local panel = instance:WaitForChild("Panel")
		local title = panel:WaitForChild("Title") :: TextLabel
		local status = panel:WaitForChild("Status") :: TextLabel
		local travelButton = panel:WaitForChild("TravelButton") :: TextButton

		local function refresh()
			if player:GetAttribute(DUNGEON_PRESENTATION_ATTRIBUTE) == true then
				setTowerPlatformPresentationActive(player, false)
				instance.Enabled = false
				return
			end
			local slot = platformSlot(player)
			if slot == nil then
				title.Text = "TOWER DEFENSE"
				status.Text = "Waiting for a playable platform..."
				travelButton.Text = "PLATFORM UNAVAILABLE"
				travelButton.Active = false
				travelButton.AutoButtonColor = false
				travelButton.BackgroundColor3 = Color3.fromRGB(78, 91, 104)
				setTowerPlatformPresentationActive(player, false)
				instance.Enabled = false
				return
			end
			title.Text = `YOUR TOWER  •  PLATFORM {string.format("%02d", slot)}`
			status.Text = "Your playable grid is ready"
			travelButton.Text = "GO TO MY TOWER"
			travelButton.Active = true
			travelButton.AutoButtonColor = true
			travelButton.BackgroundColor3 = Color3.fromRGB(45, 187, 118)
			local isOnIsland = isOnOwnPlayableIsland(player, slot)
			setTowerPlatformPresentationActive(player, isOnIsland == true)
			instance.Enabled = isOnIsland == false
		end

		travelButton.Activated:Connect(function()
			if player:GetAttribute(DUNGEON_PRESENTATION_ATTRIBUTE) == true then
				instance.Enabled = false
				return
			end
			local slot = platformSlot(player)
			if slot == nil then
				refresh()
				return
			end
			status.Text = `Moving to Platform {string.format("%02d", slot)}...`
			request("TravelToTowerPlatform", {})
			task.delay(1.25, refresh)
		end)
		player:GetAttributeChangedSignal("TowerDefensePlatformSlot"):Connect(refresh)
		player:GetAttributeChangedSignal(DUNGEON_PRESENTATION_ATTRIBUTE):Connect(refresh)
		refresh()
		local elapsed = 0
		RunService.Heartbeat:Connect(function(deltaTime: number)
			elapsed += deltaTime
			if elapsed >= REFRESH_INTERVAL then
				elapsed = 0
				refresh()
			end
		end)
	end)
end

return table.freeze(TowerDefenseTravelController)

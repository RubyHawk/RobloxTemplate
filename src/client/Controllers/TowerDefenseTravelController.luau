--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Template = ReplicatedStorage:WaitForChild("Template")
local Config = require(Template:WaitForChild("Shared"):WaitForChild("TemplateConfig"))

type Request = (action: string, payload: any, audioCue: string?) -> ()

local TowerDefenseTravelController = {}
local initialized = false

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

function TowerDefenseTravelController.initialize(request: Request)
	if initialized or Config.features.towerDefense ~= true then
		return
	end
	initialized = true

	local player = Players.LocalPlayer
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
			local slot = platformSlot(player)
			if slot == nil then
				title.Text = "TOWER DEFENSE"
				status.Text = "Waiting for a playable platform..."
				travelButton.Text = "PLATFORM UNAVAILABLE"
				travelButton.Active = false
				travelButton.AutoButtonColor = false
				travelButton.BackgroundColor3 = Color3.fromRGB(78, 91, 104)
				return
			end
			title.Text = `YOUR TOWER  •  PLATFORM {string.format("%02d", slot)}`
			status.Text = "Your playable grid is ready"
			travelButton.Text = "GO TO MY TOWER"
			travelButton.Active = true
			travelButton.AutoButtonColor = true
			travelButton.BackgroundColor3 = Color3.fromRGB(45, 187, 118)
		end

		travelButton.Activated:Connect(function()
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
		refresh()
		instance.Enabled = true
	end)
end

return table.freeze(TowerDefenseTravelController)

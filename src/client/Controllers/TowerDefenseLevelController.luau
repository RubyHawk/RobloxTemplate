--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Template = ReplicatedStorage:WaitForChild("Template")
local Config = require(Template:WaitForChild("Shared"):WaitForChild("TemplateConfig"))

type Request = (action: string, payload: any, audioCue: string?) -> ()

type LevelOption = {
	id: string,
	name: string,
	levelNumber: number,
	unlocked: boolean,
}

local TowerDefenseLevelController = {}
local initialized = false
local latestState: any = nil
local levelButtons: { TextButton } = {}
local assignedOptions: { LevelOption? } = {}
local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local rollButton: TextButton? = nil
local autoPlaceButton: TextButton? = nil
local startWaveButton: TextButton? = nil
local resetButton: TextButton? = nil
local localPlayer = Players.LocalPlayer
local DUNGEON_PRESENTATION_ATTRIBUTE = "DungeonPresentationActive"
local TOWER_PLATFORM_PRESENTATION_ATTRIBUTE = "TowerPlatformPresentationActive"

local SELECTED_COLOR = Color3.fromRGB(45, 187, 118)
local AVAILABLE_COLOR = Color3.fromRGB(37, 55, 73)
local LOCKED_COLOR = Color3.fromRGB(54, 62, 72)
local DISABLED_ACTION_COLOR = Color3.fromRGB(63, 73, 84)
local START_COLOR = Color3.fromRGB(45, 187, 118)

local function towerPresentationActive(): boolean
	return localPlayer:GetAttribute(DUNGEON_PRESENTATION_ATTRIBUTE) ~= true
		and localPlayer:GetAttribute(TOWER_PLATFORM_PRESENTATION_ATTRIBUTE) == true
end

local function validLevelOption(value: any): LevelOption?
	if
		type(value) ~= "table"
		or type(value.id) ~= "string"
		or #value.id < 1
		or #value.id > 80
		or type(value.name) ~= "string"
		or type(value.levelNumber) ~= "number"
		or value.levelNumber % 1 ~= 0
		or type(value.unlocked) ~= "boolean"
	then
		return nil
	end
	return value :: LevelOption
end

local function setActionEnabled(button: TextButton?, enabled: boolean, color: Color3)
	if button == nil then
		return
	end
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color else DISABLED_ACTION_COLOR
end

local function refresh()
	local state = latestState
	if screenGui == nil then
		return
	end
	if not towerPresentationActive() then
		screenGui.Enabled = false
		return
	end
	if statusLabel == nil or detailLabel == nil or type(state) ~= "table" then
		return
	end

	local activeStageId = if type(state.activeStageId) == "string" then state.activeStageId else ""
	local options = if type(state.levelOptions) == "table" then state.levelOptions else {}
	local activeName = "No level selected"
	table.clear(assignedOptions)
	for index, button in levelButtons do
		local option = validLevelOption(options[index])
		assignedOptions[index] = option
		button.Visible = option ~= nil
		if option == nil then
			continue
		end
		local isSelected = option.id == activeStageId
		if isSelected then
			activeName = option.name
		end
		button.Text = if option.unlocked
			then `LEVEL {option.levelNumber}`
			else `LEVEL {option.levelNumber}\nLOCKED`
		button.Active = option.unlocked
		button.AutoButtonColor = option.unlocked
		button.BackgroundColor3 = if isSelected
			then SELECTED_COLOR
			elseif option.unlocked then AVAILABLE_COLOR
			else LOCKED_COLOR
		button.TextColor3 = if isSelected
			then Color3.fromRGB(8, 29, 20)
			elseif option.unlocked then Color3.fromRGB(232, 242, 249)
			else Color3.fromRGB(148, 157, 166)
	end

	local wave = if type(state.wave) == "number" then math.max(math.floor(state.wave), 0) else 0
	local waveCount = if type(state.waveCount) == "number"
		then math.max(math.floor(state.waveCount), 0)
		else 0
	local baseHealth = if type(state.baseHealth) == "number"
		then math.max(math.floor(state.baseHealth), 0)
		else 0
	local maxBaseHealth = if type(state.maxBaseHealth) == "number"
		then math.max(math.floor(state.maxBaseHealth), 0)
		else 0
	local enemyCount = if type(state.enemies) == "table" then #state.enemies else 0
	local waveRunning = state.waveRunning == true
	-- An endless set has no last wave, so a denominator would be a lie once the
	-- run loops past it. Show the bare wave number and the loop it belongs to.
	local waveLoop = if type(state.waveLoop) == "number" then math.max(math.floor(state.waveLoop), 1) else 1
	local runComplete = state.runComplete == true
	local waveText = if runComplete
		then `COMPLETE  {wave}/{waveCount}`
		elseif state.waveEndless == false and waveCount > 0 then `WAVE {wave}/{waveCount}`
		elseif waveLoop > 1 then `WAVE {wave}  (LOOP {waveLoop})`
		else `WAVE {wave}`
	statusLabel.Text = `{activeName}  |  {waveText}  |  BASE {baseHealth}/{maxBaseHealth}`
	detailLabel.Text = if runComplete
		then "Level complete - reset to play it again or pick another level"
		elseif waveRunning then `{enemyCount} enemies alive - clear the wave or reset to change levels`
		else "Choose units below, then place manually or auto-place"

	setActionEnabled(rollButton, not waveRunning, Color3.fromRGB(73, 116, 195))
	setActionEnabled(autoPlaceButton, not waveRunning, Color3.fromRGB(72, 132, 196))
	setActionEnabled(startWaveButton, not waveRunning and not runComplete, START_COLOR)
	setActionEnabled(resetButton, true, Color3.fromRGB(168, 73, 81))
	screenGui.Enabled = true
end

function TowerDefenseLevelController.initialize(request: Request)
	if initialized or Config.features.towerDefense ~= true then
		return
	end
	initialized = true
	localPlayer:GetAttributeChangedSignal(DUNGEON_PRESENTATION_ATTRIBUTE):Connect(refresh)
	localPlayer:GetAttributeChangedSignal(TOWER_PLATFORM_PRESENTATION_ATTRIBUTE):Connect(refresh)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local candidate = playerGui:WaitForChild("TowerDefenseLevelHUD", 15)
		if candidate == nil or not candidate:IsA("ScreenGui") then
			warn("TowerDefenseLevelHUD is missing from StarterGui")
			return
		end
		screenGui = candidate
		local panel = candidate:WaitForChild("Panel") :: Frame
		local levels = panel:WaitForChild("Levels") :: Frame
		local actions = panel:WaitForChild("Actions") :: Frame
		statusLabel = panel:WaitForChild("Status") :: TextLabel
		detailLabel = panel:WaitForChild("Detail") :: TextLabel
		rollButton = actions:WaitForChild("RollButton") :: TextButton
		autoPlaceButton = actions:WaitForChild("AutoPlaceButton") :: TextButton
		startWaveButton = actions:WaitForChild("StartWaveButton") :: TextButton
		resetButton = actions:WaitForChild("ResetButton") :: TextButton

		for index = 1, Config.towerDefense.levelSelectorSlots do
			local button = levels:WaitForChild(`Level{string.format("%02d", index)}Button`) :: TextButton
			levelButtons[index] = button
			button.Activated:Connect(function()
				if not towerPresentationActive() then
					return
				end
				local option = assignedOptions[index]
				if option ~= nil and option.unlocked and latestState.waveRunning ~= true then
					request("ActivateTowerStage", { stageId = option.id })
				end
			end)
		end

		rollButton.Activated:Connect(function()
			if not towerPresentationActive() then
				return
			end
			request("RollUnit", {})
		end)
		autoPlaceButton.Activated:Connect(function()
			if not towerPresentationActive() then
				return
			end
			request("AutoPlaceBestUnits", {})
		end)
		startWaveButton.Activated:Connect(function()
			if not towerPresentationActive() then
				return
			end
			request("StartTowerWave", {})
		end)
		resetButton.Activated:Connect(function()
			if not towerPresentationActive() then
				return
			end
			request("ResetTowerDefense", {})
		end)
		refresh()
	end)
end

function TowerDefenseLevelController.apply(state: any)
	latestState = state
	refresh()
end

return table.freeze(TowerDefenseLevelController)

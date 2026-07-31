--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local StageCatalog = require(Shared.StageCatalog)
local TowerDefenseRequest = require(Shared.TowerDefenseRequest)
local TowerDefenseWaves = require(Shared.TowerDefenseWaves)

type Request = (action: string, payload: any, audioCue: string?) -> ()

local StagewrightPlaytestController = {}

local initialized = false
local selectedStageId = ""
local selectedWave = 1
local stageIds: { string } = {}
local stageButtons: { [string]: TextButton } = {}
local waveLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local LEVEL_PURPOSES = { "Basics", "Mixed", "Boss" }

local function waveCount(stageId: string): number
	local waveSet = StageCatalog.waveSetForStage(stageId)
	return if waveSet ~= nil then math.max(#waveSet.waves, 1) else 1
end

local function isEndless(stageId: string): boolean
	return TowerDefenseWaves.isEndless(StageCatalog.waveSetForStage(stageId))
end

local function refreshSelection()
	local authoredWaves = waveCount(selectedStageId)
	-- Endless sets keep going past the authored waves, and tuning the growth
	-- curve means sampling deep waves, so selection is not clamped to the set.
	local maximumWave = if isEndless(selectedStageId)
		then TowerDefenseRequest.MAX_PLAYTEST_WAVE
		else authoredWaves
	selectedWave = math.clamp(selectedWave, 1, maximumWave)
	if waveLabel ~= nil then
		local loop = math.floor((selectedWave - 1) / authoredWaves) + 1
		waveLabel.Text = if loop > 1
			then `Wave {selectedWave}  (loop {loop} of {authoredWaves})`
			else `Wave {selectedWave} / {authoredWaves}`
	end
	for stageId, button in stageButtons do
		local selected = stageId == selectedStageId
		button.BackgroundColor3 = if selected
			then Color3.fromRGB(45, 187, 118)
			else Color3.fromRGB(37, 55, 73)
		button.TextColor3 = if selected then Color3.fromRGB(8, 28, 20) else Color3.fromRGB(224, 237, 247)
	end
end

local function bindButton(parent: Instance, name: string): TextButton
	local instance = parent:WaitForChild(name)
	assert(instance:IsA("TextButton"), `{parent:GetFullName()}.{name} must be a TextButton`)
	return instance
end

function StagewrightPlaytestController.initialize(request: Request)
	if initialized or not RunService:IsStudio() or StageCatalog.isPlaytestCatalog ~= true then
		return
	end
	initialized = true

	for index = 1, math.min(3, #StageCatalog.stageOrder) do
		table.insert(stageIds, StageCatalog.stageOrder[index])
	end
	if #stageIds == 0 then
		return
	end
	selectedStageId = if table.find(stageIds, StageCatalog.preparedStageId) ~= nil
		then StageCatalog.preparedStageId
		else stageIds[1]

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local guiInstance = playerGui:WaitForChild("StagewrightPlaytestHUD")
	assert(guiInstance:IsA("ScreenGui"), "StagewrightPlaytestHUD must be a ScreenGui")
	local gui = guiInstance
	local panel = gui:WaitForChild("Panel")
	assert(panel:IsA("Frame"), "StagewrightPlaytestHUD.Panel must be a Frame")
	local scaleInstance = panel:WaitForChild("InterfaceScale")
	assert(scaleInstance:IsA("UIScale"), "Stagewright playtest panel must have an InterfaceScale")
	local interfaceScale = scaleInstance
	local catalogLabelInstance = panel:WaitForChild("CatalogLabel")
	assert(catalogLabelInstance:IsA("TextLabel"), "CatalogLabel must be a TextLabel")
	catalogLabelInstance.Text = `PREPARED  {StageCatalog.sourceChecksum}`

	local levels = panel:WaitForChild("Levels")
	for index, stageId in stageIds do
		local button = bindButton(levels, `Level{index}Button`)
		local stage = StageCatalog.get(stageId)
		button.Text = if stage ~= nil
			then `{stage.name} • {LEVEL_PURPOSES[index]}`
			else `Level {index} • {LEVEL_PURPOSES[index]}`
		stageButtons[stageId] = button
		button.Activated:Connect(function()
			selectedStageId = stageId
			selectedWave = 1
			refreshSelection()
		end)
	end

	local waveRow = panel:WaitForChild("WaveRow")
	local waveLabelInstance = waveRow:WaitForChild("WaveLabel")
	assert(waveLabelInstance:IsA("TextLabel"), "WaveLabel must be a TextLabel")
	waveLabel = waveLabelInstance
	local minusButton = bindButton(waveRow, "MinusButton")
	local plusButton = bindButton(waveRow, "PlusButton")
	minusButton.Activated:Connect(function()
		selectedWave = math.max(selectedWave - 1, 1)
		refreshSelection()
	end)
	plusButton.Activated:Connect(function()
		local ceiling = if isEndless(selectedStageId)
			then TowerDefenseRequest.MAX_PLAYTEST_WAVE
			else waveCount(selectedStageId)
		selectedWave = math.min(selectedWave + 1, ceiling)
		refreshSelection()
	end)

	local statsLabelInstance = panel:WaitForChild("StatsLabel")
	assert(statsLabelInstance:IsA("TextLabel"), "StatsLabel must be a TextLabel")
	statsLabel = statsLabelInstance
	local statusLabelInstance = panel:WaitForChild("StatusLabel")
	assert(statusLabelInstance:IsA("TextLabel"), "StatusLabel must be a TextLabel")
	statusLabel = statusLabelInstance

	bindButton(panel, "RunButton").Activated:Connect(function()
		statusLabelInstance.Text =
			`Starting Level {table.find(stageIds, selectedStageId) or "?"}, wave {selectedWave}...`
		request("RunTowerWavePlaytest", {
			stageId = selectedStageId,
			waveNumber = selectedWave,
		})
	end)
	bindButton(panel, "ResetButton").Activated:Connect(function()
		statusLabelInstance.Text = "Resetting active test wave..."
		request("ResetTowerDefense", {})
	end)

	local function updateScale()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local viewport = camera.ViewportSize
		interfaceScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.72, 1)
	end
	updateScale()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
	if Workspace.CurrentCamera ~= nil then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	refreshSelection()
	gui.Enabled = true
end

function StagewrightPlaytestController.apply(towerDefense: any)
	if not initialized or type(towerDefense) ~= "table" then
		return
	end
	local activeStageId = towerDefense.activeStageId
	if type(activeStageId) == "string" and table.find(stageIds, activeStageId) ~= nil then
		selectedStageId = activeStageId
	end
	local currentWave = if type(towerDefense.wave) == "number" then towerDefense.wave else 0
	local enemies = if type(towerDefense.enemies) == "table" then #towerDefense.enemies else 0
	local health = if type(towerDefense.baseHealth) == "number" then towerDefense.baseHealth else 0
	local maxHealth = if type(towerDefense.maxBaseHealth) == "number" then towerDefense.maxBaseHealth else 0
	if statsLabel ~= nil then
		statsLabel.Text = `ACTIVE WAVE  {currentWave}     MOBS  {enemies}     BASE  {health}/{maxHealth}`
	end
	if statusLabel ~= nil then
		statusLabel.Text = if towerDefense.waveRunning == true
			then `Running authored wave {currentWave}`
			elseif currentWave > 0 then `Wave {currentWave} complete or stopped`
			else "Ready — choose a level and wave"
	end
	refreshSelection()
end

return table.freeze(StagewrightPlaytestController)

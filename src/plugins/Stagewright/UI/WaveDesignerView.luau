--!strict

-- WAVE DESIGNER page: authors project-level enemy types and wave sets. All
-- edits flow through the injected mutate callback so they share the plugin's
-- transactional undo/redo pipeline; this module owns only presentation state.

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)
local Model = require(script.Parent.Parent.Waves.Model)
local RigCatalog = require(script.Parent.Parent.Waves.RigCatalog)

local COLORS = Theme.colors
local button = Factory.button
local create = Factory.create

local WaveDesignerView = {}

export type Config = {
	parent: Instance,
	project: () -> any,
	revision: () -> string,
	mutate: (name: string, callback: () -> ()) -> boolean,
	setStatus: (message: string, errorState: boolean?) -> (),
	confirm: (id: string, prompt: string) -> boolean,
	preparePlaytest: () -> (),
}

export type Controller = {
	root: Frame,
	refresh: (self: Controller) -> (),
}

export type WaveSetPicker = {
	field: TextButton,
	validIds: (self: WaveSetPicker) -> { [string]: boolean },
	markApplied: (self: WaveSetPicker) -> (),
	sync: (self: WaveSetPicker, current: any) -> (),
}

-- Stage-settings companion: a cycling picker over the project's authored wave
-- sets, so a Level can never reference a set that does not exist. The picker
-- keeps an unapplied cycle choice until Apply or a level switch.
function WaveDesignerView.newWaveSetPicker(parent: Instance, order: number, project: () -> any): WaveSetPicker
	local group = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Size = UDim2.new(1, 0, 0, 13),
		Text = "WAVE SET (CLICK TO CYCLE)",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group)
	local field = button(group, "", nil)
	field.Position = UDim2.fromOffset(0, 14)
	field.Size = UDim2.new(1, 0, 0, 24)
	field.TextXAlignment = Enum.TextXAlignment.Left
	local dirty = false
	local syncedLevelId: string? = nil
	field.Activated:Connect(function()
		local waveSetIds = Model.sortedWaveSetIds(project())
		if #waveSetIds == 0 then
			return
		end
		local index = table.find(waveSetIds, field.Text) or 0
		field.Text = waveSetIds[(index % #waveSetIds) + 1]
		dirty = true
	end)
	local picker: WaveSetPicker = {} :: any
	picker.field = field
	picker.validIds = function(_self: WaveSetPicker): { [string]: boolean }
		local ids: { [string]: boolean } = {}
		for _, waveSetId in Model.sortedWaveSetIds(project()) do
			ids[waveSetId] = true
		end
		return ids
	end
	picker.markApplied = function(_self: WaveSetPicker)
		dirty = false
	end
	picker.sync = function(_self: WaveSetPicker, current: any)
		if syncedLevelId ~= current.id then
			syncedLevelId = current.id
			dirty = false
		end
		if not dirty then
			field.Text = current.waveSetId
		end
	end
	return picker
end

local function column(parent: Instance, title: string, position: UDim2, size: UDim2): (Frame, ScrollingFrame)
	local host = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
	}, parent) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, host)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, host)
	local label = Factory.sectionLabel(host, title, 0)
	label.Position = UDim2.fromOffset(12, 8)
	label.Size = UDim2.new(1, -24, 0, 20)
	local list = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(8, 32),
		ScrollBarThickness = 5,
		Size = UDim2.new(1, -16, 1, -40),
	}, host) :: ScrollingFrame
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	return host, list
end

local function clearRows(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function listRow(
	list: Instance,
	text: string,
	order: number,
	selected: boolean,
	onSelect: () -> ()
): TextButton
	local row = button(list, text, nil, onSelect)
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -6, 0, 28)
	row.TextXAlignment = Enum.TextXAlignment.Left
	Factory.setSelected(row, selected)
	return row
end

local function fieldRow(parent: Instance, label: string, order: number): TextBox
	local group = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, 40),
	}, parent) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Size = UDim2.new(1, 0, 0, 13),
		Text = label,
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group)
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, field)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, field)
	return field
end

local function actionRow(parent: Instance, order: number): Frame
	local row = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, 30),
	}, parent) :: Frame
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	return row
end

function WaveDesignerView.new(config: Config): Controller
	local root = create("Frame", {
		Name = "WaveDesigner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, config.parent) :: Frame
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 10),
	}, root)

	local selectedWaveSetId = "default"
	local selectedWaveIndex = 1
	local selectedEntryIndex = 1
	local selectedEnemyTypeId: string? = nil
	local entryDraftKey: string? = nil
	local entryDraft: Model.WaveEntryInput? = nil
	local entryDraftDirty = false
	local renderedRevision: string? = nil
	local refresh: () -> () = function() end

	local function project(): any
		return config.project()
	end

	local function report(ok: boolean, message: string?, successMessage: string)
		if ok then
			config.setStatus(successMessage)
		else
			config.setStatus(message or "The wave edit could not be applied.", true)
		end
	end

	-- Applies a pure Model mutation inside one plugin transaction; the callback
	-- returns (ok, message) and failures abort the transaction via error().
	local function edit(label: string, successMessage: string, callback: () -> (boolean, string?))
		local resultOk = false
		local resultMessage: string? = nil
		local committed = config.mutate(label, function()
			resultOk, resultMessage = callback()
			return resultOk, resultMessage
		end)
		report(committed and resultOk, resultMessage, successMessage)
		refresh()
	end

	local _, setList = column(root, "Wave Sets", UDim2.fromOffset(0, 0), UDim2.new(0, 236, 0.56, -8))
	local _, endlessPanel =
		column(root, "Endless Growth", UDim2.fromScale(0, 0.56), UDim2.new(0, 236, 0.44, -96))
	local _, waveList = column(root, "Waves", UDim2.fromOffset(244, 0), UDim2.new(0, 236, 0.52, -8))
	local _, entryPanel =
		column(root, "Selected Wave Entries", UDim2.new(0, 244, 0.52, 0), UDim2.new(0, 236, 0.48, -96))
	local _, rosterPanel = column(root, "Enemy Types", UDim2.fromOffset(488, 0), UDim2.new(1, -488, 1, -96))

	local footer = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 88),
	}, root) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Wave sets are shared by every Map. Levels pick a wave set in Stage settings; the default set is the runtime fallback and every wave needs at least one entry. Endless sets repeat their authored waves and apply the growth below after each completed loop.",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, footer)

	local newIdsRow = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
	}, footer) :: Frame
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, newIdsRow)
	local newSetIdField = fieldRow(newIdsRow, "NEW WAVE SET ID", 1)
	newSetIdField.Parent.Size = UDim2.fromOffset(170, 40)
	local newSetButton = button(newIdsRow, "+ Wave Set", 96, function()
		edit("Create Stagewright wave set", "Wave set created.", function()
			local id, message = Model.createWaveSet(project(), newSetIdField.Text, selectedWaveSetId)
			if id ~= nil then
				selectedWaveSetId = id
				selectedWaveIndex = 1
				selectedEntryIndex = 1
				newSetIdField.Text = ""
			end
			return id ~= nil, message
		end)
	end)
	newSetButton.LayoutOrder = 2
	local newEnemyIdField = fieldRow(newIdsRow, "NEW ENEMY TYPE ID", 3)
	newEnemyIdField.Parent.Size = UDim2.fromOffset(170, 40)
	local newEnemyButton = button(newIdsRow, "+ Enemy Type", 104, function()
		edit("Create Stagewright enemy type", "Enemy type created.", function()
			local id, message = Model.createEnemyType(project(), newEnemyIdField.Text)
			if id ~= nil then
				selectedEnemyTypeId = id
				newEnemyIdField.Text = ""
			end
			return id ~= nil, message
		end)
	end)
	newEnemyButton.LayoutOrder = 4
	local prepareButton = button(newIdsRow, "Prepare Playtest", 126, config.preparePlaytest)
	prepareButton.LayoutOrder = 5

	-- Wave-set column footer actions live inside the list as pinned rows.
	local entryFields: { [string]: TextBox } = {}
	local enemyFields: { [string]: TextBox } = {}
	local scalingFields: { [string]: TextBox } = {}
	local scalingCurve = "Linear"
	local scalingWaveSetId: string? = nil
	local previewWave = 25

	local function selectedWaveSet(): any?
		return project().waveSets[selectedWaveSetId]
	end

	local function selectedEntryKey(): string
		return `{selectedWaveSetId}:{selectedWaveIndex}:{selectedEntryIndex}`
	end

	local function inputFromEntry(entry: any?): Model.WaveEntryInput
		if entry == nil then
			return {
				enemyTypeId = Model.sortedEnemyTypeIds(project())[1] or "",
				count = "",
				spacingSeconds = "",
				startDelaySeconds = "",
				healthScale = "",
				rewardScale = "",
				speedScale = "",
			}
		end
		return {
			enemyTypeId = entry.enemyTypeId,
			count = tostring(entry.count),
			spacingSeconds = tostring(entry.spacingSeconds),
			startDelaySeconds = tostring(entry.startDelaySeconds),
			healthScale = if entry.healthScale ~= nil then tostring(entry.healthScale) else "",
			rewardScale = if entry.rewardScale ~= nil then tostring(entry.rewardScale) else "",
			speedScale = if entry.speedScale ~= nil then tostring(entry.speedScale) else "",
		}
	end

	local function captureEntryDraft()
		local currentDraft = entryDraft
		local count = entryFields.count
		local spacingSeconds = entryFields.spacingSeconds
		local startDelaySeconds = entryFields.startDelaySeconds
		local healthScale = entryFields.healthScale
		local rewardScale = entryFields.rewardScale
		local speedScale = entryFields.speedScale
		if
			currentDraft == nil
			or count == nil
			or spacingSeconds == nil
			or startDelaySeconds == nil
			or healthScale == nil
			or rewardScale == nil
			or speedScale == nil
		then
			return
		end
		entryDraft = {
			enemyTypeId = currentDraft.enemyTypeId,
			count = count.Text,
			spacingSeconds = spacingSeconds.Text,
			startDelaySeconds = startDelaySeconds.Text,
			healthScale = healthScale.Text,
			rewardScale = rewardScale.Text,
			speedScale = speedScale.Text,
		}
	end

	local function selectEntryDraft(entry: any?): Model.WaveEntryInput
		local selectionKey = selectedEntryKey()
		if entryDraftKey ~= selectionKey or entryDraft == nil then
			entryDraftKey = selectionKey
			entryDraft = inputFromEntry(entry)
			entryDraftDirty = false
		end
		return entryDraft :: Model.WaveEntryInput
	end

	local function renderWaveSets()
		clearRows(setList)
		for order, waveSetId in Model.sortedWaveSetIds(project()) do
			local waveSet = project().waveSets[waveSetId]
			local endlessMark = if waveSet.endless ~= false then "  •  endless" else ""
			local rowText =
				`{waveSetId}  ({#waveSet.waves} wave{if #waveSet.waves == 1 then "" else "s"}){endlessMark}`
			listRow(setList, rowText, order, waveSetId == selectedWaveSetId, function()
				selectedWaveSetId = waveSetId
				selectedWaveIndex = 1
				selectedEntryIndex = 1
				refresh()
			end)
		end
		local actions = actionRow(setList, 1_000)
		button(actions, "Delete set", 104, function()
			if
				not config.confirm(
					`delete_wave_set_{selectedWaveSetId}`,
					`Delete wave set {selectedWaveSetId}?`
				)
			then
				return
			end
			edit("Delete Stagewright wave set", "Wave set deleted.", function()
				local ok, message = Model.deleteWaveSet(project(), selectedWaveSetId)
				if ok then
					selectedWaveSetId = "default"
					selectedWaveIndex = 1
					selectedEntryIndex = 1
				end
				return ok, message
			end)
		end)
	end

	local function renderWaves()
		clearRows(waveList)
		local waveSet = selectedWaveSet()
		if waveSet == nil then
			return
		end
		selectedWaveIndex = math.clamp(selectedWaveIndex, 1, math.max(#waveSet.waves, 1))
		for waveIndex, wave in waveSet.waves do
			local marker = if wave.isBoss == true then "  •  BOSS" else ""
			local rowText = `Wave {waveIndex}{marker}  •  {Model.waveSpawnTotal(wave)} spawns`
			listRow(waveList, rowText, waveIndex, waveIndex == selectedWaveIndex, function()
				selectedWaveIndex = waveIndex
				selectedEntryIndex = 1
				refresh()
			end)
		end
		local actions = actionRow(waveList, 1_000)
		button(actions, "+ Wave", 64, function()
			edit("Add Stagewright wave", "Wave added.", function()
				local ok, message = Model.addWave(project(), selectedWaveSetId)
				if ok then
					local waves = selectedWaveSet().waves
					selectedWaveIndex = #waves
					selectedEntryIndex = 1
				end
				return ok, message
			end)
		end)
		button(actions, "Delete", 62, function()
			edit("Delete Stagewright wave", "Wave deleted.", function()
				return Model.deleteWave(project(), selectedWaveSetId, selectedWaveIndex)
			end)
		end)
		button(actions, "Up", 40, function()
			edit("Reorder Stagewright wave", "Wave moved.", function()
				local ok, message = Model.moveWave(project(), selectedWaveSetId, selectedWaveIndex, -1)
				if ok then
					selectedWaveIndex -= 1
				end
				return ok, message
			end)
		end)
		button(actions, "Down", 48, function()
			edit("Reorder Stagewright wave", "Wave moved.", function()
				local ok, message = Model.moveWave(project(), selectedWaveSetId, selectedWaveIndex, 1)
				if ok then
					selectedWaveIndex += 1
				end
				return ok, message
			end)
		end)
		local bossActions = actionRow(waveList, 1_001)
		local wave = waveSet.waves[selectedWaveIndex]
		local bossOn = wave ~= nil and wave.isBoss == true
		button(bossActions, if bossOn then "Boss wave: ON" else "Boss wave: OFF", 118, function()
			edit("Toggle Stagewright boss wave", "Boss flag updated.", function()
				return Model.setBossFlag(project(), selectedWaveSetId, selectedWaveIndex, not bossOn)
			end)
		end)
	end

	local function readEntryInput(): Model.WaveEntryInput
		captureEntryDraft()
		return entryDraft or inputFromEntry(nil)
	end

	local function renderEntries()
		clearRows(entryPanel)
		local waveSet = selectedWaveSet()
		local wave = if waveSet ~= nil then waveSet.waves[selectedWaveIndex] else nil
		if wave == nil then
			return
		end
		selectedEntryIndex = math.clamp(selectedEntryIndex, 1, math.max(#wave.entries, 1))
		for entryIndex, entry in wave.entries do
			local rowText =
				`{entry.count} x {entry.enemyTypeId} @{entry.spacingSeconds}s +{entry.startDelaySeconds}s`
			listRow(entryPanel, rowText, entryIndex, entryIndex == selectedEntryIndex, function()
				selectedEntryIndex = entryIndex
				refresh()
			end)
		end
		local selectedEntry = wave.entries[selectedEntryIndex]
		local draft = selectEntryDraft(selectedEntry)
		local cycler = actionRow(entryPanel, 500)
		local enemyButton = button(cycler, `Enemy: {draft.enemyTypeId}`, 170)
		enemyButton.Activated:Connect(function()
			captureEntryDraft()
			local currentDraft = entryDraft
			if currentDraft == nil then
				return
			end
			local ids = Model.sortedEnemyTypeIds(project())
			if #ids == 0 then
				return
			end
			local index = table.find(ids, currentDraft.enemyTypeId) or 0
			currentDraft.enemyTypeId = ids[(index % #ids) + 1] or currentDraft.enemyTypeId
			entryDraftDirty = true
			enemyButton.Text = `Enemy: {currentDraft.enemyTypeId}`
		end)
		entryFields.count = fieldRow(entryPanel, "COUNT", 501)
		entryFields.spacingSeconds = fieldRow(entryPanel, "SPACING SECONDS", 502)
		entryFields.startDelaySeconds = fieldRow(entryPanel, "START DELAY SECONDS", 503)
		entryFields.healthScale = fieldRow(entryPanel, "HEALTH SCALE (BLANK = 1)", 504)
		entryFields.rewardScale = fieldRow(entryPanel, "REWARD SCALE (BLANK = 1)", 505)
		entryFields.speedScale = fieldRow(entryPanel, "SPEED SCALE (BLANK = 1)", 506)
		entryFields.count.Text = draft.count
		entryFields.spacingSeconds.Text = draft.spacingSeconds
		entryFields.startDelaySeconds.Text = draft.startDelaySeconds
		entryFields.healthScale.Text = draft.healthScale
		entryFields.rewardScale.Text = draft.rewardScale
		entryFields.speedScale.Text = draft.speedScale
		for _, field in entryFields do
			field:GetPropertyChangedSignal("Text"):Connect(function()
				entryDraftDirty = true
			end)
		end
		local actions = actionRow(entryPanel, 600)
		button(actions, "Apply entry", 90, function()
			local entry, parseError = Model.parseEntry(readEntryInput(), Model.enemyTypeIdSet(project()))
			if entry == nil then
				config.setStatus(parseError or "The wave entry is invalid.", true)
				return
			end
			edit("Update Stagewright wave entry", "Wave entry updated.", function()
				return Model.updateEntry(
					project(),
					selectedWaveSetId,
					selectedWaveIndex,
					selectedEntryIndex,
					entry
				)
			end)
		end)
		button(actions, "+ Entry", 66, function()
			local entry, parseError = Model.parseEntry(readEntryInput(), Model.enemyTypeIdSet(project()))
			if entry == nil then
				config.setStatus(parseError or "The wave entry is invalid.", true)
				return
			end
			edit("Add Stagewright wave entry", "Wave entry added.", function()
				local ok, message = Model.addEntry(project(), selectedWaveSetId, selectedWaveIndex, entry)
				if ok then
					local currentWaveSet = selectedWaveSet()
					selectedEntryIndex = #currentWaveSet.waves[selectedWaveIndex].entries
				end
				return ok, message
			end)
		end)
		button(actions, "Delete", 62, function()
			edit("Delete Stagewright wave entry", "Wave entry deleted.", function()
				return Model.deleteEntry(project(), selectedWaveSetId, selectedWaveIndex, selectedEntryIndex)
			end)
		end)
	end

	-- Endless growth panel: the curve that turns a short authored rhythm into a
	-- run with no last wave. The preview runs the real runtime math for a chosen
	-- wave number so a curve can be judged before a playtest.
	local function renderEndless()
		clearRows(endlessPanel)
		local waveSet = selectedWaveSet()
		if waveSet == nil then
			return
		end
		local scaling = waveSet.loopScaling or {}
		local endless = waveSet.endless ~= false
		local modeRow = actionRow(endlessPanel, 1)
		button(modeRow, if endless then "Endless: ON" else "Endless: OFF", 108, function()
			edit("Toggle Stagewright endless set", "Endless flag updated.", function()
				return Model.setEndless(project(), selectedWaveSetId, not endless)
			end)
		end)
		local curveButton = button(modeRow, `Curve: {scalingCurve}`, 112)
		curveButton.Activated:Connect(function()
			scalingCurve = if scalingCurve == "Linear" then "Exponential" else "Linear"
			curveButton.Text = `Curve: {scalingCurve}`
		end)
		scalingFields.healthPerLoop = fieldRow(endlessPanel, "HEALTH GROWTH / LOOP", 2)
		scalingFields.rewardPerLoop = fieldRow(endlessPanel, "REWARD GROWTH / LOOP", 3)
		scalingFields.countPerLoop = fieldRow(endlessPanel, "SPAWN COUNT GROWTH / LOOP", 4)
		scalingFields.spacingPerLoop = fieldRow(endlessPanel, "SPAWN SPACING TIGHTENING / LOOP", 5)
		scalingFields.speedPerLoop = fieldRow(endlessPanel, "SPEED GROWTH / LOOP", 6)
		scalingFields.bossEveryWaves = fieldRow(endlessPanel, "BOSS EVERY N WAVES (0 = OFF)", 7)
		for field, box in scalingFields do
			local value = scaling[field]
			box.Text = if type(value) == "number" then tostring(value) else "0"
		end
		local previewRow = actionRow(endlessPanel, 8)
		local previewLabel = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			LayoutOrder = 9,
			Size = UDim2.new(1, -6, 0, 58),
			Text = "",
			TextColor3 = COLORS.muted,
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, endlessPanel) :: TextLabel
		local function refreshPreview()
			local parsed = Model.parseLoopScaling({
				curve = scalingCurve,
				healthPerLoop = scalingFields.healthPerLoop.Text,
				rewardPerLoop = scalingFields.rewardPerLoop.Text,
				speedPerLoop = scalingFields.speedPerLoop.Text,
				countPerLoop = scalingFields.countPerLoop.Text,
				spacingPerLoop = scalingFields.spacingPerLoop.Text,
				bossEveryWaves = scalingFields.bossEveryWaves.Text,
			})
			if parsed == nil then
				previewLabel.Text = "Enter a valid growth curve to preview it."
				return
			end
			local previewSet = table.clone(waveSet)
			previewSet.loopScaling = parsed
			local preview = Model.previewWavePlan(previewSet, previewWave)
			local scalingPreview = preview.scaling
			local bossText = if preview.isBoss then " • BOSS" else ""
			local capText = if preview.spawnCapReached
				then string.format(" (cap; curve requested %d)", preview.requestedSpawns)
				else ""
			previewLabel.Text = string.format(
				"Wave %d replays authored %d/%d%s • %d mobs%s in %d stream(s) • planned %.1f-%.1fs\nHP x%.2f  reward x%.2f  count x%.2f  spacing /%.2f  speed x%.2f",
				previewWave,
				preview.authoredWaveIndex,
				preview.authoredWaveCount,
				bossText,
				preview.totalSpawns,
				capText,
				preview.streamCount,
				preview.firstSpawnSeconds,
				preview.finalSpawnSeconds,
				scalingPreview.health,
				scalingPreview.reward,
				scalingPreview.count,
				scalingPreview.spacing,
				scalingPreview.speed
			)
		end
		button(previewRow, "Preview -10", 84, function()
			previewWave = math.max(previewWave - 10, 1)
			refreshPreview()
		end)
		button(previewRow, "Preview +10", 84, function()
			previewWave = math.min(previewWave + 10, 1_000)
			refreshPreview()
		end)
		refreshPreview()
		local actions = actionRow(endlessPanel, 10)
		button(actions, "Apply growth", 100, function()
			local parsed, parseError = Model.parseLoopScaling({
				curve = scalingCurve,
				healthPerLoop = scalingFields.healthPerLoop.Text,
				rewardPerLoop = scalingFields.rewardPerLoop.Text,
				speedPerLoop = scalingFields.speedPerLoop.Text,
				countPerLoop = scalingFields.countPerLoop.Text,
				spacingPerLoop = scalingFields.spacingPerLoop.Text,
				bossEveryWaves = scalingFields.bossEveryWaves.Text,
			})
			if parsed == nil then
				config.setStatus(parseError or "The growth curve is invalid.", true)
				return
			end
			edit("Update Stagewright endless growth", "Endless growth updated.", function()
				return Model.applyLoopScaling(project(), selectedWaveSetId, parsed)
			end)
		end)
	end

	local function readEnemyInput(): Model.EnemyTypeInput
		return {
			name = enemyFields.name.Text,
			tags = enemyFields.tags.Text,
			health = enemyFields.health.Text,
			speed = enemyFields.speed.Text,
			reward = enemyFields.reward.Text,
			baseDamage = enemyFields.baseDamage.Text,
			modelId = enemyFields.modelId.Text,
			renderScale = enemyFields.renderScale.Text,
			walkAnimationId = enemyFields.walkAnimationId.Text,
			deathAnimationId = enemyFields.deathAnimationId.Text,
		}
	end

	local function renderRoster()
		clearRows(rosterPanel)
		local enemyTypeIds = Model.sortedEnemyTypeIds(project())
		if selectedEnemyTypeId == nil or project().enemyTypes[selectedEnemyTypeId] == nil then
			selectedEnemyTypeId = enemyTypeIds[1]
		end
		for order, enemyTypeId in enemyTypeIds do
			local enemyType = project().enemyTypes[enemyTypeId]
			local mobName = if enemyType.modelId ~= "" then enemyType.modelId else "no model"
			local rowText = `{enemyTypeId}  •  {enemyType.health} HP  •  {table.concat(
				enemyType.tags,
				"/"
			)}  •  {mobName}`
			listRow(rosterPanel, rowText, order, enemyTypeId == selectedEnemyTypeId, function()
				selectedEnemyTypeId = enemyTypeId
				refresh()
			end)
		end
		local selectedEnemy = if selectedEnemyTypeId ~= nil
			then project().enemyTypes[selectedEnemyTypeId]
			else nil
		enemyFields.name = fieldRow(rosterPanel, "DISPLAY NAME", 501)
		enemyFields.tags =
			fieldRow(rosterPanel, "TAGS (COMMA LIST: GROUND, FLYING, FAST, ARMORED, BOSS)", 502)
		enemyFields.health = fieldRow(rosterPanel, "HEALTH", 503)
		enemyFields.speed = fieldRow(rosterPanel, "SPEED (STUDS/S)", 504)
		enemyFields.reward = fieldRow(rosterPanel, "REWARD", 505)
		enemyFields.baseDamage = fieldRow(rosterPanel, "BASE DAMAGE", 506)
		enemyFields.modelId = fieldRow(rosterPanel, "MOB MODEL (ENEMYRIGS MODEL NAME)", 507)
		enemyFields.renderScale = fieldRow(rosterPanel, "RENDER SCALE", 509)
		enemyFields.walkAnimationId = fieldRow(rosterPanel, "WALK ANIMATION ID (BLANK = RIG'S OWN)", 510)
		enemyFields.deathAnimationId = fieldRow(rosterPanel, "DEATH ANIMATION ID (BLANK = RIG'S OWN)", 511)
		if selectedEnemy ~= nil then
			enemyFields.name.Text = selectedEnemy.name
			enemyFields.tags.Text = table.concat(selectedEnemy.tags, ", ")
			enemyFields.health.Text = tostring(selectedEnemy.health)
			enemyFields.speed.Text = tostring(selectedEnemy.speed)
			enemyFields.reward.Text = tostring(selectedEnemy.reward)
			enemyFields.baseDamage.Text = tostring(selectedEnemy.baseDamage)
			enemyFields.modelId.Text = selectedEnemy.modelId
			enemyFields.renderScale.Text = tostring(selectedEnemy.renderScale)
			local animations = if type(selectedEnemy.animations) == "table"
				then selectedEnemy.animations
				else {}
			enemyFields.walkAnimationId.Text = animations.walkId or ""
			enemyFields.deathAnimationId.Text = animations.deathId or ""
		end

		-- Mob picker: whatever Models live in EnemyRigs are the selectable mobs,
		-- so dropping a character asset in that folder is the whole workflow. The
		-- field stays editable for rigs that are not in this Studio session yet.
		local pickerRow = actionRow(rosterPanel, 508)
		local rigStatus = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			LayoutOrder = 508,
			Size = UDim2.new(1, -6, 0, 26),
			Text = "",
			TextColor3 = COLORS.muted,
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, rosterPanel) :: TextLabel
		local function refreshRigStatus()
			rigStatus.Text = RigCatalog.describe(enemyFields.modelId.Text)
		end
		button(pickerRow, "< Mob", 62, function()
			local names = RigCatalog.names()
			if #names == 0 then
				config.setStatus("No rigs found under ReplicatedStorage.Template.EnemyRigs.", true)
				return
			end
			local index = table.find(names, enemyFields.modelId.Text) or 1
			enemyFields.modelId.Text = names[((index - 2) % #names) + 1]
			refreshRigStatus()
		end)
		button(pickerRow, "Mob >", 62, function()
			local names = RigCatalog.names()
			if #names == 0 then
				config.setStatus("No rigs found under ReplicatedStorage.Template.EnemyRigs.", true)
				return
			end
			local index = table.find(names, enemyFields.modelId.Text) or 0
			enemyFields.modelId.Text = names[(index % #names) + 1]
			refreshRigStatus()
		end)
		button(pickerRow, "Use rig animations", 122, function()
			local rig = RigCatalog.find(enemyFields.modelId.Text)
			if rig == nil then
				config.setStatus("Select a rig that exists in EnemyRigs first.", true)
				return
			end
			enemyFields.walkAnimationId.Text = rig.declaredWalkId
			enemyFields.deathAnimationId.Text = rig.declaredDeathId
			config.setStatus(`Copied {rig.name} rig animation ids into the fields.`)
		end)
		enemyFields.modelId:GetPropertyChangedSignal("Text"):Connect(refreshRigStatus)
		refreshRigStatus()

		local actions = actionRow(rosterPanel, 600)
		button(actions, "Apply enemy type", 122, function()
			local enemyTypeId = selectedEnemyTypeId
			if enemyTypeId == nil then
				return
			end
			local update, parseError = Model.parseEnemyType(readEnemyInput())
			if update == nil then
				config.setStatus(parseError or "The enemy type is invalid.", true)
				return
			end
			edit("Update Stagewright enemy type", "Enemy type updated.", function()
				return Model.applyEnemyType(project(), enemyTypeId, update)
			end)
		end)
		button(actions, "Delete", 62, function()
			local enemyTypeId = selectedEnemyTypeId
			if enemyTypeId == nil then
				return
			end
			if not config.confirm(`delete_enemy_type_{enemyTypeId}`, `Delete enemy type {enemyTypeId}?`) then
				return
			end
			edit("Delete Stagewright enemy type", "Enemy type deleted.", function()
				local ok, message = Model.deleteEnemyType(project(), enemyTypeId)
				if ok then
					selectedEnemyTypeId = nil
				end
				return ok, message
			end)
		end)
	end

	refresh = function()
		local revision = config.revision()
		local revisionChanged = revision ~= renderedRevision
		if revisionChanged then
			entryDraftKey = nil
			entryDraft = nil
			entryDraftDirty = false
		elseif entryDraftDirty then
			captureEntryDraft()
		end
		renderedRevision = revision
		if project().waveSets[selectedWaveSetId] == nil then
			selectedWaveSetId = Model.sortedWaveSetIds(project())[1] or "default"
			selectedWaveIndex = 1
			selectedEntryIndex = 1
		end
		local activeSet = project().waveSets[selectedWaveSetId]
		if
			activeSet ~= nil
			and type(activeSet.loopScaling) == "table"
			and (revisionChanged or scalingWaveSetId ~= selectedWaveSetId)
		then
			scalingCurve = if activeSet.loopScaling.curve == "Exponential" then "Exponential" else "Linear"
			scalingWaveSetId = selectedWaveSetId
		end
		renderWaveSets()
		renderEndless()
		renderWaves()
		renderEntries()
		renderRoster()
	end

	local controller: Controller = {} :: any
	controller.root = root
	controller.refresh = function(_self: Controller)
		refresh()
	end
	return controller
end

return table.freeze(WaveDesignerView)

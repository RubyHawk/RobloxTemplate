--!strict

-- WAVE DESIGNER page: authors project-level enemy types and wave sets. All
-- edits flow through the injected mutate callback so they share the plugin's
-- transactional undo/redo pipeline; this module owns only presentation state.

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)
local Model = require(script.Parent.Parent.Waves.Model)

local COLORS = Theme.colors
local button = Factory.button
local create = Factory.create

local WaveDesignerView = {}

export type Config = {
	parent: Instance,
	project: () -> any,
	mutate: (name: string, callback: () -> ()) -> boolean,
	setStatus: (message: string, errorState: boolean?) -> (),
	confirm: (id: string, prompt: string) -> boolean,
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
	local entryEnemyTypeId = ""
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
			if not resultOk then
				error(resultMessage or `{label} was rejected`, 0)
			end
		end)
		report(committed and resultOk, resultMessage, successMessage)
		refresh()
	end

	local _, setList = column(root, "Wave Sets", UDim2.fromOffset(0, 0), UDim2.new(0, 236, 1, -96))
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
		Text = "Wave sets are shared by every Map. Levels pick a wave set in Stage settings; the default set is the runtime fallback and every wave needs at least one entry.",
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

	-- Wave-set column footer actions live inside the list as pinned rows.
	local entryFields: { [string]: TextBox } = {}
	local enemyFields: { [string]: TextBox } = {}

	local function selectedWaveSet(): any?
		return project().waveSets[selectedWaveSetId]
	end

	local function renderWaveSets()
		clearRows(setList)
		for order, waveSetId in Model.sortedWaveSetIds(project()) do
			local waveSet = project().waveSets[waveSetId]
			local rowText = `{waveSetId}  ({#waveSet.waves} wave{if #waveSet.waves == 1 then "" else "s"})`
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
		return {
			enemyTypeId = entryEnemyTypeId,
			count = entryFields.count.Text,
			spacingSeconds = entryFields.spacingSeconds.Text,
			startDelaySeconds = entryFields.startDelaySeconds.Text,
			healthScale = entryFields.healthScale.Text,
			rewardScale = entryFields.rewardScale.Text,
			speedScale = entryFields.speedScale.Text,
		}
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
		if selectedEntry ~= nil and entryEnemyTypeId == "" then
			entryEnemyTypeId = selectedEntry.enemyTypeId
		end
		local cycler = actionRow(entryPanel, 500)
		button(cycler, `Enemy: {entryEnemyTypeId}`, 170, function()
			local ids = Model.sortedEnemyTypeIds(project())
			local index = table.find(ids, entryEnemyTypeId) or 0
			entryEnemyTypeId = ids[(index % #ids) + 1] or entryEnemyTypeId
			refresh()
		end)
		entryFields.count = fieldRow(entryPanel, "COUNT", 501)
		entryFields.spacingSeconds = fieldRow(entryPanel, "SPACING SECONDS", 502)
		entryFields.startDelaySeconds = fieldRow(entryPanel, "START DELAY SECONDS", 503)
		entryFields.healthScale = fieldRow(entryPanel, "HEALTH SCALE (BLANK = 1)", 504)
		entryFields.rewardScale = fieldRow(entryPanel, "REWARD SCALE (BLANK = 1)", 505)
		entryFields.speedScale = fieldRow(entryPanel, "SPEED SCALE (BLANK = 1)", 506)
		if selectedEntry ~= nil then
			entryFields.count.Text = tostring(selectedEntry.count)
			entryFields.spacingSeconds.Text = tostring(selectedEntry.spacingSeconds)
			entryFields.startDelaySeconds.Text = tostring(selectedEntry.startDelaySeconds)
			entryFields.healthScale.Text = if selectedEntry.healthScale ~= nil
				then tostring(selectedEntry.healthScale)
				else ""
			entryFields.rewardScale.Text = if selectedEntry.rewardScale ~= nil
				then tostring(selectedEntry.rewardScale)
				else ""
			entryFields.speedScale.Text = if selectedEntry.speedScale ~= nil
				then tostring(selectedEntry.speedScale)
				else ""
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
			local rowText =
				`{enemyTypeId}  •  {enemyType.health} HP  •  {table.concat(enemyType.tags, "/")}`
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
		enemyFields.modelId = fieldRow(rosterPanel, "MODEL ID (ENEMYRIGS TEMPLATE NAME)", 507)
		enemyFields.renderScale = fieldRow(rosterPanel, "RENDER SCALE", 508)
		if selectedEnemy ~= nil then
			enemyFields.name.Text = selectedEnemy.name
			enemyFields.tags.Text = table.concat(selectedEnemy.tags, ", ")
			enemyFields.health.Text = tostring(selectedEnemy.health)
			enemyFields.speed.Text = tostring(selectedEnemy.speed)
			enemyFields.reward.Text = tostring(selectedEnemy.reward)
			enemyFields.baseDamage.Text = tostring(selectedEnemy.baseDamage)
			enemyFields.modelId.Text = selectedEnemy.modelId
			enemyFields.renderScale.Text = tostring(selectedEnemy.renderScale)
		end
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
		if project().waveSets[selectedWaveSetId] == nil then
			selectedWaveSetId = Model.sortedWaveSetIds(project())[1] or "default"
			selectedWaveIndex = 1
			selectedEntryIndex = 1
		end
		entryEnemyTypeId = if Model.enemyTypeIdSet(project())[entryEnemyTypeId] then entryEnemyTypeId else ""
		renderWaveSets()
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

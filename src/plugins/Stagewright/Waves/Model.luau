--!strict

-- Pure mutations and parsing for the Wave Designer. Every function operates on
-- the plugin's working project table; the composition root wraps calls in
-- ProjectStore.mutate so edits stay transactional and undoable.

local StageSchema = if script ~= nil
	then require(script.Parent.Parent.Shared.StageSchema)
	else require("../../../shared/StageSchema")
local StageWaveDefaults = if script ~= nil
	then require(script.Parent.Parent.Shared.StageWaveDefaults)
	else require("../../../shared/StageWaveDefaults")
local TowerDefenseWaves = if script ~= nil
	then require(script.Parent.Parent.Shared.TowerDefenseWaves)
	else require("../../../shared/TowerDefenseWaves")

local Model = {}

Model.MAX_WAVES = 100
Model.MAX_ENTRIES_PER_WAVE = 20

local KNOWN_TAG_BY_LOWER: { [string]: string } = {}
for _, knownTag in StageWaveDefaults.KNOWN_TAGS do
	KNOWN_TAG_BY_LOWER[string.lower(knownTag)] = knownTag
end

export type EnemyTypeInput = {
	name: string,
	tags: string,
	health: string,
	speed: string,
	reward: string,
	baseDamage: string,
	modelId: string,
	renderScale: string,
	walkAnimationId: string,
	deathAnimationId: string,
}

export type EnemyTypeUpdate = {
	name: string,
	tags: { string },
	health: number,
	speed: number,
	reward: number,
	baseDamage: number,
	modelId: string,
	renderScale: number,
	animations: { walkId: string, deathId: string },
}

export type WaveEntryInput = {
	enemyTypeId: string,
	count: string,
	spacingSeconds: string,
	startDelaySeconds: string,
	healthScale: string,
	rewardScale: string,
	speedScale: string,
}

export type LoopScalingInput = {
	curve: string,
	healthPerLoop: string,
	rewardPerLoop: string,
	speedPerLoop: string,
	countPerLoop: string,
	spacingPerLoop: string,
	bossEveryWaves: string,
}

Model.LOOP_RATE_FIELDS = table.freeze({
	"healthPerLoop",
	"rewardPerLoop",
	"speedPerLoop",
	"countPerLoop",
	"spacingPerLoop",
})

local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or ""
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = deepCopy(child)
	end
	return result
end

local function sortedKeys(registry: any): { string }
	local keys: { string } = {}
	if type(registry) == "table" then
		for key in registry do
			if type(key) == "string" then
				table.insert(keys, key)
			end
		end
	end
	table.sort(keys)
	return keys
end

local function firstError(issues: { StageSchema.Issue }): string?
	for _, issue in issues do
		if issue.severity == "Error" then
			return issue.message
		end
	end
	return nil
end

local function parsedId(requestedId: string): (string?, string?)
	local id = trim(requestedId)
	if id == "" or #id > 80 or string.match(id, "^[%l%d_]+$") == nil then
		return nil, "IDs must use lowercase letters, digits, or underscores (at most 80 characters)."
	end
	return id, nil
end

function Model.sortedEnemyTypeIds(project: any): { string }
	return sortedKeys(project.enemyTypes)
end

function Model.sortedWaveSetIds(project: any): { string }
	return sortedKeys(project.waveSets)
end

function Model.enemyTypeIdSet(project: any): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	if type(project.enemyTypes) == "table" then
		for id in project.enemyTypes do
			if type(id) == "string" then
				ids[id] = true
			end
		end
	end
	return ids
end

function Model.waveSpawnTotal(wave: any): number
	local total = 0
	if type(wave) == "table" and type(wave.entries) == "table" then
		for _, entry in wave.entries do
			if type(entry) == "table" and type(entry.count) == "number" then
				total += entry.count
			end
		end
	end
	return total
end

function Model.parseEnemyType(input: EnemyTypeInput): (EnemyTypeUpdate?, string?)
	local health = tonumber(trim(input.health))
	local speed = tonumber(trim(input.speed))
	local reward = tonumber(trim(input.reward))
	local baseDamage = tonumber(trim(input.baseDamage))
	local renderScale = tonumber(trim(input.renderScale))
	if health == nil or speed == nil or reward == nil or baseDamage == nil or renderScale == nil then
		return nil, "Health, speed, reward, base damage, and render scale must be numbers."
	end
	local tags: { string } = {}
	for tag in string.gmatch(input.tags, "[^,%s]+") do
		table.insert(tags, KNOWN_TAG_BY_LOWER[string.lower(tag)] or tag)
	end
	-- Both id forms a designer might paste normalize to one stored value, so an
	-- animation typed as a bare number and one pasted as a URI are the same.
	local walkId = StageSchema.normalizeAssetId(input.walkAnimationId or "")
	local deathId = StageSchema.normalizeAssetId(input.deathAnimationId or "")
	if walkId == nil or deathId == nil then
		return nil, "Animation ids must be blank, a Roblox asset id, or rbxassetid://<id>."
	end
	local update: EnemyTypeUpdate = {
		name = trim(input.name),
		tags = tags,
		health = health,
		speed = speed,
		reward = reward,
		baseDamage = baseDamage,
		modelId = trim(input.modelId),
		renderScale = renderScale,
		animations = { walkId = walkId, deathId = deathId },
	}
	local candidate = {
		id = "candidate",
		name = update.name,
		tags = update.tags,
		health = update.health,
		speed = update.speed,
		reward = update.reward,
		baseDamage = update.baseDamage,
		modelId = update.modelId,
		renderScale = update.renderScale,
		animations = update.animations,
	}
	local message = firstError(StageSchema.validateEnemyType(candidate))
	if message ~= nil then
		return nil, message
	end
	return update, nil
end

function Model.applyEnemyType(project: any, enemyTypeId: string, update: EnemyTypeUpdate): (boolean, string?)
	local enemyType = project.enemyTypes[enemyTypeId]
	if enemyType == nil then
		return false, `Unknown enemy type {enemyTypeId}.`
	end
	enemyType.name = update.name
	enemyType.tags = table.clone(update.tags)
	enemyType.health = update.health
	enemyType.speed = update.speed
	enemyType.reward = update.reward
	enemyType.baseDamage = update.baseDamage
	enemyType.modelId = update.modelId
	enemyType.renderScale = update.renderScale
	enemyType.animations = { walkId = update.animations.walkId, deathId = update.animations.deathId }
	return true, nil
end

function Model.createEnemyType(project: any, requestedId: string): (string?, string?)
	local id, idError = parsedId(requestedId)
	if id == nil then
		return nil, idError
	end
	if project.enemyTypes[id] ~= nil then
		return nil, `Enemy type {id} already exists.`
	end
	project.enemyTypes[id] = {
		id = id,
		name = id,
		tags = { "Ground" },
		health = 50,
		speed = 7,
		reward = 10,
		baseDamage = 1,
		modelId = "",
		renderScale = 1,
		animations = StageWaveDefaults.defaultAnimations(),
	}
	return id, nil
end

function Model.deleteEnemyType(project: any, enemyTypeId: string): (boolean, string?)
	if project.enemyTypes[enemyTypeId] == nil then
		return false, `Unknown enemy type {enemyTypeId}.`
	end
	local remaining = 0
	for _ in project.enemyTypes do
		remaining += 1
	end
	if remaining <= 1 then
		return false, "At least one enemy type must remain."
	end
	for waveSetId, waveSet in project.waveSets do
		for waveIndex, wave in waveSet.waves do
			for _, entry in wave.entries do
				if entry.enemyTypeId == enemyTypeId then
					return false, `Enemy type {enemyTypeId} is used by wave set {waveSetId} wave {waveIndex}.`
				end
			end
		end
	end
	project.enemyTypes[enemyTypeId] = nil
	return true, nil
end

-- Endless growth is authored per wave set, so a level can loop gently while
-- another ramps hard. Parsing validates through the shared schema so the plugin
-- and the exporter can never disagree about what a legal curve is.
function Model.parseLoopScaling(input: LoopScalingInput): (any?, string?)
	local curve = trim(input.curve)
	if curve ~= "Linear" and curve ~= "Exponential" then
		return nil, "Curve must be Linear or Exponential."
	end
	local scaling: any = { curve = curve }
	for _, rateField in Model.LOOP_RATE_FIELDS do
		local rate = tonumber(trim((input :: any)[rateField]))
		if rate == nil then
			return nil, `{rateField} must be a number.`
		end
		scaling[rateField] = rate
	end
	local bossEveryWaves = tonumber(trim(input.bossEveryWaves))
	if bossEveryWaves == nil then
		return nil, "Boss cadence must be a number (0 disables it)."
	end
	scaling.bossEveryWaves = bossEveryWaves
	local candidate = {
		id = "candidate",
		name = "candidate",
		endless = true,
		loopScaling = scaling,
		waves = {
			{
				entries = {
					{
						enemyTypeId = "candidate",
						count = 1,
						spacingSeconds = 1,
						startDelaySeconds = 0,
					},
				},
			},
		},
	}
	local message = firstError(StageSchema.validateWaveSet(candidate, { candidate = true }))
	if message ~= nil then
		return nil, message
	end
	return scaling, nil
end

function Model.applyLoopScaling(project: any, waveSetId: string, scaling: any): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	waveSet.loopScaling = deepCopy(scaling)
	return true, nil
end

function Model.setEndless(project: any, waveSetId: string, endless: boolean): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	waveSet.endless = endless
	return true, nil
end

-- Projected difficulty for one wave number, used by the designer preview so a
-- curve can be judged without starting a playtest. It runs the exact runtime
-- math rather than a lookalike, so the preview cannot drift from the server.
function Model.previewScaling(waveSet: any, waveNumber: number): TowerDefenseWaves.WaveScaling
	local scaling = TowerDefenseWaves.resolveScaling(waveSet, StageWaveDefaults.defaultLoopScaling())
	return TowerDefenseWaves.scalingFor(scaling, waveNumber, math.max(#waveSet.waves, 1))
end

function Model.createWaveSet(project: any, requestedId: string, copyFromId: string?): (string?, string?)
	local id, idError = parsedId(requestedId)
	if id == nil then
		return nil, idError
	end
	if project.waveSets[id] ~= nil then
		return nil, `Wave set {id} already exists.`
	end
	local waves: any
	local source = if copyFromId ~= nil then project.waveSets[copyFromId] else nil
	local endless = true
	local loopScaling = StageWaveDefaults.defaultLoopScaling()
	if source ~= nil then
		waves = deepCopy(source.waves)
		endless = source.endless ~= false
		if type(source.loopScaling) == "table" then
			loopScaling = deepCopy(source.loopScaling)
		end
	else
		local firstEnemyTypeId = Model.sortedEnemyTypeIds(project)[1]
		if firstEnemyTypeId == nil then
			return nil, "Create an enemy type before creating a wave set."
		end
		waves = {
			{
				entries = {
					{
						enemyTypeId = firstEnemyTypeId,
						count = 8,
						spacingSeconds = 0.7,
						startDelaySeconds = 0,
					},
				},
			},
		}
	end
	project.waveSets[id] = { id = id, name = id, waves = waves, endless = endless, loopScaling = loopScaling }
	return id, nil
end

function Model.renameWaveSet(project: any, waveSetId: string, name: string): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	local trimmed = trim(name)
	if trimmed == "" or #trimmed > 120 then
		return false, "Wave set name must contain 1 to 120 characters."
	end
	waveSet.name = trimmed
	return true, nil
end

function Model.deleteWaveSet(project: any, waveSetId: string): (boolean, string?)
	if project.waveSets[waveSetId] == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	if waveSetId == StageWaveDefaults.DEFAULT_WAVE_SET_ID then
		return false, "The default wave set is the runtime fallback and cannot be deleted."
	end
	for stageId, stage in project.stages do
		if stage.waveSetId == waveSetId then
			return false, `Wave set {waveSetId} is used by level {stageId}.`
		end
	end
	project.waveSets[waveSetId] = nil
	return true, nil
end

local function waveAt(project: any, waveSetId: string, waveIndex: number): (any?, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return nil, `Unknown wave set {waveSetId}.`
	end
	local wave = waveSet.waves[waveIndex]
	if wave == nil then
		return nil, `Wave set {waveSetId} has no wave {waveIndex}.`
	end
	return wave, nil
end

function Model.addWave(project: any, waveSetId: string): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	if #waveSet.waves >= Model.MAX_WAVES then
		return false, `Wave sets support at most {Model.MAX_WAVES} waves.`
	end
	local firstEnemyTypeId = Model.sortedEnemyTypeIds(project)[1]
	if firstEnemyTypeId == nil then
		return false, "Create an enemy type before adding waves."
	end
	table.insert(waveSet.waves, {
		entries = {
			{
				enemyTypeId = firstEnemyTypeId,
				count = 8,
				spacingSeconds = 0.7,
				startDelaySeconds = 0,
			},
		},
	})
	return true, nil
end

function Model.deleteWave(project: any, waveSetId: string, waveIndex: number): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	if waveSet.waves[waveIndex] == nil then
		return false, `Wave set {waveSetId} has no wave {waveIndex}.`
	end
	if #waveSet.waves <= 1 then
		return false, "Wave sets must keep at least one wave."
	end
	table.remove(waveSet.waves, waveIndex)
	return true, nil
end

function Model.moveWave(
	project: any,
	waveSetId: string,
	waveIndex: number,
	offset: number
): (boolean, string?)
	local waveSet = project.waveSets[waveSetId]
	if waveSet == nil then
		return false, `Unknown wave set {waveSetId}.`
	end
	local target = waveIndex + offset
	if waveSet.waves[waveIndex] == nil or waveSet.waves[target] == nil then
		return false, "That wave cannot move further."
	end
	waveSet.waves[waveIndex], waveSet.waves[target] = waveSet.waves[target], waveSet.waves[waveIndex]
	return true, nil
end

function Model.setBossFlag(
	project: any,
	waveSetId: string,
	waveIndex: number,
	isBoss: boolean
): (boolean, string?)
	local wave, message = waveAt(project, waveSetId, waveIndex)
	if wave == nil then
		return false, message
	end
	wave.isBoss = if isBoss then true else nil
	return true, nil
end

function Model.parseEntry(input: WaveEntryInput, enemyTypeIds: { [string]: boolean }): (any?, string?)
	local count = tonumber(trim(input.count))
	local spacingSeconds = tonumber(trim(input.spacingSeconds))
	local startDelaySeconds = tonumber(trim(input.startDelaySeconds))
	if count == nil or spacingSeconds == nil or startDelaySeconds == nil then
		return nil, "Count, spacing, and start delay must be numbers."
	end
	local entry: any = {
		enemyTypeId = trim(input.enemyTypeId),
		count = count,
		spacingSeconds = spacingSeconds,
		startDelaySeconds = startDelaySeconds,
	}
	for _, scaleField in { "healthScale", "rewardScale", "speedScale" } do
		local raw = trim((input :: any)[scaleField])
		if raw ~= "" then
			local scale = tonumber(raw)
			if scale == nil then
				return nil, `{scaleField} must be blank or a number.`
			end
			entry[scaleField] = scale
		end
	end
	local candidate = {
		id = "candidate",
		name = "candidate",
		endless = true,
		loopScaling = StageWaveDefaults.defaultLoopScaling(),
		waves = { { entries = { entry } } },
	}
	local message = firstError(StageSchema.validateWaveSet(candidate, enemyTypeIds))
	if message ~= nil then
		return nil, message
	end
	return entry, nil
end

function Model.addEntry(project: any, waveSetId: string, waveIndex: number, entry: any): (boolean, string?)
	local wave, message = waveAt(project, waveSetId, waveIndex)
	if wave == nil then
		return false, message
	end
	if #wave.entries >= Model.MAX_ENTRIES_PER_WAVE then
		return false, `Waves support at most {Model.MAX_ENTRIES_PER_WAVE} entries.`
	end
	if Model.waveSpawnTotal(wave) + entry.count > StageSchema.MAX_WAVE_SPAWNS then
		return false, `Waves cannot schedule more than {StageSchema.MAX_WAVE_SPAWNS} spawns.`
	end
	table.insert(wave.entries, deepCopy(entry))
	return true, nil
end

function Model.updateEntry(
	project: any,
	waveSetId: string,
	waveIndex: number,
	entryIndex: number,
	entry: any
): (boolean, string?)
	local wave, message = waveAt(project, waveSetId, waveIndex)
	if wave == nil then
		return false, message
	end
	if wave.entries[entryIndex] == nil then
		return false, `Wave {waveIndex} has no entry {entryIndex}.`
	end
	local otherSpawns = 0
	for index, existing in wave.entries do
		if index ~= entryIndex then
			otherSpawns += existing.count
		end
	end
	if otherSpawns + entry.count > StageSchema.MAX_WAVE_SPAWNS then
		return false, `Waves cannot schedule more than {StageSchema.MAX_WAVE_SPAWNS} spawns.`
	end
	wave.entries[entryIndex] = deepCopy(entry)
	return true, nil
end

function Model.deleteEntry(
	project: any,
	waveSetId: string,
	waveIndex: number,
	entryIndex: number
): (boolean, string?)
	local wave, message = waveAt(project, waveSetId, waveIndex)
	if wave == nil then
		return false, message
	end
	if wave.entries[entryIndex] == nil then
		return false, `Wave {waveIndex} has no entry {entryIndex}.`
	end
	if #wave.entries <= 1 then
		return false, "Waves must keep at least one entry."
	end
	table.remove(wave.entries, entryIndex)
	return true, nil
end

return table.freeze(Model)

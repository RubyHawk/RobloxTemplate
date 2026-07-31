--!strict

-- Seed data for the Stagewright wave-authoring collections. The default wave
-- set must keep reproducing the pre-schema-5 hardcoded runtime waves so that
-- migrated projects play identically until a designer edits them.

local StageWaveDefaults = {}

StageWaveDefaults.DEFAULT_WAVE_SET_ID = "default"

StageWaveDefaults.KNOWN_TAGS = table.freeze({ "Ground", "Flying", "Fast", "Armored", "Boss" })

export type Animations = {
	walkId: string,
	deathId: string,
}

export type EnemyType = {
	id: string,
	name: string,
	tags: { string },
	health: number,
	speed: number,
	reward: number,
	baseDamage: number,
	modelId: string,
	renderScale: number,
	tint: { r: number, g: number, b: number }?,
	animations: Animations?,
}

export type WaveEntry = {
	enemyTypeId: string,
	count: number,
	spacingSeconds: number,
	startDelaySeconds: number,
	healthScale: number?,
	rewardScale: number?,
	speedScale: number?,
}

export type Wave = {
	entries: { WaveEntry },
	isBoss: boolean?,
}

export type LoopScaling = {
	curve: "Linear" | "Exponential",
	healthPerLoop: number,
	rewardPerLoop: number,
	speedPerLoop: number,
	countPerLoop: number,
	spacingPerLoop: number,
	bossEveryWaves: number,
}

export type WaveSet = {
	id: string,
	name: string,
	waves: { Wave },
	endless: boolean,
	loopScaling: LoopScaling,
}

StageWaveDefaults.LOOP_CURVES = table.freeze({ "Linear", "Exponential" })

-- The canonical default curve. It must keep reproducing the pre-schema-6
-- behavior exactly: a linear 0.35 health and reward ramp per completed loop,
-- with no speed, count, or spacing growth and no independent boss cadence.
-- TemplateConfig re-exports this as the runtime fallback so the two can never
-- drift apart.
function StageWaveDefaults.defaultLoopScaling(): LoopScaling
	return {
		curve = "Linear",
		healthPerLoop = 0.35,
		rewardPerLoop = 0.35,
		speedPerLoop = 0,
		countPerLoop = 0,
		spacingPerLoop = 0,
		bossEveryWaves = 0,
	}
end

function StageWaveDefaults.enemyTypes(): { [string]: EnemyType }
	return {
		forest_grunt = {
			id = "forest_grunt",
			name = "Forest Grunt",
			tags = { "Ground" },
			health = 45,
			speed = 7,
			reward = 12,
			baseDamage = 1,
			modelId = "forest_grunt",
			renderScale = 1,
			tint = { r = 0.5, g = 0.375, b = 0.25 },
			animations = { walkId = "", deathId = "" },
		},
		forest_runner = {
			id = "forest_runner",
			name = "Forest Runner",
			tags = { "Ground", "Fast" },
			health = 28,
			speed = 11,
			reward = 14,
			baseDamage = 1,
			modelId = "forest_runner",
			renderScale = 0.875,
			tint = { r = 0.375, g = 0.75, b = 0.375 },
			animations = { walkId = "", deathId = "" },
		},
		bark_bruiser = {
			id = "bark_bruiser",
			name = "Bark Bruiser",
			tags = { "Ground", "Armored" },
			health = 120,
			speed = 5,
			reward = 22,
			baseDamage = 2,
			modelId = "bark_bruiser",
			renderScale = 1.25,
			tint = { r = 0.375, g = 0.25, b = 0.125 },
			animations = { walkId = "", deathId = "" },
		},
		sky_wisp = {
			id = "sky_wisp",
			name = "Sky Wisp",
			tags = { "Flying" },
			health = 36,
			speed = 9,
			reward = 16,
			baseDamage = 1,
			modelId = "sky_wisp",
			renderScale = 0.875,
			tint = { r = 0.625, g = 0.875, b = 1 },
			animations = { walkId = "", deathId = "" },
		},
		grove_titan = {
			id = "grove_titan",
			name = "Grove Titan",
			tags = { "Ground", "Boss" },
			health = 900,
			speed = 3.5,
			reward = 150,
			baseDamage = 5,
			modelId = "grove_titan",
			renderScale = 2.25,
			tint = { r = 0.25, g = 0.5, b = 0.25 },
			animations = { walkId = "", deathId = "" },
		},
	}
end

local function entry(
	enemyTypeId: string,
	count: number,
	spacingSeconds: number,
	startDelaySeconds: number,
	scales: { healthScale: number?, rewardScale: number?, speedScale: number? }?
): WaveEntry
	local result: WaveEntry = {
		enemyTypeId = enemyTypeId,
		count = count,
		spacingSeconds = spacingSeconds,
		startDelaySeconds = startDelaySeconds,
	}
	if scales ~= nil then
		result.healthScale = scales.healthScale
		result.rewardScale = scales.rewardScale
		result.speedScale = scales.speedScale
	end
	return result
end

function StageWaveDefaults.defaultWaveSet(): WaveSet
	-- Waves 1-4 mirror the legacy TowerDefenseCatalog wave loop exactly; waves
	-- 5-6 showcase mixed entries and a boss wave for migrated projects.
	return {
		id = StageWaveDefaults.DEFAULT_WAVE_SET_ID,
		name = "Default Waves",
		endless = true,
		loopScaling = StageWaveDefaults.defaultLoopScaling(),
		waves = {
			{ entries = { entry("forest_grunt", 8, 0.7, 0, { healthScale = 1, rewardScale = 1 }) } },
			{
				entries = {
					entry("forest_grunt", 12, 0.6, 0, { healthScale = 1.25, rewardScale = 1.08 }),
				},
			},
			{
				entries = {
					entry("forest_grunt", 16, 0.5, 0, { healthScale = 1.55, rewardScale = 1.16 }),
				},
			},
			{
				entries = {
					entry("forest_grunt", 22, 0.45, 0, { healthScale = 2, rewardScale = 1.25 }),
				},
			},
			{
				entries = {
					entry("forest_grunt", 10, 0.6, 0),
					entry("forest_runner", 8, 0.45, 4),
					entry("bark_bruiser", 4, 1.2, 8),
				},
			},
			{
				isBoss = true,
				entries = {
					entry("sky_wisp", 6, 0.8, 0),
					entry("grove_titan", 1, 1, 6),
				},
			},
		},
	}
end

local function isEmptyTable(value: any): boolean
	return type(value) ~= "table" or next(value) == nil
end

-- Fills in the wave-authoring collections on a project that predates them and
-- clones the default set under any wave-set id that levels reference but the
-- project does not define (the field used to be free text). Returns whether
-- anything changed.
function StageWaveDefaults.seed(project: any): boolean
	assert(type(project) == "table", "Stagewright project must be a table")
	local changed = false
	if isEmptyTable(project.enemyTypes) then
		project.enemyTypes = StageWaveDefaults.enemyTypes()
		changed = true
	end
	if type(project.waveSets) ~= "table" then
		project.waveSets = {}
		changed = true
	end
	if type(project.waveSets[StageWaveDefaults.DEFAULT_WAVE_SET_ID]) ~= "table" then
		project.waveSets[StageWaveDefaults.DEFAULT_WAVE_SET_ID] = StageWaveDefaults.defaultWaveSet()
		changed = true
	end
	if type(project.stages) == "table" then
		for _, stage in project.stages do
			local waveSetId = if type(stage) == "table" then stage.waveSetId else nil
			if
				type(waveSetId) == "string"
				and waveSetId ~= ""
				and #waveSetId <= 80
				and project.waveSets[waveSetId] == nil
			then
				local cloned = StageWaveDefaults.defaultWaveSet()
				cloned.id = waveSetId
				cloned.name = waveSetId
				project.waveSets[waveSetId] = cloned
				changed = true
			end
		end
	end
	if StageWaveDefaults.seedLoopScaling(project) then
		changed = true
	end
	if StageWaveDefaults.seedAnimations(project) then
		changed = true
	end
	return changed
end

-- Gives every authored enemy type the animation overrides introduced by schema
-- 7. Empty ids mean "use whatever the rig model declares", so nothing about how
-- an existing rig renders changes. Returns whether anything changed.
function StageWaveDefaults.seedAnimations(project: any): boolean
	assert(type(project) == "table", "Stagewright project must be a table")
	if type(project.enemyTypes) ~= "table" then
		return false
	end
	local changed = false
	for _, enemyType in project.enemyTypes do
		if type(enemyType) ~= "table" then
			continue
		end
		if type(enemyType.animations) ~= "table" then
			enemyType.animations = StageWaveDefaults.defaultAnimations()
			changed = true
		else
			local animations: any = enemyType.animations
			for _, field in { "walkId", "deathId" } do
				if type(animations[field]) ~= "string" then
					animations[field] = ""
					changed = true
				end
			end
		end
	end
	return changed
end

function StageWaveDefaults.defaultAnimations(): Animations
	return { walkId = "", deathId = "" }
end

-- Gives every authored wave set the loop-growth fields introduced by schema 6.
-- Existing sets keep playing identically because the seeded curve reproduces the
-- previous hardcoded ramp. Returns whether anything changed.
function StageWaveDefaults.seedLoopScaling(project: any): boolean
	assert(type(project) == "table", "Stagewright project must be a table")
	if type(project.waveSets) ~= "table" then
		return false
	end
	local changed = false
	for _, waveSet in project.waveSets do
		if type(waveSet) ~= "table" then
			continue
		end
		if type(waveSet.endless) ~= "boolean" then
			waveSet.endless = true
			changed = true
		end
		if type(waveSet.loopScaling) ~= "table" then
			waveSet.loopScaling = StageWaveDefaults.defaultLoopScaling()
			changed = true
		else
			local scaling: any = waveSet.loopScaling
			for field, fallback in StageWaveDefaults.defaultLoopScaling() :: any do
				if type(scaling[field]) ~= type(fallback) then
					scaling[field] = fallback
					changed = true
				end
			end
		end
	end
	return changed
end

return table.freeze(StageWaveDefaults)

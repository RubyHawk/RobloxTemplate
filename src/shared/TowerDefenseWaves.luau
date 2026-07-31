--!strict

-- Pure wave-scheduling math for the tower-defense runtime. A wave authored in
-- Stagewright expands into one spawn stream per entry; the simulation asks
-- which stream is due and advances it, so mixed enemy groups and delayed
-- reinforcements need no extra state on the match.
--
-- Authored wave sets loop forever. Every completed loop applies the set's
-- growth curve to health, reward, speed, spawn count, and spawn spacing, which
-- is what turns a short authored rhythm into an endless run.

local StageTypes = if script ~= nil then require(script.Parent.StageTypes) else require("./StageTypes")

local TowerDefenseWaves = {}

TowerDefenseWaves.MINIMUM_SPACING_SECONDS = 0.05
-- Enemies that outrun the fixed simulation step would skip past tower ranges
-- between samples, so growth on the speed axis is bounded regardless of curve.
TowerDefenseWaves.MAXIMUM_SPEED_MULTIPLIER = 8
-- Exponential authoring is useful for short curves, but deep Studio jumps can
-- overflow a Luau number. Keep every authored axis finite so enemies never
-- receive infinite health and rewards never become invalid profile values.
TowerDefenseWaves.MAXIMUM_LOOP_MULTIPLIER = 1_000_000
-- A single wave may never schedule more spawns than the authoring cap, however
-- steep the count curve gets; the scheduler and the per-player enemy cap are
-- both sized against this number.
TowerDefenseWaves.MAXIMUM_WAVE_SPAWNS = 500

export type LoopScaling = StageTypes.WaveLoopScaling

export type WaveScaling = {
	health: number,
	reward: number,
	speed: number,
	count: number,
	spacing: number,
	loops: number,
}

export type SpawnStream = {
	enemyTypeId: string,
	remaining: number,
	spacingSeconds: number,
	nextSpawnAt: number,
	healthScale: number,
	rewardScale: number,
	speedScale: number,
}

export type LegacyCatalogWave = {
	enemyId: string,
	count: number,
	spacingSeconds: number,
	healthScale: number,
	rewardScale: number,
}

local DEFAULT_SCALING: LoopScaling = table.freeze({
	curve = "Linear" :: "Linear",
	healthPerLoop = 0.35,
	rewardPerLoop = 0.35,
	speedPerLoop = 0,
	countPerLoop = 0,
	spacingPerLoop = 0,
	bossEveryWaves = 0,
})

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end

-- 1-based modulo lookup mirroring the legacy catalog loop; also returns the
-- set length so callers can scale difficulty per completed loop.
function TowerDefenseWaves.waveForIndex(
	waveSet: StageTypes.WaveSetDefinition,
	waveNumber: number
): (StageTypes.WaveDefinition, number)
	local waveCount = math.max(#waveSet.waves, 1)
	local index = ((math.max(math.floor(waveNumber), 1) - 1) % waveCount) + 1
	return waveSet.waves[index], waveCount
end

-- Bundles generated before schema 6 carry no growth curve; the caller supplies
-- the configured fallback so the runtime never invents difficulty of its own.
function TowerDefenseWaves.resolveScaling(waveSet: any, fallback: any): LoopScaling
	local authored = if type(waveSet) == "table" then waveSet.loopScaling else nil
	local source = if type(authored) == "table"
		then authored
		elseif type(fallback) == "table" then fallback
		else DEFAULT_SCALING
	return {
		curve = if source.curve == "Exponential" then "Exponential" else "Linear",
		healthPerLoop = math.max(finite(source.healthPerLoop, DEFAULT_SCALING.healthPerLoop), 0),
		rewardPerLoop = math.max(finite(source.rewardPerLoop, DEFAULT_SCALING.rewardPerLoop), 0),
		speedPerLoop = math.max(finite(source.speedPerLoop, 0), 0),
		countPerLoop = math.max(finite(source.countPerLoop, 0), 0),
		spacingPerLoop = math.max(finite(source.spacingPerLoop, 0), 0),
		bossEveryWaves = math.max(math.floor(finite(source.bossEveryWaves, 0)), 0),
	}
end

function TowerDefenseWaves.isEndless(waveSet: any): boolean
	return type(waveSet) == "table" and waveSet.endless ~= false
end

-- Completed loops of the authored set before this wave. Wave 1 is loop 0.
function TowerDefenseWaves.loopIndex(waveNumber: number, waveCount: number): number
	local waves = math.max(math.floor(waveCount), 1)
	return math.max(math.floor((math.max(math.floor(waveNumber), 1) - 1) / waves), 0)
end

function TowerDefenseWaves.multiplier(curve: string, rate: number, loops: number): number
	if rate <= 0 or loops <= 0 then
		return 1
	end
	local result: number
	if curve == "Exponential" then
		result = (1 + rate) ^ loops
	else
		result = 1 + rate * loops
	end
	if result ~= result or result == math.huge then
		return TowerDefenseWaves.MAXIMUM_LOOP_MULTIPLIER
	end
	return math.clamp(result, 1, TowerDefenseWaves.MAXIMUM_LOOP_MULTIPLIER)
end

-- Resolves every growth axis for one wave number. Spacing is returned as the
-- divisor applied to authored spacing, so larger always means harder.
function TowerDefenseWaves.scalingFor(
	scaling: LoopScaling,
	waveNumber: number,
	waveCount: number
): WaveScaling
	local loops = TowerDefenseWaves.loopIndex(waveNumber, waveCount)
	local curve = scaling.curve
	return {
		health = TowerDefenseWaves.multiplier(curve, scaling.healthPerLoop, loops),
		reward = TowerDefenseWaves.multiplier(curve, scaling.rewardPerLoop, loops),
		speed = math.min(
			TowerDefenseWaves.multiplier(curve, scaling.speedPerLoop, loops),
			TowerDefenseWaves.MAXIMUM_SPEED_MULTIPLIER
		),
		count = TowerDefenseWaves.multiplier(curve, scaling.countPerLoop, loops),
		spacing = TowerDefenseWaves.multiplier(curve, scaling.spacingPerLoop, loops),
		loops = loops,
	}
end

function TowerDefenseWaves.baseScaling(): WaveScaling
	return { health = 1, reward = 1, speed = 1, count = 1, spacing = 1, loops = 0 }
end

function TowerDefenseWaves.fromCatalogWave(wave: LegacyCatalogWave): StageTypes.WaveDefinition
	return {
		entries = {
			{
				enemyTypeId = wave.enemyId,
				count = wave.count,
				spacingSeconds = wave.spacingSeconds,
				startDelaySeconds = 0,
				healthScale = wave.healthScale,
				rewardScale = wave.rewardScale,
			},
		},
	}
end

function TowerDefenseWaves.buildStreams(
	wave: StageTypes.WaveDefinition,
	now: number,
	scaling: WaveScaling
): { SpawnStream }
	local streams: { SpawnStream } = {}
	-- Count growth is applied against a shared budget so a steep curve can never
	-- schedule a wave the spawn scheduler and enemy cap cannot drain.
	local budget = TowerDefenseWaves.MAXIMUM_WAVE_SPAWNS
	for _, entry in wave.entries do
		if budget <= 0 then
			break
		end
		local authoredCount = math.max(math.floor(entry.count), 1)
		local grownCount = math.max(math.floor(authoredCount * scaling.count + 0.5), 1)
		local count = math.min(grownCount, budget)
		budget -= count
		table.insert(streams, {
			enemyTypeId = entry.enemyTypeId,
			remaining = count,
			spacingSeconds = math.max(
				entry.spacingSeconds / scaling.spacing,
				TowerDefenseWaves.MINIMUM_SPACING_SECONDS
			),
			nextSpawnAt = now + math.max(entry.startDelaySeconds, 0),
			healthScale = (entry.healthScale or 1) * scaling.health,
			rewardScale = (entry.rewardScale or 1) * scaling.reward,
			speedScale = (entry.speedScale or 1) * scaling.speed,
		})
	end
	return streams
end

function TowerDefenseWaves.dueStreamIndex(streams: { SpawnStream }, now: number): number?
	for index, stream in streams do
		if stream.remaining > 0 and now >= stream.nextSpawnAt then
			return index
		end
	end
	return nil
end

function TowerDefenseWaves.remainingSpawns(streams: { SpawnStream }): number
	local total = 0
	for _, stream in streams do
		total += math.max(stream.remaining, 0)
	end
	return total
end

function TowerDefenseWaves.hasTag(tags: { string }, tag: string): boolean
	return table.find(tags, tag) ~= nil
end

function TowerDefenseWaves.armorMultiplier(tags: { string }, armoredMultiplier: number): number
	return if TowerDefenseWaves.hasTag(tags, "Armored") then math.clamp(armoredMultiplier, 0.05, 1) else 1
end

-- An authored boss flag always wins. A cadence additionally promotes every Nth
-- wave number, which lets an endless set keep a boss rhythm that does not
-- depend on how many waves the designer authored.
function TowerDefenseWaves.isBossWave(
	wave: StageTypes.WaveDefinition,
	bossEveryWaves: number?,
	waveNumber: number?
): boolean
	if wave.isBoss == true then
		return true
	end
	local cadence = math.floor(bossEveryWaves or 0)
	local number = math.floor(waveNumber or 0)
	return cadence > 0 and number > 0 and number % cadence == 0
end

return table.freeze(TowerDefenseWaves)

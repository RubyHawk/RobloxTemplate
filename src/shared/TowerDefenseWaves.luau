--!strict

-- Pure wave-scheduling math for the tower-defense runtime. A wave authored in
-- Stagewright expands into one spawn stream per entry; the simulation asks
-- which stream is due and advances it, so mixed enemy groups and delayed
-- reinforcements need no extra state on the match.

local StageTypes = if script ~= nil then require(script.Parent.StageTypes) else require("./StageTypes")

local TowerDefenseWaves = {}

TowerDefenseWaves.MINIMUM_SPACING_SECONDS = 0.05

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
	loopScale: number
): { SpawnStream }
	local streams: { SpawnStream } = {}
	for _, entry in wave.entries do
		table.insert(streams, {
			enemyTypeId = entry.enemyTypeId,
			remaining = math.max(math.floor(entry.count), 1),
			spacingSeconds = math.max(entry.spacingSeconds, TowerDefenseWaves.MINIMUM_SPACING_SECONDS),
			nextSpawnAt = now + math.max(entry.startDelaySeconds, 0),
			healthScale = (entry.healthScale or 1) * loopScale,
			rewardScale = (entry.rewardScale or 1) * loopScale,
			speedScale = entry.speedScale or 1,
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

function TowerDefenseWaves.isBossWave(wave: StageTypes.WaveDefinition): boolean
	return wave.isBoss == true
end

return table.freeze(TowerDefenseWaves)

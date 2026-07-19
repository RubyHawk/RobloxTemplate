--!strict

-- Dungeon (portal -> reserved-server boss fight) configuration compiler. Kept
-- dependency-free like CurrencyConfig and RuneModeConfig so TemplateConfig can
-- normalize per-recipe overrides and the Lune specs can exercise every
-- validation branch without a Roblox runtime.
--
-- Every tunable accepts a `DesignerConfig.dungeon` override. Numbers clamp to a
-- safe range with a fallback; the boss list is all-or-nothing (a partially
-- applied list could strand the default boss id), so any structural problem
-- falls back to the authored defaults wholesale, mirroring RuneModeConfig.

local DungeonConfig = {}

DungeonConfig.MAX_BOSSES = 8

export type Boss = {
	id: string,
	name: string,
	baseHealth: number,
	healthPerExtraPlayer: number,
	partyDpsPerPlayer: number,
	attackDamage: number,
	timeLimitSeconds: number,
	rewardCurrencyId: string,
	rewardAmount: number,
}

export type Dungeon = {
	partyMax: number,
	countdownSeconds: number,
	padPadding: number,
	padHeightTolerance: number,
	tickSeconds: number,
	snapshotSeconds: number,
	arenaSpawn: { number },
	bossOffset: { number },
	damageRingRadius: number,
	attackRingRadius: number,
	attackIntervalSeconds: number,
	teleportRetries: number,
	defaultBossId: string,
	bosses: { Boss },
}

local DEFAULT_BOSSES: { Boss } = {
	{
		id = "forest_warden",
		name = "Forest Warden",
		baseHealth = 2500,
		healthPerExtraPlayer = 1500,
		partyDpsPerPlayer = 120,
		attackDamage = 22,
		timeLimitSeconds = 120,
		rewardCurrencyId = "coins",
		rewardAmount = 5000,
	},
}

local DEFAULTS: Dungeon = {
	partyMax = 4,
	countdownSeconds = 5,
	padPadding = 1.5,
	padHeightTolerance = 8,
	tickSeconds = 0.2,
	snapshotSeconds = 0.15,
	-- The arena is authored far above the lobby map (see src/world/DungeonArena)
	-- so a public lobby server never streams it; the reserved dungeon server
	-- pivots arrivals onto it. Keep these in sync with the authored geometry.
	arenaSpawn = { 0, 503, 0 },
	bossOffset = { 0, 4, 55 },
	damageRingRadius = 46,
	attackRingRadius = 22,
	attackIntervalSeconds = 3,
	teleportRetries = 4,
	defaultBossId = "forest_warden",
	bosses = DEFAULT_BOSSES,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function number(raw: any, key: string, fallback: number, minimum: number, maximum: number): number
	local value = if type(raw) == "table" then raw[key] else nil
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function vector3(raw: any, key: string, fallback: { number }): { number }
	local value = if type(raw) == "table" then raw[key] else nil
	if type(value) ~= "table" or #value ~= 3 then
		return { fallback[1], fallback[2], fallback[3] }
	end
	local out: { number } = {}
	for index = 1, 3 do
		local component = value[index]
		if not isFiniteNumber(component) then
			return { fallback[1], fallback[2], fallback[3] }
		end
		out[index] = component
	end
	return out
end

local function copyBosses(bosses: { Boss }): { Boss }
	local result: { Boss } = {}
	for _, boss in bosses do
		table.insert(result, {
			id = boss.id,
			name = boss.name,
			baseHealth = boss.baseHealth,
			healthPerExtraPlayer = boss.healthPerExtraPlayer,
			partyDpsPerPlayer = boss.partyDpsPerPlayer,
			attackDamage = boss.attackDamage,
			timeLimitSeconds = boss.timeLimitSeconds,
			rewardCurrencyId = boss.rewardCurrencyId,
			rewardAmount = boss.rewardAmount,
		})
	end
	return result
end

-- A boss entry only applies if every field is present and in range. Any bad
-- entry rejects the whole override list back to the authored defaults so the
-- configured `defaultBossId` can never point at a dropped boss.
local function normalizedBoss(raw: any, used: { [string]: boolean }): Boss?
	if type(raw) ~= "table" then
		return nil
	end
	local id = raw.id
	if
		type(id) ~= "string"
		or #id < 1
		or #id > 32
		or string.match(id, "^[a-z][a-z0-9_]*$") == nil
		or used[id]
	then
		return nil
	end
	local rewardCurrencyId = raw.rewardCurrencyId
	if type(rewardCurrencyId) ~= "string" or #rewardCurrencyId < 1 or #rewardCurrencyId > 32 then
		return nil
	end
	local baseHealth = raw.baseHealth
	local healthPerExtraPlayer = raw.healthPerExtraPlayer
	local partyDpsPerPlayer = raw.partyDpsPerPlayer
	local attackDamage = raw.attackDamage
	local timeLimitSeconds = raw.timeLimitSeconds
	local rewardAmount = raw.rewardAmount
	if
		not isFiniteNumber(baseHealth)
		or baseHealth < 1
		or not isFiniteNumber(healthPerExtraPlayer)
		or healthPerExtraPlayer < 0
		or not isFiniteNumber(partyDpsPerPlayer)
		or partyDpsPerPlayer < 1
		or not isFiniteNumber(attackDamage)
		or attackDamage < 0
		or not isFiniteNumber(timeLimitSeconds)
		or timeLimitSeconds < 5
		or not isFiniteNumber(rewardAmount)
		or rewardAmount < 0
	then
		return nil
	end
	local name = if type(raw.name) == "string" and #raw.name >= 1 and #raw.name <= 40 then raw.name else id
	used[id] = true
	return {
		id = id,
		name = name,
		baseHealth = baseHealth,
		healthPerExtraPlayer = healthPerExtraPlayer,
		partyDpsPerPlayer = partyDpsPerPlayer,
		attackDamage = attackDamage,
		timeLimitSeconds = timeLimitSeconds,
		rewardCurrencyId = rewardCurrencyId,
		rewardAmount = rewardAmount,
	}
end

local function normalizedBosses(raw: any): { Boss }
	if type(raw) ~= "table" then
		return copyBosses(DEFAULT_BOSSES)
	end
	local bosses: { Boss } = {}
	local used: { [string]: boolean } = {}
	for _, candidate in raw do
		if #bosses >= DungeonConfig.MAX_BOSSES then
			break
		end
		local boss = normalizedBoss(candidate, used)
		if boss == nil then
			return copyBosses(DEFAULT_BOSSES)
		end
		table.insert(bosses, boss)
	end
	if #bosses == 0 then
		return copyBosses(DEFAULT_BOSSES)
	end
	return bosses
end

local function resolveDefaultBossId(raw: any, bosses: { Boss }): string
	local requested = if type(raw) == "table" and type(raw.defaultBossId) == "string"
		then raw.defaultBossId
		else nil
	if requested ~= nil then
		for _, boss in bosses do
			if boss.id == requested then
				return requested
			end
		end
	end
	return bosses[1].id
end

-- Returns a fully populated, range-checked dungeon configuration. `raw` is the
-- optional `DesignerConfig.dungeon` table; anything missing or malformed falls
-- back to the authored defaults.
function DungeonConfig.normalize(raw: any): Dungeon
	local bosses = normalizedBosses(if type(raw) == "table" then raw.bosses else nil)
	return {
		partyMax = math.floor(number(raw, "partyMax", DEFAULTS.partyMax, 1, 12)),
		countdownSeconds = number(raw, "countdownSeconds", DEFAULTS.countdownSeconds, 1, 60),
		padPadding = number(raw, "padPadding", DEFAULTS.padPadding, 0, 50),
		padHeightTolerance = number(raw, "padHeightTolerance", DEFAULTS.padHeightTolerance, 1, 50),
		tickSeconds = number(raw, "tickSeconds", DEFAULTS.tickSeconds, 0.05, 1),
		snapshotSeconds = number(raw, "snapshotSeconds", DEFAULTS.snapshotSeconds, 0.05, 2),
		arenaSpawn = vector3(raw, "arenaSpawn", DEFAULTS.arenaSpawn),
		bossOffset = vector3(raw, "bossOffset", DEFAULTS.bossOffset),
		damageRingRadius = number(raw, "damageRingRadius", DEFAULTS.damageRingRadius, 1, 500),
		attackRingRadius = number(raw, "attackRingRadius", DEFAULTS.attackRingRadius, 1, 500),
		attackIntervalSeconds = number(raw, "attackIntervalSeconds", DEFAULTS.attackIntervalSeconds, 0.5, 30),
		teleportRetries = math.floor(number(raw, "teleportRetries", DEFAULTS.teleportRetries, 0, 10)),
		defaultBossId = resolveDefaultBossId(raw, bosses),
		bosses = bosses,
	}
end

function DungeonConfig.bossById(dungeon: Dungeon, bossId: string): Boss?
	for _, boss in dungeon.bosses do
		if boss.id == bossId then
			return boss
		end
	end
	return nil
end

return table.freeze(DungeonConfig)

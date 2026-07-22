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
DungeonConfig.AUTHORED_PARTY_SLOTS = 4
DungeonConfig.MAX_TELEPORT_RETRIES = 4

export type Weapon = {
	id: string,
	name: string,
	toolName: string,
	damage: number,
	rangeStuds: number,
	verticalToleranceStuds: number,
	facingDot: number,
	cooldownSeconds: number,
}

export type Camera = {
	fieldOfView: number,
	minZoom: number,
	maxZoom: number,
}

export type Boss = {
	id: string,
	name: string,
	baseHealth: number,
	healthPerExtraPlayer: number,
	partyDpsPerPlayer: number,
	attackDamagePerHit: number,
	attackDamage: number,
	timeLimitSeconds: number,
	rewardCurrencyId: string,
	rewardAmount: number,
	rewardItemId: string?,
	rewardItemQuantity: number?,
}

export type Dungeon = {
	weapons: { [string]: Weapon },
	equipmentSlot: string,
	starterWeaponId: string,
	camera: Camera,
	partyMax: number,
	countdownSeconds: number,
	padPadding: number,
	padHeightTolerance: number,
	tickSeconds: number,
	snapshotSeconds: number,
	readySeconds: number,
	walkSpeed: number,
	dodgeSpeed: number,
	dodgeDurationSeconds: number,
	dodgeCooldownSeconds: number,
	wipeGraceSeconds: number,
	strikeRaycastPaddingStuds: number,
	enrageHealthFraction: number,
	enrageAttackIntervalMultiplier: number,
	enrageDamageMultiplier: number,
	slamRadiusStuds: number,
	slamHeightToleranceStuds: number,
	slamIntervalSeconds: number,
	slamTelegraphSeconds: number,
	arenaSpawn: { number },
	bossOffset: { number },
	damageRingRadius: number,
	attackRingRadius: number,
	attackIntervalSeconds: number,
	telegraphSeconds: number,
	attackCooldownSeconds: number,
	proximityAutoDps: boolean,
	teleportRetries: number,
	arrivalTimeoutSeconds: number,
	profileReadyTimeoutSeconds: number,
	defaultBossId: string,
	bosses: { Boss },
}

local WEAPON_IDS = { "warden_blade", "thorn_spear", "grove_hammer" }

local DEFAULT_WEAPONS: { [string]: Weapon } = {
	warden_blade = {
		id = "warden_blade",
		name = "Warden Blade",
		toolName = "WardenBlade",
		damage = 70,
		rangeStuds = 13,
		verticalToleranceStuds = 9,
		-- The current encounter has one server-known boss target. Attacks therefore
		-- auto-target inside the authoritative range instead of trusting a freshly
		-- replicated character facing direction from the client.
		facingDot = -1,
		cooldownSeconds = 0.45,
	},
	thorn_spear = {
		id = "thorn_spear",
		name = "Thorn Spear",
		toolName = "ThornSpear",
		damage = 58,
		rangeStuds = 18,
		verticalToleranceStuds = 10,
		facingDot = -1,
		cooldownSeconds = 0.4,
	},
	grove_hammer = {
		id = "grove_hammer",
		name = "Grove Hammer",
		toolName = "GroveHammer",
		damage = 120,
		rangeStuds = 10.5,
		verticalToleranceStuds = 8,
		facingDot = -1,
		cooldownSeconds = 0.8,
	},
}

local DEFAULT_BOSSES: { Boss } = {
	{
		id = "forest_warden",
		name = "Forest Warden",
		-- The three default weapons land between roughly 29 and 35 seconds solo.
		-- Matching per-player health scaling keeps a full party in the same band.
		baseHealth = 4500,
		healthPerExtraPlayer = 4500,
		partyDpsPerPlayer = 150,
		attackDamagePerHit = 70,
		attackDamage = 24,
		timeLimitSeconds = 120,
		rewardCurrencyId = "coins",
		rewardAmount = 5000,
		rewardItemId = "grove_hammer",
		rewardItemQuantity = 1,
	},
	{
		-- A tougher second encounter so boss selection is meaningful: more health,
		-- harder-hitting slams, a longer timer, and a richer reward with a
		-- different weapon drop. Same authored arena/core; only the tuning differs.
		id = "grove_matron",
		name = "Grove Matron",
		baseHealth = 6200,
		healthPerExtraPlayer = 6200,
		partyDpsPerPlayer = 150,
		attackDamagePerHit = 85,
		attackDamage = 32,
		timeLimitSeconds = 140,
		rewardCurrencyId = "coins",
		rewardAmount = 8000,
		rewardItemId = "thorn_spear",
		rewardItemQuantity = 1,
	},
}

local DEFAULTS: Dungeon = {
	weapons = DEFAULT_WEAPONS,
	equipmentSlot = "DungeonWeapon",
	starterWeaponId = "warden_blade",
	camera = {
		fieldOfView = 74,
		minZoom = 8,
		maxZoom = 24,
	},
	partyMax = 4,
	countdownSeconds = 5,
	padPadding = 1.5,
	padHeightTolerance = 8,
	tickSeconds = 0.2,
	snapshotSeconds = 0.15,
	readySeconds = 3,
	walkSpeed = 18,
	dodgeSpeed = 34,
	dodgeDurationSeconds = 0.28,
	dodgeCooldownSeconds = 1.25,
	wipeGraceSeconds = 2,
	strikeRaycastPaddingStuds = 1.5,
	enrageHealthFraction = 0.5,
	enrageAttackIntervalMultiplier = 0.7,
	enrageDamageMultiplier = 1.4,
	slamRadiusStuds = 15,
	slamHeightToleranceStuds = 14,
	slamIntervalSeconds = 3,
	slamTelegraphSeconds = 1.1,
	-- The arena is authored far above the lobby map (see src/world/DungeonArena)
	-- so a public lobby server never streams it; the reserved dungeon server
	-- pivots arrivals onto it. Keep these in sync with the authored geometry.
	arenaSpawn = { 0, 503, -28 },
	bossOffset = { 0, 4, 58 },
	-- These legacy aliases describe the starter blade and target-centered slam.
	-- Close-range weapons fight inside the slam, while the spear can work its edge;
	-- either way the telegraph leaves enough room for a deliberate dodge.
	damageRingRadius = 13,
	attackRingRadius = 15,
	attackIntervalSeconds = 3,
	telegraphSeconds = 1.1,
	-- Players attack by clicking/tapping; the server enforces this per-player
	-- cooldown between accepted hits. proximityAutoDps keeps the old "stand in
	-- the ring and auto-damage" behavior available as an opt-in fallback.
	attackCooldownSeconds = 0.45,
	proximityAutoDps = false,
	teleportRetries = 4,
	-- Cross-server arrivals can be staggered even when the source teleports the
	-- whole party together. This covers the full retry backoff plus teleport
	-- startup time; later arrivals are explicitly returned to the lobby.
	arrivalTimeoutSeconds = 45,
	profileReadyTimeoutSeconds = 30,
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

local function boolean(raw: any, key: string, fallback: boolean): boolean
	local value = if type(raw) == "table" then raw[key] else nil
	if type(value) ~= "boolean" then
		return fallback
	end
	return value
end

local function stringValue(
	raw: any,
	key: string,
	fallback: string,
	pattern: string,
	maximumLength: number
): string
	local value = if type(raw) == "table" then raw[key] else nil
	if
		type(value) ~= "string"
		or #value < 1
		or #value > maximumLength
		or string.match(value, pattern) == nil
	then
		return fallback
	end
	return value
end

local function copyWeapon(weapon: Weapon): Weapon
	return {
		id = weapon.id,
		name = weapon.name,
		toolName = weapon.toolName,
		damage = weapon.damage,
		rangeStuds = weapon.rangeStuds,
		verticalToleranceStuds = weapon.verticalToleranceStuds,
		facingDot = weapon.facingDot,
		cooldownSeconds = weapon.cooldownSeconds,
	}
end

local function normalizedWeapons(raw: any): { [string]: Weapon }
	local weapons: { [string]: Weapon } = {}
	for _, id in WEAPON_IDS do
		local fallback = DEFAULT_WEAPONS[id]
		local candidate = if type(raw) == "table" and type(raw[id]) == "table" then raw[id] else nil
		if candidate == nil then
			weapons[id] = copyWeapon(fallback)
			continue
		end
		weapons[id] = {
			id = id,
			name = stringValue(candidate, "name", fallback.name, "^[%w ]+$", 40),
			toolName = stringValue(candidate, "toolName", fallback.toolName, "^[%a][%w_]*$", 40),
			damage = number(candidate, "damage", fallback.damage, 1, 10_000),
			rangeStuds = number(candidate, "rangeStuds", fallback.rangeStuds, 1, 100),
			verticalToleranceStuds = number(
				candidate,
				"verticalToleranceStuds",
				fallback.verticalToleranceStuds,
				1,
				50
			),
			facingDot = number(candidate, "facingDot", fallback.facingDot, -1, 1),
			cooldownSeconds = number(candidate, "cooldownSeconds", fallback.cooldownSeconds, 0.1, 5),
		}
	end
	return weapons
end

local function normalizedCamera(raw: any): Camera
	local cameraRaw = if type(raw) == "table" and type(raw.camera) == "table" then raw.camera else nil
	local minZoom = number(cameraRaw, "minZoom", DEFAULTS.camera.minZoom, 0.5, 64)
	local maxZoom = number(cameraRaw, "maxZoom", DEFAULTS.camera.maxZoom, 0.5, 128)
	if maxZoom < minZoom then
		maxZoom = minZoom
	end
	return {
		fieldOfView = number(cameraRaw, "fieldOfView", DEFAULTS.camera.fieldOfView, 40, 100),
		minZoom = minZoom,
		maxZoom = maxZoom,
	}
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
			attackDamagePerHit = boss.attackDamagePerHit,
			attackDamage = boss.attackDamage,
			timeLimitSeconds = boss.timeLimitSeconds,
			rewardCurrencyId = boss.rewardCurrencyId,
			rewardAmount = boss.rewardAmount,
			rewardItemId = boss.rewardItemId,
			rewardItemQuantity = boss.rewardItemQuantity,
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
	-- attackDamagePerHit is optional (defaults to the authored value) so recipes
	-- need not restate every combat number; a present-but-invalid value still
	-- rejects the whole list, matching the all-or-nothing rule above.
	local attackDamagePerHit = raw.attackDamagePerHit
	if attackDamagePerHit == nil then
		attackDamagePerHit = DEFAULT_WEAPONS.warden_blade.damage
	elseif not isFiniteNumber(attackDamagePerHit) or attackDamagePerHit < 1 then
		return nil
	end
	local rewardItemId: string? = nil
	local rewardItemQuantity: number? = nil
	if raw.rewardItemId ~= nil then
		if
			type(raw.rewardItemId) ~= "string"
			or #raw.rewardItemId < 1
			or #raw.rewardItemId > 64
			or string.match(raw.rewardItemId, "^[a-z][a-z0-9_]*$") == nil
		then
			return nil
		end
		rewardItemId = raw.rewardItemId
		local quantity = if raw.rewardItemQuantity == nil then 1 else raw.rewardItemQuantity
		if not isFiniteNumber(quantity) or quantity % 1 ~= 0 or quantity < 1 or quantity > 100 then
			return nil
		end
		rewardItemQuantity = quantity
	elseif raw.rewardItemQuantity ~= nil then
		-- A quantity without an item id is almost certainly a recipe mistake.
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
		attackDamagePerHit = attackDamagePerHit,
		attackDamage = attackDamage,
		timeLimitSeconds = timeLimitSeconds,
		rewardCurrencyId = rewardCurrencyId,
		rewardAmount = rewardAmount,
		rewardItemId = rewardItemId,
		rewardItemQuantity = rewardItemQuantity,
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
	local weapons = normalizedWeapons(if type(raw) == "table" then raw.weapons else nil)
	local requestedStarter = if type(raw) == "table" then raw.starterWeaponId else nil
	local starterWeaponId = if type(requestedStarter) == "string"
			and weapons[requestedStarter] ~= nil
		then requestedStarter
		else DEFAULTS.starterWeaponId
	local starterWeapon = weapons[starterWeaponId]
	local walkSpeed = number(raw, "walkSpeed", DEFAULTS.walkSpeed, 6, 32)
	local dodgeSpeed = math.max(walkSpeed, number(raw, "dodgeSpeed", DEFAULTS.dodgeSpeed, 8, 80))
	-- New slam names win when both are present. The legacy aliases remain equal
	-- so existing runtime code and older recipe files continue to behave.
	local legacySlamRadius = number(raw, "attackRingRadius", DEFAULTS.slamRadiusStuds, 4, 100)
	local slamRadiusStuds = number(raw, "slamRadiusStuds", legacySlamRadius, 4, 100)
	local legacySlamInterval = number(raw, "attackIntervalSeconds", DEFAULTS.slamIntervalSeconds, 0.5, 30)
	local slamIntervalSeconds = number(raw, "slamIntervalSeconds", legacySlamInterval, 0.5, 30)
	local legacySlamTelegraph = number(raw, "telegraphSeconds", DEFAULTS.slamTelegraphSeconds, 0.1, 10)
	local slamTelegraphSeconds = number(raw, "slamTelegraphSeconds", legacySlamTelegraph, 0.1, 10)
	return {
		weapons = weapons,
		equipmentSlot = stringValue(raw, "equipmentSlot", DEFAULTS.equipmentSlot, "^[%a][%w_]*$", 32),
		starterWeaponId = starterWeaponId,
		camera = normalizedCamera(raw),
		partyMax = math.floor(
			number(raw, "partyMax", DEFAULTS.partyMax, 1, DungeonConfig.AUTHORED_PARTY_SLOTS)
		),
		countdownSeconds = number(raw, "countdownSeconds", DEFAULTS.countdownSeconds, 1, 60),
		padPadding = number(raw, "padPadding", DEFAULTS.padPadding, 0, 50),
		padHeightTolerance = number(raw, "padHeightTolerance", DEFAULTS.padHeightTolerance, 1, 50),
		tickSeconds = number(raw, "tickSeconds", DEFAULTS.tickSeconds, 0.05, 1),
		snapshotSeconds = number(raw, "snapshotSeconds", DEFAULTS.snapshotSeconds, 0.05, 2),
		readySeconds = number(raw, "readySeconds", DEFAULTS.readySeconds, 0, 15),
		walkSpeed = walkSpeed,
		dodgeSpeed = dodgeSpeed,
		dodgeDurationSeconds = number(raw, "dodgeDurationSeconds", DEFAULTS.dodgeDurationSeconds, 0.1, 1),
		dodgeCooldownSeconds = number(raw, "dodgeCooldownSeconds", DEFAULTS.dodgeCooldownSeconds, 0.2, 10),
		wipeGraceSeconds = number(raw, "wipeGraceSeconds", DEFAULTS.wipeGraceSeconds, 0.25, 10),
		strikeRaycastPaddingStuds = number(
			raw,
			"strikeRaycastPaddingStuds",
			DEFAULTS.strikeRaycastPaddingStuds,
			0,
			5
		),
		enrageHealthFraction = number(raw, "enrageHealthFraction", DEFAULTS.enrageHealthFraction, 0.1, 0.9),
		enrageAttackIntervalMultiplier = number(
			raw,
			"enrageAttackIntervalMultiplier",
			DEFAULTS.enrageAttackIntervalMultiplier,
			0.25,
			1
		),
		enrageDamageMultiplier = number(raw, "enrageDamageMultiplier", DEFAULTS.enrageDamageMultiplier, 1, 5),
		slamRadiusStuds = slamRadiusStuds,
		slamHeightToleranceStuds = number(
			raw,
			"slamHeightToleranceStuds",
			DEFAULTS.slamHeightToleranceStuds,
			2,
			50
		),
		slamIntervalSeconds = slamIntervalSeconds,
		slamTelegraphSeconds = slamTelegraphSeconds,
		arenaSpawn = vector3(raw, "arenaSpawn", DEFAULTS.arenaSpawn),
		bossOffset = vector3(raw, "bossOffset", DEFAULTS.bossOffset),
		damageRingRadius = number(raw, "damageRingRadius", starterWeapon.rangeStuds, 1, 500),
		attackRingRadius = slamRadiusStuds,
		attackIntervalSeconds = slamIntervalSeconds,
		telegraphSeconds = slamTelegraphSeconds,
		attackCooldownSeconds = number(raw, "attackCooldownSeconds", starterWeapon.cooldownSeconds, 0.05, 5),
		proximityAutoDps = boolean(raw, "proximityAutoDps", DEFAULTS.proximityAutoDps),
		teleportRetries = math.floor(
			number(raw, "teleportRetries", DEFAULTS.teleportRetries, 0, DungeonConfig.MAX_TELEPORT_RETRIES)
		),
		arrivalTimeoutSeconds = number(raw, "arrivalTimeoutSeconds", DEFAULTS.arrivalTimeoutSeconds, 3, 60),
		profileReadyTimeoutSeconds = number(
			raw,
			"profileReadyTimeoutSeconds",
			DEFAULTS.profileReadyTimeoutSeconds,
			3,
			60
		),
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

function DungeonConfig.weaponById(dungeon: Dungeon, weaponId: string): Weapon?
	return dungeon.weapons[weaponId]
end

return table.freeze(DungeonConfig)

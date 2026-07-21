--!strict

-- Pure dungeon combat + occupancy math. No Roblox globals, so the Lune specs can
-- exercise boss scaling, damage application, ring checks, and countdown timing
-- without a runtime. PortalService and DungeonService supply the Vector3/os.clock
-- inputs; every authority decision (who is on the pad, how much health the boss
-- has, whether it is defeated) is computed here and stays on the server.

-- Dual-path require so the Lune specs (no `script`) and the Roblox runtime both
-- resolve the sibling module, matching StageExport/StageSchema in this folder.
local DungeonConfig = if script ~= nil
	then require(script.Parent.DungeonConfig)
	else require("./DungeonConfig")

local DungeonLogic = {}

export type PartyManifest = {
	kind: "DungeonParty",
	v: number,
	launchId: string,
	party: { number },
}

local function validUserId(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value > 0
		and value <= 9e15
end

-- Returns a dense, unique, bounded user-id list. TeleportData is visible to the
-- client, so this parser only establishes session shape and membership; rewards
-- and boss selection remain configured on the destination server.
function DungeonLogic.normalizePartyIds(raw: any, partyMax: number): { number }?
	if type(raw) ~= "table" then
		return nil
	end
	local entryCount = 0
	local largestIndex = 0
	for key in raw do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil
		end
		entryCount += 1
		largestIndex = math.max(largestIndex, key)
	end
	local limit = math.max(0, math.floor(partyMax))
	if entryCount < 1 or entryCount > limit or largestIndex ~= entryCount then
		return nil
	end
	local result: { number } = {}
	local seen: { [number]: boolean } = {}
	for index = 1, entryCount do
		local userId = raw[index]
		if not validUserId(userId) or seen[userId] then
			return nil
		end
		seen[userId] = true
		result[index] = userId
	end
	return result
end

function DungeonLogic.normalizePartyManifest(raw: any, partyMax: number): PartyManifest?
	if type(raw) ~= "table" or raw.kind ~= "DungeonParty" or raw.v ~= 1 then
		return nil
	end
	local allowedKeys: { [string]: boolean } = {
		kind = true,
		v = true,
		launchId = true,
		party = true,
	}
	local keyCount = 0
	for key in raw do
		if type(key) ~= "string" or allowedKeys[key] ~= true then
			return nil
		end
		keyCount += 1
	end
	if keyCount ~= 4 then
		return nil
	end
	local launchId = raw.launchId
	if
		type(launchId) ~= "string"
		or #launchId < 1
		or #launchId > 64
		or string.match(launchId, "^[%w_-]+$") == nil
	then
		return nil
	end
	local party = DungeonLogic.normalizePartyIds(raw.party, partyMax)
	if party == nil then
		return nil
	end
	return {
		kind = "DungeonParty",
		v = 1,
		launchId = launchId,
		party = party,
	}
end

local function finiteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Pure server-side strike geometry. `dx/dy/dz` points from the attacker to the
-- boss and `lookX/lookZ` is the attacker's horizontal facing. The client never
-- supplies any of these values; DungeonService derives them from the replicated
-- character and authored boss core before doing its separate obstruction raycast.
function DungeonLogic.canStrike(
	dx: number,
	dy: number,
	dz: number,
	lookX: number,
	lookZ: number,
	rangeStuds: number,
	verticalToleranceStuds: number,
	minimumFacingDot: number
): boolean
	if
		not finiteNumber(dx)
		or not finiteNumber(dy)
		or not finiteNumber(dz)
		or not finiteNumber(lookX)
		or not finiteNumber(lookZ)
		or not finiteNumber(rangeStuds)
		or not finiteNumber(verticalToleranceStuds)
		or not finiteNumber(minimumFacingDot)
		or rangeStuds < 0
		or verticalToleranceStuds < 0
	then
		return false
	end
	if math.abs(dy) > verticalToleranceStuds then
		return false
	end

	local horizontalDistanceSquared = dx * dx + dz * dz
	if horizontalDistanceSquared > rangeStuds * rangeStuds then
		return false
	end
	-- At effectively the same horizontal point there is no meaningful direction
	-- to face, so range/height authority is sufficient.
	if horizontalDistanceSquared <= 1e-8 then
		return true
	end

	local lookLengthSquared = lookX * lookX + lookZ * lookZ
	if lookLengthSquared <= 1e-8 then
		return false
	end
	local facingDot = (lookX * dx + lookZ * dz) / math.sqrt(lookLengthSquared * horizontalDistanceSquared)
	return facingDot >= math.clamp(minimumFacingDot, -1, 1)
end

-- The MVP encounter has exactly two phases: calm above the configured threshold
-- and enraged at or below it. Keeping the transition pure avoids an extensible
-- phase framework until a second boss actually needs one.
function DungeonLogic.phaseForHealth(
	currentHealth: number,
	maxHealth: number,
	enrageHealthFraction: number
): number
	if
		not finiteNumber(currentHealth)
		or not finiteNumber(maxHealth)
		or not finiteNumber(enrageHealthFraction)
		or maxHealth <= 0
	then
		return 1
	end
	local threshold = maxHealth * math.clamp(enrageHealthFraction, 0, 1)
	return if currentHealth <= threshold then 2 else 1
end

-- Tracks the start of a continuous no-combatants window. Any remaining living
-- party member clears the timer; eliminated players are excluded by the caller.
function DungeonLogic.nextAllDeadSince(allDeadSince: number?, aliveCount: number, now: number): number?
	if not finiteNumber(aliveCount) or not finiteNumber(now) then
		return nil
	end
	if aliveCount > 0 then
		return nil
	end
	if allDeadSince ~= nil and finiteNumber(allDeadSince) then
		return allDeadSince
	end
	return now
end

function DungeonLogic.isPartyWiped(allDeadSince: number?, now: number, wipeGraceSeconds: number): boolean
	if
		allDeadSince == nil
		or not finiteNumber(allDeadSince)
		or not finiteNumber(now)
		or not finiteNumber(wipeGraceSeconds)
	then
		return false
	end
	return now - allDeadSince >= math.max(0, wipeGraceSeconds)
end

-- Cylinder occupancy check shared by the portal pad and the boss rings: `dx/dy/dz`
-- is the offset from the center to the point. The horizontal distance must be
-- within `radius` and the vertical offset within `heightTolerance`. Mirrors the
-- authored RuneCircle geometry test but takes plain numbers so it is testable.
function DungeonLogic.isWithinCylinder(
	dx: number,
	dy: number,
	dz: number,
	radius: number,
	heightTolerance: number
): boolean
	if math.abs(dy) > heightTolerance then
		return false
	end
	return (dx * dx + dz * dz) <= radius * radius
end

-- Boss health scales with the number of players who actually arrived so a solo
-- run and a full party both take a comparable amount of time.
function DungeonLogic.bossMaxHealth(boss: DungeonConfig.Boss, playerCount: number): number
	local extra = math.max(0, playerCount - 1)
	return boss.baseHealth + boss.healthPerExtraPlayer * extra
end

-- Total damage-per-second the boss takes given how many players are inside the
-- damage ring this tick. Standing outside the ring contributes nothing.
function DungeonLogic.partyDps(boss: DungeonConfig.Boss, attackersInRange: number): number
	return boss.partyDpsPerPlayer * math.max(0, attackersInRange)
end

-- Applies `dps` for `deltaSeconds`, clamped so health never drops below zero.
function DungeonLogic.applyDamage(currentHealth: number, dps: number, deltaSeconds: number): number
	local remaining = currentHealth - dps * math.max(0, deltaSeconds)
	if remaining < 0 then
		return 0
	end
	return remaining
end

-- Applies a single validated player hit, clamped so health never drops below
-- zero. Negative damage never heals.
function DungeonLogic.applyHit(currentHealth: number, damage: number): number
	local remaining = currentHealth - math.max(0, damage)
	if remaining < 0 then
		return 0
	end
	return remaining
end

function DungeonLogic.isDefeated(health: number): boolean
	return health <= 0
end

-- HUD helper: 0..1 fraction of the boss health bar.
function DungeonLogic.healthFraction(currentHealth: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end
	return math.clamp(currentHealth / maxHealth, 0, 1)
end

-- Whole seconds left on a countdown, never negative. `deadline` and `now` share
-- the same clock (os.clock on the server).
function DungeonLogic.countdownRemaining(deadline: number, now: number): number
	return math.max(0, math.ceil(deadline - now))
end

-- Caps a pad roster to the configured maximum, preserving arrival order. The
-- service passes stable identifiers (user ids); the first `partyMax` win a seat.
function DungeonLogic.clampParty(orderedUserIds: { number }, partyMax: number): { number }
	local limit = math.max(0, partyMax)
	if #orderedUserIds <= limit then
		local copy: { number } = {}
		for _, id in orderedUserIds do
			table.insert(copy, id)
		end
		return copy
	end
	local capped: { number } = {}
	for index = 1, limit do
		capped[index] = orderedUserIds[index]
	end
	return capped
end

return DungeonLogic

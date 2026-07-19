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

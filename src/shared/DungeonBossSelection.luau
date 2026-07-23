--!strict

-- Pure boss-selection resolution + session-record validation for the dungeon.
-- Dependency-free (no Roblox globals, injected validators) so the Lune specs can
-- exercise every precedence branch without a runtime, matching DungeonLogic.
--
-- The reserved server never trusts client-visible TeleportData for the boss. The
-- lobby resolves one boss id per launch and writes an opaque session record to a
-- store keyed by the server-generated launch id; the reserved server reads it back and
-- re-validates the shape here before running that boss.

local DungeonBossSelection = {}

export type SessionRecord = {
	v: number,
	bossId: string,
	launchId: string,
}

-- Precedence: forced event boss > party (pad leader) pick > personal saved pick
-- > configured default. Each candidate is only honored when `isValidBossId`
-- accepts it, so a stale or unknown id (a boss removed from a recipe, an empty
-- string) safely falls through to the next source.
function DungeonBossSelection.resolveBossId(
	eventBossId: string?,
	partyPickId: string?,
	personalId: string?,
	defaultBossId: string,
	isValidBossId: (string) -> boolean
): string
	if type(eventBossId) == "string" and eventBossId ~= "" and isValidBossId(eventBossId) then
		return eventBossId
	end
	if type(partyPickId) == "string" and partyPickId ~= "" and isValidBossId(partyPickId) then
		return partyPickId
	end
	if type(personalId) == "string" and personalId ~= "" and isValidBossId(personalId) then
		return personalId
	end
	return defaultBossId
end

-- The forced event boss, if one is active. Returns the boss id when set and not
-- past its optional expiry (`untilTime`, os.time seconds); nil otherwise. Purely
-- the activity/expiry decision -- the caller still validates the id against the
-- catalog through resolveBossId.
function DungeonBossSelection.eventBossIfActive(bossId: string?, untilTime: number?, now: number): string?
	if type(bossId) ~= "string" or bossId == "" then
		return nil
	end
	if type(untilTime) == "number" and now >= untilTime then
		return nil
	end
	return bossId
end

-- Shape-validates a session record read back from the reserved-server store.
-- Mirrors DungeonLogic.normalizePartyManifest: strict key set, bounded strings,
-- the same lowercase boss-id rule DungeonConfig enforces. Returns nil on any
-- mismatch so the caller falls back to the default boss.
function DungeonBossSelection.normalizeSessionRecord(raw: any): SessionRecord?
	if type(raw) ~= "table" or raw.v ~= 1 then
		return nil
	end
	local allowedKeys: { [string]: boolean } = { v = true, bossId = true, launchId = true }
	local keyCount = 0
	for key in raw do
		if type(key) ~= "string" or allowedKeys[key] ~= true then
			return nil
		end
		keyCount += 1
	end
	if keyCount ~= 3 then
		return nil
	end
	local bossId = raw.bossId
	if
		type(bossId) ~= "string"
		or #bossId < 1
		or #bossId > 32
		or string.match(bossId, "^[a-z][a-z0-9_]*$") == nil
	then
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
	return { v = 1, bossId = bossId, launchId = launchId }
end

return DungeonBossSelection

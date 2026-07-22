--!strict

-- Global "event boss" value shared by every lobby server. An allowlisted admin
-- sets it (see DungeonService.setEventBoss); while active it forces every dungeon
-- run to that boss, overriding personal and party picks. Stored in one
-- GlobalDataStore key so the choice survives server restarts until changed, and
-- cached with a periodic refresh so other lobby servers pick up a change without
-- a read on every pad tick.
--
-- Live-only, like the rest of the DataStore layer: mock mode keeps the value in
-- memory, and every failure is swallowed so the absence of an event simply means
-- personal/party picks apply.

local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreNames = require(Shared.DataStoreNames)
local DungeonBossSelection = require(Shared.DungeonBossSelection)

local DataStoreRuntime = require(script.Parent.DataStoreRuntime)

local DungeonEventStore = {}

local STORE_NAME = DataStoreNames.scoped("dungeon_event", Config.dataNamespace)
local KEY = "current"
local REFRESH_SECONDS = 30
local MAX_CACHE_STALE_SECONDS = REFRESH_SECONDS * 3
local INITIAL_REFRESH_WAIT_SECONDS = 5
local INITIAL_REFRESH_POLL_SECONDS = 0.05

local cachedBossId: string? = nil
local cachedUntil: number? = nil
local mockValue: any = nil
local started = false
local store: GlobalDataStore? = nil
local lastSuccessfulStoreClock: number? = nil
local cacheGeneration = 0
local initialRefreshComplete = false
local initialRefreshSucceeded = false

local function getStore(): GlobalDataStore?
	if store ~= nil then
		return store
	end
	local ok, resolved = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "event GetDataStore", resolved)
		return nil
	end
	store = resolved
	return resolved
end

local function validUntilTime(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
end

local function applyValue(value: any)
	local bossId = if type(value) == "table" then value.bossId else nil
	local untilTime = if type(value) == "table" then value.untilTime else nil
	if
		type(bossId) ~= "string"
		or bossId == ""
		or #bossId > 32
		or string.match(bossId, "^[a-z][a-z0-9_]*$") == nil
		or (untilTime ~= nil and not validUntilTime(untilTime))
	then
		cachedBossId = nil
		cachedUntil = nil
		return
	end
	cachedBossId = bossId
	cachedUntil = untilTime
end

local function applyFreshValue(value: any)
	applyValue(value)
	lastSuccessfulStoreClock = os.clock()
end

-- Writes the event boss (nil/"" clears it). `untilTime` is an optional os.time
-- expiry. Updates the local cache immediately so the setting server reflects it
-- without waiting for the next refresh. Returns whether the write persisted.
function DungeonEventStore.set(bossId: string?, untilTime: number?): boolean
	if untilTime ~= nil and not validUntilTime(untilTime) then
		return false
	end
	local value: any = if type(bossId) == "string" and bossId ~= ""
		then { bossId = bossId, untilTime = untilTime }
		else nil
	if DataStoreRuntime.isMock() then
		mockValue = value
		cacheGeneration += 1
		applyFreshValue(value)
		return true
	end
	local resolved = getStore()
	if resolved == nil then
		return false
	end
	local clearing = value == nil
	local ok, err = pcall(function()
		if clearing then
			resolved:RemoveAsync(KEY)
		else
			resolved:SetAsync(KEY, value)
		end
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", if clearing then "event RemoveAsync" else "event SetAsync", err)
		return false
	end
	-- A failed write must never alter the local view. On success, advance the
	-- generation before applying so an older in-flight refresh cannot overwrite
	-- this admin's newer decision when it eventually resumes.
	cacheGeneration += 1
	applyFreshValue(value)
	return true
end

local function refresh(): boolean
	if DataStoreRuntime.isMock() then
		applyFreshValue(mockValue)
		return true
	end
	local resolved = getStore()
	if resolved == nil then
		return false
	end
	local generationAtReadStart = cacheGeneration
	local ok, value = pcall(function()
		return resolved:GetAsync(KEY)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "event GetAsync", value)
		return false
	end
	if generationAtReadStart == cacheGeneration then
		applyFreshValue(value)
	end
	return true
end

-- The active event boss id, or nil when none is set or it has expired. `now` is
-- os.time(). The caller (resolveBossId) still validates it against the catalog.
function DungeonEventStore.activeBossId(now: number): string?
	if not DataStoreRuntime.isMock() then
		local refreshedAt = lastSuccessfulStoreClock
		if refreshedAt == nil or os.clock() - refreshedAt > MAX_CACHE_STALE_SECONDS then
			-- Fail open to normal party/personal/default selection after a bounded
			-- outage instead of forcing an event from an indefinitely stale cache.
			return nil
		end
	end
	return DungeonBossSelection.eventBossIfActive(cachedBossId, cachedUntil, now)
end

-- Lobby-only: seed the cache and keep it fresh so an event set on another server
-- takes effect here within one refresh interval. Returns true only when the
-- initial read completed successfully within a bounded startup wait. Callers may
-- then fail open to the configured default without blocking server startup.
function DungeonEventStore.start(): boolean
	if started then
		local deadline = os.clock() + INITIAL_REFRESH_WAIT_SECONDS
		while not initialRefreshComplete and os.clock() < deadline do
			task.wait(INITIAL_REFRESH_POLL_SECONDS)
		end
		return initialRefreshComplete and initialRefreshSucceeded
	end
	started = true
	if DataStoreRuntime.isMock() then
		initialRefreshSucceeded = refresh()
		initialRefreshComplete = true
		return true
	end
	task.spawn(function()
		initialRefreshSucceeded = refresh()
		initialRefreshComplete = true
		while true do
			task.wait(REFRESH_SECONDS)
			refresh()
		end
	end)
	local deadline = os.clock() + INITIAL_REFRESH_WAIT_SECONDS
	while not initialRefreshComplete and os.clock() < deadline do
		task.wait(INITIAL_REFRESH_POLL_SECONDS)
	end
	return initialRefreshComplete and initialRefreshSucceeded
end

return DungeonEventStore

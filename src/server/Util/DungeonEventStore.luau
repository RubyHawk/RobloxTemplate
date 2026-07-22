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

local cachedBossId: string? = nil
local cachedUntil: number? = nil
local mockValue: any = nil
local started = false
local store: GlobalDataStore? = nil

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

local function applyValue(value: any)
	if type(value) == "table" and type(value.bossId) == "string" and value.bossId ~= "" then
		cachedBossId = value.bossId
		cachedUntil = if type(value.untilTime) == "number" then value.untilTime else nil
	else
		cachedBossId = nil
		cachedUntil = nil
	end
end

-- Writes the event boss (nil/"" clears it). `untilTime` is an optional os.time
-- expiry. Updates the local cache immediately so the setting server reflects it
-- without waiting for the next refresh. Returns whether the write persisted.
function DungeonEventStore.set(bossId: string?, untilTime: number?): boolean
	local value: any = if type(bossId) == "string" and bossId ~= ""
		then { bossId = bossId, untilTime = untilTime }
		else nil
	if DataStoreRuntime.isMock() then
		mockValue = value
		applyValue(value)
		return true
	end
	local resolved = getStore()
	if resolved == nil then
		return false
	end
	local ok, err = pcall(function()
		resolved:SetAsync(KEY, value)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "event SetAsync", err)
		return false
	end
	applyValue(value)
	return true
end

local function refresh()
	if DataStoreRuntime.isMock() then
		applyValue(mockValue)
		return
	end
	local resolved = getStore()
	if resolved == nil then
		return
	end
	local ok, value = pcall(function()
		return resolved:GetAsync(KEY)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "event GetAsync", value)
		return
	end
	applyValue(value)
end

-- The active event boss id, or nil when none is set or it has expired. `now` is
-- os.time(). The caller (resolveBossId) still validates it against the catalog.
function DungeonEventStore.activeBossId(now: number): string?
	return DungeonBossSelection.eventBossIfActive(cachedBossId, cachedUntil, now)
end

-- Lobby-only: seed the cache and keep it fresh so an event set on another server
-- takes effect here within one refresh interval.
function DungeonEventStore.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		refresh()
		while true do
			task.wait(REFRESH_SECONDS)
			refresh()
		end
	end)
end

return DungeonEventStore

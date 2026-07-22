--!strict

-- Per-reserved-server dungeon session handoff. The lobby reserves a server,
-- resolves one boss id, and writes it here keyed by the reserved server's
-- PrivateServerId; the reserved server reads it back on boot. This is the
-- server-authoritative channel that replaces trusting client-visible
-- TeleportData for the boss.
--
-- MemoryStore is a live-only, published-place service. In mock mode (template
-- workbench) and in Studio -- where the dungeon is simulated in-place and never
-- actually reserves a server -- this degrades to an in-memory table so requires
-- and specs stay happy; the real cross-server handoff only runs on the live
-- published place. Every failure is swallowed so a missing record simply falls
-- back to the default boss on the reserved server.

local MemoryStoreService = game:GetService("MemoryStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreNames = require(Shared.DataStoreNames)

local DataStoreRuntime = require(script.Parent.DataStoreRuntime)

local DungeonSessionStore = {}

-- Records only need to outlive the teleport + arrival window; a short TTL keeps a
-- recycled reserved server from ever reading a previous session's record.
local TTL_SECONDS = 600
local mapName = DataStoreNames.scoped("dungeon_sessions", Config.dataNamespace)
local mockRecords: { [string]: any } = {}

local function hashMap(): any
	local ok, map = pcall(function()
		return MemoryStoreService:GetHashMap(mapName)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "GetHashMap", map)
		return nil
	end
	return map
end

function DungeonSessionStore.write(privateServerId: string, record: any): boolean
	if type(privateServerId) ~= "string" or privateServerId == "" then
		return false
	end
	if DataStoreRuntime.isMock() then
		mockRecords[privateServerId] = record
		return true
	end
	local map = hashMap()
	if map == nil then
		return false
	end
	local ok, err = pcall(function()
		map:SetAsync(privateServerId, record, TTL_SECONDS)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "SetAsync", err)
		return false
	end
	return true
end

function DungeonSessionStore.read(privateServerId: string): any?
	if type(privateServerId) ~= "string" or privateServerId == "" then
		return nil
	end
	if DataStoreRuntime.isMock() then
		return mockRecords[privateServerId]
	end
	local map = hashMap()
	if map == nil then
		return nil
	end
	local ok, value = pcall(function()
		return map:GetAsync(privateServerId)
	end)
	if not ok then
		DataStoreRuntime.failure("dungeon", "GetAsync", value)
		return nil
	end
	return value
end

return DungeonSessionStore

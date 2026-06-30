--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Migrations = require(Shared.Migrations)
local ProfileTemplate = require(Shared.ProfileTemplate)
local SeedProfiles = require(Shared.SeedProfiles)
local Types = require(Shared.Types)
local SessionLock = require(script.Parent.Parent.Util.SessionLock)

type PlayerProfileV1 = Types.PlayerProfileV1
type Envelope = {
	data: PlayerProfileV1,
	lock: SessionLock.Lock?,
	updatedAt: number,
}

local ProfileService = {}
local profiles: { [Player]: PlayerProfileV1 } = {}
local dirty: { [Player]: boolean } = {}
local mockProfiles: { [number]: PlayerProfileV1 } = {}
local changedEvent = Instance.new("BindableEvent")
local store: GlobalDataStore? = nil
local lockTimeoutSeconds = 180
local autosaveSeconds = 60
local closing = false

ProfileService.changed = changedEvent.Event

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in value do
		output[copy(key)] = copy(child)
	end
	return output
end

local function keyFor(player: Player): string
	return `player:{player.UserId}`
end

-- In Studio, persist to a physically separate "<name>_canary" DataStore so
-- SeedProfiles and Data Delve inspection can never touch production data.
local function useCanary(): boolean
	return RunService:IsStudio() and Config.studio.useCanaryStore
end

local function shouldMock(): boolean
	return RunService:IsStudio() and not Config.studio.useLiveDataStore and not useCanary()
end

local function storeName(): string
	if useCanary() then
		return `{Config.profileStoreName}_canary`
	end
	return Config.profileStoreName
end

local function getStore(): GlobalDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetDataStore(storeName())
		store = current
	end
	return current
end

local function updateEnvelope(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	profile.updatedAt = os.time()

	if shouldMock() then
		mockProfiles[player.UserId] = copy(profile)
		return true
	end

	local success, result = pcall(function()
		return getStore():UpdateAsync(keyFor(player), function(old: Envelope?): Envelope?
			if old == nil or old.lock == nil or old.lock.jobId ~= game.JobId then
				return nil
			end
			return {
				data = copy(profile),
				lock = if release then nil else SessionLock.claim(game.JobId, game.PlaceId, os.time()),
				updatedAt = os.time(),
			}
		end)
	end)
	if not success or result == nil then
		return false
	end
	return release or (result.lock ~= nil and result.lock.jobId == game.JobId)
end

function ProfileService.load(player: Player): PlayerProfileV1?
	if profiles[player] ~= nil then
		return profiles[player]
	end

	local now = os.time()
	local loaded: PlayerProfileV1? = nil
	if shouldMock() then
		loaded = Migrations.migrate(mockProfiles[player.UserId] or ProfileTemplate.create(now), now)
		if loaded then
			loaded.coins = math.max(loaded.coins, Config.studio.mockStartingCoins)
			loaded.currencies[Config.economy.primaryCurrencyId] = loaded.coins
		end
	else
		for attempt = 1, 5 do
			local attemptNow = os.time()
			local success, result = pcall(function()
				return getStore():UpdateAsync(keyFor(player), function(old: Envelope?): Envelope?
					local envelope = old
					if envelope == nil then
						envelope = {
							data = ProfileTemplate.create(now),
							lock = nil,
							updatedAt = now,
						}
					end
					if
						not SessionLock.canClaim(envelope.lock, game.JobId, attemptNow, lockTimeoutSeconds)
					then
						return nil
					end
					envelope.data = Migrations.migrate(envelope.data, now)
					envelope.lock = SessionLock.claim(game.JobId, game.PlaceId, attemptNow)
					envelope.updatedAt = attemptNow
					return envelope
				end)
			end)
			if success and result ~= nil and result.lock ~= nil and result.lock.jobId == game.JobId then
				loaded = result.data
				break
			end
			task.wait(math.min(2 ^ attempt, 8))
		end
	end

	if loaded == nil or player.Parent == nil then
		return nil
	end
	loaded.stats.joins += 1
	loaded.updatedAt = now
	profiles[player] = loaded
	dirty[player] = true
	changedEvent:Fire(player, "loaded")
	return loaded
end

function ProfileService.get(player: Player): PlayerProfileV1?
	return profiles[player]
end

function ProfileService.snapshot(player: Player): PlayerProfileV1?
	local profile = profiles[player]
	return if profile then copy(profile) else nil
end

function ProfileService.markDirty(player: Player, reason: string?)
	if profiles[player] == nil then
		return
	end
	dirty[player] = true
	changedEvent:Fire(player, reason or "updated")
end

function ProfileService.save(player: Player): boolean
	if not dirty[player] then
		return true
	end
	local success = updateEnvelope(player, false)
	if success then
		dirty[player] = nil
	end
	return success
end

function ProfileService.release(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profile.lastSeenAt = os.time()
	profile.updatedAt = os.time()
	updateEnvelope(player, true)
	profiles[player] = nil
	dirty[player] = nil
end

function ProfileService.startAutosave()
	task.spawn(function()
		while not closing do
			task.wait(autosaveSeconds)
			for player in profiles do
				ProfileService.save(player)
			end
		end
	end)
end

-- Writes deterministic fixtures to the canary store for Data Delve inspection.
-- No-op unless running in Studio with useCanaryStore enabled, so production is
-- never seeded. Keys are "seed:<archetype>".
function ProfileService.seedCanary()
	if not useCanary() then
		return
	end
	for key, profile in SeedProfiles.all() do
		local migrated = Migrations.migrate(profile, os.time())
		local success = pcall(function()
			getStore():UpdateAsync(`seed:{key}`, function(): Envelope
				return { data = migrated, lock = nil, updatedAt = os.time() }
			end)
		end)
		if not success then
			warn(`[ProfileService] failed to seed canary profile "{key}"`)
		end
	end
end

function ProfileService.close()
	closing = true
	local threads = 0
	for player in profiles do
		threads += 1
		task.spawn(function()
			ProfileService.release(player)
			threads -= 1
		end)
	end
	local deadline = os.clock() + 25
	while threads > 0 and os.clock() < deadline do
		task.wait()
	end
end

return ProfileService

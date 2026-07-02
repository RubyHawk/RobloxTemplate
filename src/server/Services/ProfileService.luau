--!strict

local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreKeys = require(Shared.DataStoreKeys)
local Migrations = require(Shared.Migrations)
local ProfileTemplate = require(Shared.ProfileTemplate)
local Types = require(Shared.Types)
local SessionLock = require(script.Parent.Parent.Util.SessionLock)
local DataStoreRuntime = require(script.Parent.Parent.Util.DataStoreRuntime)

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
	return DataStoreKeys.profile(player.UserId)
end

local function shouldMock(): boolean
	return DataStoreRuntime.isMock()
end

local function getStore(): GlobalDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetDataStore(Config.profileStoreName)
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
	if not success then
		DataStoreRuntime.failure("Profiles", `save {keyFor(player)}`, result)
		return false
	end
	if result == nil then
		DataStoreRuntime.failure(
			"Profiles",
			`save {keyFor(player)}`,
			"the session lock is no longer owned by this server"
		)
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
		local success, result = pcall(function()
			return Migrations.migrate(mockProfiles[player.UserId] or ProfileTemplate.create(now), now)
		end)
		if success then
			loaded = result
		else
			DataStoreRuntime.failure("Profiles", `load mock {keyFor(player)}`, result)
		end
		if loaded then
			for index, definition in Config.economy.currencies do
				local minimum = definition.startingAmount
				if index == 1 then
					minimum = math.max(minimum, Config.studio.mockStartingCoins)
				end
				loaded.currencies[definition.id] = math.max(loaded.currencies[definition.id] or 0, minimum)
			end
			loaded.coins = loaded.currencies[Config.economy.primaryCurrencyId]
		end
	else
		local finalIssue: any = "request did not return a profile"
		for attempt = 1, 5 do
			local attemptNow = os.time()
			local callbackIssue: string? = nil
			local success, result = pcall(function()
				return getStore():UpdateAsync(keyFor(player), function(old: Envelope?): Envelope?
					local envelope: Envelope
					if old == nil then
						envelope = {
							data = ProfileTemplate.create(now),
							lock = nil,
							updatedAt = now,
						}
					elseif type(old) ~= "table" then
						callbackIssue = "stored profile is not a table; refusing to overwrite it"
						return nil
					elseif type((old :: any).data) == "table" then
						envelope = old
					elseif
						type((old :: any).schemaVersion) == "number"
						or type((old :: any).coins) == "number"
						or type((old :: any).currencies) == "table"
					then
						-- Compatibility with early builds that stored the profile directly.
						envelope = {
							data = old :: any,
							lock = nil,
							updatedAt = attemptNow,
						}
					else
						callbackIssue = "stored profile has an unknown shape; refusing to overwrite it"
						return nil
					end
					if
						not SessionLock.canClaim(envelope.lock, game.JobId, attemptNow, lockTimeoutSeconds)
					then
						callbackIssue = "profile is still locked by another server"
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
			finalIssue = if success then callbackIssue or "session lock was not acquired" else result
			task.wait(math.min(2 ^ attempt, 8))
		end
		if loaded == nil then
			DataStoreRuntime.failure("Profiles", `load {keyFor(player)}`, finalIssue)
		end
	end

	if loaded == nil or player.Parent == nil then
		return nil
	end
	for _, definition in Config.economy.currencies do
		if type(loaded.currencies[definition.id]) ~= "number" then
			loaded.currencies[definition.id] = definition.startingAmount
		end
	end
	loaded.coins = loaded.currencies[Config.economy.primaryCurrencyId]
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
	local released = false
	for attempt = 1, 3 do
		if updateEnvelope(player, true) then
			released = true
			break
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	if not released then
		DataStoreRuntime.failure(
			"Profiles",
			`release {keyFor(player)}`,
			"profile could not be saved after three attempts"
		)
	end
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

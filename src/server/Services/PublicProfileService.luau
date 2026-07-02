--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreKeys = require(Shared.DataStoreKeys)
local Types = require(Shared.Types)
local DataStoreRuntime = require(script.Parent.Parent.Util.DataStoreRuntime)
local ProfileService = require(script.Parent.ProfileService)

type PublicProfile = Types.PublicProfile

local PublicProfileService = {}
local store: GlobalDataStore? = nil
local mock: { [number]: PublicProfile } = {}
local usernameCache: { [string]: number } = {}
local lastPublished: { [number]: PublicProfile } = {}

local function getStore(): GlobalDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetDataStore(Config.publicProfileStoreName)
		store = current
	end
	return current
end

local function key(userId: number): string
	return DataStoreKeys.publicProfile(userId)
end

local function sameSnapshot(left: PublicProfile?, right: PublicProfile): boolean
	return left ~= nil
		and left.username == right.username
		and left.displayName == right.displayName
		and left.coins == right.coins
		and left.joins == right.joins
		and left.playSeconds == right.playSeconds
		and left.dailyStreak == right.dailyStreak
end

local function validStored(value: any): PublicProfile?
	if
		type(value) ~= "table"
		or type(value.userId) ~= "number"
		or type(value.username) ~= "string"
		or type(value.displayName) ~= "string"
		or type(value.coins) ~= "number"
		or type(value.joins) ~= "number"
		or type(value.playSeconds) ~= "number"
		or type(value.dailyStreak) ~= "number"
		or type(value.updatedAt) ~= "number"
	then
		return nil
	end
	return value :: PublicProfile
end

function PublicProfileService.fromPlayer(player: Player): PublicProfile?
	local profile = ProfileService.get(player)
	if profile == nil then
		return nil
	end
	return {
		userId = player.UserId,
		username = player.Name,
		displayName = player.DisplayName,
		coins = profile.coins,
		joins = profile.stats.joins,
		playSeconds = profile.stats.playSeconds,
		dailyStreak = profile.daily.streak,
		updatedAt = os.time(),
	}
end

function PublicProfileService.publish(player: Player)
	local public = PublicProfileService.fromPlayer(player)
	if public == nil or sameSnapshot(lastPublished[player.UserId], public) then
		return
	end
	if DataStoreRuntime.isMock() then
		mock[player.UserId] = public
		lastPublished[player.UserId] = public
		return
	end
	local success, failure = pcall(function()
		return getStore():UpdateAsync(key(player.UserId), function(old: any): any
			local existing = validStored(old)
			if existing and existing.updatedAt > public.updatedAt then
				return existing
			end
			return public
		end)
	end)
	if success then
		lastPublished[player.UserId] = public
	else
		DataStoreRuntime.failure("Public profiles", `publish {key(player.UserId)}`, failure)
	end
end

function PublicProfileService.find(rawUsername: any): (boolean, PublicProfile? | string)
	if type(rawUsername) ~= "string" or #rawUsername < 3 or #rawUsername > 20 then
		return false, "Enter an exact Roblox username"
	end
	local normalized = string.lower(rawUsername)
	local userId: any = usernameCache[normalized]
	local success = userId ~= nil
	if userId == nil then
		success, userId = pcall(function()
			return Players:GetUserIdFromNameAsync(rawUsername)
		end)
		if success and type(userId) == "number" then
			usernameCache[normalized] = userId
		end
	end
	if not success or type(userId) ~= "number" then
		return false, "Player was not found"
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return true, PublicProfileService.fromPlayer(online)
	end
	if DataStoreRuntime.isMock() then
		return if mock[userId] then true else false, mock[userId] or "No public stats are available"
	end
	local readSuccess, result = pcall(function()
		return getStore():GetAsync(key(userId))
	end)
	if not readSuccess then
		DataStoreRuntime.failure("Public profiles", `read {key(userId)}`, result)
		return false, "No public stats are available"
	end
	local public = validStored(result)
	if public == nil or public.userId ~= userId then
		return false, "No public stats are available"
	end
	return true, public
end

return PublicProfileService

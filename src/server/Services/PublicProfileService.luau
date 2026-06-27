--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Types = require(Shared.Types)
local ProfileService = require(script.Parent.ProfileService)

type PublicProfile = Types.PublicProfile

local PublicProfileService = {}
local store: GlobalDataStore? = nil
local mock: { [number]: PublicProfile } = {}

local function getStore(): GlobalDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetDataStore(Config.publicProfileStoreName)
		store = current
	end
	return current
end

local function key(userId: number): string
	return `user:{userId}`
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
	if public == nil then
		return
	end
	if RunService:IsStudio() and not Config.studio.useLiveDataStore then
		mock[player.UserId] = public
		return
	end
	pcall(function()
		getStore():SetAsync(key(player.UserId), public)
	end)
end

function PublicProfileService.find(rawUsername: any): (boolean, PublicProfile? | string)
	if type(rawUsername) ~= "string" or #rawUsername < 3 or #rawUsername > 20 then
		return false, "Enter an exact Roblox username"
	end
	local success, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(rawUsername)
	end)
	if not success or type(userId) ~= "number" then
		return false, "Player was not found"
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return true, PublicProfileService.fromPlayer(online)
	end
	if RunService:IsStudio() and not Config.studio.useLiveDataStore then
		return if mock[userId] then true else false, mock[userId] or "No public stats are available"
	end
	local readSuccess, result = pcall(function()
		return getStore():GetAsync(key(userId))
	end)
	if not readSuccess or result == nil then
		return false, "No public stats are available"
	end
	return true, result
end

return PublicProfileService

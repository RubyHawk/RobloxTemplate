--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreKeys = require(Shared.DataStoreKeys)
local DataStoreRuntime = require(script.Parent.Parent.Util.DataStoreRuntime)
local ProfileService = require(script.Parent.ProfileService)

local LeaderboardService = {}
local store: OrderedDataStore? = nil
local nameCache: { [number]: string } = {}
local lastFlushed: { [number]: number } = {}
local globalCache: { any }? = nil
local globalCacheAt = 0
local globalCacheBusy = false

local function getStore(): OrderedDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetOrderedDataStore(Config.leaderboardStoreName)
		store = current
	end
	return current
end

local function displayName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if success and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return `User {userId}`
end

function LeaderboardService.updateLeaderstats(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil then
		return
	end
	local folder = player:FindFirstChild("leaderstats") :: Folder?
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local coins = folder:FindFirstChild("Coins") :: IntValue?
	if coins == nil then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = folder
	end
	coins.Value = math.clamp(math.floor(profile.coins), 0, 2147483647)
end

function LeaderboardService.serverBoard(): { any }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local profile = ProfileService.get(player)
		if profile then
			table.insert(rows, { userId = player.UserId, name = player.DisplayName, value = profile.coins })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	return rows
end

function LeaderboardService.globalBoard(): (boolean, { any } | string)
	if DataStoreRuntime.isMock() then
		return true, LeaderboardService.serverBoard()
	end
	local now = os.clock()
	if globalCache and now - globalCacheAt < Config.leaderboards.refreshSeconds then
		return true, globalCache
	end
	if globalCacheBusy then
		return if globalCache then true else false, globalCache or "Global leaderboard is refreshing"
	end
	globalCacheBusy = true
	local success, result = pcall(function()
		local pages = getStore():GetSortedAsync(false, Config.leaderboards.globalSize)
		local rows = {}
		for rank, entry in pages:GetCurrentPage() do
			local userId = tonumber(entry.key) or 0
			table.insert(
				rows,
				{ rank = rank, userId = userId, name = displayName(userId), value = entry.value }
			)
		end
		return rows
	end)
	globalCacheBusy = false
	if success then
		globalCache = result
		globalCacheAt = now
		return true, result
	end
	DataStoreRuntime.failure("Leaderboard", "read global board", result)
	if globalCache then
		return true, globalCache
	end
	return false, "Global leaderboard is unavailable"
end

function LeaderboardService.flushPlayer(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil or DataStoreRuntime.isMock() then
		return
	end
	local value = math.clamp(math.floor(profile.coins), 0, 9e15)
	if lastFlushed[player.UserId] == value then
		return
	end
	local success, failure = pcall(function()
		getStore():SetAsync(DataStoreKeys.leaderboard(player.UserId), value)
	end)
	if success then
		lastFlushed[player.UserId] = value
	else
		DataStoreRuntime.failure("Leaderboard", `write user {player.UserId}`, failure)
	end
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			if #players == 0 then
				task.wait(Config.leaderboards.refreshSeconds)
			else
				local delayPerPlayer = Config.leaderboards.refreshSeconds / #players
				for _, player in players do
					LeaderboardService.updateLeaderstats(player)
					LeaderboardService.flushPlayer(player)
					task.wait(delayPerPlayer)
				end
			end
		end
	end)
end

return LeaderboardService

--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local ProfileService = require(script.Parent.ProfileService)

local LeaderboardService = {}
local store: OrderedDataStore? = nil
local nameCache: { [number]: string } = {}

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
	local result = if success then name else `User {userId}`
	nameCache[userId] = result
	return result
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
	if RunService:IsStudio() and not Config.studio.useLiveDataStore then
		return true, LeaderboardService.serverBoard()
	end
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
	return success, if success then result else "Global leaderboard is unavailable"
end

function LeaderboardService.flushPlayer(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil or (RunService:IsStudio() and not Config.studio.useLiveDataStore) then
		return
	end
	pcall(function()
		getStore():SetAsync(tostring(player.UserId), math.floor(profile.coins))
	end)
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			task.wait(Config.leaderboards.refreshSeconds)
			for _, player in Players:GetPlayers() do
				LeaderboardService.updateLeaderstats(player)
				LeaderboardService.flushPlayer(player)
			end
		end
	end)
end

return LeaderboardService

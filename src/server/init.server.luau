--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared").TemplateConfig)

local Services = script.Services
local AnnouncementService = require(Services.AnnouncementService)
local FeedbackService = require(Services.FeedbackService)
local LeaderboardService = require(Services.LeaderboardService)
local NotificationService = require(Services.NotificationService)
local ProfileService = require(Services.ProfileService)
local PublicProfileService = require(Services.PublicProfileService)
local RemoteService = require(Services.RemoteService)
local RewardService = require(Services.RewardService)
local SocialService = require(Services.SocialService)
local StoreService = require(Services.StoreService)
local EconomyRateProvider = require(script.Providers.DefaultEconomyRateProvider)

RemoteService.initialize()
if Config.features.store then
	StoreService.initialize()
end
ProfileService.startAutosave()
if Config.features.leaderboards then
	LeaderboardService.start()
end
if Config.features.crossServerChat then
	AnnouncementService.start(RemoteService.broadcastAnnouncement)
end

local function playerAdded(player: Player)
	task.spawn(function()
		local profile = ProfileService.load(player)
		if profile == nil then
			if player.Parent then
				player:Kick("Your data could not be loaded safely. Please rejoin.")
			end
			return
		end
		NotificationService.cancel(player)
		StoreService.refreshEntitlements(player)
		SocialService.refresh(player)
		player:GetPropertyChangedSignal("MembershipType"):Connect(function()
			SocialService.refresh(player)
		end)
		if Config.features.offlineEarnings then
			RewardService.prepareOffline(player)
		end
		if Config.features.leaderboards then
			LeaderboardService.updateLeaderstats(player)
		end
		if Config.features.profiles then
			PublicProfileService.publish(player)
		end
		RemoteService.publish(player)
		SocialService.refreshAll()
	end)
end

local function playerRemoving(player: Player)
	if Config.features.notifications then
		NotificationService.scheduleOnLeave(player)
	end
	if Config.features.profiles then
		PublicProfileService.publish(player)
	end
	if Config.features.leaderboards then
		LeaderboardService.flushPlayer(player)
	end
	RewardService.forget(player)
	FeedbackService.forget(player)
	RemoteService.forget(player)
	ProfileService.release(player)
	task.defer(SocialService.refreshAll)
end

Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(playerRemoving)
for _, player in Players:GetPlayers() do
	playerAdded(player)
end

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			local profile = ProfileService.get(player)
			if profile then
				profile.stats.playSeconds += 60
				profile.lastSeenAt = os.time()
				profile.offlineRateSnapshot = EconomyRateProvider.getRate(player)
				ProfileService.markDirty(player, "playtime")
				if Config.features.profiles then
					PublicProfileService.publish(player)
				end
			end
		end
	end
end)

game:BindToClose(function()
	ProfileService.close()
end)

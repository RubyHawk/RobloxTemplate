--!strict

local Players = game:GetService("Players")

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
StoreService.initialize()
ProfileService.startAutosave()
LeaderboardService.start()
AnnouncementService.start(RemoteService.broadcastAnnouncement)

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
		RewardService.prepareOffline(player)
		LeaderboardService.updateLeaderstats(player)
		PublicProfileService.publish(player)
		RemoteService.publish(player)
		SocialService.refreshAll()
	end)
end

local function playerRemoving(player: Player)
	NotificationService.scheduleOnLeave(player)
	PublicProfileService.publish(player)
	LeaderboardService.flushPlayer(player)
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
				PublicProfileService.publish(player)
			end
		end
	end
end)

game:BindToClose(function()
	ProfileService.close()
end)

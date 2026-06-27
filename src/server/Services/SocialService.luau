--!strict

local Players = game:GetService("Players")

local ProfileService = require(script.Parent.ProfileService)
local CommunityVerificationProvider = require(script.Parent.Parent.Providers.CommunityVerificationProvider)

local SocialService = {}

local function countFriends(player: Player): number
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local success, isFriend = pcall(function()
				return player:IsFriendsWithAsync(other.UserId)
			end)
			if success and isFriend then
				count += 1
			end
		end
	end
	return count
end

function SocialService.refresh(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil then
		return
	end
	profile.entitlements.premium = player.MembershipType == Enum.MembershipType.Premium
	profile.social.friendCountInServer = countFriends(player)

	local verification = CommunityVerificationProvider.verify(player)
	profile.social.communityVerified = verification.status == "available" and verification.value == true
	ProfileService.markDirty(player, "social:refresh")
end

function SocialService.refreshAll()
	task.spawn(function()
		for _, player in Players:GetPlayers() do
			SocialService.refresh(player)
		end
	end)
end

return SocialService

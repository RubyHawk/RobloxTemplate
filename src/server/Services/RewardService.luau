--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local LikesService = require(script.Parent.LikesService)
local EconomyRateProvider = require(script.Parent.Parent.Providers.DefaultEconomyRateProvider)

local RewardService = {}
local pendingOffline: { [Player]: { amount: number, elapsed: number } } = {}

function RewardService.prepareOffline(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil then
		return
	end
	local capHours = if profile.entitlements.extendedOffline
		then Config.economy.paidOfflineCapHours
		else Config.economy.freeOfflineCapHours
	local amount, elapsed = Calculations.offlineEarnings(
		profile.lastSeenAt,
		os.time(),
		profile.offlineRateSnapshot,
		capHours,
		EconomyService.permanentOfflineMultiplier(player)
	)
	profile.offline.pendingAmount = math.min(profile.offline.pendingAmount + amount, 9e15)
	profile.offline.pendingElapsed = math.min(profile.offline.pendingElapsed + elapsed, 365 * 86400)
	profile.offline.preparedAt = os.time()
	pendingOffline[player] = {
		amount = profile.offline.pendingAmount,
		elapsed = profile.offline.pendingElapsed,
	}
	profile.lastSeenAt = os.time()
	profile.offlineRateSnapshot = EconomyRateProvider.getRate(player)
	ProfileService.markDirty(player, "offline:prepared")
end

function RewardService.getPendingOffline(player: Player): { amount: number, elapsed: number }
	local profile = ProfileService.get(player)
	if profile then
		return { amount = profile.offline.pendingAmount, elapsed = profile.offline.pendingElapsed }
	end
	return pendingOffline[player] or { amount = 0, elapsed = 0 }
end

function RewardService.claimOffline(player: Player): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil or profile.offline.pendingAmount <= 0 then
		return false, "No offline earnings are ready"
	end
	local amount = profile.offline.pendingAmount
	EconomyService.awardRaw(player, amount, "offline")
	profile.offline.pendingAmount = 0
	profile.offline.pendingElapsed = 0
	profile.offline.preparedAt = 0
	pendingOffline[player] = nil
	ProfileService.markDirty(player, "offline:claim")
	return true, `Claimed {amount} Coins`
end

function RewardService.claimDaily(player: Player): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	local canClaim, nextStreak = Calculations.dailyClaim(
		profile.daily.lastClaimDay,
		profile.daily.streak,
		os.time(),
		#Config.rewards.daily
	)
	if not canClaim then
		return false, "Daily reward already claimed"
	end
	local amount = Config.rewards.daily[nextStreak]
	profile.daily.lastClaimDay = Calculations.utcDay(os.time())
	profile.daily.streak = nextStreak
	EconomyService.awardRaw(player, amount, "daily")
	ProfileService.markDirty(player, "daily:claim")
	return true, `Day {nextStreak}: {amount} Coins`
end

function RewardService.redeemCode(player: Player, rawCode: any): (boolean, string)
	local code = Calculations.normalizeCode(rawCode)
	local profile = ProfileService.get(player)
	if code == nil or profile == nil then
		return false, "Invalid code"
	end
	local reward = Config.rewards.codes[code]
	if reward == nil then
		return false, "Code does not exist"
	end
	if profile.redemptions[code] then
		return false, "Code already redeemed"
	end
	for _, milestone in Config.rewards.likesMilestones do
		if milestone.code == code then
			local likes = LikesService.getLikes()
			if (likes.value or 0) < milestone.likes then
				return false, `Code unlocks at {milestone.likes} likes`
			end
			break
		end
	end
	profile.redemptions[code] = true
	if reward.coins and reward.coins > 0 then
		EconomyService.awardRaw(player, reward.coins, `code:{code}`)
	end
	if reward.itemId and reward.quantity then
		InventoryService.grant(player, reward.itemId, reward.quantity)
	end
	ProfileService.markDirty(player, `code:{code}`)
	return true, "Code redeemed"
end

function RewardService.forget(player: Player)
	pendingOffline[player] = nil
end

return RewardService

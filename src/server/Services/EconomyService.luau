--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

function EconomyService.getMultiplier(player: Player): number
	local profile = ProfileService.get(player)
	if profile == nil then
		return 1
	end
	return Calculations.earningsMultiplier(
		profile.social.friendCountInServer,
		profile.entitlements.premium,
		profile.boosts,
		os.time(),
		Config.economy.friendBonusPerFriend,
		Config.economy.friendBonusCap,
		Config.economy.premiumBonus
	)
end

function EconomyService.awardRaw(player: Player, amount: number, source: string): (boolean, number)
	local profile = ProfileService.get(player)
	if profile == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, 0
	end
	local granted = math.floor(math.min(amount, 1e12))
	profile.coins = math.min(profile.coins + granted, 9e15)
	profile.stats.totalCoinsEarned = math.min(profile.stats.totalCoinsEarned + granted, 9e15)
	ProfileService.markDirty(player, `award:{source}`)
	return true, granted
end

function EconomyService.award(player: Player, baseAmount: number, source: string): (boolean, number)
	return EconomyService.awardRaw(player, baseAmount * EconomyService.getMultiplier(player), source)
end

function EconomyService.spend(player: Player, amount: number, source: string): boolean
	local profile = ProfileService.get(player)
	if profile == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	local cost = math.floor(amount)
	if profile.coins < cost then
		return false
	end
	profile.coins -= cost
	ProfileService.markDirty(player, `spend:{source}`)
	return true
end

function EconomyService.permanentOfflineMultiplier(player: Player): number
	local profile = ProfileService.get(player)
	if profile == nil then
		return 1
	end
	return 1 + (if profile.entitlements.premium then Config.economy.premiumBonus else 0)
end

return EconomyService

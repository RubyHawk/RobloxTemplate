--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

local function isConfiguredCurrency(currencyId: string): boolean
	for _, definition in Config.economy.currencies do
		if definition.id == currencyId then
			return true
		end
	end
	return false
end

local function synchronizeLegacyCoins(profile: any, currencyId: string)
	if currencyId == Config.economy.primaryCurrencyId then
		profile.coins = profile.currencies[currencyId]
	end
end

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
	return EconomyService.awardCurrencyRaw(player, Config.economy.primaryCurrencyId, amount, source)
end

function EconomyService.awardCurrencyRaw(
	player: Player,
	currencyId: string,
	amount: number,
	source: string
): (boolean, number)
	local profile = ProfileService.get(player)
	if
		profile == nil
		or not isConfiguredCurrency(currencyId)
		or amount ~= amount
		or amount <= 0
		or amount == math.huge
	then
		return false, 0
	end
	local granted = math.floor(math.min(amount, 1e12))
	if granted <= 0 then
		return false, 0
	end
	profile.currencies[currencyId] = math.min((profile.currencies[currencyId] or 0) + granted, 9e15)
	synchronizeLegacyCoins(profile, currencyId)
	if currencyId == Config.economy.primaryCurrencyId then
		profile.stats.totalCoinsEarned = math.min(profile.stats.totalCoinsEarned + granted, 9e15)
	end
	ProfileService.markDirty(player, `award:{source}`)
	return true, granted
end

function EconomyService.award(player: Player, baseAmount: number, source: string): (boolean, number)
	return EconomyService.awardRaw(player, baseAmount * EconomyService.getMultiplier(player), source)
end

function EconomyService.spend(player: Player, amount: number, source: string): boolean
	return EconomyService.spendCurrency(player, Config.economy.primaryCurrencyId, amount, source)
end

function EconomyService.spendCurrency(
	player: Player,
	currencyId: string,
	amount: number,
	source: string
): boolean
	local profile = ProfileService.get(player)
	if
		profile == nil
		or not isConfiguredCurrency(currencyId)
		or amount ~= amount
		or amount <= 0
		or amount == math.huge
	then
		return false
	end
	local cost = math.floor(amount)
	if cost <= 0 then
		return false
	end
	local balance = profile.currencies[currencyId] or 0
	if balance < cost then
		return false
	end
	profile.currencies[currencyId] = balance - cost
	synchronizeLegacyCoins(profile, currencyId)
	ProfileService.markDirty(player, `spend:{source}`)
	return true
end

function EconomyService.getBalance(player: Player, currencyId: string): number?
	local profile = ProfileService.get(player)
	if profile == nil or not isConfiguredCurrency(currencyId) then
		return nil
	end
	return profile.currencies[currencyId] or 0
end

function EconomyService.permanentOfflineMultiplier(player: Player): number
	local profile = ProfileService.get(player)
	if profile == nil then
		return 1
	end
	return 1 + (if profile.entitlements.premium then Config.economy.premiumBonus else 0)
end

return EconomyService

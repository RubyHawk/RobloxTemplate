--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local RuneCatalog = require(Shared.RuneCatalog)
local RuneLogic = require(Shared.RuneLogic)
local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

-- Runes are permanent additive generation bonuses, so they form their own
-- multiplicative bucket next to the social/premium/potion multiplier instead
-- of competing with the strongest-potion rule.
local function runeMultiplier(profile: any): number
	if Config.features.runes ~= true then
		return 1
	end
	return RuneLogic.multiplier(
		profile.runes,
		RuneCatalog,
		Config.runes.copyMilestones,
		Config.runes.maxTotalBonusPercent
	)
end

-- A feature (the rune altar's surge channel today) can register a live boost
-- for the strongest-temporary-boost bucket. The provider keeps this service
-- feature-agnostic and avoids a require cycle with RuneService; its value is
-- never persisted and never stacks with potions.
local channelBoostProvider: ((player: Player) -> number)? = nil

function EconomyService.setChannelBoostProvider(provider: (player: Player) -> number)
	channelBoostProvider = provider
end

local function channelMultiplier(player: Player): number
	local provider = channelBoostProvider
	if provider == nil then
		return 1
	end
	return provider(player)
end

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
	local social = Calculations.friendBonus(
		profile.social.friendCountInServer,
		Config.economy.friendBonusPerFriend,
		Config.economy.friendBonusCap
	)
	local premium = if profile.entitlements.premium then Config.economy.premiumBonus else 0
	local temporary = Calculations.temporaryMultiplier(profile.boosts, os.time(), channelMultiplier(player))
	return Calculations.compositeMultiplier(social, premium, temporary, runeMultiplier(profile))
end

function EconomyService.getRuneMultiplier(player: Player): number
	local profile = ProfileService.get(player)
	if profile == nil then
		return 1
	end
	return runeMultiplier(profile)
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
	-- Rune bonuses are permanent, so unlike potions and channel surges they
	-- also raise the offline generation rate.
	return Calculations.permanentMultiplier(
		Config.economy.premiumBonus,
		profile.entitlements.premium,
		runeMultiplier(profile)
	)
end

return EconomyService

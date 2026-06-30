--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local Calculations = require(Shared.Calculations)
local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

local PRIMARY = Config.economy.primaryCurrencyId
local CURRENCY_CAP = 9e15

-- Ensures the multi-currency map exists and returns it. The primary currency is
-- kept in sync with the legacy top-level profile.coins field so every existing
-- reader (leaderboards, public profiles, screens) keeps working unchanged.
local function ensureCurrencies(profile: any): { [string]: number }
	if type(profile.currencies) ~= "table" then
		profile.currencies = { [PRIMARY] = profile.coins or 0 }
	end
	return profile.currencies
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
	local profile = ProfileService.get(player)
	if profile == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, 0
	end
	local granted = math.floor(math.min(amount, 1e12))
	profile.coins = math.min(profile.coins + granted, CURRENCY_CAP)
	ensureCurrencies(profile)[PRIMARY] = profile.coins
	profile.stats.totalCoinsEarned = math.min(profile.stats.totalCoinsEarned + granted, CURRENCY_CAP)
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
	ensureCurrencies(profile)[PRIMARY] = profile.coins
	ProfileService.markDirty(player, `spend:{source}`)
	return true
end

-- Reads any currency balance. The primary currency reads through the canonical
-- profile.coins mirror.
function EconomyService.getCurrency(player: Player, currencyId: string): number
	local profile = ProfileService.get(player)
	if profile == nil then
		return 0
	end
	if currencyId == PRIMARY then
		return profile.coins
	end
	return ensureCurrencies(profile)[currencyId] or 0
end

-- Credits a secondary currency (gems, etc.). The primary currency is routed
-- through awardRaw so its mirror and earnings stats stay correct.
function EconomyService.creditCurrency(
	player: Player,
	currencyId: string,
	amount: number,
	source: string
): (boolean, number)
	if currencyId == PRIMARY then
		return EconomyService.awardRaw(player, amount, source)
	end
	local profile = ProfileService.get(player)
	if profile == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, 0
	end
	local granted = math.floor(math.min(amount, 1e12))
	local currencies = ensureCurrencies(profile)
	currencies[currencyId] = math.min((currencies[currencyId] or 0) + granted, CURRENCY_CAP)
	ProfileService.markDirty(player, `award:{currencyId}:{source}`)
	return true, granted
end

-- Spends a secondary currency. The primary currency is routed through spend().
function EconomyService.spendCurrency(
	player: Player,
	currencyId: string,
	amount: number,
	source: string
): boolean
	if currencyId == PRIMARY then
		return EconomyService.spend(player, amount, source)
	end
	local profile = ProfileService.get(player)
	if profile == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	local cost = math.floor(amount)
	local currencies = ensureCurrencies(profile)
	if (currencies[currencyId] or 0) < cost then
		return false
	end
	currencies[currencyId] -= cost
	ProfileService.markDirty(player, `spend:{currencyId}:{source}`)
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

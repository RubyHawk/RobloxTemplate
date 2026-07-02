--!strict

local CurrencyConfig = {}

CurrencyConfig.MAX_CURRENCIES = 5

export type Definition = {
	id: string,
	name: string,
	symbol: string,
	color: { number },
	startingAmount: number,
}

local DEFAULT: Definition = {
	id = "coins",
	name = "Coins",
	symbol = "$",
	color = { 255, 202, 10 },
	startingAmount = 0,
}

local function validId(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 24
		and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
end

local function channel(value: any, fallback: number): number
	return if type(value) == "number" and value == value
		then math.clamp(math.floor(value), 0, 255)
		else fallback
end

function CurrencyConfig.normalize(raw: any): { Definition }
	local result: { Definition } = {}
	local used: { [string]: boolean } = {}
	if type(raw) == "table" then
		for _, candidate in raw do
			if #result >= CurrencyConfig.MAX_CURRENCIES or type(candidate) ~= "table" then
				break
			end
			local id = candidate.id
			if not validId(id) or used[id] then
				continue
			end
			local name = if type(candidate.name) == "string"
					and #candidate.name >= 1
					and #candidate.name <= 24
				then candidate.name
				else id
			local symbol = if type(candidate.symbol) == "string"
					and #candidate.symbol >= 1
					and #candidate.symbol <= 4
				then candidate.symbol
				else string.upper(string.sub(name, 1, 1))
			local rawColor = if type(candidate.color) == "table" then candidate.color else {}
			local startingAmount = if type(candidate.startingAmount) == "number"
					and candidate.startingAmount == candidate.startingAmount
				then math.clamp(math.floor(candidate.startingAmount), 0, 1e12)
				else 0
			used[id] = true
			table.insert(result, {
				id = id,
				name = name,
				symbol = symbol,
				color = {
					channel(rawColor[1], DEFAULT.color[1]),
					channel(rawColor[2], DEFAULT.color[2]),
					channel(rawColor[3], DEFAULT.color[3]),
				},
				startingAmount = startingAmount,
			})
		end
	end
	if #result == 0 then
		table.insert(result, {
			id = DEFAULT.id,
			name = DEFAULT.name,
			symbol = DEFAULT.symbol,
			color = table.clone(DEFAULT.color),
			startingAmount = DEFAULT.startingAmount,
		})
	end
	return result
end

function CurrencyConfig.startingBalances(currencies: { Definition }): { [string]: number }
	local balances: { [string]: number } = {}
	for _, definition in currencies do
		balances[definition.id] = definition.startingAmount
	end
	return balances
end

-- Shared by profile creation and migration so every path agrees on balances:
-- profiles saved before schema 2 move their single legacy `coins` number into
-- the primary currency, a currency the profile has never held starts at its
-- configured startingAmount (never retroactively re-granted once the key
-- exists), and the legacy `coins` field keeps mirroring the primary balance
-- for old readers. Balances a profile already has are left untouched.
function CurrencyConfig.reconcileProfileCurrencies(
	profile: any,
	currencies: { Definition },
	primaryId: string,
	previousVersion: number
)
	if type(profile.currencies) ~= "table" then
		profile.currencies = {}
	end
	if previousVersion < 2 then
		profile.currencies[primaryId] = if type(profile.coins) == "number" then profile.coins else 0
	end
	for _, definition in currencies do
		if type(profile.currencies[definition.id]) ~= "number" then
			profile.currencies[definition.id] = definition.startingAmount
		end
	end
	profile.coins = profile.currencies[primaryId]
end

return CurrencyConfig

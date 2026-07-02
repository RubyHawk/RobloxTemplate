--!strict

local Types = require(script.Parent.Types)
local Config = require(script.Parent.TemplateConfig)
type PlayerProfileV1 = Types.PlayerProfileV1

local ProfileTemplate = {}

function ProfileTemplate.create(now: number): PlayerProfileV1
	local currencies: { [string]: number } = {}
	for _, definition in Config.economy.currencies do
		currencies[definition.id] = definition.startingAmount
	end
	return {
		schemaVersion = 4,
		coins = currencies[Config.economy.primaryCurrencyId] or 0,
		currencies = currencies,
		inventory = {
			double_coins_potion = { quantity = 1 },
		},
		boosts = {},
		settings = {
			musicVolume = 0.5,
			sfxVolume = 0.7,
			uiScale = 1,
			reducedMotion = false,
			announcements = true,
			afKRollOver = true,
			notifications = false,
		},
		stats = {
			playSeconds = 0,
			joins = 0,
			totalCoinsEarned = 0,
		},
		daily = {
			lastClaimDay = -1,
			streak = 0,
		},
		redemptions = {},
		entitlements = {
			extendedOffline = false,
			premium = false,
		},
		social = {
			friendCountInServer = 0,
			communityVerified = false,
			discordVerified = false,
		},
		guild = {},
		feedback = {
			lastSubmittedAt = 0,
		},
		offline = {
			pendingAmount = 0,
			pendingElapsed = 0,
			preparedAt = 0,
		},
		lastSeenAt = now,
		offlineRateSnapshot = 0,
		createdAt = now,
		updatedAt = now,
	}
end

return ProfileTemplate

--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local DataStoreNames = require(script.Parent.DataStoreNames)
local DesignerConfig = require(script.Parent.DesignerConfig)
local IconAssets = require(script.Parent.IconAssets)

local configuredCurrencies = CurrencyConfig.normalize(DesignerConfig.currencies)
local dataNamespace = DataStoreNames.validateNamespace(DesignerConfig.dataNamespace)
local configuredIdentity = if type(DesignerConfig.identity) == "table" then DesignerConfig.identity else {}
-- Any independently authored pack passes through; the same rule the preset
-- builder enforces (lowercase start, then lowercase/digits/underscore/hyphen).
local configuredPreset = if type(DesignerConfig.preset) == "string"
		and #DesignerConfig.preset <= 40
		and string.match(DesignerConfig.preset, "^[a-z][a-z0-9_-]*$") ~= nil
	then DesignerConfig.preset
	else "incremental"

local Config = {
	version = "0.1.0",
	dataNamespace = dataNamespace,
	profileStoreName = DataStoreNames.scoped("RobloxTemplate_Profile_v1", dataNamespace),
	publicProfileStoreName = DataStoreNames.scoped("RobloxTemplate_PublicProfiles_v1", dataNamespace),
	feedbackStoreName = DataStoreNames.scoped("RobloxTemplate_Feedback_v1", dataNamespace),
	leaderboardStoreName = DataStoreNames.scoped("RobloxTemplate_CoinsLeaderboard_v1", dataNamespace),
	ui = {
		preset = configuredPreset,
	},

	features = {
		store = true,
		inventory = true,
		profiles = true,
		dailyRewards = true,
		offlineEarnings = true,
		leaderboards = true,
		crossServerChat = true,
		feedback = true,
		codes = true,
		settings = true,
		likesBoard = true,
		notifications = true,
		afKRollOver = true,
		runes = true,
		communityVerification = false,
		discordVerification = false,
		guilds = false,
	},

	studio = {
		-- Template/showroom recipes use "mock" everywhere, even on published
		-- servers of the permanent template experience. Generated playable
		-- recipes use "live", including Studio after API Services access is
		-- enabled.
		dataStoreMode = if DesignerConfig.experienceMode == "template" then "mock" else "live",
		mockStartingCoins = 100_000_000_000,
		openComponentGallery = true,
	},

	identity = {
		universeId = if type(configuredIdentity.universeId) == "number"
			then configuredIdentity.universeId
			else 0,
		placeId = if type(configuredIdentity.placeId) == "number" then configuredIdentity.placeId else 0,
		communityId = 0,
	},

	economy = {
		primaryCurrency = configuredCurrencies[1].name,
		primaryCurrencyId = configuredCurrencies[1].id,
		currencies = configuredCurrencies,
		baseOfflineRatePerSecond = 1,
		friendBonusPerFriend = 0.10,
		friendBonusCap = 0.50,
		premiumBonus = 0.10,
		freeOfflineCapHours = 4,
		paidOfflineCapHours = 12,
		extendedOfflineGamePassId = 0,
	},

	-- Rune altar: standing in the authored circle automatically spends the
	-- primary currency on random rune cards that permanently raise currency
	-- generation. Odds live in RuneCatalog; tunables live here.
	runes = {
		baseCost = 75,
		costGrowth = 1,
		maxCost = 75,
		autoRollSeconds = 2,
		firstRollChargeSeconds = 1.25,
		circlePadding = 1.5,
		circleHeightTolerance = 8,
		pityThreshold = 40,
		pityMinimumRarity = "epic",
	},

	rewards = {
		daily = { 250, 500, 750, 1000, 1500, 2000, 3000 },
		codes = {
			WELCOME = { coins = 500, itemId = "double_coins_potion", quantity = 1 },
			THANKYOU500 = { coins = 2500, itemId = "triple_coins_potion", quantity = 1 },
		},
		likesMilestones = {
			{ likes = 100, code = "WELCOME", label = "500 Coins + x2 Potion" },
			{ likes = 500, code = "THANKYOU500", label = "Community boost" },
		},
		manualLikes = 0,
		likesRefreshSeconds = 300,
	},

	announcements = {
		intervalSeconds = 180,
		messages = {
			"Open your Bag to use boosts you've collected!",
			"Come back tomorrow to keep your daily streak going!",
			"Check the game page for community news and updates.",
		},
	},

	afK = {
		warnAfterIdleSeconds = 15 * 60,
		countdownSeconds = 30,
	},

	feedback = {
		maxLength = 500,
		cooldownSeconds = 300,
	},

	leaderboards = {
		-- The leaderstat column shows the recipe's primary currency name. The
		-- ordered store keeps the "RobloxTemplate_CoinsLeaderboard_v1" name so
		-- existing saved rankings stay compatible.
		metric = configuredCurrencies[1].name,
		globalSize = 50,
		refreshSeconds = 60,
	},

	notifications = {
		workerUrl = "",
		dailyMessageId = "",
		offlineMessageId = "",
	},

	products = {
		coinPackSmall = { id = 0, coins = 1000 },
		coinPackLarge = { id = 0, coins = 10000 },
	},

	audio = {
		music = "",
		-- Public Roblox-owned sounds selected from Sound Kit v1.6.0 (asset 7209483381).
		-- Keeping the IDs here makes every game built from this template free to replace the sound theme.
		click = "rbxassetid://12221967", -- button.wav
		cash = "rbxassetid://12222054", -- Kerplunk.wav
		reward = "rbxassetid://12222253", -- victory.wav
		inventory = "rbxassetid://12222170", -- switch.wav
		lootboxOpen = "rbxassetid://12222200", -- swoosh.wav
		spin = "rbxassetid://12221976", -- clickfast.wav
		notification = "rbxassetid://12222076", -- Pageturn1
	},

	-- The tracked manifest connects licensed source PNGs to Roblox content.
	-- Manage it through ICON_LIBRARY.cmd so both developers share the same mapping.
	icons = IconAssets.ids,
}

if type(DesignerConfig.features) == "table" then
	for feature, enabled in DesignerConfig.features do
		if Config.features[feature] ~= nil and type(enabled) == "boolean" then
			Config.features[feature] = enabled
		end
	end
end

return table.freeze(Config)

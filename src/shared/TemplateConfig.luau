--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local DataStoreNames = require(script.Parent.DataStoreNames)
local DesignerConfig = require(script.Parent.DesignerConfig)

local configuredCurrencies = CurrencyConfig.normalize(DesignerConfig.currencies)
local dataNamespace = DataStoreNames.validateNamespace(DesignerConfig.dataNamespace)
local configuredIdentity = if type(DesignerConfig.identity) == "table" then DesignerConfig.identity else {}

local Config = {
	version = "0.1.0",
	dataNamespace = dataNamespace,
	profileStoreName = DataStoreNames.scoped("RobloxTemplate_Profile_v1", dataNamespace),
	publicProfileStoreName = DataStoreNames.scoped("RobloxTemplate_PublicProfiles_v1", dataNamespace),
	feedbackStoreName = DataStoreNames.scoped("RobloxTemplate_Feedback_v1", dataNamespace),
	leaderboardStoreName = DataStoreNames.scoped("RobloxTemplate_CoinsLeaderboard_v1", dataNamespace),
	ui = {
		preset = if DesignerConfig.preset == "rpg" then "rpg" else "incremental",
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
		communityVerification = false,
		discordVerification = false,
		guilds = false,
	},

	studio = {
		-- Template/showroom recipes use "mock". Published playable recipes use
		-- "live", including Studio after API Services access is enabled.
		dataStoreMode = if DesignerConfig.experienceMode == "template" then "mock" else "live",
		mockStartingCoins = 2500,
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
		metric = "Coins",
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
		-- Keeping the IDs here makes every map branch free to replace the sound theme.
		click = "rbxassetid://12221967", -- button.wav
		cash = "rbxassetid://12222054", -- Kerplunk.wav
		reward = "rbxassetid://12222253", -- victory.wav
		inventory = "rbxassetid://12222170", -- switch.wav
		lootboxOpen = "rbxassetid://12222200", -- swoosh.wav
		spin = "rbxassetid://12221976", -- clickfast.wav
		notification = "rbxassetid://12222076", -- Pageturn1
	},

	-- These public demo IDs come from the user-supplied Zxgly V5 pack so the
	-- starter is icon-rich immediately. Replace any entry with an uploaded file
	-- from assets/icons/gvesster-basic when branding a map branch.
	icons = {
		bag = "94001317361506", -- backpack
		shop = "118554800883386", -- shop basket
		rewards = "125907024425133", -- reward egg
		profile = "132073513775656", -- blue cat
		more = "78666886648909", -- quest scroll
		codes = "128511762212540", -- code ticket
		leaderboard = "72712419474456", -- ranking bars
		community = "121433088081713", -- cow pet
		feedback = "89113974252559", -- feedback book
		settings = "94272687133453", -- settings gear
		coin = "105300168575798", -- cash stack
		daily = "71479056537473", -- calendar
		offline = "107794977982643", -- timer
		premium = "111977708425543", -- Robux token
		search = "",
		close = "",
		likes = "128953798572692", -- dog pet
		friends = "71515579128420", -- pig pet
		notifications = "107794977982643", -- timer
		cart = "118554800883386", -- shop basket
		verification = "121433088081713", -- cow pet
		item = "125907024425133", -- reward egg
		starterTool = "134119181427014", -- sword
		potionX2 = "72854331493787", -- x2 clover
		potionX3 = "102321175672770", -- potion bottle
	},
}

if type(DesignerConfig.features) == "table" then
	for feature, enabled in DesignerConfig.features do
		if Config.features[feature] ~= nil and type(enabled) == "boolean" then
			Config.features[feature] = enabled
		end
	end
end

return table.freeze(Config)

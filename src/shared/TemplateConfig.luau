--!strict

local Config = {
	version = "0.1.0",
	profileStoreName = "RobloxTemplate_Profile_v1",
	publicProfileStoreName = "RobloxTemplate_PublicProfiles_v1",
	feedbackStoreName = "RobloxTemplate_Feedback_v1",
	leaderboardStoreName = "RobloxTemplate_CoinsLeaderboard_v1",

	features = {
		store = true,
		inventory = true,
		profiles = true,
		dailyRewards = true,
		offlineEarnings = true,
		leaderboards = true,
		crossServerChat = true,
		feedback = true,
		likesBoard = true,
		notifications = true,
		afKRollOver = true,
		communityVerification = false,
		discordVerification = false,
		guilds = false,
	},

	studio = {
		useLiveDataStore = false,
		mockStartingCoins = 2500,
		openComponentGallery = true,
	},

	identity = {
		universeId = 0,
		placeId = 0,
		communityId = 0,
	},

	economy = {
		primaryCurrency = "Coins",
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
		click = "",
		cash = "",
		reward = "",
		inventory = "",
		lootboxOpen = "",
		spin = "",
	},

	-- Upload the matching files from assets/icons/gvesster-basic, then paste the
	-- Roblox image asset IDs here. Leave an entry empty to keep its authored
	-- Studio fallback visible.
	icons = {
		bag = "",
		shop = "",
		rewards = "",
		profile = "",
		more = "",
		codes = "",
		leaderboard = "",
		community = "",
		feedback = "",
		settings = "",
		coin = "",
		daily = "",
		offline = "",
		premium = "",
		search = "",
		close = "",
		likes = "",
		friends = "",
		notifications = "",
		cart = "",
		verification = "",
		item = "",
		starterTool = "",
		potionX2 = "",
		potionX3 = "",
	},
}

return table.freeze(Config)

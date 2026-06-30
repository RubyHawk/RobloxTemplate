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
		-- When true (Studio only), ProfileService persists to a separate
		-- "<profileStoreName>_canary" DataStore and SeedProfiles writes
		-- deterministic fixtures there for inspection in Data Delve Canary.
		-- Production data is never touched. Keep false on the live experience.
		useCanaryStore = false,
		seedCanaryProfiles = false,
	},

	-- UI pack layer. Each game picks an active pack; widgets bind to a finite
	-- pool of pre-authored HUD slots whose sizes are pinned here so the authored
	-- model, pack descriptors, and binder/validator can never drift apart.
	ui = {
		defaultPackId = "incremental",
		allowPlayerPackSelection = false,
		statWidgetPoolSize = 6,
		actionSlotPoolSize = 4,
		progressBarPoolSize = 2,
	},

	identity = {
		universeId = 0,
		placeId = 0,
		communityId = 0,
	},

	economy = {
		primaryCurrency = "Coins",
		-- Stable data key for the primary currency inside profile.currencies. The
		-- top-level profile.coins field mirrors currencies[primaryCurrencyId].
		primaryCurrencyId = "coins",
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
		-- UI-pack stat icons. Left blank so the widget's text Symbol shows until a
		-- map branch uploads art and pastes the asset id here.
		health = "",
		stamina = "",
		energy = "",
		gem = "",
		income = "",
		multiplier = "",
		rebirth = "",
		objective = "",
		ability = "",
	},
}

return table.freeze(Config)

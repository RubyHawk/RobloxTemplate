--!strict

local CurrencyConfig = require(script.Parent.CurrencyConfig)
local DataStoreNames = require(script.Parent.DataStoreNames)
local DesignerConfig = require(script.Parent.DesignerConfig)
local DungeonConfig = require(script.Parent.DungeonConfig)
local IconAssets = require(script.Parent.IconAssets)
local RuneModeConfig = require(script.Parent.RuneModeConfig)
local StagePlatformLayout = require(script.Parent.StagePlatformLayout)

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

-- Optional per-recipe rune overrides. The template's own DesignerConfig has no
-- runes table; generated recipes may add one to retune altar pacing, milestone
-- curves, or channel-mode availability per game stage.
local designerRunes: { [string]: any } = if type((DesignerConfig :: any).runes) == "table"
	then (DesignerConfig :: any).runes
	else {}

local function runeNumber(key: string, fallback: number, minimum: number, maximum: number): number
	local value = designerRunes[key]
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function runeRarityId(key: string, fallback: string): string
	local value = designerRunes[key]
	return if type(value) == "string" and #value >= 1 and #value <= 24 then value else fallback
end

local runeChannelModes = RuneModeConfig.normalize(designerRunes.channelModes, {
	{
		id = "luck",
		name = "Lucky Channel",
		kind = "luck",
		unlock = { kind = "always", value = 0 },
		tiers = {
			{ atSeconds = 10, value = 1.25 },
			{ atSeconds = 30, value = 1.75 },
			{ atSeconds = 60, value = 2.5 },
		},
	},
	{
		id = "surge",
		name = "Coin Surge",
		kind = "surge",
		unlock = { kind = "totalRolls", value = 25 },
		tiers = {
			{ atSeconds = 10, value = 1.25 },
			{ atSeconds = 30, value = 1.5 },
			{ atSeconds = 60, value = 2 },
		},
	},
})

local runeCopyMilestones = RuneModeConfig.normalizeMilestones(designerRunes.copyMilestones, {
	{ copies = 5, multiplier = 1.25 },
	{ copies = 10, multiplier = 1.5 },
	{ copies = 25, multiplier = 2 },
})

-- The persisted default must always resolve to a configured mode, even when a
-- recipe renames or removes the template's "luck" mode.
local function runeDefaultMode(): string
	local candidate = designerRunes.defaultChannelMode
	local requested = if type(candidate) == "string" then candidate else "luck"
	for _, mode in runeChannelModes do
		if mode.id == requested then
			return requested
		end
	end
	return runeChannelModes[1].id
end

local firstPlatformOffsetFromCenter = { 183.524, 13.344, 94.169 }
local centerFacingLocalDirection = { -54, 0, -32 }
local firstPlatformYawDegrees = math.deg(StagePlatformLayout.alignDirectionYaw({
	x = firstPlatformOffsetFromCenter[1],
	y = firstPlatformOffsetFromCenter[2],
	z = firstPlatformOffsetFromCenter[3],
}, {
	x = centerFacingLocalDirection[1],
	y = centerFacingLocalDirection[2],
	z = centerFacingLocalDirection[3],
}))

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
		towerDefense = false,
		dungeon = false,
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
	-- generation. Uninterrupted channeling builds momentum through the active
	-- channel mode's tiers (luck shifts rarity odds, surge boosts earnings
	-- under the strongest-temporary-boost rule), and duplicate copies unlock
	-- milestone multipliers. Odds live in RuneCatalog; every tunable here
	-- accepts a DesignerConfig.runes override.
	runes = {
		baseCost = runeNumber("baseCost", 75, 1, 1e9),
		costGrowth = runeNumber("costGrowth", 1, 1, 10),
		maxCost = runeNumber("maxCost", 75, 1, 1e12),
		autoRollSeconds = runeNumber("autoRollSeconds", 2, 0.5, 60),
		firstRollChargeSeconds = runeNumber("firstRollChargeSeconds", 1.25, 0, 30),
		circlePadding = runeNumber("circlePadding", 1.5, 0, 50),
		circleHeightTolerance = runeNumber("circleHeightTolerance", 8, 1, 50),
		pityThreshold = runeNumber("pityThreshold", 40, 0, 1000),
		pityMinimumRarity = runeRarityId("pityMinimumRarity", "epic"),
		tickSeconds = runeNumber("tickSeconds", 0.25, 0.05, 2),
		maxTotalBonusPercent = runeNumber("maxTotalBonusPercent", 1_000_000, 100, 1e9),
		maxOwnedPerRune = runeNumber("maxOwnedPerRune", 1_000_000_000, 1000, 1e12),
		maxTotalRolls = runeNumber("maxTotalRolls", 1_000_000_000, 1000, 1e12),
		revealSeconds = runeNumber("revealSeconds", 3, 0.5, 30),
		rareAudioMinimumRarity = runeRarityId("rareAudioMinimumRarity", "epic"),
		minCommonWeight = runeNumber("minCommonWeight", 500, 0, 9999),
		copyMilestones = runeCopyMilestones,
		defaultChannelMode = runeDefaultMode(),
		channelModes = runeChannelModes,
	},

	towerDefense = {
		unitRollCost = 75,
		loadoutSlots = 4,
		baseHealth = 20,
		autoPlaceMaxUnits = 4,
		simulationHz = 20,
		networkSnapshotHz = 4,
		maximumEnemiesPerPlayer = 500,
		starterLevelsPerStage = 10,
		platformSlotCount = 6,
		centerPartNames = { "center_grass", "ccenter_grass" },
		firstPlatformIslandName = "FirstPrivateIsland",
		platformModelName = "GamePlatform",
		platformOriginName = "PlatformOrigin",
		firstPlatformOffsetFromCenter = firstPlatformOffsetFromCenter,
		centerFacingLocalDirection = centerFacingLocalDirection,
		firstPlatformYawDegrees = firstPlatformYawDegrees,
		platformOriginsFolderName = "StagePlatformOrigins",
		platformOwnerMarkersFolderName = "StagePlatformOwners",
		platformOwnerAnchorsFolderName = "StagewrightOwnerAnchors",
		platformOwnerMarkerHeight = 16,
		authoringArea = {
			enabled = true,
			areaName = "StagewrightAdminArea",
			offsetFromCenter = { 0, -1000, 3000 },
			roomSize = { 168, 44, 148 },
			wallThickness = 2,
		},
		developmentOutlines = {
			folderName = "StagewrightIslandOutlines",
			heightOffset = 0.22,
			lineHeight = 0.14,
			lineThickness = 0.32,
			lineTransparency = 0.08,
			lineColor = { 69, 224, 255 },
			gridLineThickness = 0.12,
			gridLineTransparency = 0.32,
			fillTransparency = 0.9,
			fillColor = { 35, 139, 170 },
		},
		gridVisuals = {
			enabled = true,
			folderName = "StagewrightClientGrids",
			otherPlatformFade = 0.58,
			heightOffset = 0.22,
			surfaceHeight = 0.025,
			surfaceTransparency = 0.94,
			surfaceColor = { 24, 61, 78 },
			lineHeight = 0.08,
			lineThickness = 0.16,
			lineTransparency = 0.08,
			lineColor = { 112, 232, 255 },
			routeHeight = 0.08,
			routeWidth = 2.4,
			routeSampleSpacing = 3.5,
			routeVerticalOffset = -0.22,
			routeTransparency = 0.24,
			routeColor = { 237, 170, 66 },
			markerHeight = 0.075,
			markerTransparency = 0.2,
			spawnColor = { 73, 222, 128 },
			goalColor = { 248, 92, 92 },
			autoPlaceColor = { 84, 158, 255 },
			blockedColor = { 132, 55, 68 },
		},
		towerVisuals = {
			folderName = "StagewrightClientTowers",
			size = { 1.4, 2.6, 2.6 },
			color = { 78, 151, 73 },
		},
	},

	-- Portal -> reserved-server dungeon: standing on the authored portal pad forms
	-- a party (solo allowed), a server-owned countdown runs, then the party is
	-- teleported into a private instance of this same place to fight a boss. Every
	-- tunable accepts a DesignerConfig.dungeon override; DungeonConfig clamps and
	-- validates the whole block so a bad recipe never strands the default boss.
	dungeon = DungeonConfig.normalize((DesignerConfig :: any).dungeon),

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

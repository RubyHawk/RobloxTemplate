--!strict

local Calculations = require("../src/shared/Calculations")
local CurrencyConfig = require("../src/shared/CurrencyConfig")
local RuneCatalog = require("../src/shared/RuneCatalog")
local RuneLogic = require("../src/shared/RuneLogic")
local RuneModeConfig = require("../src/shared/RuneModeConfig")
local TowerDefenseCatalog = require("../src/shared/TowerDefenseCatalog")
local TowerDefenseLogic = require("../src/shared/TowerDefenseLogic")
local DataStoreNames = require("../src/shared/DataStoreNames")
local DataStoreKeys = require("../src/shared/DataStoreKeys")
local MigrationCore = require("../src/shared/MigrationCore")
local ReceiptLedger = require("../src/shared/ReceiptLedger")
local SessionLock = require("../src/server/Util/SessionLock")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local passed = 0

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
	passed += 1
end

local normalizedCurrencies = CurrencyConfig.normalize({
	{
		id = "coins",
		name = "Coins",
		symbol = "$",
		iconAssetId = "105300168575798",
		color = { 999, -2, 20 },
		startingAmount = 5,
	},
	{ id = "coins", name = "Duplicate", symbol = "D" },
	{ id = "gems", name = "Gems", symbol = "◆", startingAmount = 10 },
	{ id = "stars", name = "Stars", symbol = "★" },
	{ id = "tokens", name = "Tokens", symbol = "T" },
	{ id = "event", name = "Event", symbol = "!" },
	{ id = "sixth", name = "Sixth", symbol = "6" },
})
expectEqual(#normalizedCurrencies, 5, "currency configuration caps authored slots at five")
expectEqual(normalizedCurrencies[1].color[1], 255, "currency color clamps high channels")
expectEqual(normalizedCurrencies[1].color[2], 0, "currency color clamps low channels")
expectEqual(normalizedCurrencies[2].id, "gems", "duplicate currency IDs are rejected")
expectEqual(normalizedCurrencies[1].iconAssetId, "105300168575798", "currency icon keeps numeric asset ID")

local configuredCurrencies = CurrencyConfig.normalize({
	{ id = "gold", name = "Gold", symbol = "G", iconAssetId = "rbxassetid://123", startingAmount = 500 },
	{ id = "crystals", name = "Crystals", symbol = "C", iconAssetId = "not-an-id", startingAmount = 10 },
})
expectEqual(configuredCurrencies[1].iconAssetId, "123", "currency icon normalizes rbxassetid prefix")
expectEqual(configuredCurrencies[2].iconAssetId, "", "invalid currency icon uses symbol fallback")
local seededBalances = CurrencyConfig.startingBalances(configuredCurrencies)
expectEqual(seededBalances.gold, 500, "fresh profiles seed the configured starting balance")
expectEqual(seededBalances.crystals, 10, "fresh profiles seed every configured currency")
local legacyCurrencyProfile = { coins = 100 }
CurrencyConfig.reconcileProfileCurrencies(legacyCurrencyProfile, configuredCurrencies, "gold", 1)
expectEqual(legacyCurrencyProfile.currencies.gold, 100, "legacy coins migrate to primary currency")
expectEqual(legacyCurrencyProfile.currencies.crystals, 10, "new currencies receive starting balance")
local savedCurrencyProfile = { coins = 42, currencies = { gold = 42, crystals = "corrupt" } }
CurrencyConfig.reconcileProfileCurrencies(savedCurrencyProfile, configuredCurrencies, "gold", 4)
expectEqual(savedCurrencyProfile.currencies.gold, 42, "saved balances are not re-granted")
expectEqual(savedCurrencyProfile.currencies.crystals, 10, "corrupt balances recover safely")
expectEqual(
	DataStoreNames.scoped("RobloxTemplate_Profile_v1", "incremental"),
	"RobloxTemplate_Profile_v1_incremental",
	"preset namespace isolates profile stores inside the shared sandbox"
)
expectEqual(
	pcall(function()
		DataStoreNames.validateNamespace("bad-preset")
	end),
	false,
	"DataStore namespaces reject unsafe characters"
)

local canClaim, streak = Calculations.dailyClaim(9, 2, 10 * 86400, 7)
expectEqual(canClaim, true, "daily can claim")
expectEqual(streak, 3, "daily increments")

local missed, resetStreak = Calculations.dailyClaim(7, 6, 10 * 86400, 7)
expectEqual(missed, true, "missed day can claim")
expectEqual(resetStreak, 1, "missed day resets")

local amount, elapsed = Calculations.offlineEarnings(0, 20 * 3600, 2, 4, 1.1)
expectEqual(elapsed, 4 * 3600, "offline cap")
expectEqual(amount, math.floor(4 * 3600 * 2 * 1.1), "offline reward")

expectEqual(
	Calculations.potionMultiplier(
		{ { multiplier = 2, expiresAt = 100 }, { multiplier = 3, expiresAt = 90 } },
		95
	),
	2,
	"strongest active potion"
)
expectEqual(Calculations.friendBonus(8, 0.1, 0.5), 0.5, "friend cap")
expectEqual(Calculations.normalizeCode(" welcome "), "WELCOME", "code normalization")
expectEqual(Calculations.normalizeCode("bad code!"), nil, "invalid code")

expectEqual(SessionLock.canClaim(nil, "job", 100, 180), true, "empty lock")
expectEqual(
	SessionLock.canClaim({ jobId = "other", placeId = 1, touchedAt = 50 }, "job", 100, 180),
	false,
	"fresh foreign lock"
)
expectEqual(
	SessionLock.canClaim({ jobId = "other", placeId = 1, touchedAt = 0 }, "job", 200, 180),
	true,
	"expired lock"
)

local migrated = MigrationCore.migrate({ schemaVersion = 0, coins = 5, unknown = "keep" }, {
	schemaVersion = 1,
	coins = 0,
	settings = { musicVolume = 0.5 },
}, 1)
expectEqual(migrated.schemaVersion, 1, "profile version migration")
expectEqual(migrated.settings.musicVolume, 0.5, "profile reconciliation")
expectEqual(migrated.unknown, "keep", "migration preserves unknown data")

local repaired = MigrationCore.migrate({ schemaVersion = 1, settings = "broken", coins = 0 / 0 }, {
	schemaVersion = 1,
	coins = 0,
	settings = { musicVolume = 0.5 },
}, 1)
expectEqual(type(repaired.settings), "table", "migration repairs invalid nested table types")
expectEqual(repaired.coins, 0, "migration repairs non-finite persisted numbers")
local futureOk = pcall(function()
	MigrationCore.migrate({ schemaVersion = 99 }, { schemaVersion = 1 }, 1)
end)
expectEqual(futureOk, false, "future profile schemas are refused instead of overwritten")
local migrationsSource = fs.readFile("src/shared/Migrations.luau")
expectEqual(
	string.find(migrationsSource, "Migrations.CURRENT_VERSION = 6", 1, true) ~= nil,
	true,
	"tower defense profile schema version is current"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 6", 1, true) ~= nil,
	true,
	"schema 5 profiles gain tower defense state"
)
expectEqual(
	string.find(migrationsSource, "ownedUnits = {}", 1, true) ~= nil,
	true,
	"tower defense migration creates owned unit storage"
)
expectEqual(
	string.find(migrationsSource, "bestWave = 0", 1, true) ~= nil,
	true,
	"tower defense migration initializes best wave"
)

expectEqual(DataStoreKeys.profile(123), "player:123", "profile key is documented and stable")
expectEqual(DataStoreKeys.publicProfile(123), "user:123", "public profile key is documented")
expectEqual(
	DataStoreKeys.feedback(123, 456, "abc"),
	"user:123:report:456:abc",
	"feedback keys can be listed or erased by user prefix"
)

local rewardServiceSource = fs.readFile("src/server/Services/RewardService.luau")
expectEqual(
	string.find(rewardServiceSource, "profile.offline.pendingAmount", 1, true) ~= nil,
	true,
	"unclaimed offline earnings live in the saved profile"
)

local receipts = {}
expectEqual(ReceiptLedger.claim(receipts, "purchase"), true, "first receipt grants")
expectEqual(ReceiptLedger.claim(receipts, "purchase"), false, "duplicate receipt rejected")

for _, servicePath in
	{
		"src/server/Services/FeedbackService.luau",
		"src/server/Services/LeaderboardService.luau",
		"src/server/Services/ProfileService.luau",
		"src/server/Services/PublicProfileService.luau",
	}
do
	local source = fs.readFile(servicePath)
	expectEqual(
		string.find(source, "local store = DataStoreService:Get", 1, true),
		nil,
		`{servicePath} does not open DataStores while loading`
	)
end

local templateConfigSource = fs.readFile("src/shared/TemplateConfig.luau")
expectEqual(
	string.find(templateConfigSource, "useLiveDataStore", 1, true),
	nil,
	"ambiguous live DataStore switch was removed"
)
expectEqual(
	string.find(
		templateConfigSource,
		'dataStoreMode = if DesignerConfig.experienceMode == "template"',
		1,
		true
	) ~= nil,
	true,
	"persistence mode follows the generated experience kind"
)
expectEqual(
	string.find(templateConfigSource, "DataStoreNames.scoped", 1, true) ~= nil,
	true,
	"all persistent stores are isolated by preset namespace"
)
expectEqual(
	string.find(templateConfigSource, "IconAssets.ids", 1, true) ~= nil,
	true,
	"connected icons come from the shared tracked manifest"
)
local presetBuilderSource = fs.readFile("scripts/build-game-preset.ps1")
expectEqual(
	string.find(presetBuilderSource, 'experienceMode = `"playable`"', 1, true) ~= nil,
	true,
	"generated playable experiences select real persistence"
)
expectEqual(
	string.find(presetBuilderSource, '$preset -notin @("incremental", "rpg")', 1, true),
	nil,
	"preset builder accepts independently authored packs"
)
local gameDesignerSource = fs.readFile("scripts/game-designer.ps1")
expectEqual(
	string.find(gameDesignerSource, "src\\ui\\presets", 1, true) ~= nil,
	true,
	"Game Designer discovers authored preset folders"
)
local sandboxSource = fs.readFile("scripts/sandbox.ps1")
expectEqual(
	string.find(sandboxSource, '"-task", "EditPlace"', 1, true) ~= nil,
	true,
	"sandbox launcher opens the existing cloud place"
)
expectEqual(
	string.find(sandboxSource, "build-game-preset.ps1", 1, true) ~= nil,
	true,
	"sandbox launcher rebuilds the selected preset before opening"
)
expectEqual(
	string.find(sandboxSource, "experiences.config.json", 1, true) ~= nil,
	true,
	"sandbox launcher reads the two-experience config"
)

local experiences = serde.decode("json", fs.readFile("experiences.config.json"))
expectEqual(type(experiences.template) == "table", true, "template experience entry exists")
expectEqual(type(experiences.playerTest) == "table", true, "player-test experience entry exists")
expectEqual(
	experiences.playerTest.universeId > 0 and experiences.playerTest.placeId > 0,
	true,
	"player-test experience keeps its permanent cloud IDs"
)
expectEqual(
	type(experiences.playerTest.defaultPreset) == "string",
	true,
	"player-test default preset is configured"
)

local startSource = fs.readFile("scripts/start.ps1")
expectEqual(
	string.find(startSource, "experiences.config.json", 1, true) ~= nil,
	true,
	"template launcher reads the two-experience config"
)
expectEqual(
	string.find(startSource, '"-task", "EditPlace"', 1, true) ~= nil,
	true,
	"template launcher opens the existing template experience when configured"
)
expectEqual(
	string.find(startSource, "servePlaceIds", 1, true) ~= nil,
	true,
	"template serve project is restricted to the template place"
)

local figmaUiSource = fs.readFile("scripts/figma-ui.ps1")
expectEqual(
	string.find(figmaUiSource, "ValidateSet", 1, true),
	nil,
	"Figma apply path accepts independently authored packs"
)
expectEqual(
	string.find(figmaUiSource, "src/ui/presets", 1, true) ~= nil,
	true,
	"Figma apply path discovers authored preset folders"
)

local dataStoreRuntimeSource = fs.readFile("src/server/Util/DataStoreRuntime.luau")
expectEqual(
	string.find(dataStoreRuntimeSource, 'if Config.studio.dataStoreMode == "mock"', 1, true) ~= nil,
	true,
	"template mock persistence applies outside Studio too"
)
expectEqual(
	string.find(dataStoreRuntimeSource, "RunService:IsStudio() and Config.studio.dataStoreMode", 1, true),
	nil,
	"mock mode no longer depends on running inside Studio"
)

local profileServiceSource = fs.readFile("src/server/Services/ProfileService.luau")
expectEqual(
	string.find(profileServiceSource, "local releasing: { [Player]: boolean }", 1, true) ~= nil,
	true,
	"profile releases track an in-flight owner"
)
expectEqual(
	string.find(profileServiceSource, "while releasing[player] do", 1, true) ~= nil,
	true,
	"overlapping shutdown releases wait instead of clearing the same lock twice"
)
expectEqual(
	string.find(profileServiceSource, "RunService:IsStudio()", 1, true) ~= nil
		and string.find(
				profileServiceSource,
				"math.max(loaded.currencies[definition.id], definition.startingAmount)",
				1,
				true
			)
			~= nil,
	true,
	"Studio playtests top up existing profiles to the configured starting currency"
)

local leaderboardSource = fs.readFile("src/server/Services/LeaderboardService.luau")
expectEqual(
	string.find(leaderboardSource, 'Name = "Coins"', 1, true),
	nil,
	"leaderstat name is not hardcoded to Coins"
)
expectEqual(
	string.find(leaderboardSource, "Config.leaderboards.metric", 1, true) ~= nil,
	true,
	"leaderstat column follows the configured metric"
)
expectEqual(
	string.find(templateConfigSource, 'metric = "Coins"', 1, true),
	nil,
	"leaderboard metric is not hardcoded to Coins"
)
expectEqual(
	string.find(templateConfigSource, "metric = configuredCurrencies[1].name", 1, true) ~= nil,
	true,
	"leaderboard metric follows the recipe primary currency"
)
expectEqual(
	string.find(templateConfigSource, 'if DesignerConfig.preset == "rpg"', 1, true),
	nil,
	"ui preset is not collapsed to two hardcoded packs"
)
expectEqual(
	string.find(templateConfigSource, '"^[a-z][a-z0-9_-]*$"', 1, true) ~= nil,
	true,
	"ui preset validates any authored pack name"
)
expectEqual(
	string.find(templateConfigSource, "preset = configuredPreset", 1, true) ~= nil,
	true,
	"ui preset passes through the validated pack name"
)

local chatSource = fs.readFile("src/client/init.client.luau") .. fs.readFile("default.project.json")
for _, legacyToken in
	{
		'GetService("Chat")',
		"LegacyChatService",
		"DefaultChatSystemChatEvents",
		"SayMessageRequest",
		"ChatVersion",
		"LoadDefaultChat",
	}
do
	expectEqual(string.find(chatSource, legacyToken, 1, true), nil, `legacy chat token: {legacyToken}`)
end
expectEqual(string.find(chatSource, "RBXSystem", 1, true) ~= nil, true, "announcements use RBXSystem")

local iconCatalogSource = fs.readFile("src/shared/IconCatalog.luau")
expectEqual(
	string.find(iconCatalogSource, 'string.find(assetId, "^rbxgameasset")', 1, true) ~= nil,
	true,
	"icon catalog preserves experience-local Asset Manager image names"
)

for _, showroomPath in
	{
		"assets/ui/ZxglyV5Showroom.rbxmx",
		"assets/ui/NotificationV2Showroom.rbxmx",
	}
do
	local showroom = fs.readFile(showroomPath)
	expectEqual(
		string.find(showroom, '<bool name="Enabled">false</bool>', 1, true) ~= nil,
		true,
		`{showroomPath} is disabled until selected`
	)
	for _, scriptClass in { "LocalScript", "ModuleScript", "Script" } do
		expectEqual(
			string.find(showroom, `<Item class="{scriptClass}"`, 1, true),
			nil,
			`{showroomPath} contains no {scriptClass}`
		)
	end
end

local bootstrap = fs.readFile("bootstrap.project.json")
expectEqual(
	string.find(bootstrap, "TemplateLoading.model.json", 1, true) ~= nil,
	true,
	"loading screen is bootstrapped from an authored StarterGui model"
)
expectEqual(
	string.find(bootstrap, "StarterSignUI.model.json", 1, true) ~= nil,
	true,
	"playable sign is bootstrapped from an authored StarterGui model"
)
if string.find(bootstrap, "ZxglyV5Showroom", 1, true) then
	expectEqual(string.find(bootstrap, "GalleryMenu", 1, true) ~= nil, true, "gallery menu is bootstrapped")
	expectEqual(
		string.find(bootstrap, "GalleryBackdrop", 1, true) ~= nil,
		true,
		"gallery backdrop is bootstrapped"
	)
else
	expectEqual(string.find(bootstrap, "GalleryMenu", 1, true), nil, "starter excludes gallery menu")
	expectEqual(string.find(bootstrap, "GalleryBackdrop", 1, true), nil, "starter excludes gallery backdrop")
end
local connectedUi = fs.readFile("src/ui/TemplateUI.model.json")
local compactConnectedUi = string.gsub(connectedUi, "%s+", "")
for _, requiredObject in
	{
		'"Name":"CurrencyHUD"',
		'"Name":"Navigation"',
		'"Name":"MoreButton"',
		'"Name":"MoreMenu"',
		'"Name":"ScreenTemplate"',
		'"Name":"ItemCardTemplate"',
		'"Name":"RewardTileTemplate"',
		'"Name":"AddCoinsButton"',
	}
do
	expectEqual(
		string.find(compactConnectedUi, requiredObject, 1, true) ~= nil,
		true,
		`connected UI includes {requiredObject}`
	)
end
for _, preset in { "incremental", "rpg" } do
	local presetUi = fs.readFile(`src/ui/presets/{preset}/TemplateUI.model.json`)
	expectEqual(
		string.find(presetUi, '"Name": "CurrencySlot05"', 1, true) ~= nil
			or string.find(presetUi, '"Name":"CurrencySlot05"', 1, true) ~= nil,
		true,
		`{preset} preset pre-authors all five configurable currency slots`
	)
	expectEqual(
		string.find(presetUi, '"Enabled": false', 1, true) ~= nil
			or string.find(presetUi, '"Enabled":false', 1, true) ~= nil,
		true,
		`{preset} preset stays isolated until selected`
	)
	local compactPresetUi = string.gsub(presetUi, "%s+", "")
	local iconCount = 0
	for _ in string.gmatch(compactPresetUi, '"Name":"Icon","ClassName":"ImageLabel"') do
		iconCount += 1
	end
	expectEqual(iconCount >= 5, true, `{preset} preset pre-authors currency ImageLabels`)
end
local incrementalPreset = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
local rpgPreset = fs.readFile("src/ui/presets/rpg/TemplateUI.model.json")
expectEqual(incrementalPreset == rpgPreset, false, "RPG and Incremental are independent visual files")
local compactIncrementalPreset = string.gsub(incrementalPreset, "%s+", "")
for _, modernObject in
	{
		'"Name":"CategoryTabs"',
		'"Name":"AllButton"',
		'"Name":"ConsumableButton"',
		'"Name":"EquipmentButton"',
		'"Name":"MiscButton"',
		'"Name":"BoostPanel"',
		'"Name":"SummaryButton"',
		'"Name":"TotalValue"',
	}
do
	expectEqual(
		string.find(compactIncrementalPreset, modernObject, 1, true) ~= nil,
		true,
		`Incremental preset physically authors {modernObject}`
	)
end
expectEqual(
	string.find(rpgPreset, '"Text": "MERCHANT"', 1, true) ~= nil
		or string.find(rpgPreset, '"Text":"MERCHANT"', 1, true) ~= nil,
	true,
	"RPG preset carries its own game-specific labels"
)

local loadingUi = fs.readFile("src/ui/TemplateLoading.model.json")
for _, authoredLoadingObject in
	{ '"Name": "Card"', '"Name": "Status"', '"Name": "ProgressTrack"', '"Name": "Fill"' }
do
	expectEqual(
		string.find(loadingUi, authoredLoadingObject, 1, true) ~= nil,
		true,
		`loading UI pre-authors {authoredLoadingObject}`
	)
end

local starterSignUi = fs.readFile("src/ui/StarterSignUI.model.json")
for _, authoredSignObject in { '"Name": "Header"', '"Name": "Instruction"', '"Name": "Reward"' } do
	expectEqual(
		string.find(starterSignUi, authoredSignObject, 1, true) ~= nil,
		true,
		`starter sign pre-authors {authoredSignObject}`
	)
end

local authoredVisualBinders = fs.readFile("src/ReplicatedFirst/Loading.client.luau")
	.. fs.readFile("src/starter/StarterExample.server.luau")
	.. fs.readFile("src/starter-client/StarterExample.client.luau")
	.. fs.readFile("src/starter/RuneCircle.server.luau")
	.. fs.readFile("src/starter-client/RuneCircle.client.luau")
for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
	expectEqual(
		string.find(authoredVisualBinders, forbiddenConstructor, 1, true),
		nil,
		`loading and starter sign binders do not use {forbiddenConstructor}`
	)
end

local playableProject = fs.readFile("default.project.json")
for _, authoredWorldObject in
	{
		'"ExampleEarningPad"',
		'"EarnPrompt"',
		'"BonusEarningPad"',
		'"BonusPrompt"',
		'"FirstPrivateIsland"',
		'"PlayableStarterClient"',
		'"RuneCircle"',
		'"GlowRing"',
		'"CoreGlow"',
		'"RuneCircleSign"',
		'"RuneCircleUI"',
	}
do
	expectEqual(
		string.find(playableProject, authoredWorldObject, 1, true) ~= nil,
		true,
		`playable project pre-authors {authoredWorldObject}`
	)
end
local firstPrivateIsland = fs.readFile("src/world/FirstPrivateIslandGridDemo.model.json")
for _, authoredGridObject in
	{
		'"Name": "GamePlatform"',
		'"Name": "PlatformBase"',
		'"Name": "PlatformOrigin"',
		'"Name": "GridOverlay"',
		'"Name": "Cells"',
		'"Name": "Cell_01_01"',
		'"Name": "Cell_32_27"',
		'"Name": "CellMap"',
		'"Name": "Row_01"',
		'"Name": "Row_27"',
		'"Value": "................................"',
		'"Name": "CellSize"',
		'"Name": "Columns"',
		'"Name": "Rows"',
		'"Name": "PlatformEnabled"',
		'"Name": "GridVisible"',
		'"Name": "PathTiles"',
		'"Name": "PathPoints"',
		'"Name": "GridNpc"',
	}
do
	expectEqual(
		string.find(firstPrivateIsland, authoredGridObject, 1, true) ~= nil,
		true,
		`first private island pre-authors {authoredGridObject}`
	)
end
expectEqual(
	string.find(firstPrivateIsland, '"Name": "VisibilityMarker"', 1, true),
	nil,
	"first private island no longer includes the temporary visibility marker"
)
local firstPrivateIslandModel = serde.decode("json", firstPrivateIsland)
local function namedChild(parent: { Children: { any } }, name: string): any?
	for _, child in parent.Children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
local gamePlatformModel = namedChild(firstPrivateIslandModel, "GamePlatform")
expectEqual(gamePlatformModel ~= nil, true, "first private island has a game platform model")
local cellMapModel = namedChild(gamePlatformModel, "CellMap")
expectEqual(cellMapModel ~= nil, true, "first private island keeps an authored cell map folder")
expectEqual(#cellMapModel.Children, 27, "empty stage template keeps 27 authored map rows")
for _, rowValue in cellMapModel.Children do
	expectEqual(
		rowValue.Properties.Value,
		"................................",
		`empty stage template row {rowValue.Name} starts fully buildable`
	)
end
expectEqual(
	string.find(firstPrivateIsland, '"Name": "PathCurve_', 1, true),
	nil,
	"empty stage template does not pre-bake route path tiles"
)
expectEqual(
	string.find(firstPrivateIsland, '"Name": "Control_', 1, true),
	nil,
	"empty stage template does not pre-bake spline control handles"
)
expectEqual(
	namedChild(gamePlatformModel, "PathPoints") ~= nil,
	true,
	"spline path controls move with GamePlatform"
)
expectEqual(
	namedChild(gamePlatformModel, "PathTiles") ~= nil,
	true,
	"spline path visuals move with GamePlatform"
)
expectEqual(
	#namedChild(gamePlatformModel, "PathPoints").Children,
	0,
	"empty template starts with no spline handles"
)
expectEqual(
	#namedChild(gamePlatformModel, "PathTiles").Children,
	0,
	"empty template starts with no route visuals"
)
expectEqual(
	namedChild(firstPrivateIslandModel, "PathPoints"),
	nil,
	"spline controls are not orphaned at island root"
)
expectEqual(
	namedChild(firstPrivateIslandModel, "PathTiles"),
	nil,
	"spline visuals are not orphaned at island root"
)
local gridPatchProject = fs.readFile("patches/rng-defender-grid-demo.project.json")
for _, patchObject in
	{
		'"Template"',
		'"Shared"',
		'"TemplateServer"',
		'"GridNpcDemo"',
		'"RuneCircle"',
		'"RuneCircleSign"',
		'"RuneCircleUI"',
		'"RuneCircleClient"',
		'"FirstPrivateIsland"',
		'"servePlaceIds": [128136881672145]',
		'"$path": "rng-defender/DesignerConfig.luau"',
		'"TowerDefenseCatalog"',
		'"TowerDefenseLogic"',
	}
do
	expectEqual(
		string.find(gridPatchProject, patchObject, 1, true) ~= nil,
		true,
		`RNG Defender grid patch includes {patchObject}`
	)
end
local rngPatchDesignerConfig = fs.readFile("patches/rng-defender/DesignerConfig.luau")
for _, patchConfigObject in
	{
		'experienceMode = "playable"',
		'dataNamespace = "rngdefender"',
		"placeId = 128136881672145",
		"startingAmount = 100_000_000_000",
		"towerDefense = true",
	}
do
	expectEqual(
		string.find(rngPatchDesignerConfig, patchConfigObject, 1, true) ~= nil,
		true,
		`RNG Defender patch config includes {patchConfigObject}`
	)
end
local runeCircleWorld = fs.readFile("src/world/RuneCircle.model.json")
for _, runeCircleObject in
	{
		'"Name": "OuterAura"',
		'"Name": "OuterGlass"',
		'"Name": "Platform"',
		'"Name": "GlowRing"',
		'"Name": "MiddleGlow"',
		'"Name": "InnerWell"',
		'"Name": "CoreGlow"',
		'"Name": "RuneLight"',
		'"Name": "RuneSigilPlate"',
		'"Name": "ForestMotes"',
		'"Name": "RuneMist"',
		'"Name": "RootBand1"',
		'"Name": "LeafRune1"',
		'"Name": "MossStone1"',
		'"Name": "RuneBlade8"',
		'"Name": "AnchorCrystal6"',
		'"Name": "Shard1"',
		'"Name": "Shard2"',
		'"Name": "Shard3"',
		"FOREST RUNES",
		"rbxassetid://125907024425133",
	}
do
	expectEqual(
		string.find(runeCircleWorld, runeCircleObject, 1, true) ~= nil,
		true,
		`rune test altar pre-authors {runeCircleObject}`
	)
end
for _, removedPatchObject in
	{
		'"GridPlatformEditorRemote"',
		'"GridPlatformEditor"',
		'"GridPlatformEditorClient"',
		'"GridPlatformEditorService"',
		'"GridForgeEditor"',
		'"GridForgePanel"',
		'"StagewrightEditor"',
		'"StagewrightPanel"',
		'"StarterPack"',
	}
do
	expectEqual(
		string.find(gridPatchProject, removedPatchObject, 1, true),
		nil,
		`RNG Defender grid patch keeps edit-only plugin object out of Rojo patch: {removedPatchObject}`
	)
end
local gridPluginProject = fs.readFile("plugins/grid-platform-editor.project.json")
local gridPluginSource = fs.readFile("src/plugins/GridPlatformEditPlugin.server.luau")
for _, pluginObject in
	{
		"StagewrightPlugin",
		"GridPlatformEditPlugin.server.luau",
		"plugin:CreateToolbar",
		"CreateDockWidgetPluginGuiAsync",
		"DockWidgetPluginGuiInfo",
		"StagewrightPanel",
		"MaterialPicker",
		"TemplateDrawer",
		"StageSelector",
		"StageProfile_{profile.id}",
		"Blank Template",
		"Empty map and route",
		"Stage 1",
		"Export Layout",
		"Undo sync on",
		"CanvasGuide_",
		"Stagewright",
		"rbxasset://textures/StudioSharedUI/grid@2x.png",
		"plugin:GetMouse",
		"TryBeginRecording",
		"FinishRecording",
		"ToolHeader",
		"StatusDock",
		"ModeHint",
		"TargetInfo",
		"CommandTabs",
		"tabSections",
		"applyTabContent",
		"CanvasPosition",
		"StageProfiles",
		"CanvasGrid",
		"CanvasHover",
		"CanvasRouteLayer",
		"CanvasRouteSegment_",
		"CanvasRouteDot_",
		"CanvasFirst",
		"handleCanvasCellPaintStart",
		"Paint canvas cells",
		"Move canvas spline point",
		"Clear spline route",
		"Reset empty stage template",
		"Release to rebuild",
		"TextButton",
		"InputEnded",
		"InputChanged",
		"InspectorPanel",
		"LayerTree",
		"Stage profile selected",
		"ButtonStroke",
		"ModeLegend",
		"Calibrate Grid",
		"mousePlatformHit",
		"syncGridTemplate",
		"gridFootprint",
		"GridOverlay",
		"CellMap",
		"PlatformBase",
		"Select Platform",
		"Reset Flat",
		"Snap to Selection",
		"Spline Path",
		"Portal",
		"Goal",
		"Auto Place",
		"CellCode",
		"P = portal spawn",
		"GridHoverPreview",
		"HoverStroke",
		"mouseGridCell",
		"hoverColumn",
		"paintHoveredCell",
		"mouse.Move",
		"Button1Up",
		"dragPainting",
		"Select Points",
		"Rebuild Curve",
		"Add Point",
		"Delete Selected",
		"Snap Points",
		"Clear Route",
		"Export Spline",
		"createSplineControl",
		"rebuildSplineFromControls",
		"worldFromCanvasScale",
		"PATH_GRID_RADIUS",
		"PathCurve",
		"ControlPending",
		"platform.PrimaryPart",
		"island.PrimaryPart",
		"WorldPivot",
	}
do
	expectEqual(
		string.find(gridPluginProject .. gridPluginSource, pluginObject, 1, true) ~= nil,
		true,
		`edit-mode grid plugin includes {pluginObject}`
	)
end
for _, removedPluginObject in { "BoxHandleAdornment", "paintCellAt" } do
	expectEqual(
		string.find(gridPluginSource, removedPluginObject, 1, true),
		nil,
		`edit-mode grid plugin no longer uses separate {removedPluginObject} targeting`
	)
end
local gridNpcBinder = fs.readFile("src/starter/GridNpcDemo.server.luau")
for _, splineMarker in
	{
		"catmullRomPosition",
		"catmullRomTangent",
		"buildSplinePath",
		"sampleSplinePath",
		"SPLINE_SAMPLES_PER_SEGMENT",
		"PLATFORM_NAME",
	}
do
	expectEqual(
		string.find(gridNpcBinder, splineMarker, 1, true) ~= nil,
		true,
		`grid NPC movement uses spline marker {splineMarker}`
	)
end
for _, oldPathMarker in { "nextPathIndex", "segmentDuration", "startPoint.Position:Lerp" } do
	expectEqual(
		string.find(gridNpcBinder, oldPathMarker, 1, true),
		nil,
		`grid NPC movement no longer uses boxy path marker {oldPathMarker}`
	)
end
for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
	expectEqual(
		string.find(gridNpcBinder, forbiddenConstructor, 1, true),
		nil,
		`grid NPC binder does not use {forbiddenConstructor}`
	)
end
expectEqual(
	string.find(compactConnectedUi, '"AnchorPoint":[0.5,1]', 1, true) ~= nil,
	true,
	"connected UI uses a compact bottom navigation dock"
)
expectEqual(
	string.find(compactConnectedUi, '"Text":"TOP"', 1, true),
	nil,
	"secondary actions are not crowded into the main navigation"
)

local screenCopy = fs.readFile("src/client/UI/Screens.luau")
for _, authoredObject in
	{
		'"Name":"InventoryScreen"',
		'"Name":"StoreScreen"',
		'"Name":"RewardsScreen"',
		'"Name":"ProfileScreen"',
		'"Name":"SettingsScreen"',
		'"Name":"ItemSlot12"',
		'"Name":"StoreSlot08"',
		'"Name":"Day7"',
		'"Name":"LeaderRow10"',
		'"Name":"ListRow50"',
	}
do
	expectEqual(
		string.find(compactConnectedUi, authoredObject, 1, true) ~= nil,
		true,
		`connected UI pre-authors {authoredObject}`
	)
end
for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
	expectEqual(
		string.find(screenCopy, forbiddenConstructor, 1, true),
		nil,
		`screen binder does not use {forbiddenConstructor}`
	)
end
for _, developerFacingCopy in { "Project defaults", "Verification is scaffolded", "Discord" } do
	expectEqual(
		string.find(screenCopy, developerFacingCopy, 1, true),
		nil,
		`player UI hides developer wording: {developerFacingCopy}`
	)
end

local audioConfig = fs.readFile("src/shared/TemplateConfig.luau")
for _, audioId in { "12221967", "12222054", "12222253", "12222170", "12222200", "12221976", "12222076" } do
	expectEqual(
		string.find(audioConfig, audioId, 1, true) ~= nil,
		true,
		`audio config includes selected public sound {audioId}`
	)
end

local audioController = fs.readFile("src/client/Controllers/AudioController.luau")
for _, modernAudioObject in
	{ 'Instance.new("AudioPlayer")', 'Instance.new("AudioDeviceOutput")', 'Instance.new("Wire")' }
do
	expectEqual(
		string.find(audioController, modernAudioObject, 1, true) ~= nil,
		true,
		`audio controller uses {modernAudioObject}`
	)
end
for _, legacyAudioObject in { 'Instance.new("Sound")', 'Instance.new("SoundGroup")' } do
	expectEqual(
		string.find(audioController, legacyAudioObject, 1, true),
		nil,
		`audio controller avoids discouraged {legacyAudioObject}`
	)
end
expectEqual(
	string.find(audioController, "player.Asset = ", 1, true) ~= nil,
	true,
	"audio controller assigns the public, documented AudioPlayer.Asset property"
)
expectEqual(
	string.find(audioController, "AudioContent", 1, true),
	nil,
	"audio controller avoids the Hidden AudioPlayer.AudioContent property"
)

local initClient = fs.readFile("src/client/init.client.luau")
for _, silentBackgroundCall in { 'query("InitialState", {}, "")', 'request("AfkRollover", {}, "")' } do
	expectEqual(
		string.find(initClient, silentBackgroundCall, 1, true) ~= nil,
		true,
		`background polling and AFK rollover stay silent: {silentBackgroundCall}`
	)
end

local responsiveController = fs.readFile("src/client/Controllers/ResponsiveController.luau")
for _, requiredMarker in
	{
		"clampNavigation",
		"clampModalsAgainstHud",
		"findSizeConstraint",
		"collectModalRoots",
		"originalMaxSize",
		"updateHudVisibility",
		"modalNeedsHudHidden",
		"safeWidthRaw",
	}
do
	expectEqual(
		string.find(responsiveController, requiredMarker, 1, true) ~= nil,
		true,
		`responsive controller clamps overflow/overlap on short viewports: {requiredMarker}`
	)
end

local figmaBridge = fs.readFile("figma/roblox-ui-bridge/code.js")
expectEqual(
	string.find(figmaBridge, "if (!isText)", 1, true),
	nil,
	"Figma bridge does not treat TextButton as a leaf and discard authored icon children"
)
expectEqual(
	string.find(figmaBridge, "for (const child of namedChildren(object))", 1, true) ~= nil,
	true,
	"Figma bridge recursively imports named children for every supported GUI class"
)
expectEqual(
	string.find(figmaBridge, 'entry.cornerRadius = typeof node.cornerRadius === "number"', 1, true) ~= nil,
	true,
	"Figma bridge exports corner styling for TextButtons as well as non-text controls"
)
expectEqual(
	string.find(figmaBridge, 'String(className).startsWith("Image") ? null : solidPaint(node)', 1, true)
		~= nil,
	true,
	"Figma bridge does not export synthetic image-placeholder fills"
)

local figmaPatchApplier = fs.readFile("scripts/figma-ui-bridge.mjs")
expectEqual(
	string.find(figmaPatchApplier, '!String(node.ClassName).startsWith("Image")', 1, true) ~= nil,
	true,
	"Figma patch applier rejects image-placeholder fills from older patches"
)

-- StoreScreen's header was 60 tall while its own Body label already
-- reserved 92px (Title + wrapped 2-line Body); found via mechanical
-- rendering at phone width, where the description wraps and visibly
-- spills out of the yellow header. Fixed to 100 tall with ProductsGrid and
-- CanvasSize shifted to match; the licensed ShowcaseCanvas duplicate
-- (ZIndex 192) is intentionally left untouched, same as every other
-- restyle pass in this file.
expectEqual(
	string.find(
		compactConnectedUi,
		'"LayoutOrder":1,"Size":{"UDim2":[[1,0],[0,100]]},"Visible":true,"ZIndex":42,',
		1,
		true
	) ~= nil,
	true,
	"real StoreHeader grows to fit its own wrapped 2-line Body label"
)
expectEqual(
	string.find(
		compactConnectedUi,
		'"Position":{"UDim2":[[0,0],[0,112]]},"Size":{"UDim2":[[1,0],[0,1024]]},"ZIndex":41',
		1,
		true
	) ~= nil,
	true,
	"ProductsGrid shifts down to match the taller StoreHeader"
)

-- Tower defense: unit collection, loadout ranking, grid cell roles, and wave scaling.
expectEqual(TowerDefenseLogic.isBuildableCell("."), true, "normal grid cells are buildable for units")
expectEqual(TowerDefenseLogic.isBuildableCell("A"), true, "auto-place grid cells are buildable for units")
expectEqual(
	TowerDefenseLogic.isPortalCell("P") and TowerDefenseLogic.isBlockedCell("P"),
	true,
	"portal grid cells spawn enemies and block unit placement"
)
expectEqual(
	TowerDefenseLogic.isGoalCell("G") and TowerDefenseLogic.isBlockedCell("G"),
	true,
	"goal grid cells end enemy paths and block unit placement"
)
expectEqual(
	TowerDefenseLogic.pickWeightedUnitIndex(TowerDefenseCatalog.units, 0) >= 1,
	true,
	"unit rolls pick a catalog entry at the lower bound"
)
expectEqual(
	TowerDefenseLogic.pickWeightedUnitIndex(TowerDefenseCatalog.units, 0.9999) <= #TowerDefenseCatalog.units,
	true,
	"unit rolls pick a catalog entry at the upper bound"
)
local bestTowerLoadout = TowerDefenseLogic.bestLoadout({
	forest_archer = { count = 1 },
	mushroom_bomber = { count = 1 },
	ancient_treant = { count = 1 },
}, TowerDefenseCatalog.units, 2)
expectEqual(bestTowerLoadout[1], "ancient_treant", "equip best favors the strongest owned unit")
expectEqual(#bestTowerLoadout, 2, "equip best respects loadout slot cap")
expectEqual(TowerDefenseLogic.waveScale(1), 1, "first tower defense wave uses base scale")
expectEqual(TowerDefenseLogic.waveScale(5) > 1, true, "later tower defense waves scale up")

-- Rune altar: weighted rolls, pity, flat configured cost, and permanent multiplier.
expectEqual(
	RuneLogic.weightTotal(RuneCatalog.rarities),
	10000,
	"rune rarity weights sum to exactly 10000 so disclosed odds total 100%"
)
local oddsSum = 0
for _, rarity in RuneCatalog.rarities do
	oddsSum += RuneLogic.oddsPercent(rarity)
	expectEqual(
		#RuneCatalog.runesForRarity(rarity.id) > 0,
		true,
		`rarity {rarity.id} has at least one authored rune`
	)
end
expectEqual(math.abs(oddsSum - 100) < 1e-9, true, "displayed rune odds add up to exactly 100 percent")
for _, rune in RuneCatalog.runes do
	expectEqual(RuneCatalog.rarity(rune.rarityId) ~= nil, true, `rune {rune.id} maps to a real rarity`)
	expectEqual(rune.bonusPercent > 0, true, `rune {rune.id} grants a positive generation bonus`)
end

local commonIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 0, 40, 4)
expectEqual(commonIndex, 1, "lowest roll lands on the most common rarity")
local boundaryIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0.54, 0, 40, 4)
expectEqual(boundaryIndex, 2, "exact tier boundary promotes to the next rarity")
local mythicIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0.9999, 0, 40, 4)
expectEqual(mythicIndex, #RuneCatalog.rarities, "highest roll lands on the rarest rarity")

local pityIndex, pityTriggered = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 39, 40, 4)
expectEqual(pityTriggered, true, "pity triggers on the guaranteed roll")
expectEqual(pityIndex >= 4, true, "pity roll cannot drop below the guaranteed rarity")
local noPityIndex, noPityTriggered = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 38, 40, 4)
expectEqual(noPityTriggered, false, "pity stays quiet before the threshold")
expectEqual(noPityIndex, 1, "regular rolls still hit common before the pity threshold")

expectEqual(RuneLogic.pickRuneIndex(2, 0), 1, "rune pick lower bound")
expectEqual(RuneLogic.pickRuneIndex(2, 0.99), 2, "rune pick upper bound")
expectEqual(RuneLogic.pickRuneIndex(0, 0.5), 0, "empty rune pools pick nothing")

expectEqual(RuneLogic.rollCost(75, 1.12, 0, 250000), 75, "first roll costs the base price")
expectEqual(RuneLogic.rollCost(75, 1, 500, 75), 75, "configured rune cost stays flat")
expectEqual(RuneLogic.rollCost(75, 1.12, 2, 250000), math.floor(75 * 1.12 * 1.12), "roll cost escalates")
expectEqual(RuneLogic.rollCost(75, 1.12, 500, 250000), 250000, "roll cost clamps at the configured cap")

local ownedSample = {
	ember_rune = { count = 2 },
	celestial_rune = { count = 1 },
	forgotten_rune = { count = 5 },
	corrupt_rune = { count = 0 / 0 },
}
expectEqual(
	RuneLogic.totalBonusPercent(ownedSample, RuneCatalog),
	104,
	"generation bonus sums owned copies and skips unknown or corrupt entries"
)
expectEqual(
	math.floor(RuneLogic.multiplier({ owned = ownedSample }, RuneCatalog) * 100 + 0.5),
	204,
	"rune multiplier converts the summed bonus into an earnings factor"
)
expectEqual(RuneLogic.multiplier(nil, RuneCatalog), 1, "missing rune state keeps a neutral multiplier")
expectEqual(RuneLogic.countOwned(ownedSample), 8, "owned counter keeps unknown saved runes")
expectEqual(
	RuneLogic.countOwnedForRarity(ownedSample, "common", RuneCatalog),
	2,
	"per-rarity counter follows the catalog"
)

local runeMigrated = MigrationCore.migrate({ schemaVersion = 4, coins = 5 }, {
	schemaVersion = 5,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0 },
}, 5)
expectEqual(type(runeMigrated.runes), "table", "older profiles gain the rune state on migration")
expectEqual(runeMigrated.runes.totalRolls, 0, "migrated rune state starts unrolled")
local runePreserved = MigrationCore.migrate({
	schemaVersion = 5,
	coins = 5,
	runes = { owned = { mystery_rune = { count = 3 } }, totalRolls = 7, rollsSincePity = 2 },
}, {
	schemaVersion = 5,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0 },
}, 5)
expectEqual(
	runePreserved.runes.owned.mystery_rune.count,
	3,
	"unknown saved runes survive migration untouched"
)
expectEqual(runePreserved.runes.totalRolls, 7, "rune roll history survives migration")

local runeServiceSource = fs.readFile("src/server/Services/RuneService.luau")
expectEqual(
	string.find(runeServiceSource, "GetPolicyInfoForPlayerAsync", 1, true) ~= nil,
	true,
	"rune rolls check the paid-random-items policy"
)
expectEqual(
	string.find(runeServiceSource, "ArePaidRandomItemsRestricted", 1, true) ~= nil,
	true,
	"rune rolls respect ArePaidRandomItemsRestricted"
)
expectEqual(
	string.find(runeServiceSource, "OnServerEvent", 1, true),
	nil,
	"rune rolls are server-initiated; no client remote can trigger them"
)
local runeConfigSource = fs.readFile("src/shared/TemplateConfig.luau")
expectEqual(
	string.find(runeConfigSource, "pityMinimumRarity", 1, true) ~= nil,
	true,
	"rune pity guarantee is configurable"
)
expectEqual(
	string.find(runeConfigSource, "mockStartingCoins = 100_000_000_000", 1, true) ~= nil,
	true,
	"Studio mock testing starts with 100B coins"
)
expectEqual(
	string.find(runeConfigSource, '"costGrowth", 1', 1, true) ~= nil,
	true,
	"configured rune price does not grow after each roll"
)
expectEqual(
	string.find(runeConfigSource, '"maxCost", 75', 1, true) ~= nil,
	true,
	"configured rune price cap matches the flat base price"
)
local designerConfigSource = fs.readFile("src/shared/DesignerConfig.luau")
expectEqual(
	string.find(designerConfigSource, "startingAmount = 100_000_000_000", 1, true) ~= nil,
	true,
	"template test currency starts at 100B coins"
)

local runeUi = fs.readFile("src/ui/RuneCircleUI.model.json")
for _, authoredRuneObject in
	{
		'"Name": "RevealCard"',
		'"Name": "RarityBanner"',
		'"Name": "GlassArtwork"',
		'"Name": "RuneHalo"',
		'"Name": "NewTag"',
		'"Name": "PityTag"',
		'"Name": "OddsPanel"',
		'"Name": "OddsArtwork"',
		'"Name": "RarityRow6"',
		'"Name": "TotalChip"',
		'"Name": "RestrictedNote"',
		'"Name": "ModePanel"',
		'"Name": "ModeButton4"',
		'"Name": "MomentumMeter"',
		'"Name": "ModeHint"',
		'"Name": "MilestoneLine"',
		"rbxassetid://125907024425133",
		"rbxassetid://111977708425543",
	}
do
	expectEqual(
		string.find(runeUi, authoredRuneObject, 1, true) ~= nil,
		true,
		`rune UI pre-authors {authoredRuneObject}`
	)
end
local runeSign = fs.readFile("src/ui/RuneCircleSign.model.json")
for _, authoredSignObject in
	{
		'"Name": "CostLine"',
		'"Name": "StatusLine"',
		'"Name": "AutoChip"',
		'"Name": "RuneBadge"',
		'"Name": "CoinWatermark"',
		"FOREST RUNES",
		"rbxassetid://105300168575798",
	}
do
	expectEqual(
		string.find(runeSign, authoredSignObject, 1, true) ~= nil,
		true,
		`rune sign pre-authors {authoredSignObject}`
	)
end

-- Rune channel modes: momentum tiers, luck-adjusted odds, copy milestones,
-- and the strongest-temporary-boost rule for surge channeling.
local sampleTiers = {
	{ atSeconds = 10, value = 1.25 },
	{ atSeconds = 30, value = 1.75 },
	{ atSeconds = 60, value = 2.5 },
}
local tierIndexBelow, tierValueBelow = RuneLogic.momentumTier(sampleTiers, 9.9)
expectEqual(tierIndexBelow, 0, "momentum below the first threshold reaches no tier")
expectEqual(tierValueBelow, 1, "momentum below the first threshold keeps a neutral value")
local tierIndexExact, tierValueExact = RuneLogic.momentumTier(sampleTiers, 10)
expectEqual(tierIndexExact, 1, "momentum reaches a tier exactly at its threshold")
expectEqual(tierValueExact, 1.25, "tier value follows the reached tier")
local tierIndexTop, tierValueTop = RuneLogic.momentumTier(sampleTiers, 500)
expectEqual(tierIndexTop, 3, "long channels reach the top tier")
expectEqual(tierValueTop, 2.5, "top tier keeps the configured value")
local tierIndexNaN, tierValueNaN = RuneLogic.momentumTier(sampleTiers, 0 / 0)
expectEqual(tierIndexNaN, 0, "corrupt momentum reaches no tier")
expectEqual(tierValueNaN, 1, "corrupt momentum keeps a neutral value")
local tierIndexEmpty = RuneLogic.momentumTier({}, 100)
expectEqual(tierIndexEmpty, 0, "empty tier lists never promote")
expectEqual(RuneLogic.nextTierAt(sampleTiers, 5), 10, "next tier threshold is reported for meters")
expectEqual(RuneLogic.nextTierAt(sampleTiers, 30), 60, "reached tiers advance the next threshold")
expectEqual(RuneLogic.nextTierAt(sampleTiers, 60), nil, "the top tier has no next threshold")

for _, luckFactor in { 1.25, 1.75, 2.5 } do
	local adjusted = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, luckFactor, 500)
	expectEqual(
		RuneLogic.weightTotal(adjusted),
		10000,
		`luck factor {luckFactor} keeps rarity weights summing to exactly 10000`
	)
	local adjustedOdds = 0
	for index, rarity in adjusted do
		adjustedOdds += RuneLogic.oddsPercent(rarity)
		expectEqual(rarity.id, RuneCatalog.rarities[index].id, "luck keeps rarity order and ids")
		if index >= 2 then
			expectEqual(
				rarity.weight >= RuneCatalog.rarities[index].weight,
				true,
				`luck never lowers the {rarity.id} weight`
			)
		end
	end
	expectEqual(
		math.abs(adjustedOdds - 100) < 1e-9,
		true,
		`luck factor {luckFactor} still discloses odds totaling exactly 100 percent`
	)
end
local neutralLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 1, 500)
expectEqual(neutralLuck[1].weight, RuneCatalog.rarities[1].weight, "luck factor 1 leaves weights untouched")
local weakLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 0.5, 500)
expectEqual(weakLuck[2].weight, RuneCatalog.rarities[2].weight, "luck below 1 never nerfs odds")
local nanLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 0 / 0, 500)
expectEqual(
	nanLuck[#nanLuck].weight,
	RuneCatalog.rarities[#RuneCatalog.rarities].weight,
	"corrupt luck factors leave weights untouched"
)
local extremeLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 1000, 500)
expectEqual(RuneLogic.weightTotal(extremeLuck), 10000, "extreme luck keeps the weight invariant")
expectEqual(extremeLuck[1].weight >= 500, true, "extreme luck respects the common weight floor")
local luckyCommon = RuneLogic.pickRarityIndex(extremeLuck, 0, 0, 40, 4)
expectEqual(luckyCommon, 1, "the lowest roll still lands on the first rarity under luck")
local luckyTop = RuneLogic.pickRarityIndex(extremeLuck, 0.9999, 0, 40, 4)
expectEqual(luckyTop, #extremeLuck, "the highest roll still lands on the rarest rarity under luck")
local luckyPity, luckyPityTriggered = RuneLogic.pickRarityIndex(extremeLuck, 0, 39, 40, 4)
expectEqual(luckyPityTriggered, true, "pity still triggers over luck-adjusted odds")
expectEqual(luckyPity >= 4, true, "pity still promotes over luck-adjusted odds")

local sampleMilestones = {
	{ copies = 5, multiplier = 1.25 },
	{ copies = 10, multiplier = 1.5 },
	{ copies = 25, multiplier = 2 },
}
expectEqual(
	RuneLogic.milestoneMultiplier(sampleMilestones, 4),
	1,
	"below the first milestone nothing changes"
)
expectEqual(
	RuneLogic.milestoneMultiplier(sampleMilestones, 5),
	1.25,
	"reaching a milestone applies its multiplier"
)
expectEqual(RuneLogic.milestoneMultiplier(sampleMilestones, 26), 2, "the highest reached milestone wins")
expectEqual(RuneLogic.milestoneMultiplier(nil, 5), 1, "missing milestones stay neutral")
expectEqual(
	RuneLogic.milestoneMultiplier({ { copies = 2, multiplier = 0 / 0 }, { copies = 3, multiplier = 0.1 } }, 5),
	1,
	"corrupt milestone entries are ignored"
)
local upcomingMilestone = RuneLogic.nextMilestone(sampleMilestones, 5)
expectEqual(
	if upcomingMilestone ~= nil then upcomingMilestone.copies else 0,
	10,
	"the next milestone reports the closest target"
)
expectEqual(RuneLogic.nextMilestone(sampleMilestones, 25), nil, "maxed milestones report no next target")
local milestoneOwned = {
	ember_rune = { count = 5 },
	celestial_rune = { count = 1 },
	forgotten_rune = { count = 25 },
	corrupt_rune = { count = 0 / 0 },
}
expectEqual(
	RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog),
	110,
	"without milestones duplicates still stack linearly"
)
expectEqual(
	RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog, sampleMilestones),
	112.5,
	"copy milestones scale known runes while unknown and corrupt entries still contribute nothing"
)
expectEqual(
	RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog, sampleMilestones, 50),
	50,
	"an explicit bonus cap clamps the milestone-scaled total"
)

local sampleModes = {
	{
		id = "luck",
		name = "Lucky",
		kind = "luck",
		unlock = { kind = "always", value = 0 },
		tiers = sampleTiers,
	},
	{
		id = "surge",
		name = "Surge",
		kind = "surge",
		unlock = { kind = "totalRolls", value = 25 },
		tiers = sampleTiers,
	},
	{
		id = "stage",
		name = "Stage",
		kind = "surge",
		unlock = { kind = "provider", value = 0 },
		tiers = sampleTiers,
	},
}
expectEqual(RuneLogic.resolveModeId("surge", sampleModes, "luck"), "surge", "a saved known mode is respected")
expectEqual(
	RuneLogic.resolveModeId("ghost_mode", sampleModes, "luck"),
	"luck",
	"an unknown saved mode resolves to the default without being overwritten"
)
expectEqual(
	RuneLogic.isModeUnlocked(sampleModes[1], { totalRolls = 0, runesOwned = 0 }),
	true,
	"always modes unlock immediately"
)
expectEqual(
	RuneLogic.isModeUnlocked(sampleModes[2], { totalRolls = 24, runesOwned = 0 }),
	false,
	"threshold modes stay locked below the requirement"
)
expectEqual(
	RuneLogic.isModeUnlocked(sampleModes[2], { totalRolls = 25, runesOwned = 0 }),
	true,
	"threshold modes unlock at the requirement"
)
expectEqual(
	RuneLogic.isModeUnlocked(sampleModes[3], { totalRolls = 100, runesOwned = 100 }),
	false,
	"provider modes fail closed without an answer"
)
expectEqual(
	RuneLogic.isModeUnlocked(sampleModes[3], { totalRolls = 0, runesOwned = 0 }, true),
	true,
	"provider modes unlock only on an explicit yes"
)
expectEqual(
	RuneLogic.isModeUnlocked({ id = "x", unlock = { kind = "mystery" } }, { totalRolls = 0, runesOwned = 0 }),
	false,
	"unknown unlock kinds fail closed"
)

local fallbackModes = {
	{
		id = "luck",
		name = "Lucky",
		kind = "luck",
		unlock = { kind = "always", value = 0 },
		tiers = { { atSeconds = 10, value = 1.25 } },
	},
}
local normalizedModes = RuneModeConfig.normalize({
	{ id = "luck", name = "Custom Luck", kind = "luck", tiers = { { atSeconds = 5, value = 1.5 } } },
	{
		id = "surge",
		name = "Surge",
		kind = "surge",
		unlock = { kind = "totalRolls", value = 10 },
		tiers = { { atSeconds = 5, value = 1.2 }, { atSeconds = 15, value = 1.4 } },
	},
}, fallbackModes)
expectEqual(#normalizedModes, 2, "valid channel mode overrides pass through")
expectEqual(normalizedModes[1].unlock.kind, "always", "a missing unlock defaults to always")
local duplicateModes = RuneModeConfig.normalize({
	{ id = "luck", kind = "luck", tiers = { { atSeconds = 5, value = 1.5 } } },
	{ id = "luck", kind = "surge", tiers = { { atSeconds = 5, value = 1.5 } } },
}, fallbackModes)
expectEqual(#duplicateModes, 1, "duplicate mode ids fall back to the authored defaults")
expectEqual(duplicateModes[1].name, "Lucky", "the wholesale fallback keeps the authored mode")
local badKindModes = RuneModeConfig.normalize(
	{ { id = "warp", kind = "teleport", tiers = { { atSeconds = 5, value = 1.5 } } } },
	fallbackModes
)
expectEqual(badKindModes[1].id, "luck", "unknown mode kinds fall back wholesale")
local descendingModes = RuneModeConfig.normalize({
	{
		id = "luck",
		kind = "luck",
		tiers = { { atSeconds = 30, value = 1.5 }, { atSeconds = 10, value = 2 } },
	},
}, fallbackModes)
expectEqual(descendingModes[1].tiers[1].atSeconds, 10, "descending tier thresholds fall back wholesale")
local weakTierModes = RuneModeConfig.normalize(
	{ { id = "luck", kind = "luck", tiers = { { atSeconds = 10, value = 0.5 } } } },
	fallbackModes
)
expectEqual(weakTierModes[1].tiers[1].value, 1.25, "tier values below 1 fall back wholesale")
local crowdedModes = {}
for index = 1, 6 do
	table.insert(crowdedModes, {
		id = `mode{index}`,
		kind = "luck",
		tiers = { { atSeconds = 10, value = 1.25 } },
	})
end
expectEqual(
	#RuneModeConfig.normalize(crowdedModes, fallbackModes),
	4,
	"channel modes cap at the four authored buttons"
)
expectEqual(
	#RuneModeConfig.normalizeMilestones(
		{ { copies = 5, multiplier = 1.25 }, { copies = 10, multiplier = 1.5 } },
		{}
	),
	2,
	"valid milestone overrides pass through"
)
local weakeningMilestones = RuneModeConfig.normalizeMilestones(
	{ { copies = 5, multiplier = 1.5 }, { copies = 10, multiplier = 1.2 } },
	{ { copies = 3, multiplier = 1.1 } }
)
expectEqual(weakeningMilestones[1].copies, 3, "weakening milestone curves fall back wholesale")
expectEqual(
	#RuneModeConfig.normalizeMilestones({}, { { copies = 3, multiplier = 1.1 } }),
	0,
	"an explicit empty list disables milestones"
)

local potionBoosts = { { id = "p", expiresAt = 1000, multiplier = 2 } }
expectEqual(
	Calculations.temporaryMultiplier(potionBoosts, 0, 1.2),
	2,
	"the strongest potion beats a weaker channel surge; they never stack"
)
expectEqual(
	Calculations.temporaryMultiplier(potionBoosts, 0, 3),
	3,
	"a stronger channel surge beats the potion; they never stack"
)
expectEqual(
	Calculations.temporaryMultiplier(potionBoosts, 0),
	2,
	"temporary multiplier works without a channel value"
)
expectEqual(
	Calculations.temporaryMultiplier(potionBoosts, 0, 0 / 0),
	2,
	"corrupt channel values stay neutral"
)
expectEqual(Calculations.temporaryMultiplier({}, 0, 0.25), 1, "channel surges below 1 never punish earnings")
expectEqual(
	Calculations.compositeMultiplier(0.5, 0.1, 2, 1.5),
	(1 + 0.5 + 0.1) * 2 * 1.5,
	"composite multiplier composes additive bonuses with temporary and permanent buckets"
)
expectEqual(
	Calculations.permanentMultiplier(0.1, true, 2),
	1.1 * 2,
	"offline multiplier keeps premium and runes"
)
expectEqual(
	Calculations.permanentMultiplier(0.1, false, 2),
	2,
	"offline multiplier drops premium for free players"
)
expectEqual(
	Calculations.earningsMultiplier(3, true, potionBoosts, 0, 0.1, 0.5, 0.1),
	(1 + 0.3 + 0.1) * 2,
	"earnings multiplier still composes social, premium, and the strongest potion"
)

local modeMigrated = MigrationCore.migrate({
	schemaVersion = 6,
	coins = 5,
	runes = { owned = { mystery_rune = { count = 3 } }, totalRolls = 7, rollsSincePity = 2 },
}, {
	schemaVersion = 7,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "luck" },
}, 7)
expectEqual(modeMigrated.runes.selectedMode, "luck", "older profiles gain the default channel mode")
expectEqual(modeMigrated.runes.owned.mystery_rune.count, 3, "unknown saved runes survive the v7 migration")
expectEqual(modeMigrated.runes.totalRolls, 7, "roll history survives the v7 migration")
local modePreserved = MigrationCore.migrate({
	schemaVersion = 7,
	coins = 5,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "surge" },
}, {
	schemaVersion = 7,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "luck" },
}, 7)
expectEqual(modePreserved.runes.selectedMode, "surge", "a saved mode selection survives migration")

expectEqual(
	string.find(runeServiceSource, "luckAdjustedRarities", 1, true) ~= nil,
	true,
	"rune rolls apply luck-adjusted odds server-side"
)
expectEqual(
	string.find(runeServiceSource, "RuneService.setMode", 1, true) ~= nil,
	true,
	"channel mode swaps are validated in RuneService"
)
expectEqual(
	string.find(runeServiceSource, "channelEarningsMultiplier", 1, true) ~= nil,
	true,
	"surge channeling exposes a live multiplier"
)
expectEqual(
	string.find(runeServiceSource, "Config.runes.tickSeconds", 1, true) ~= nil,
	true,
	"rune tick cadence comes from TemplateConfig"
)
expectEqual(
	string.find(runeServiceSource, "TICK_SECONDS", 1, true),
	nil,
	"the hardcoded rune tick constant is gone"
)
local remoteServiceSource = fs.readFile("src/server/Services/RemoteService.luau")
expectEqual(
	string.find(remoteServiceSource, 'SetRuneMode = "runes"', 1, true) ~= nil,
	true,
	"mode swaps are feature-gated behind the runes flag"
)
expectEqual(
	string.find(remoteServiceSource, "temporaryMultiplier", 1, true) ~= nil,
	true,
	"snapshots publish the strongest temporary multiplier"
)
local economyServiceSource = fs.readFile("src/server/Services/EconomyService.luau")
expectEqual(
	string.find(economyServiceSource, "setChannelBoostProvider", 1, true) ~= nil,
	true,
	"economy exposes the channel boost provider hook"
)
expectEqual(
	string.find(economyServiceSource, "compositeMultiplier", 1, true) ~= nil,
	true,
	"economy composes active earnings through Calculations"
)
expectEqual(
	string.find(economyServiceSource, "permanentMultiplier", 1, true) ~= nil,
	true,
	"economy composes offline earnings through Calculations"
)
for _, configMarker in
	{
		"defaultChannelMode",
		"channelModes",
		"copyMilestones",
		"tickSeconds",
		"maxTotalBonusPercent",
		"maxOwnedPerRune",
		"revealSeconds",
		"rareAudioMinimumRarity",
		"minCommonWeight",
	}
do
	expectEqual(
		string.find(runeConfigSource, configMarker, 1, true) ~= nil,
		true,
		`rune channel tunable {configMarker} lives in TemplateConfig`
	)
end
local runeClientSource = fs.readFile("src/starter-client/RuneCircle.client.luau")
expectEqual(
	string.find(runeClientSource, "SetRuneMode", 1, true) ~= nil,
	true,
	"mode buttons send the SetRuneMode intent"
)
expectEqual(
	string.find(runeClientSource, "effectiveWeights", 1, true) ~= nil,
	true,
	"the odds panel renders the server-sent effective odds"
)
local incrementalUi = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
for _, authoredHudObject in { '"Name": "RunesValue"', '"Name": "ChannelValue"' } do
	expectEqual(
		string.find(incrementalUi, authoredHudObject, 1, true) ~= nil,
		true,
		`incremental HUD pre-authors {authoredHudObject}`
	)
end

local towerDefenseServiceSource = fs.readFile("src/server/Services/TowerDefenseService.luau")
for _, towerDefenseMarker in
	{
		"TowerDefenseService.rollUnit",
		"TowerDefenseService.setLoadout",
		"TowerDefenseService.equipBest",
		"TowerDefenseService.placeUnit",
		"TowerDefenseService.autoPlaceBest",
		"TowerDefenseService.startWave",
		"TowerDefenseService.resetMatch",
		"TowerDefenseService.snapshotFor",
		"EconomyService.spendCurrency",
		"TowerDefenseLogic.isBuildableCell",
		"runtimeFolderName",
		"RunService.Heartbeat",
		"Portal, spline path, and goal need a valid route",
		"grid.columns * grid.cellSize",
		"BillboardGui",
		"DebugNameplate",
		"HealthBarFill",
		"setNameplateBar",
		"StudsOffsetWorldSpace",
	}
do
	expectEqual(
		string.find(towerDefenseServiceSource, towerDefenseMarker, 1, true) ~= nil,
		true,
		`tower defense service includes {towerDefenseMarker}`
	)
end
expectEqual(
	string.find(towerDefenseServiceSource, "OnServerEvent", 1, true),
	nil,
	"tower defense service does not listen directly to client remotes"
)
local remoteServiceSource = fs.readFile("src/server/Services/RemoteService.luau")
for _, towerDefenseRemoteMarker in
	{
		"RollUnit",
		"SetTowerLoadout",
		"EquipBestUnits",
		"PlaceUnit",
		"AutoPlaceBestUnits",
		"StartTowerWave",
		"ResetTowerDefense",
		"TowerDefenseService.snapshotFor",
	}
do
	expectEqual(
		string.find(remoteServiceSource, towerDefenseRemoteMarker, 1, true) ~= nil,
		true,
		`remote service exposes validated tower defense action {towerDefenseRemoteMarker}`
	)
end
expectEqual(
	string.find(runeConfigSource, "towerDefense = false", 1, true) ~= nil,
	true,
	"tower defense feature is disabled by default template config"
)
expectEqual(
	string.find(runeConfigSource, "unitRollCost = 75", 1, true) ~= nil
		and string.find(runeConfigSource, "loadoutSlots = 4", 1, true) ~= nil,
	true,
	"tower defense gameplay loop has configured roll cost and loadout slots"
)

print(`{passed} pure Luau assertions passed`)

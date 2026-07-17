--!strict

local Calculations = require("../src/shared/Calculations")
local CurrencyConfig = require("../src/shared/CurrencyConfig")
local RuneCatalog = require("../src/shared/RuneCatalog")
local RuneLogic = require("../src/shared/RuneLogic")
local RuneModeConfig = require("../src/shared/RuneModeConfig")
local TowerDefenseCatalog = require("../src/shared/TowerDefenseCatalog")
local TowerDefenseLogic = require("../src/shared/TowerDefenseLogic")
local StageGraph = require("../src/shared/StageGraph")
local StageHierarchy = require("../src/shared/StageHierarchy")
local StageLanes = require("../src/shared/StageLanes")
local StageLegacy = require("../src/shared/StageLegacy")
local StagePath = require("../src/shared/StagePath")
local StagePlatformLayout = require("../src/shared/StagePlatformLayout")
local StageSchema = require("../src/shared/StageSchema")
local StageStarterProject = require("../src/shared/StageStarterProject")
local StageExport = require("../src/shared/StageExport")
local StageTrace = require("../src/shared/StageTrace")
local PaintBrushes = require("../src/plugins/Stagewright/Paint/Brushes")
local StageSettings = require("../src/plugins/Stagewright/Stage/Settings")
local DataStoreNames = require("../src/shared/DataStoreNames")
local DataStoreKeys = require("../src/shared/DataStoreKeys")
local MigrationCore = require("../src/shared/MigrationCore")
local ReceiptLedger = require("../src/shared/ReceiptLedger")
local SessionLock = require("../src/server/Util/SessionLock")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local passed = 0

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
	passed += 1
end

local function expectCompiles(source: string, label: string)
	local chunk, compileError = luau.load(source)
	expectEqual(chunk ~= nil, true, `{label}: {tostring(compileError)}`)
end

do
	local grid: any = {
		columns = 3,
		rows = 2,
		cells = {},
	}
	local paintedKeys: { [string]: boolean } = {}
	PaintBrushes.applyArea(grid, PaintBrushes.find("build_blocked"), 1, 1, 3, paintedKeys)
	expectEqual(grid.cells["1:1"].buildPolicy, "Blocked", "paint brush mutates the selected cell")
	expectEqual(grid.cells["2:2"].buildPolicy, "Blocked", "paint brush covers its bounded area")
	expectEqual(grid.cells["3:1"], nil, "paint brush clamps at the grid edge")

	PaintBrushes.applyArea(grid, PaintBrushes.find(PaintBrushes.RESET_ID), 1, 1, 3, paintedKeys)
	expectEqual(
		grid.cells["1:1"].buildPolicy,
		"Blocked",
		"painted-key tracking prevents repeated drag mutations"
	)
	PaintBrushes.applyArea(grid, PaintBrushes.find(PaintBrushes.RESET_ID), 1, 1, 1, {})
	expectEqual(grid.cells["1:1"], nil, "reset brush removes an empty authored override")

	grid.cells["3:2"] = { buildPolicy = "Blocked" }
	PaintBrushes.applyArea(grid, PaintBrushes.find("role_AutoPlace"), 3, 2, 1, {})
	expectEqual(grid.cells["3:2"].roles.AutoPlace, true, "role brush toggles the requested role")
	expectEqual(grid.cells["3:2"].buildPolicy, "Allowed", "auto-place role preserves its compatibility rule")
	expectEqual(
		PaintBrushes.find("unknown-brush").id,
		PaintBrushes.RESET_ID,
		"unknown brush IDs fail safely to reset"
	)
end

do
	local update, parseError = StageSettings.parse({
		name = "Forest Pass",
		waveSetId = "wave_forest",
		themeId = "forest",
		columns = "32.9",
		rows = "27.4",
		cellSize = "4",
	})
	expectEqual(parseError, nil, "valid stage settings parse without an error")
	expectEqual(update and update.columns, 32, "stage width floors to a whole cell")
	expectEqual(update and update.rows, 27, "stage height floors to a whole cell")

	local invalidUpdate, invalidError = StageSettings.parse({
		name = "",
		waveSetId = "default",
		themeId = "default",
		columns = "513",
		rows = "27",
		cellSize = "4",
	})
	expectEqual(invalidUpdate, nil, "out-of-range stage settings are rejected")
	expectEqual(invalidError, StageSettings.INVALID_GRID_MESSAGE, "invalid stage settings explain limits")

	local definition: any = {
		name = "Original",
		waveSetId = "old_wave",
		themeId = "old_theme",
		grid = {
			columns = 4,
			rows = 3,
			cellSize = 2,
			cells = {
				["1:1"] = { metadata = { keep = true } },
				["4:3"] = { buildPolicy = "Blocked" },
				malformed = { metadata = { unknown = true } },
			},
		},
	}
	expectEqual(
		StageSettings.countTruncated(definition.grid, 2, 2),
		2,
		"grid shrink reports out-of-bounds and malformed overrides"
	)
	local blankNameUpdate = StageSettings.parse({
		name = "",
		waveSetId = "new_wave",
		themeId = "new_theme",
		columns = "2",
		rows = "2",
		cellSize = "3",
	})
	StageSettings.apply(definition, blankNameUpdate :: any)
	expectEqual(definition.name, "Original", "blank stage name preserves the existing name")
	expectEqual(definition.waveSetId, "new_wave", "stage settings update catalog references")
	expectEqual(definition.grid.cells["1:1"].metadata.keep, true, "grid shrink preserves in-bounds data")
	expectEqual(definition.grid.cells["4:3"], nil, "grid shrink removes out-of-bounds data")
	expectEqual(definition.grid.cells.malformed, nil, "grid shrink removes malformed cell keys")
end

do
	local StagePayload = require("../src/shared/StagePayload")
	local largePayload = string.rep("a", StagePayload.CHUNK_SIZE)
		.. string.rep("b", StagePayload.CHUNK_SIZE)
		.. string.rep("c", 121_372)
	local payloadChunks = StagePayload.split(largePayload)
	expectEqual(#payloadChunks, 3, "large Stagewright payload splits below the StringValue limit")
	expectEqual(#payloadChunks[1], 180_000, "Stagewright payload chunk uses the safe byte limit")
	local payloadManifest = StagePayload.manifest("fnv1a32-deadbeef", #payloadChunks, #largePayload)
	local parsedPayloadManifest = StagePayload.parseManifest(payloadManifest)
	expectEqual(parsedPayloadManifest ~= nil, true, "Stagewright chunk manifest parses")
	expectEqual(
		parsedPayloadManifest and parsedPayloadManifest.chunkCount,
		3,
		"chunk manifest preserves count"
	)
	local joinedPayload, joinedPayloadError = StagePayload.join(payloadChunks, #payloadChunks, #largePayload)
	expectEqual(joinedPayloadError, nil, "complete Stagewright payload joins without an error")
	expectEqual(joinedPayload, largePayload, "chunked Stagewright payload round trips byte-for-byte")
	local missingPayload, missingPayloadError =
		StagePayload.join({ payloadChunks[1] }, #payloadChunks, #largePayload)
	expectEqual(missingPayload, nil, "missing Stagewright chunk is rejected")
	expectEqual(type(missingPayloadError), "string", "missing Stagewright chunk reports a diagnostic")
	local shortPayload, shortPayloadError =
		StagePayload.join(payloadChunks, #payloadChunks, #largePayload - 1)
	expectEqual(shortPayload, nil, "Stagewright payload length mismatch is rejected")
	expectEqual(type(shortPayloadError), "string", "Stagewright payload length mismatch reports a diagnostic")
	expectEqual(
		StagePayload.parseManifest("StagewrightChunked:v1:999999999:1:fnv1a32-deadbeef"),
		nil,
		"impossible Stagewright chunk count is rejected before allocation"
	)
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
	string.find(migrationsSource, "Migrations.CURRENT_VERSION = 7", 1, true) ~= nil,
	true,
	"profile schema version is current"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 6", 1, true) ~= nil,
	true,
	"schema 5 profiles gain tower defense state"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 7", 1, true) ~= nil,
	true,
	"schema 6 profiles gain the rune channel mode selection"
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
for _, stageMigrationMarker in
	{ "previousVersion < 7", "selectedStageId", "stageProgress", "startingProgress.unlocked = true" }
do
	expectEqual(
		string.find(migrationsSource, stageMigrationMarker, 1, true) ~= nil,
		true,
		`stage profile migration includes {stageMigrationMarker}`
	)
end

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
		'"servePlaceIds": [128136881672145]',
		'"$path": "rng-defender/DesignerConfig.luau"',
		'"TowerDefenseCatalog"',
		'"TowerDefenseLogic"',
		'"RuneModeConfig"',
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
		"universeId = 10479279603",
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
expectEqual(
	string.find(gridPatchProject, '"FirstPrivateIsland"', 1, true),
	nil,
	"shared tower-defense patch never manages the Team Create island"
)
expectEqual(
	string.find(gridPatchProject, '"StageCatalog.generated"', 1, true) ~= nil,
	true,
	"shared tower-defense patch includes generated Stagewright runtime data"
)
local gridPluginProject = fs.readFile("plugins/grid-platform-editor.project.json")
local gridPluginSource = fs.readFile("src/plugins/GridPlatformEditPlugin.server.luau")
local gridPluginTopLevelLocals = 0
for line in string.gmatch(gridPluginSource, "[^\r\n]+") do
	if string.match(line, "^local%s+") ~= nil then
		gridPluginTopLevelLocals += 1
	end
end
expectEqual(
	gridPluginTopLevelLocals <= 185,
	true,
	"Stagewright bootstrap stays below Studio's top-level local-register danger zone"
)
local stagewrightStoreSource = fs.readFile("src/plugins/Stagewright/ProjectStore.luau")
	.. fs.readFile("src/shared/StagePayload.luau")
	.. fs.readFile("src/plugins/Stagewright/RouteOverview.luau")
local stagewrightAuthoringAreaSource = fs.readFile("src/plugins/Stagewright/AuthoringArea.luau")
local stagewrightAppShellSource = fs.readFile("src/plugins/Stagewright/UI/AppShell.luau")
local stagewrightThemeSource = fs.readFile("src/plugins/Stagewright/UI/Theme.luau")
local stagewrightFactorySource = fs.readFile("src/plugins/Stagewright/UI/Factory.luau")
local stagewrightHeaderControllerSource = fs.readFile("src/plugins/Stagewright/UI/HeaderController.luau")
local stagewrightPaintAppearanceSource = fs.readFile("src/plugins/Stagewright/UI/PaintAppearance.luau")
local stagewrightToolbarSource = fs.readFile("src/plugins/Stagewright/UI/Toolbar.luau")
local stagewrightGraphOperationsSource = fs.readFile("src/plugins/Stagewright/Graph/Operations.luau")
local stagewrightPredicateFieldsSource = fs.readFile("src/plugins/Stagewright/Graph/PredicateFields.luau")
local stagewrightPaintBrushesSource = fs.readFile("src/plugins/Stagewright/Paint/Brushes.luau")
local stagewrightStageSettingsSource = fs.readFile("src/plugins/Stagewright/Stage/Settings.luau")
local stagewrightIssueModelSource = fs.readFile("src/plugins/Stagewright/Validation/IssueModel.luau")
local stagewrightUiSource = stagewrightAppShellSource
	.. stagewrightThemeSource
	.. stagewrightFactorySource
	.. stagewrightHeaderControllerSource
	.. stagewrightPaintAppearanceSource
	.. stagewrightToolbarSource
local stagewrightGraphSource = stagewrightGraphOperationsSource .. stagewrightPredicateFieldsSource
local stagewrightPaintSource = stagewrightPaintBrushesSource
local stagewrightStageSource = stagewrightStageSettingsSource
expectCompiles(gridPluginSource, "modern Stagewright plugin shell compiles as Luau")
expectCompiles(stagewrightAppShellSource, "Stagewright app shell compiles as Luau")
expectCompiles(stagewrightThemeSource, "Stagewright UI theme compiles as Luau")
expectCompiles(stagewrightFactorySource, "Stagewright UI factory compiles as Luau")
expectCompiles(stagewrightHeaderControllerSource, "Stagewright header controller compiles as Luau")
expectCompiles(stagewrightPaintAppearanceSource, "Stagewright paint appearance compiles as Luau")
expectCompiles(stagewrightToolbarSource, "Stagewright toolbar compiles as Luau")
expectCompiles(stagewrightGraphOperationsSource, "Stagewright graph operations compile as Luau")
expectCompiles(stagewrightPredicateFieldsSource, "Stagewright predicate fields compile as Luau")
expectCompiles(stagewrightPaintBrushesSource, "Stagewright paint brushes compile as Luau")
expectCompiles(stagewrightStageSettingsSource, "Stagewright stage settings compile as Luau")
expectCompiles(stagewrightIssueModelSource, "Stagewright validation issue model compiles as Luau")
expectEqual(
	string.find(gridPluginSource, "require(script.UI.AppShell)", 1, true) ~= nil
		and string.find(gridPluginSource, "require(script.UI.Theme)", 1, true) ~= nil
		and string.find(gridPluginSource, "require(script.Graph.Operations)", 1, true) ~= nil,
	true,
	"Stagewright bootstrap composes dedicated UI and graph modules"
)
for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "GuiObject" } do
	expectEqual(
		string.find(stagewrightGraphSource, forbiddenDependency, 1, true),
		nil,
		`Stagewright graph domain stays independent from {forbiddenDependency}`
	)
end
for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new", "UI.Theme" } do
	expectEqual(
		string.find(stagewrightPaintSource, forbiddenDependency, 1, true),
		nil,
		`Stagewright paint domain stays independent from {forbiddenDependency}`
	)
end
for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new", "UI.Theme" } do
	expectEqual(
		string.find(stagewrightStageSource, forbiddenDependency, 1, true),
		nil,
		`Stagewright stage settings stay independent from {forbiddenDependency}`
	)
end
for _, forbiddenDependency in { "ProjectStore", "ServerStorage", "StagePayload", "Graph.Operations" } do
	expectEqual(
		string.find(stagewrightUiSource, forbiddenDependency, 1, true),
		nil,
		`Stagewright UI primitives stay independent from {forbiddenDependency}`
	)
end
for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new" } do
	expectEqual(
		string.find(stagewrightIssueModelSource, forbiddenDependency, 1, true),
		nil,
		`Stagewright validation model stays independent from {forbiddenDependency}`
	)
end
local gridPluginLineCount = 0
for _ in string.gmatch(gridPluginSource, "[^\r\n]+") do
	gridPluginLineCount += 1
end
expectEqual(gridPluginLineCount <= 6400, true, "Stagewright bootstrap does not absorb extracted module code")
do
	local routeOverviewSource = fs.readFile("src/plugins/Stagewright/RouteOverview.luau")
	expectCompiles(routeOverviewSource, "Stagewright 2D route overview compiles as Luau")
	for _, behavior in { "connectionFromNodeId", "connectNodes", "outputPort", "positionEdgeLine" } do
		expectEqual(
			string.find(routeOverviewSource, behavior, 1, true) ~= nil,
			true,
			`Stagewright route logic view includes {behavior}`
		)
	end
end
do
	local worldPathSource = fs.readFile("src/plugins/Stagewright/WorldPathView.luau")
	expectCompiles(worldPathSource, "Stagewright real-world path view compiles as Luau")
	for _, behavior in
		{
			"GRAVEL",
			"ViewportFrame",
			"FirstPrivateIsland",
			"Lane centerline",
			"Selected spline",
			"Test segment",
			"Build mask derived automatically",
			"lineButton",
			"setLanes",
			"IsMouseButtonPressed",
			"dragStartScreen",
			".Magnitude < 4",
		}
	do
		expectEqual(
			string.find(worldPathSource, behavior, 1, true) ~= nil,
			true,
			`Stagewright world path view includes {behavior}`
		)
	end
end
expectEqual(
	string.find(gridPluginSource, "RouteCell_", 1, true),
	nil,
	"Stagewright no longer floods every route-reserved cell with a cyan preview part"
)
expectEqual(
	string.find(gridPluginSource, "workspacePreviewEnabled = true", 1, true),
	nil,
	"Stagewright never enables automatic Workspace route generation"
)
expectCompiles(stagewrightAuthoringAreaSource, "Stagewright admin authoring area compiles as Luau")
for _, pluginObject in
	{
		"StagewrightPlugin",
		"GridPlatformEditPlugin.server.luau",
		"plugin:CreateToolbar",
		"CreateDockWidgetPluginGuiAsync",
		"StagewrightPanel",
		"Stagewright - Tower Defense Stage Editor",
		"StagewrightPanelV2",
		"StagewrightProject",
		"StagewrightPayload",
		"StagewrightPayloadChunks",
		"StagewrightRuntime",
		"PromptSaveSelectionAsync",
		"PluginAction",
		"plugin.Unloading",
		"TryBeginRecording",
		"FinishRecording",
		"ProjectStore.createStage",
		"ProjectStore.createLevel",
		"ensureStarterLevels",
		"ProjectStore.deleteStage",
		"ProjectStore.inboundReferences",
		"GenerateGUID",
		"StageLegacy.project",
		"StageExport.bake",
		"StagewrightTransientPreview",
		"terrain_ground",
		"build_blocked",
		"traversal_blocked",
		"EnemySpawn",
		"StageTransition",
		"Junction",
		"Connect",
		"Add condition",
		"Trace route",
		"Set fallback",
		"1 Lane",
		"2 Lanes",
		"3 Lanes",
		"+ Stage",
		"+ Level",
		"Apply changes",
		"GraphToolMode",
		"graphActionPages",
		"buildControls",
		"rulesControls",
		"testControls",
		"Delete edge",
		"RouteOverview.new",
		'local label = if mode == "Graph"',
		"STAGES & LEVELS",
		'else "LAYERS"',
		'then "VALIDATION"',
		"Search levels",
		"Brush 1 x 1",
		"Reset to default",
		"Center in graph",
		"paintCellPixels",
		"LevelPreviewCanvas",
		"ValidationErrorValue",
		"StageMoreMenu",
		"PROJECT MENU",
		"StageSelector",
		"StageDropdown",
		"VectorIcon",
		"ToggleExtra",
		"setNavigationSelected",
		"Focus authoring area",
		"Hide editor",
		"+  Add node",
		"Split edge",
		"GraphPrimaryLanes",
		"PaintTool_",
		'activePaintTool == "Rect"',
		"HeaderSignature",
		"Export bundle",
		"applyResponsiveShell",
		"paintBrushSize",
		"paintModifierDown",
		"Shift + drag to paint",
		"EnemyRouteOverlay",
		"Paint cells",
		"Edit enemy route",
		"ROUTE WORKFLOW",
		"Connect ->",
		"paintRuntime.beginRouteInteraction",
		"paintRuntime.hitRoute",
		"Move Stagewright route node",
		"Shape Stagewright route spline",
		"RouteAffected",
		"RouteConflict_",
		"World Path",
		"Route Logic",
		"Asset Preview",
		"Perspective",
		"Selected spline",
		"Open World Path",
		"workspacePreviewEnabled = false",
		"Workspace remains unchanged",
		"routeDragStartScreen",
		"StagewrightPathAsset",
		"Enum.Material.Pebble",
		"ProjectStore.preview",
		"UserInputService.InputChanged",
		'GetAttribute("Column")',
		"PaintValidationPanel",
		"PaintInspectorBrushName",
		"GraphMiniPreviewCanvas",
		"GraphLevelStrip",
		"GraphInspectorDock",
		'activeMode == "Graph"',
		"matching issues",
		"selectedCellKey",
		"Apply node",
		"Select an issue to jump",
		"AutomaticCanvasSize",
		"setButtonSelected",
		"STAGE {address.stageNumber}",
		"StageLanes.offsets",
		"outHandleOffset",
		"inHandleOffset",
		"Working changes",
		"Export hash matched",
		"CanvasPosition",
		"AbsoluteWindowSize",
		"AuthoringArea",
		"StagewrightAdminArea",
		"WhiteRoom",
		"Focus Stagewright Admin Area",
		"StagewrightFocusAdminArea",
		"StagewrightToggleIslandOutlines",
		"Guides",
		"showIslandOutlines",
		"StagewrightIslandOutlinePreview",
		"StagePlatformLayout",
		"developmentOutlines",
		"centerFacingLocalDirection",
		"GridColumn_",
		"GridRow_",
		"gridLineThickness",
		"lineThickness = 0.16",
		"routeWidth = 2.4",
		"starterLevelsPerStage = 10",
		"AlwaysOnTop",
		"RunService:IsRunning()",
	}
do
	expectEqual(
		string.find(
			gridPluginProject
				.. gridPluginSource
				.. stagewrightStoreSource
				.. stagewrightAuthoringAreaSource
				.. stagewrightUiSource
				.. stagewrightGraphSource
				.. stagewrightPaintSource
				.. stagewrightStageSource
				.. stagewrightIssueModelSource
				.. templateConfigSource,
			pluginObject,
			1,
			true
		) ~= nil,
		true,
		`edit-mode grid plugin includes {pluginObject}`
	)
end
for _, obsoleteToolbarGlyph in { "⌁", "▦", "✋", "⊕", "⌘", "↖" } do
	expectEqual(
		string.find(gridPluginSource .. stagewrightUiSource, obsoleteToolbarGlyph, 1, true),
		nil,
		`Stagewright toolbar no longer depends on the {obsoleteToolbarGlyph} text glyph`
	)
end
expectEqual(
	string.find(gridPluginSource, "UDim2.fromOffset(414, 23)", 1, true),
	nil,
	"Stagewright level settings no longer depend on the clipped fixed-width form"
)
for _, removedPluginObject in
	{
		"DEFAULT_STAGE_PROFILES",
		"catmullRomPosition",
		"PATH_GRID_RADIUS",
		"Runtime: any",
	}
do
	expectEqual(
		string.find(gridPluginSource, removedPluginObject, 1, true),
		nil,
		`edit-mode grid plugin no longer uses separate {removedPluginObject} targeting`
	)
end
expectEqual(
	string.find(stagewrightAuthoringAreaSource, "CenterFacingGuide", 1, true),
	nil,
	"edit-mode island guides no longer draw a misleading orientation bar"
)
local runePluginProject = fs.readFile("plugins/rune-config-editor.project.json")
local runePluginSource = fs.readFile("src/plugins/RunewrightPlugin.server.luau")
for _, runePluginObject in
	{
		"RunewrightPlugin",
		"RunewrightPlugin.server.luau",
		"Runewright",
		"RunewrightPanel",
		"Rune altar workbench",
		"plugin:CreateToolbar",
		"CreateDockWidgetPluginGuiAsync",
		"DockWidgetPluginGuiInfo",
		"TryBeginRecording",
		"FinishRecording",
		"Apply to Place",
		"Print Sources",
		"Normalize Weights to 10000",
		"must equal exactly 10000",
		"needs at least one rune",
		"DesignerConfig",
		"RuneCatalog",
		"TemplateConfig",
		"channelModes",
		"copyMilestones",
		"defaultChannelMode",
		"pityMinimumRarity",
		"rareAudioMinimumRarity",
		"baseCost",
		"tickSeconds",
		"minCommonWeight",
		"unlockKind",
		"tiers",
		"bonusPercent",
		"glyph",
		"flavor",
		"Fix first:",
		"Add Rune Card",
		"Remove Card",
		-- Tabbed workbench UX contract: tab navigation, live validation with
		-- per-tab issue tags, visible pill pickers, entry-time range hints,
		-- reload recovery, and confirmed destructive actions.
		"selectTab",
		"optionPills",
		"Refresh.validation",
		"Ready to apply",
		"issue.tab",
		"rangeText",
		"Reload from Place",
		"Confirm remove?",
		"Discard edits?",
		-- Professional control taxonomy: segmented pickers for exclusive
		-- choices, a real toggle switch for mode enablement, hex color entry,
		-- and the live weight-distribution bar on the Rarity tab.
		"segmentedControl",
		"toggleSwitch",
		"parseHexColor",
		"OddsBar",
		-- Glyphs accept a Roblox image asset id (5-16 digits) as well as an
		-- emoji; the card cell previews the actual image via the same rule
		-- RuneLogic.glyphImage applies at runtime.
		"glyphImageId",
		"GlyphPreview",
		-- Tier and milestone editors hold everything the runtime accepts
		-- (RuneModeConfig.MAX_TIERS / MAX_MILESTONES), so loading a place
		-- never silently truncates authored rows.
		"local TIER_ROWS = 8",
		"local MILESTONE_ROWS = 8",
	}
do
	expectEqual(
		string.find(runePluginProject .. runePluginSource, runePluginObject, 1, true) ~= nil,
		true,
		`rune workbench plugin includes {runePluginObject}`
	)
end
-- The workbench edits the open place only; it must never touch live services
-- or publish anything. The blind cycle buttons stay retired: fixed choices
-- render as visible pill pickers instead.
for _, forbiddenPluginCall in
	{ "PolicyService", "DataStoreService", "HttpService", "PublishAsync", "cycleField" }
do
	expectEqual(
		string.find(runePluginSource, forbiddenPluginCall, 1, true),
		nil,
		`rune workbench plugin never references {forbiddenPluginCall}`
	)
end
local runePluginCheck = fs.readFile("scripts/check.ps1")
expectEqual(
	string.find(runePluginCheck, "rune-config-editor.project.json", 1, true) ~= nil,
	true,
	"check.ps1 builds the Runewright plugin package"
)
local gridNpcBinder = fs.readFile("src/starter/GridNpcDemo.server.luau")
for _, sharedPathMarker in
	{
		"StageCatalog",
		"StagePath.sample",
		"edge.samples",
		"sample.tangent",
		"sample.up",
		"Workspace:GetServerTimeNow",
	}
do
	expectEqual(
		string.find(gridNpcBinder, sharedPathMarker, 1, true) ~= nil,
		true,
		`grid NPC movement uses shared path marker {sharedPathMarker}`
	)
end
for _, oldPathMarker in { "catmullRomPosition", "buildSplinePath", "sampleSplinePath", "PathPoints" } do
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

-- Stagewright: shared Bezier geometry and deterministic conditional graph traversal.
local straightSamples, straightLength = StagePath.bake(
	{ x = 0, y = 0, z = 0 },
	{ x = 10 / 3, y = 0, z = 0 },
	{ x = 20 / 3, y = 0, z = 0 },
	{ x = 10, y = 0, z = 0 }
)
expectEqual(math.abs(straightLength - 10) < 1e-6, true, "stage path bake preserves straight edge length")
local straightMiddle = StagePath.sample(straightSamples, straightLength, 5)
expectEqual(
	straightMiddle ~= nil and math.abs(straightMiddle.position.x - 5) < 1e-6,
	true,
	"stage path samples by distance"
)
expectEqual(
	straightMiddle ~= nil and straightMiddle.tangent.x > 0.999,
	true,
	"stage path provides stable orientation tangent"
)
do
	local single = StageLanes.offsets(1)
	local double = StageLanes.offsets(2)
	local triple = StageLanes.offsets(3)
	expectEqual(#single == 1 and single[1] == 0, true, "single lane stays on the spline centerline")
	expectEqual(
		#double == 2 and double[1] == -2 and double[2] == 2,
		true,
		"two lanes split evenly across the spline"
	)
	expectEqual(
		#triple == 3 and triple[1] == -4 and triple[2] == 0 and triple[3] == 4,
		true,
		"three lanes remain centered around the spline"
	)
	expectEqual(StageLanes.index(4, 3), 1, "lane assignment cycles deterministically")
	expectEqual(
		StageLanes.sequenceForSpawn(1, 2) == 1
			and StageLanes.sequenceForSpawn(2, 2) == 1
			and StageLanes.sequenceForSpawn(3, 2) == 2,
		true,
		"lane sequence advances independently after distributing across spawns"
	)
	expectEqual(StageLanes.clearanceRadius(triple), 6, "lane clearance covers the full corridor")
end
do
	local firstPlatformOffset = { x = 183.524, y = 13.344, z = 94.169 }
	local centerFacingLocalDirection = { x = -54, y = 0, z = -32 }
	local alignmentYaw =
		StagePlatformLayout.alignDirectionYaw(firstPlatformOffset, centerFacingLocalDirection)
	expectEqual(
		math.abs(math.deg(alignmentYaw) - 3.4876078885171) < 1e-9,
		true,
		"platform yaw aligns the stage's authored center-facing direction"
	)
	local alignedX = math.cos(alignmentYaw) * centerFacingLocalDirection.x
		+ math.sin(alignmentYaw) * centerFacingLocalDirection.z
	local alignedZ = -math.sin(alignmentYaw) * centerFacingLocalDirection.x
		+ math.cos(alignmentYaw) * centerFacingLocalDirection.z
	local alignedMagnitude = math.sqrt(alignedX * alignedX + alignedZ * alignedZ)
	local centerMagnitude = math.sqrt(
		firstPlatformOffset.x * firstPlatformOffset.x + firstPlatformOffset.z * firstPlatformOffset.z
	)
	local centerAlignment = (alignedX * -firstPlatformOffset.x + alignedZ * -firstPlatformOffset.z)
		/ (alignedMagnitude * centerMagnitude)
	expectEqual(centerAlignment > 0.999999999, true, "aligned stage direction points at the world center")
	local slotOneOffset, slotOneYaw = StagePlatformLayout.slotOffset(firstPlatformOffset, 1, 6)
	local slotFourOffset, slotFourYaw = StagePlatformLayout.slotOffset(firstPlatformOffset, 4, 6)
	expectEqual(
		math.abs(slotOneOffset.x - firstPlatformOffset.x) < 1e-9,
		true,
		"platform slot one preserves authored X"
	)
	expectEqual(
		math.abs(slotOneOffset.z - firstPlatformOffset.z) < 1e-9,
		true,
		"platform slot one preserves authored Z"
	)
	expectEqual(slotOneYaw, 0, "platform slot one preserves authored orientation")
	expectEqual(
		math.abs(slotFourOffset.x + firstPlatformOffset.x) < 1e-9,
		true,
		"opposite platform mirrors X"
	)
	expectEqual(
		math.abs(slotFourOffset.z + firstPlatformOffset.z) < 1e-9,
		true,
		"opposite platform mirrors Z"
	)
	expectEqual(math.abs(slotFourYaw - math.pi) < 1e-9, true, "six platform slots rotate in 60-degree steps")
end

local branchGraph = {
	nodes = {
		spawn = { id = "spawn", kind = "Spawn" },
		upper = { id = "upper", kind = "Goal" },
		fallback = { id = "fallback", kind = "Goal" },
	},
	edges = {
		wave_gate = {
			id = "wave_gate",
			fromNodeId = "spawn",
			toNodeId = "upper",
			priority = 1,
			predicates = { { kind = "WaveRange", minimum = 5, maximum = 10 } },
		},
		fallback = {
			id = "fallback",
			fromNodeId = "spawn",
			toNodeId = "fallback",
			priority = 2,
			predicates = {},
		},
	},
}
local routeContext = {
	wave = 2,
	stageFlags = {},
	enemyTags = {},
	nodeVisits = {},
	unlockedStages = {},
	upgradeLevels = {},
	currencies = {},
}
local selectedEdge = StageGraph.chooseEdge(branchGraph, "spawn", routeContext)
expectEqual(selectedEdge ~= nil and selectedEdge.id, "fallback", "stage graph uses unconditional fallback")
routeContext.wave = 6
selectedEdge = StageGraph.chooseEdge(branchGraph, "spawn", routeContext)
expectEqual(selectedEdge ~= nil and selectedEdge.id, "wave_gate", "stage graph evaluates built-in predicates")
expectEqual(#StageGraph.validate(branchGraph), 0, "valid stage graph passes shared validation")
local fallbackTrace = StageTrace.trace(branchGraph, "spawn", routeContext)
expectEqual(fallbackTrace.reachedGoal, true, "edit-mode route trace reaches a goal")
expectEqual(fallbackTrace.edgeIds[1], "wave_gate", "route trace uses the same deterministic edge evaluator")
local predicateContext = {
	wave = 7,
	stageFlags = { hardMode = true },
	enemyTags = { Flying = true },
	nodeVisits = { spawn = 1 },
	unlockedStages = { stage_two = true },
	upgradeLevels = { range = 4 },
	currencies = { coins = 500 },
}
expectEqual(
	StageGraph.predicatesPass({
		{ kind = "StageFlagEquals", key = "hardMode", value = true },
		{ kind = "EnemyTag", tag = "Flying" },
		{ kind = "VisitCountBelow", nodeId = "spawn", maximum = 3 },
		{ kind = "StageUnlocked", stageId = "stage_two" },
		{ kind = "UpgradeLevelAtLeast", upgradeId = "range", level = 4 },
		{ kind = "CurrencyAtLeast", currencyId = "coins", amount = 250 },
	}, predicateContext),
	true,
	"all built-in route predicates evaluate from authoritative context"
)
local cyclicGraph = serde.decode("json", serde.encode("json", branchGraph))
cyclicGraph.nodes.loop = { id = "loop", kind = "Junction" }
cyclicGraph.edges.wave_gate.toNodeId = "loop"
cyclicGraph.edges.loop = {
	id = "loop",
	fromNodeId = "loop",
	toNodeId = "loop",
	priority = 1,
	predicates = {},
}
local cyclicIssues = StageGraph.validate(cyclicGraph)
expectEqual(#cyclicIssues > 0, true, "unbounded graph cycles are rejected before export")
local cyclicTrace = StageTrace.trace(cyclicGraph, "spawn", routeContext, 12)
expectEqual(cyclicTrace.reachedGoal, false, "route trace safety cap stops an unbounded cycle")
expectEqual(
	string.find(cyclicTrace.stoppedReason, "Maximum node visits", 1, true) ~= nil,
	true,
	"route trace reports the safety cap diagnostic"
)
local finiteJsonOk = pcall(function()
	StageSchema.encodeCanonical({ invalid = 0 / 0 })
end)
expectEqual(finiteJsonOk, false, "Stagewright serialization rejects NaN payloads")
local invalidCellIssues = StageSchema.validateStage({
	id = "invalid_cell_stage",
	stageGroupId = "invalid_cell_group",
	stageNumber = 1,
	levelNumber = 1,
	grid = {
		columns = 2,
		rows = 2,
		cellSize = 4,
		defaultCell = {},
		cells = { ["3:1"] = { buildPolicy = "Allowed" } },
	},
	pathGraphs = {},
})
expectEqual(invalidCellIssues[1].code, "CellOutOfBounds", "out-of-range stage cells fail validation")
local legacyLayered = StageSchema.legacyCells({ ".#PGA?" }, 6)
expectEqual(legacyLayered["2:1"].buildPolicy, "Blocked", "legacy path blocks remain authored manual blocks")
expectEqual(legacyLayered["3:1"].roles.EnemySpawn, true, "legacy portal migrates to spawn role")
expectEqual(legacyLayered["4:1"].roles.EnemyGoal, true, "legacy goal migrates to goal role")
expectEqual(legacyLayered["5:1"].roles.AutoPlace, true, "legacy auto-place migrates independently")
expectEqual(legacyLayered["6:1"].metadata.legacyCode, "?", "unknown legacy cells are preserved as metadata")
local importedLegacy, legacyNotices = StageLegacy.project({
	columns = 4,
	rows = 2,
	cellSize = 2,
	rowValues = { "....", "...G" },
	controlPositions = {
		{ x = -3, y = 0, z = 0 },
		{ x = 0, y = 0, z = 0 },
	},
	stageId = "stage_default",
	graphId = "graph_main",
	stageName = "Legacy Fixture",
	blankFallback = false,
})
local importedLegacyStage = importedLegacy.stages.stage_default
local importedLegacyGraph = importedLegacyStage.pathGraphs.graph_main
expectEqual(
	importedLegacyStage.grid.cells["1:2"].roles.EnemySpawn,
	true,
	"legacy controls infer a missing spawn role at Control_001"
)
expectEqual(
	importedLegacyGraph.nodes.node_spawn.position.x,
	-3,
	"Control_001 becomes the inferred graph spawn without an extra segment"
)
expectEqual(
	importedLegacyGraph.edges.edge_001.toNodeId,
	"node_control_002",
	"legacy controls retain their authored order"
)
expectEqual(
	importedLegacyGraph.edges.edge_001.outHandleOffset.x,
	0.5,
	"legacy Catmull-Rom tangents convert to cubic Bezier handles"
)
local convertedEdge = importedLegacyGraph.edges.edge_001
local convertedFrom = importedLegacyGraph.nodes[convertedEdge.fromNodeId].position
local convertedTo = importedLegacyGraph.nodes[convertedEdge.toNodeId].position
local convertedAlpha = 0.37
local convertedBezier = StagePath.position(convertedFrom, {
	x = convertedFrom.x + convertedEdge.outHandleOffset.x,
	y = convertedFrom.y + convertedEdge.outHandleOffset.y,
	z = convertedFrom.z + convertedEdge.outHandleOffset.z,
}, {
	x = convertedTo.x + convertedEdge.inHandleOffset.x,
	y = convertedTo.y + convertedEdge.inHandleOffset.y,
	z = convertedTo.z + convertedEdge.inHandleOffset.z,
}, convertedTo, convertedAlpha)
local function catmullComponent(p0: number, p1: number, p2: number, p3: number, alpha: number): number
	local alpha2 = alpha * alpha
	local alpha3 = alpha2 * alpha
	return (
		(p1 * 2)
		+ ((p2 - p0) * alpha)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * alpha2)
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * alpha3)
	) * 0.5
end
local legacyGoalPosition = importedLegacyGraph.nodes.node_goal.position
local expectedLegacyX =
	catmullComponent(convertedFrom.x, convertedFrom.x, convertedTo.x, legacyGoalPosition.x, convertedAlpha)
local expectedLegacyZ =
	catmullComponent(convertedFrom.z, convertedFrom.z, convertedTo.z, legacyGoalPosition.z, convertedAlpha)
expectEqual(
	math.abs(convertedBezier.x - expectedLegacyX) < 1e-9
		and math.abs(convertedBezier.z - expectedLegacyZ) < 1e-9,
	true,
	"converted Bezier geometry exactly matches the legacy Catmull-Rom segment"
)
expectEqual(#legacyNotices, 1, "legacy spawn inference produces an explicit diagnostic")
expectEqual(
	StageExport.bake(importedLegacy).bundle ~= nil,
	true,
	"inferred legacy route exports successfully"
)
local schemaOneProject = {
	schemaVersion = 1,
	startingStageId = "legacy",
	stages = {
		legacy = {
			id = "legacy",
			grid = { columns = 2, rows = 2, cellSize = 4, cells = {} },
			pathGraphs = {},
			unknownFutureField = { preserved = true },
		},
	},
}
local migratedStageProject = StageSchema.migrateProject(schemaOneProject)
expectEqual(migratedStageProject.schemaVersion, 3, "Stagewright authoring schemas migrate sequentially")
expectEqual(
	migratedStageProject.stages.legacy.stageNumber == 1
		and migratedStageProject.stages.legacy.levelNumber == 1,
	true,
	"legacy flat stages migrate into stable Stage 1 / Level 1 hierarchy fields"
)
expectEqual(
	migratedStageProject.stages.legacy.unknownFutureField.preserved,
	true,
	"Stagewright migration preserves unknown stage data"
)
expectEqual(
	StageSchema.migrateProject(migratedStageProject).schemaVersion,
	3,
	"Stagewright migration is idempotent"
)
do
	local authoringProject = serde.decode("json", fs.readFile("stage-data/stagewright-project.json"))
	local authoredProductionStage = authoringProject.stages.stage_default
	expectEqual(authoredProductionStage.name, "Level 1", "repository names the starting definition Level 1")
	expectEqual(
		authoringProject.metadata["stagewright.approvedStarterRevision"],
		StageStarterProject.REVISION,
		"repository starter data records its approved replacement revision"
	)
	local authoredLevelIds = StageHierarchy.sortedIds(authoringProject.stages)
	expectEqual(#authoredLevelIds, 10, "repository seeds Stage 1 with the first ten levels")
	local copiedStarterLayoutsMatch = true
	local uniqueGraphIds: { [string]: boolean } = {}
	local function topologySignature(level: any): string
		local graphId, graph = next(level.pathGraphs)
		local names: { [string]: string } = {}
		for nodeId, node in graph.nodes do
			names[nodeId] = node.name
		end
		local routes: { string } = {}
		for _, edge in graph.edges do
			table.insert(
				routes,
				`{names[edge.fromNodeId]}->{names[edge.toNodeId]}:{edge.priority}:{#edge.predicates}`
			)
		end
		table.sort(routes)
		uniqueGraphIds[graphId] = true
		return table.concat(routes, "|")
	end
	local authoredTopology = topologySignature(authoredProductionStage)
	for levelNumber, levelId in authoredLevelIds do
		local level = authoringProject.stages[levelId]
		local address = StageHierarchy.address(level)
		if
			StageSchema.encodeCanonical(level.grid)
				~= StageSchema.encodeCanonical(authoredProductionStage.grid)
			or topologySignature(level) ~= authoredTopology
		then
			copiedStarterLayoutsMatch = false
		end
		expectEqual(
			address.stageNumber == 1 and address.levelNumber == levelNumber,
			true,
			`authored Stage 1 level order includes Level {levelNumber}`
		)
		if levelNumber > 1 then
			expectEqual(
				level.unlockRequirements[1].stageId,
				authoredLevelIds[levelNumber - 1],
				`Level {levelNumber} preserves sequential progression`
			)
		end
	end
	expectEqual(
		copiedStarterLayoutsMatch,
		true,
		"all ten starter levels copy the same editable map and graph"
	)
	local uniqueGraphIdCount = 0
	for _ in uniqueGraphIds do
		uniqueGraphIdCount += 1
	end
	expectEqual(uniqueGraphIdCount, 10, "copied starter levels receive independent graph identities")
	do
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(authoringProject),
			false,
			"approved starter content can never be mistaken for replaceable test data"
		)
		local recognizedLegacy = serde.decode("json", serde.encode("json", authoringProject))
		recognizedLegacy.metadata["stagewright.approvedStarterRevision"] = nil
		for _, legacyStage in recognizedLegacy.stages do
			for _, legacyGraph in legacyStage.pathGraphs do
				local legacyIndex = 1
				for _, legacyNode in legacyGraph.nodes do
					if legacyIndex <= 5 then
						legacyNode.name = `Legacy Control {legacyIndex}`
					end
					legacyIndex += 1
				end
			end
		end
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(recognizedLegacy),
			true,
			"only the exact ten-level random legacy signature authorizes starter replacement"
		)
		recognizedLegacy.stages[authoredLevelIds[10]] = nil
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(recognizedLegacy),
			false,
			"near-matching authored projects remain untouched"
		)
	end
	do
		local duplicateHierarchy = serde.decode("json", serde.encode("json", authoringProject))
		duplicateHierarchy.stages[authoredLevelIds[2]].levelNumber = 1
		local duplicateResult = StageExport.bake(duplicateHierarchy)
		local foundDuplicateLevel = false
		for _, issue in duplicateResult.issues do
			if issue.code == "DuplicateLevelNumber" then
				foundDuplicateLevel = true
				break
			end
		end
		expectEqual(
			duplicateResult.bundle == nil and foundDuplicateLevel,
			true,
			"duplicate level numbers block deterministic export"
		)
	end
	expectEqual(
		authoredProductionStage.metadata["stagewright.layoutVersion"],
		3,
		"repository records the intentional production layout version"
	)
	expectEqual(
		authoredProductionStage.grid.cells["4:6"].roles.EnemySpawn,
		true,
		"production stage provides a north spawn"
	)
	expectEqual(
		authoredProductionStage.grid.cells["4:22"].roles.EnemySpawn,
		true,
		"production stage provides a south spawn"
	)
	expectEqual(
		authoredProductionStage.grid.cells["31:14"].roles.EnemyGoal,
		true,
		"production goal sits opposite both spawns"
	)
	local authoredGraphId, authoringGraph = next(authoredProductionStage.pathGraphs)
	local edgeByRoute: { [string]: any } = {}
	for _, edge in authoringGraph.edges do
		edgeByRoute[`{authoringGraph.nodes[edge.fromNodeId].name}->{authoringGraph.nodes[edge.toNodeId].name}`] =
			edge
	end
	expectEqual(edgeByRoute["Rejoin->Goal"] ~= nil, true, "merged production route reaches the goal")
	expectEqual(
		edgeByRoute["North Spawn->Merge"] ~= nil and edgeByRoute["South Spawn->Merge"] ~= nil,
		true,
		"north and south spawn splines merge at one stable junction"
	)
	expectEqual(
		edgeByRoute["Merge->Wave Gate"].predicates[1].kind == "WaveRange"
			and edgeByRoute["Merge->Fallback Path"].priority == 2
			and #edgeByRoute["Merge->Fallback Path"].predicates == 0,
		true,
		"production route has a wave-gated branch and unconditional fallback"
	)
	expectEqual(
		edgeByRoute["Wave Gate->Rejoin"] ~= nil and edgeByRoute["Fallback Path->Rejoin"] ~= nil,
		true,
		"conditional and fallback branches rejoin before the goal"
	)
	expectEqual(
		#authoringGraph.laneProfiles.lane_default.offsets,
		2,
		"production route defaults to two enemy lanes"
	)
	do
		local invalidLaneStage = serde.decode("json", serde.encode("json", authoredProductionStage))
		invalidLaneStage.pathGraphs[authoredGraphId].laneProfiles.lane_default.offsets = { -6, -2, 2, 6 }
		local foundLaneCountError = false
		for _, issue in StageSchema.validateStage(invalidLaneStage) do
			if issue.code == "LaneCount" then
				foundLaneCountError = true
			end
		end
		expectEqual(foundLaneCountError, true, "stage validation rejects profiles beyond three lanes")
	end
	local firstExport = StageExport.bake(authoringProject)
	local secondExport = StageExport.bake(authoringProject)
	expectEqual(firstExport.bundle ~= nil, true, "valid Stagewright project bakes a runtime bundle")
	expectEqual(
		firstExport.bundle ~= nil and #firstExport.bundle.stageOrder,
		10,
		"runtime bundle exports all ten Stage 1 levels"
	)
	expectEqual(
		firstExport.bundle ~= nil and secondExport.bundle ~= nil and firstExport.bundle.checksum,
		secondExport.bundle ~= nil and secondExport.bundle.checksum,
		"unchanged Stagewright exports are checksum deterministic"
	)
	local runtimeStage = firstExport.bundle ~= nil and firstExport.bundle.stages.stage_default or nil
	local runtimeGraph = runtimeStage ~= nil and runtimeStage.pathGraphs[authoredGraphId] or nil
	local autoPlaceCount = 0
	for key, cell in authoredProductionStage.grid.cells do
		if cell.roles ~= nil and cell.roles.AutoPlace == true then
			autoPlaceCount += 1
			expectEqual(
				runtimeStage ~= nil and runtimeStage.routeNoBuildMask[key],
				nil,
				`production auto-place cell {key} stays outside the route corridor`
			)
		end
	end
	expectEqual(autoPlaceCount, 6, "production stage provides six safe auto-place cells")
	local firstRuntimeEdgeId: string? = nil
	if runtimeGraph ~= nil then
		for edgeId in runtimeGraph.edges do
			if firstRuntimeEdgeId == nil or edgeId < firstRuntimeEdgeId then
				firstRuntimeEdgeId = edgeId
			end
		end
	end
	local firstRuntimeEdge = if firstRuntimeEdgeId ~= nil then runtimeGraph.edges[firstRuntimeEdgeId] else nil
	expectEqual(
		firstRuntimeEdge ~= nil and firstRuntimeEdge.length > 0,
		true,
		"runtime export includes baked edge arc length"
	)
	local routeMaskKey = if runtimeStage ~= nil then next(runtimeStage.routeNoBuildMask) else nil
	expectEqual(
		routeMaskKey ~= nil,
		true,
		"runtime export derives route reservation without rewriting authored cells"
	)
	expectEqual(
		firstRuntimeEdgeId ~= nil and authoringGraph.edges[firstRuntimeEdgeId].samples,
		nil,
		"runtime baking does not mutate the authoring working copy"
	)
	local traversalConflict = serde.decode("json", serde.encode("json", authoringProject))
	local conflictingCell = traversalConflict.stages.stage_default.grid.cells[routeMaskKey] or {}
	conflictingCell.enemyTraversalPolicy = "Blocked"
	traversalConflict.stages.stage_default.grid.cells[routeMaskKey] = conflictingCell
	local conflictExport = StageExport.bake(traversalConflict)
	expectEqual(conflictExport.bundle, nil, "enemy-blocked route corridors prevent export")
	local foundTraversalConflict = false
	for _, issue in conflictExport.issues do
		if issue.code == "RouteTraversalConflict" and issue.objectId == routeMaskKey then
			foundTraversalConflict = true
			break
		end
	end
	expectEqual(foundTraversalConflict, true, "route conflict validation identifies the authored cell")
	do
		local preview = StageExport.preview(traversalConflict.stages.stage_default)
		local previewGraph = if preview ~= nil then preview.pathGraphs[authoredGraphId] else nil
		local previewEdge = if previewGraph ~= nil then previewGraph.edges[firstRuntimeEdgeId] else nil
		expectEqual(
			preview ~= nil and preview.routeNoBuildMask[routeMaskKey] == true,
			true,
			"invalid working stages still expose the derived route footprint to the editor"
		)
		expectEqual(
			previewEdge ~= nil and #previewEdge.samples > 1,
			true,
			"invalid working stages still bake their visible spline preview"
		)
		expectEqual(
			traversalConflict.stages.stage_default.pathGraphs[authoredGraphId].edges[firstRuntimeEdgeId].samples,
			nil,
			"editor route preview does not mutate authored graph data"
		)
	end
	local coincidentEdge = serde.decode("json", serde.encode("json", authoringProject))
	local coincidentGraph = coincidentEdge.stages.stage_default.pathGraphs[authoredGraphId]
	local zeroEdge = coincidentGraph.edges[firstRuntimeEdgeId]
	local zeroFromPosition = coincidentGraph.nodes[zeroEdge.fromNodeId].position
	coincidentGraph.nodes[zeroEdge.toNodeId].position = {
		x = zeroFromPosition.x,
		y = zeroFromPosition.y,
		z = zeroFromPosition.z,
	}
	zeroEdge.outHandleOffset = { x = 0, y = 0, z = 0 }
	zeroEdge.inHandleOffset = { x = 0, y = 0, z = 0 }
	expectEqual(StageExport.bake(coincidentEdge).bundle, nil, "zero-length Bezier edges prevent export")
end

-- Rune altar: weighted rolls, pity, flat configured cost, and permanent multiplier.
expectEqual(
	RuneLogic.weightTotal(RuneCatalog.rarities),
	10000,
	"rune rarity weights sum to exactly 10000 so disclosed odds total 100%"
)

-- Glyphs: 5-16 digit strings name Roblox image assets; everything else is text.
expectEqual(
	RuneLogic.glyphImage("105300168575798"),
	"rbxassetid://105300168575798",
	"digit glyphs resolve to Roblox image asset content"
)
expectEqual(RuneLogic.glyphImage("🔥"), nil, "emoji glyphs stay display text")
expectEqual(RuneLogic.glyphImage("7"), nil, "short digit glyphs stay display text")
expectEqual(RuneLogic.glyphImage("12345678901234567"), nil, "overlong digit strings stay display text")
expectEqual(RuneLogic.glyphImage("123a5"), nil, "mixed alphanumeric glyphs stay display text")
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
		'"Name": "GlyphImage"',
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

do
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
	expectEqual(
		neutralLuck[1].weight,
		RuneCatalog.rarities[1].weight,
		"luck factor 1 leaves weights untouched"
	)
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
		RuneLogic.milestoneMultiplier(
			{ { copies = 2, multiplier = 0 / 0 }, { copies = 3, multiplier = 0.1 } },
			5
		),
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
	expectEqual(
		RuneLogic.resolveModeId("surge", sampleModes, "luck"),
		"surge",
		"a saved known mode is respected"
	)
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
		RuneLogic.isModeUnlocked(
			{ id = "x", unlock = { kind = "mystery" } },
			{ totalRolls = 0, runesOwned = 0 }
		),
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
	expectEqual(
		Calculations.temporaryMultiplier({}, 0, 0.25),
		1,
		"channel surges below 1 never punish earnings"
	)
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
	expectEqual(
		modeMigrated.runes.owned.mystery_rune.count,
		3,
		"unknown saved runes survive the v7 migration"
	)
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
	local runeRemoteSource = fs.readFile("src/server/Services/RemoteService.luau")
	expectEqual(
		string.find(runeRemoteSource, 'SetRuneMode = "runes"', 1, true) ~= nil,
		true,
		"mode swaps are feature-gated behind the runes flag"
	)
	expectEqual(
		string.find(runeRemoteSource, "temporaryMultiplier", 1, true) ~= nil,
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
	expectEqual(
		string.find(runeClientSource, "RuneLogic.glyphImage", 1, true) ~= nil,
		true,
		"the reveal card resolves image glyphs through the shared RuneLogic rule"
	)
	expectEqual(
		string.find(runeClientSource, "GlyphImage", 1, true) ~= nil,
		true,
		"the reveal card binds the authored GlyphImage slot optionally"
	)
	local incrementalUi = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
	for _, authoredHudObject in { '"Name": "RunesValue"', '"Name": "ChannelValue"' } do
		expectEqual(
			string.find(incrementalUi, authoredHudObject, 1, true) ~= nil,
			true,
			`incremental HUD pre-authors {authoredHudObject}`
		)
	end
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
		"TowerDefenseService.activateStage",
		"TowerDefenseService.snapshotFor",
		"EconomyService.spendCurrency",
		"TowerDefenseLogic.isBuildableCell",
		"runtimeFolderName",
		"RunService.Heartbeat",
		"StageRuntimeService.chooseEdge",
		"maximum travel distance exceeded",
		"Workspace:GetServerTimeNow",
		"buildEnemySpatialIndex",
		"simulationAccumulator",
		"StageCatalog.nextLevelId",
		"publishEnemies",
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
local stageRuntimeSource = fs.readFile("src/server/Services/StageRuntimeService.luau")
for _, authorityMarker in
	{
		'type(stageId) ~= "string"',
		"#stageId > 80",
		"StageRuntimeService.isUnlocked",
		"ProfileService.get(player)",
		"upgradeLevelProvider(player",
		"profile.currencies",
		"availabilityProvider(player)",
		"activationPublisher(player",
	}
do
	expectEqual(
		string.find(stageRuntimeSource, authorityMarker, 1, true) ~= nil,
		true,
		`stage activation and predicates remain server-authoritative: {authorityMarker}`
	)
end
local stagePlatformSource = fs.readFile("src/server/Services/StagePlatformService.luau")
local stagePlatformCompiles = pcall(function()
	luau.load(stagePlatformSource)
end)
expectEqual(stagePlatformCompiles, true, "six-platform allocator compiles as Luau")
for _, platformMarker in
	{
		"platformSlotCount",
		"centerPartNames",
		"firstPlatformOffsetFromCenter",
		"cachedFirstRelative = configuredRelativeFrame()",
		"CFrame.Angles(0, yaw, 0)",
		"TowerDefensePlatformSlot",
		"StagePlatformService.originForSlot",
		"platformOriginsFolderName",
		"CFrameValue",
		"OwnerUserId",
		"OwnerDisplayName",
		"ActiveStageId",
		"StagePlatformService.publishActiveStage",
		"Players.MaxPlayers",
		"CapacityMatchesSlotCount",
		"Players.PlayerAdded:Connect",
		"publishOwner(existing, player)",
		"StagewrightRuntimeStowed",
		"area.Parent = ServerStorage",
	}
do
	expectEqual(
		string.find(stagePlatformSource, platformMarker, 1, true) ~= nil,
		true,
		`six-platform allocator includes {platformMarker}`
	)
end
for _, multiRouteMarker in
	{
		"StageRuntimeService.spawnNodes",
		"StageLanes.index",
		"laneSequence",
	}
do
	expectEqual(
		string.find(stageRuntimeSource .. towerDefenseServiceSource, multiRouteMarker, 1, true) ~= nil,
		true,
		`server route runtime includes {multiRouteMarker}`
	)
end
expectEqual(
	string.find(stagePlatformSource, "center.CFrame:ToObjectSpace(firstOrigin.CFrame)", 1, true),
	nil,
	"runtime island origins no longer depend on the movable authoring platform"
)
local serverBootstrapSource = fs.readFile("src/server/init.server.luau")
expectEqual(
	string.find(serverBootstrapSource, "not StagePlatformService.hasPlatform(player)", 1, true) ~= nil,
	true,
	"players without an authoritative platform are rejected before profile load"
)
local stageGridRendererSource = fs.readFile("src/client/Controllers/StageGridRenderer.luau")
local gridRendererCompiles = pcall(function()
	luau.load(stageGridRendererSource)
end)
expectEqual(gridRendererCompiles, true, "six-grid renderer compiles as Luau")
for _, gridRendererMarker in
	{
		"StageCatalog.defaultStageId",
		"platformOriginsFolderName",
		"StagePath.sample",
		"laneProfile.offsets",
		"routePoint",
		"ActiveStageId",
		"StageCatalog.get(activeStageId)",
		"gridVisuals",
		"LocalTransparencyModifier",
		"Platform_",
		"otherPlatformFade",
		"TowerDefensePlatformSlot",
		"LocalOwner",
		"VisualFade",
		"StagewrightEditorOnly",
		"authoring.areaName",
		"outlines.folderName",
		"hideLegacyEditGridUi",
		'"edit grid"',
		"gridplatformeditor",
	}
do
	expectEqual(
		string.find(stageGridRendererSource, gridRendererMarker, 1, true) ~= nil,
		true,
		`six-grid renderer includes {gridRendererMarker}`
	)
end
for _, forbiddenGridRendererMarker in { 'Instance.new("SurfaceGui")', 'Instance.new("Frame")', ":Clone(" } do
	expectEqual(
		string.find(stageGridRendererSource, forbiddenGridRendererMarker, 1, true),
		nil,
		`six-grid renderer avoids runtime GUI cloning: {forbiddenGridRendererMarker}`
	)
end
local stageOwnerControllerSource = fs.readFile("src/client/Controllers/StagePlatformOwnerController.luau")
local stageOwnerControllerCompiles = pcall(function()
	luau.load(stageOwnerControllerSource)
end)
expectEqual(stageOwnerControllerCompiles, true, "platform owner marker controller compiles as Luau")
for _, ownerMarker in
	{
		"OwnerUserId",
		"OwnerDisplayName",
		"GetUserThumbnailAsync",
		"Enum.ThumbnailType.HeadShot",
		"rbxthumb://type=AvatarHeadShot",
		'card:IsA("CanvasGroup")',
		"YOUR PLATFORM",
		"WAITING FOR PLAYER",
		"platformOwnerMarkerHeight",
		"Players:GetPlayers",
		'GetAttributeChangedSignal("TowerDefensePlatformSlot")',
		"owner.DisplayName",
	}
do
	expectEqual(
		string.find(stageOwnerControllerSource, ownerMarker, 1, true) ~= nil,
		true,
		`platform owner display includes {ownerMarker}`
	)
end
for _, forbiddenOwnerMarker in { 'Instance.new("BillboardGui")', 'Instance.new("Frame")', ":Clone(" } do
	expectEqual(
		string.find(stageOwnerControllerSource, forbiddenOwnerMarker, 1, true),
		nil,
		`platform owner display uses authored GUI for {forbiddenOwnerMarker}`
	)
end
local ownerMarkersModel = fs.readFile("src/ui/StagePlatformOwners.model.json")
expectEqual(
	string.find(ownerMarkersModel, '"ClassName": "CanvasGroup"', 1, true) ~= nil,
	true,
	"platform owner cards support authored whole-card fading"
)
for slot = 1, 6 do
	expectEqual(
		string.find(ownerMarkersModel, `"Name": "Slot_{string.format("%02d", slot)}"`, 1, true) ~= nil,
		true,
		`platform owner UI authors slot {slot}`
	)
end
expectEqual(
	string.find(gridPatchProject, '"TemplateClient"', 1, true) ~= nil,
	true,
	"shared-place patch delivers the client grid renderer"
)
expectEqual(
	string.find(gridPatchProject, '"StagePlatformOwners"', 1, true) ~= nil,
	true,
	"shared-place patch delivers authored platform owner markers"
)
expectEqual(
	string.find(stagePlatformSource, "OnServerEvent", 1, true),
	nil,
	"platform allocation has no client-controlled remote"
)
expectEqual(
	string.find(towerDefenseServiceSource, "OnServerEvent", 1, true),
	nil,
	"tower defense service does not listen directly to client remotes"
)
expectEqual(
	string.find(towerDefenseServiceSource, "createEnemyPart", 1, true),
	nil,
	"server simulates scalar route state without enemy visual parts"
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
		"ActivateTowerStage",
		"TowerEnemies",
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

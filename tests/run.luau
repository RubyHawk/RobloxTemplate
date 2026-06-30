--!strict

local Calculations = require("../src/shared/Calculations")
local MigrationCore = require("../src/shared/MigrationCore")
local ReceiptLedger = require("../src/shared/ReceiptLedger")
local SessionLock = require("../src/server/Util/SessionLock")
local Store = require("../src/client/UI/Store")
local TableMerge = require("../src/shared/TableMerge")
local ProfileMigrationSteps = require("../src/shared/ProfileMigrationSteps")
local PackValidation = require("../src/shared/PackValidation")
local fs = require("@lune/fs")

local passed = 0

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
	passed += 1
end

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

local receipts = {}
expectEqual(ReceiptLedger.claim(receipts, "purchase"), true, "first receipt grants")
expectEqual(ReceiptLedger.claim(receipts, "purchase"), false, "duplicate receipt rejected")

-- ===== Reactive store (HUD data binding) =====
local store = Store.new()
expectEqual(store:get("missing.path", 42), 42, "store returns default for missing path")
store:set({ currencies = { coins = 100 } })
expectEqual(store:get("currencies.coins", 0), 100, "store reads nested value after set")
store:setLocal("local.health", 75)
expectEqual(store:get("local.health", 0), 75, "store reads client-local value")
store:set({ currencies = { coins = 250 } })
expectEqual(store:get("local.health", 0), 75, "store preserves local subtree across set")
expectEqual(store:get("currencies.coins", 0), 250, "store updates server value across set")
local observed: any = nil
local unsubscribe = store:subscribe("currencies.coins", function(value)
	observed = value
end)
expectEqual(observed, 250, "subscribe fires immediately with current value")
store:set({ currencies = { coins = 999 } })
expectEqual(observed, 999, "subscribe fires on set")
unsubscribe()
store:set({ currencies = { coins = 7 } })
expectEqual(observed, 999, "unsubscribe stops notifications")

-- ===== Theme deep merge =====
local mergeBase = { colors = { primary = "P", text = "T" }, radius = { small = 1 } }
local merged = TableMerge.deep(mergeBase, { colors = { primary = "X", accent = "A" } })
expectEqual(merged.colors.primary, "X", "deep merge overrides nested value")
expectEqual(merged.colors.text, "T", "deep merge keeps base nested value")
expectEqual(merged.colors.accent, "A", "deep merge adds override value")
expectEqual(merged.radius.small, 1, "deep merge keeps untouched subtree")
expectEqual(mergeBase.colors.primary, "P", "deep merge does not mutate base")

-- ===== Profile v1 -> v2 migration step =====
local upgradeV1 = { schemaVersion = 1, coins = 5000 }
ProfileMigrationSteps.v1ToV2(upgradeV1)
expectEqual(upgradeV1.currencies.coins, 5000, "v1->v2 seeds currencies from coins")
local keepV1 = { schemaVersion = 1, coins = 1, currencies = { coins = 999, gems = 3 } }
ProfileMigrationSteps.v1ToV2(keepV1)
expectEqual(keepV1.currencies.coins, 999, "v1->v2 does not clobber existing currencies")
expectEqual(keepV1.currencies.gems, 3, "v1->v2 preserves existing secondary currency")
local emptyV1 = { schemaVersion = 1 }
ProfileMigrationSteps.v1ToV2(emptyV1)
expectEqual(emptyV1.currencies.coins, 0, "v1->v2 defaults missing coins to 0")

local reconciledV2 = MigrationCore.migrate({
	schemaVersion = 1,
	coins = 50,
	currencies = { coins = 50 },
	legacyThing = "x",
}, {
	schemaVersion = 2,
	coins = 0,
	currencies = { coins = 0, gems = 0 },
	upgrades = {},
	progress = { rebirths = 0 },
}, 2)
expectEqual(reconciledV2.schemaVersion, 2, "reconcile stamps v2")
expectEqual(reconciledV2.coins, 50, "reconcile preserves coins")
expectEqual(reconciledV2.currencies.gems, 0, "reconcile adds missing secondary currency")
expectEqual(reconciledV2.progress.rebirths, 0, "reconcile adds progress section")
expectEqual(reconciledV2.legacyThing, "x", "reconcile preserves unknown data")

-- ===== Pack descriptor validation =====
local pool = { stat = 6, action = 4, progress = 2 }
local goodPack = {
	id = "demo",
	currencies = { { id = "coins", primary = true } },
	hud = {
		stats = { { slot = 1, path = "currencies.coins" }, { slot = 6, path = "x" } },
		progress = { { slot = 2, path = "p" } },
		actions = { { slot = 4, action = "OpenScreen", screen = "Profile" } },
	},
	screens = { "Profile" },
	navigation = { { screen = "Profile" } },
}
expectEqual((PackValidation.check(goodPack, pool)), true, "valid pack descriptor passes validation")
local badSlotPack = {
	id = "bad",
	currencies = { { id = "c", primary = true } },
	hud = { stats = { { slot = 7, path = "x" } }, actions = {} },
	screens = {},
	navigation = {},
}
expectEqual((PackValidation.check(badSlotPack, pool)), false, "stat slot out of pool range fails")
local noPrimaryPack = {
	id = "np",
	currencies = { { id = "c" } },
	hud = { stats = {}, actions = {} },
	screens = {},
	navigation = {},
}
expectEqual((PackValidation.check(noPrimaryPack, pool)), false, "missing primary currency fails")
local badNavPack = {
	id = "bn",
	currencies = { { id = "c", primary = true } },
	hud = { stats = {}, actions = {} },
	screens = { "Profile" },
	navigation = { { screen = "Store" } },
}
expectEqual((PackValidation.check(badNavPack, pool)), false, "nav to a disabled screen fails")

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

-- The UI pack layer binds a finite pool of PRE-AUTHORED slots; assert they exist.
for _, authoredPoolObject in
	{
		'"Name":"StatRail"',
		'"Name":"ProgressRail"',
		'"Name":"ActionRail"',
		'"Name":"StatWidget06"',
		'"Name":"ProgressBar02"',
		'"Name":"ActionSlot04"',
		'"Name":"CooldownFill"',
	}
do
	expectEqual(
		string.find(compactConnectedUi, authoredPoolObject, 1, true) ~= nil,
		true,
		`connected UI pre-authors {authoredPoolObject}`
	)
end

-- The pack HUD binders must populate authored slots, never construct GuiObjects.
for _, uiModulePath in
	{
		"src/client/UI/Store.luau",
		"src/client/UI/WidgetBinder.luau",
		"src/client/UI/ThemeProvider.luau",
		"src/client/UI/PackController.luau",
		"src/client/UI/VitalsFeeder.luau",
	}
do
	local moduleSource = fs.readFile(uiModulePath)
	for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
		expectEqual(
			string.find(moduleSource, forbiddenConstructor, 1, true),
			nil,
			`{uiModulePath} does not use {forbiddenConstructor}`
		)
	end
end

print(`{passed} pure Luau assertions passed`)

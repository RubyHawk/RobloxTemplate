--!strict

local Calculations = require("../src/shared/Calculations")
local MigrationCore = require("../src/shared/MigrationCore")
local ReceiptLedger = require("../src/shared/ReceiptLedger")
local SessionLock = require("../src/server/Util/SessionLock")
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

local audioConfig = fs.readFile("src/shared/TemplateConfig.luau")
for _, audioId in { "12221967", "12222054", "12222253", "12222170", "910988901", "12221976", "12222076" } do
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

print(`{passed} pure Luau assertions passed`)

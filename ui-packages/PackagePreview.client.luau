--!strict

-- Standalone visual behavior for games that do not have TemplateCore yet.
-- It only binds and populates authored instances; it never creates GUI objects.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local template = ReplicatedStorage:FindFirstChild("Template")
if template and template:FindFirstChild("Shared") then
	return
end

local screenGui = script.Parent
assert(screenGui:IsA("ScreenGui"), "PackagePreview must be inside the TemplateUI ScreenGui")
local root = screenGui:WaitForChild("Root") :: Frame
local screens = root:WaitForChild("Screens") :: Frame
local moreMenu = root:WaitForChild("MoreMenu") :: Frame
local navButtons = (root:WaitForChild("Navigation") :: Frame):WaitForChild("Buttons") :: ScrollingFrame
local toast = root:WaitForChild("Toast") :: Frame
local toastMessage = toast:WaitForChild("Message") :: TextLabel

local screenMap: { [string]: Frame } = {
	Inventory = screens:WaitForChild("InventoryScreen") :: Frame,
	Store = screens:WaitForChild("StoreScreen") :: Frame,
	Rewards = screens:WaitForChild("RewardsScreen") :: Frame,
	Profile = screens:WaitForChild("ProfileScreen") :: Frame,
	Settings = screens:WaitForChild("SettingsScreen") :: Frame,
	Feedback = screens:WaitForChild("FeedbackScreen") :: Frame,
	Codes = screens:WaitForChild("CodesScreen") :: Frame,
	Boards = screens:WaitForChild("BoardsScreen") :: Frame,
	Community = screens:WaitForChild("CommunityScreen") :: Frame,
}

local function closeScreens()
	for _, screen in screenMap do
		screen.Visible = false
	end
end

local function openScreen(name: string)
	closeScreens()
	moreMenu.Visible = false
	local screen = screenMap[name]
	if screen then
		screen.Visible = true
	end
end

local toastToken = 0
local function showToast(message: string)
	toastToken += 1
	local token = toastToken
	toastMessage.Text = message
	toast.Position = UDim2.new(0.5, 0, 0, 12)
	task.delay(2.5, function()
		if toastToken == token then
			toast.Position = UDim2.new(0.5, 0, 0, -180)
		end
	end)
end

local function setLabel(parent: Instance, name: string, value: string)
	local label = parent:WaitForChild(name)
	assert(label:IsA("TextLabel"), `{label:GetFullName()} must be a TextLabel`)
	label.Text = value
end

local navMap = {
	BagButton = "Inventory",
	ShopButton = "Store",
	GiftButton = "Rewards",
	ProfileButton = "Profile",
}
for buttonName, screenName in navMap do
	local button = navButtons:WaitForChild(buttonName) :: TextButton
	button.Activated:Connect(function()
		openScreen(screenName)
	end)
end

(navButtons:WaitForChild("MoreButton") :: TextButton).Activated:Connect(function()
	closeScreens()
	moreMenu.Visible = not moreMenu.Visible
end)

local moreButtons = moreMenu:WaitForChild("Buttons") :: ScrollingFrame
local moreMap = {
	CodesButton = "Codes",
	BoardsButton = "Boards",
	CommunityButton = "Community",
	FeedbackButton = "Feedback",
	SettingsButton = "Settings",
}
for buttonName, screenName in moreMap do
	local button = moreButtons:WaitForChild(buttonName) :: TextButton
	button.Activated:Connect(function()
		openScreen(screenName)
	end)
end

(moreMenu:WaitForChild("CloseButton") :: TextButton).Activated:Connect(function()
	moreMenu.Visible = false
end)

for _, screen in screenMap do
	(screen:WaitForChild("CloseButton") :: TextButton).Activated:Connect(closeScreens)
end

local hud = root:WaitForChild("CurrencyHUD") :: Frame
setLabel(hud, "CoinLabel", "12.5K")
setLabel(hud, "BoostLabel", "x2.00 BOOST  •  2 FRIENDS")(hud:WaitForChild("AddCoinsButton") :: TextButton).Activated:Connect(
	function()
		openScreen("Store")
	end
)

local function fillItemSlot(
	content: ScrollingFrame,
	slotName: string,
	title: string,
	body: string,
	quantity: string,
	glyph: string
)
	local slot = content:WaitForChild(slotName) :: Frame
	setLabel(slot, "Title", title)
	setLabel(slot, "Body", body)
	setLabel(slot, "Quantity", quantity)
	local artwork = slot:WaitForChild("Artwork") :: Frame
	setLabel(artwork, "Glyph", glyph)
	local action = slot:WaitForChild("ActionButton") :: TextButton
	action.Text = if string.find(slotName, "Store", 1, true) then "BUY" else "USE"
	action.Activated:Connect(function()
		showToast("Preview mode — add TemplateCore for live purchases and inventory")
	end)
	slot.Visible = true
end

local inventoryContent = screenMap.Inventory:WaitForChild("Content") :: ScrollingFrame
fillItemSlot(
	inventoryContent,
	"ItemSlot01",
	"Double Coins Potion",
	"Earn x2 Coins for 15 minutes.",
	"x3",
	"x2"
)
fillItemSlot(
	inventoryContent,
	"ItemSlot02",
	"Triple Coins Potion",
	"Earn x3 Coins for 10 minutes.",
	"x1",
	"x3"
)
fillItemSlot(inventoryContent, "ItemSlot03", "Starter Hammer", "A bright starter equipment item.", "x1", "H")

local storeContent = screenMap.Store:WaitForChild("Content") :: ScrollingFrame
fillItemSlot(
	storeContent,
	"StoreSlot01",
	"Double Coins Potion",
	"A quick boost for your next session.",
	"1K C",
	"x2"
)
fillItemSlot(
	storeContent,
	"StoreSlot02",
	"Triple Coins Potion",
	"The strongest temporary coin boost.",
	"2.5K C",
	"x3"
)
fillItemSlot(storeContent, "StoreSlot03", "Starter Hammer", "A useful starter equipment item.", "500 C", "H")

local rewardsContent = screenMap.Rewards:WaitForChild("Content") :: ScrollingFrame
for _, buttonName in { "ClaimDailyButton", "ClaimOfflineButton", "ExtendedOfflineButton" } do
	(rewardsContent:WaitForChild(buttonName) :: TextButton).Activated:Connect(function()
		showToast("Preview mode — rewards connect when TemplateCore is installed")
	end)
end

local profileContent = screenMap.Profile:WaitForChild("Content") :: ScrollingFrame
(profileContent:WaitForChild("SearchButton") :: TextButton).Activated:Connect(function()
	local result = profileContent:WaitForChild("SearchResult") :: Frame
	setLabel(result, "Title", "SamplePlayer (@sampleplayer)")
	setLabel(result, "Body", "12.5K Coins  •  24 joins")
end)

local settingsContent = screenMap.Settings:WaitForChild("Content") :: ScrollingFrame
for _, child in settingsContent:GetChildren() do
	if child:IsA("TextButton") then
		child.Activated:Connect(function()
			showToast("Preview setting — TemplateCore saves the real value")
		end)
	end
end

local feedbackContent = screenMap.Feedback:WaitForChild("Content") :: ScrollingFrame
(feedbackContent:WaitForChild("SubmitButton") :: TextButton).Activated:Connect(function()
	showToast("Preview feedback — TemplateCore securely stores real submissions")
end)

local codesContent = screenMap.Codes:WaitForChild("Content") :: ScrollingFrame
(codesContent:WaitForChild("RedeemButton") :: TextButton).Activated:Connect(function()
	showToast("Preview code — TemplateCore validates real codes on the server")
end)

local boardsContent = screenMap.Boards:WaitForChild("Content") :: ScrollingFrame
for index = 1, 3 do
	local row = boardsContent:WaitForChild(`LeaderRow{string.format("%02d", index)}`) :: Frame
	setLabel(row, "Title", `#{index}  SamplePlayer{index}`)
	setLabel(row, "Body", `{15 - index * 2}.5K Coins`)
	row.Visible = true
end
(boardsContent:WaitForChild("GlobalButton") :: TextButton).Activated:Connect(function()
	showToast("Preview leaderboard — TemplateCore loads live rankings")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		if moreMenu.Visible then
			moreMenu.Visible = false
		else
			closeScreens()
		end
	end
end)

closeScreens()
moreMenu.Visible = false
showToast("UI_BrightSimulator preview — install TemplateCore for live data")

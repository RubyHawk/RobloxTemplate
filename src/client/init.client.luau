--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local IconCatalog = require(Shared.IconCatalog)
local RemoteNames = require(Shared.RemoteNames)
local Theme = require(Shared.Theme)

type IconName = IconCatalog.IconName

local Controllers = script.Controllers
local AudioController = require(Controllers.AudioController)
local AfkController = require(Controllers.AfkController)
local NotificationController = require(Controllers.NotificationController)
local ResponsiveController = require(Controllers.ResponsiveController)
local StageEnemyRenderer = require(Controllers.StageEnemyRenderer)
local StageGridRenderer = require(Controllers.StageGridRenderer)
local StagePlatformOwnerController = require(Controllers.StagePlatformOwnerController)
local StageTowerRenderer = require(Controllers.StageTowerRenderer)
local UIFactory = require(script.UI.UIFactory)
local ScreenRegistry = require(script.UI.ScreenRegistry)
local Screens = require(script.UI.Screens)

StageGridRenderer.initialize()
StagePlatformOwnerController.initialize()

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local requestRemote = remotes:WaitForChild(RemoteNames.request) :: RemoteEvent
local stateRemote = remotes:WaitForChild(RemoteNames.state) :: RemoteEvent
local queryRemote = remotes:WaitForChild(RemoteNames.query) :: RemoteFunction

task.spawn(function()
	for _ = 1, 10 do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if success then
			break
		end
		task.wait(0.25)
	end
end)

local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("TemplateUI") :: ScreenGui
assert(screenGui:IsA("ScreenGui"), "StarterGui.TemplateUI must be a ScreenGui")
screenGui.Enabled = true

local root = screenGui:WaitForChild("Root") :: Frame
local showcaseCanvas = root:FindFirstChild("ShowcaseCanvas")
if showcaseCanvas and showcaseCanvas:IsA("GuiObject") then
	-- The source model is an editable WYSIWYG showroom. Gameplay only hides it;
	-- every connected screen and data slot remains a permanent StarterGui instance.
	showcaseCanvas.Visible = false
end
local uiScale = root:WaitForChild("InterfaceScale") :: UIScale
ResponsiveController.initialize(root, uiScale)
local hud = root:WaitForChild("CurrencyHUD") :: Frame
local currencyTray = root:WaitForChild("CurrencyTray", 10) :: Frame?
local currencySlots: { Frame } = {}
if currencyTray then
	hud.Visible = false
	local currencySlotsRoot = currencyTray:WaitForChild("Slots") :: ScrollingFrame
	for index = 1, 5 do
		table.insert(
			currencySlots,
			currencySlotsRoot:WaitForChild(`CurrencySlot{string.format("%02d", index)}`) :: Frame
		)
	end
else
	warn(
		"TemplateUI is missing CurrencyTray; rebuild the place from bootstrap.project.json to show all configured currencies"
	)
end
local boostLabel = (
	if currencyTray then currencyTray:WaitForChild("BoostLabel") else hud:WaitForChild("BoostLabel")
) :: TextLabel
local addCoinsButton = hud:WaitForChild("AddCoinsButton") :: TextButton
local nav = root:WaitForChild("Navigation") :: Frame
local navScroll = nav:WaitForChild("Buttons") :: ScrollingFrame
local moreMenu = root:WaitForChild("MoreMenu") :: Frame
local moreMenuButtons = moreMenu:WaitForChild("Buttons") :: ScrollingFrame
local moreCloseButton = moreMenu:WaitForChild("CloseButton") :: TextButton
local screensLayer = root:WaitForChild("Screens") :: Frame
local toast = root:WaitForChild("Toast") :: Frame
local toastLabel = toast:WaitForChild("Message") :: TextLabel
local toastToken = 0
local boostPanelInstance = root:FindFirstChild("BoostPanel")
local boostPanel: Frame? = if boostPanelInstance and boostPanelInstance:IsA("Frame")
	then boostPanelInstance
	else nil
local boostSummaryButton: TextButton? = nil
local boostDetails: Frame? = nil
if boostPanel then
	local summary = boostPanel:FindFirstChild("SummaryButton")
	local details = boostPanel:FindFirstChild("Details")
	if summary and summary:IsA("TextButton") and details and details:IsA("Frame") then
		boostSummaryButton = summary
		boostDetails = details
	end
end

local function applyIcon(container: Instance, name: IconName, imageName: string, fallbackName: string?)
	local image = container:FindFirstChild(imageName)
	if not image or not image:IsA("ImageLabel") then
		return
	end
	local content = IconCatalog.get(name)
	if content == "" then
		return
	end
	image.Image = content
	image.Visible = true
	if fallbackName then
		local fallback = container:FindFirstChild(fallbackName)
		if fallback and fallback:IsA("GuiObject") then
			fallback.Visible = false
		end
	end
end

applyIcon(hud:WaitForChild("CoinBadge"), "coin", "Icon", "Symbol")
applyIcon(toast:WaitForChild("IconBadge"), "notifications", "Icon", "Symbol")
applyIcon(moreCloseButton, "close", "Icon", nil)
if boostSummaryButton then
	applyIcon(boostSummaryButton, "potionX2", "Icon", nil)
end
if IconCatalog.get("close") ~= "" then
	moreCloseButton.Text = ""
end

if boostSummaryButton and boostDetails then
	local summaryButton = boostSummaryButton
	local details = boostDetails
	summaryButton.Activated:Connect(function()
		AudioController.play("click")
		details.Visible = not details.Visible
	end)
end

local function tweenInfo(duration: number, easingStyle: Enum.EasingStyle?): TweenInfo
	local adjustedDuration = if GuiService.ReducedMotionEnabled then 0 else duration
	return if easingStyle
		then TweenInfo.new(adjustedDuration, easingStyle)
		else TweenInfo.new(adjustedDuration)
end

local function showToast(message: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	TweenService:Create(toast, tweenInfo(0.2, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 12) })
		:Play()
	task.delay(3.5, function()
		if token == toastToken then
			TweenService:Create(toast, tweenInfo(0.2), { Position = UDim2.new(0.5, 0, 0, -180) }):Play()
		end
	end)
end

AudioController.initialize()
StageEnemyRenderer.initialize()
StageTowerRenderer.initialize()

local function optionalScreenGui(name: string): ScreenGui?
	local candidate = playerGui:FindFirstChild(name)
	return if candidate and candidate:IsA("ScreenGui") then candidate else nil
end

local function setupGalleryMenu()
	local galleryMenu = optionalScreenGui("GalleryMenu")
	if not galleryMenu then
		return
	end
	galleryMenu.Enabled = true

	local packShowroom = optionalScreenGui("ZxglyV5Showroom")
	local notificationShowroom = optionalScreenGui("NotificationV2Showroom")
	local backdrop = optionalScreenGui("GalleryBackdrop")
	local menuRoot = galleryMenu:WaitForChild("Root") :: Frame
	local toolbar = menuRoot:WaitForChild("Toolbar") :: Frame
	local modesFrame = toolbar:WaitForChild("Modes") :: Frame
	local modeCard = menuRoot:WaitForChild("ModeCard") :: Frame
	local description = modeCard:WaitForChild("Description") :: TextLabel

	local modes = {
		{
			name = "Connected",
			buttonName = "ConnectedButton",
			description = "Connected UI: the real HUD and systems. Use this to test the starter experience.",
			heading = "CONNECTED TEMPLATE UI",
			detail = "The real inventory, store, rewards, profiles, settings, and HUD.",
		},
		{
			name = "Pack",
			buttonName = "PackButton",
			description = "UI Pack: the editable Giga Simulator showroom. Every visible control is a StarterGui instance.",
			heading = "GIGA SIMULATOR UI PACK",
			detail = "Bright icon-driven HUD, shop, inventory, rewards, codes, settings, and boards.",
		},
		{
			name = "Notification",
			buttonName = "NotificationButton",
			description = "Notification: one isolated visual preview. Runtime messages still use secure template logic.",
			heading = "NOTIFICATION PREVIEW",
			detail = "Visual reference only; supplied third-party scripts were intentionally removed.",
		},
	}

	local buttons: { [string]: TextButton } = {}
	local function setMode(modeName: string)
		screenGui.Enabled = modeName == "Connected" or modeName == "Pack"
		if showcaseCanvas and showcaseCanvas:IsA("GuiObject") then
			showcaseCanvas.Visible = modeName == "Pack"
		end
		if packShowroom then
			packShowroom.Enabled = false
		end
		if notificationShowroom then
			notificationShowroom.Enabled = modeName == "Notification"
		end
		if backdrop then
			backdrop.Enabled = modeName ~= "Connected"
		end

		for _, mode in modes do
			local selected = mode.name == modeName
			buttons[mode.name].BackgroundColor3 = if selected
				then Theme.colors.primary
				else Theme.colors.surfaceRaised
			if selected then
				description.Text = mode.description
				if backdrop then
					local background = backdrop:WaitForChild("Background") :: Frame
					local heading = background:WaitForChild("Heading") :: TextLabel
					local detail = background:WaitForChild("Detail") :: TextLabel
					heading.Text = mode.heading
					detail.Text = mode.detail
				end
			end
		end
	end

	for _, mode in modes do
		local button = modesFrame:WaitForChild(mode.buttonName) :: TextButton
		local modeName = mode.name
		buttons[modeName] = button
		button.Activated:Connect(function()
			AudioController.play("click")
			setMode(modeName)
		end)
	end

	setMode("Connected")
end

setupGalleryMenu()
local registry = ScreenRegistry.new()
local state: any = nil
local towerPlacementRevision = -1
local latestTowerPlacements: any = {}

local function normalizedTowerPlacementRevision(value: any): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value >= 0
			and value % 1 == 0
		then value
		else 0
end

local function acceptTowerPlacements(records: any, revision: any): boolean
	local nextRevision = normalizedTowerPlacementRevision(revision)
	if nextRevision < towerPlacementRevision then
		return false
	end
	local nextPlacements = if type(records) == "table" then records else {}
	towerPlacementRevision = nextRevision
	latestTowerPlacements = nextPlacements
	StageTowerRenderer.apply(nextPlacements)
	if state ~= nil then
		state.towerPlacements = nextPlacements
		state.towerPlacementRevision = nextRevision
	end
	return true
end

local function request(action: string, payload: any, audioCue: string?)
	AudioController.play(audioCue or "click")
	requestRemote:FireServer({ action = action, payload = payload })
end

local function query(action: string, payload: any, audioCue: string?): any
	AudioController.play(audioCue or "click")
	local success, response = pcall(function()
		return queryRemote:InvokeServer(action, payload)
	end)
	return if success then response else { ok = false, message = "Server request failed" }
end

local binder = Screens.bind(screensLayer, {
	request = request,
	query = query,
	close = function()
		AudioController.play("click")
		registry:close()
	end,
	open = function(name: string)
		registry:open(name)
	end,
	toast = showToast,
	playAudio = AudioController.play,
	promptNotifications = function()
		AudioController.play("click")
		task.spawn(function()
			local _, message = NotificationController.prompt()
			showToast(message)
		end)
	end,
	promptProduct = function(productName: string)
		AudioController.play("click")
		if not state then
			return
		end
		local productId = state.productIds[productName]
		if type(productId) == "number" and productId > 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		else
			showToast("Product is not configured")
		end
	end,
	promptExtendedOffline = function()
		AudioController.play("click")
		if not state then
			return
		end
		local passId = state.productIds.extendedOffline
		if type(passId) == "number" and passId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, passId)
		else
			showToast("Game pass is not configured")
		end
	end,
	promptPremium = function()
		AudioController.play("click")
		MarketplaceService:PromptPremiumPurchase(player)
	end,
})

for name, screen in binder.screens do
	registry:register(name, screen)
end

local navItems = {
	{ "BagButton", "Inventory", "bag", "inventory" },
	{ "ShopButton", "Store", "shop", "click" },
	{ "GiftButton", "Rewards", "rewards", "click" },
	{ "ProfileButton", "Profile", "profile", "click" },
}
local navButtonsByScreen: { [string]: TextButton } = {}
for _, item in navItems do
	local button = navScroll:WaitForChild(item[1]) :: TextButton
	local screenName = item[2]
	local iconName = item[3] :: IconName
	local audioCue = item[4] :: string
	navButtonsByScreen[screenName] = button
	applyIcon(button:WaitForChild("IconBubble"), iconName, "PackIcon", "Icon")
	local restingColor = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(button, tweenInfo(0.12), { BackgroundColor3 = Theme.colors.surfaceRaised }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, tweenInfo(0.12), { BackgroundColor3 = restingColor }):Play()
	end)
	button.Activated:Connect(function()
		AudioController.play(audioCue)
		moreMenu.Visible = false
		if registry.current == screenName then
			registry:close()
		else
			registry:open(screenName)
		end
	end)
end

local moreButton = navScroll:WaitForChild("MoreButton") :: TextButton
applyIcon(moreButton:WaitForChild("IconBubble"), "more", "PackIcon", "Icon")
local moreButtonRestingColor = moreButton.BackgroundColor3
moreButton.MouseEnter:Connect(function()
	TweenService:Create(moreButton, tweenInfo(0.12), { BackgroundColor3 = Theme.colors.surfaceRaised }):Play()
end)
moreButton.MouseLeave:Connect(function()
	TweenService:Create(moreButton, tweenInfo(0.12), { BackgroundColor3 = moreButtonRestingColor }):Play()
end)
moreButton.Activated:Connect(function()
	AudioController.play("click")
	registry:close()
	moreMenu.Visible = not moreMenu.Visible
end)

moreCloseButton.Activated:Connect(function()
	AudioController.play("click")
	moreMenu.Visible = false
end)

addCoinsButton.Activated:Connect(function()
	AudioController.play("click")
	moreMenu.Visible = false
	if registry.current == "Store" then
		registry:close()
	else
		registry:open("Store")
	end
end)

local moreItems = {
	{ "CodesButton", "Codes", "codes" },
	{ "BoardsButton", "Boards", "leaderboard" },
	{ "CommunityButton", "Community", "community" },
	{ "FeedbackButton", "Feedback", "feedback" },
	{ "SettingsButton", "Settings", "settings" },
}
local moreButtonsByScreen: { [string]: TextButton } = {}
for _, item in moreItems do
	local button = moreMenuButtons:WaitForChild(item[1]) :: TextButton
	local screenName = item[2]
	local iconName = item[3] :: IconName
	moreButtonsByScreen[screenName] = button
	applyIcon(button, iconName, "Icon", "Fallback")
	local restingColor = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(button, tweenInfo(0.12), { BackgroundColor3 = Theme.colors.surfaceRaised }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, tweenInfo(0.12), { BackgroundColor3 = restingColor }):Play()
	end)
	button.Activated:Connect(function()
		AudioController.play("click")
		moreMenu.Visible = false
		registry:open(screenName)
	end)
end

local function applyState(nextState: any)
	if nextState == nil or nextState.profile == nil then
		return
	end
	if not acceptTowerPlacements(nextState.towerPlacements, nextState.towerPlacementRevision) then
		nextState.towerPlacements = latestTowerPlacements
		nextState.towerPlacementRevision = towerPlacementRevision
	end
	local definitions = if type(nextState.currencyDefinitions) == "table"
		then nextState.currencyDefinitions
		else {}
	local balances = if type(nextState.profile.currencies) == "table"
		then nextState.profile.currencies
		else {}
	local primaryId = if definitions[1] then definitions[1].id else "coins"
	local previousPrimary = if state
			and state.profile
			and type(state.profile.currencies) == "table"
		then state.profile.currencies[primaryId] or state.profile.coins
		else balances[primaryId] or nextState.profile.coins
	state = nextState
	for index, slot in currencySlots do
		local definition = definitions[index]
		slot.Visible = definition ~= nil
		if definition then
			local amount = slot:WaitForChild("AmountLabel") :: TextLabel
			local caption = slot:WaitForChild("Caption") :: TextLabel
			local symbol = slot:WaitForChild("Symbol") :: TextLabel
			local icon = slot:WaitForChild("Icon") :: ImageLabel
			local accent = slot:WaitForChild("Accent") :: Frame
			amount.Text = UIFactory.formatNumber(balances[definition.id] or 0)
			caption.Text = string.upper(definition.name)
			symbol.Text = definition.symbol
			local hasIcon = definition.iconAssetId ~= ""
			symbol.Visible = not hasIcon
			icon.Image = if hasIcon
				then `rbxthumb://type=Asset&id={definition.iconAssetId}&w=150&h=150`
				else ""
			icon.Visible = hasIcon
			local color = definition.color
			if type(color) == "table" then
				accent.BackgroundColor3 = Color3.fromRGB(color[1] or 255, color[2] or 202, color[3] or 10)
			end
		end
	end
	local legacyCoinLabel = hud:FindFirstChild("CoinLabel")
	if legacyCoinLabel and legacyCoinLabel:IsA("TextLabel") then
		legacyCoinLabel.Text = UIFactory.formatNumber(balances[primaryId] or state.profile.coins or 0)
	end
	local runeMultiplier = if type(state.runeMultiplier) == "number" then state.runeMultiplier else 1
	local channelMultiplier = if type(state.channelMultiplier) == "number" then state.channelMultiplier else 1
	-- Strongest temporary boost (potion vs channel surge, never stacked);
	-- older servers only send potionMultiplier.
	local temporaryMultiplier = if type(state.temporaryMultiplier) == "number"
		then state.temporaryMultiplier
		else state.potionMultiplier
	local totalBoost = (1 + state.friendBonus + state.premiumBonus) * temporaryMultiplier * runeMultiplier
	boostLabel.Text =
		`x{string.format("%.2f", totalBoost)} BOOST  •  {state.profile.social.friendCountInServer} FRIENDS`
	if boostSummaryButton and boostDetails then
		local value = boostSummaryButton:FindFirstChild("Value")
		if value and value:IsA("TextLabel") then
			value.Text = `x{string.format("%.2f", totalBoost)}`
		end
		local detailValues = {
			FriendsValue = `+{math.round(state.friendBonus * 100)}%`,
			PremiumValue = `+{math.round(state.premiumBonus * 100)}%`,
			PotionValue = `x{string.format("%.2f", state.potionMultiplier)}`,
			-- Presets may pre-author RunesValue/ChannelValue labels; packs
			-- without them simply skip those rows below.
			RunesValue = `x{string.format("%.2f", runeMultiplier)}`,
			ChannelValue = `x{string.format("%.2f", channelMultiplier)}`,
			TotalValue = `x{string.format("%.2f", totalBoost)}`,
		}
		for name, text in detailValues do
			local label = boostDetails:FindFirstChild(name)
			if label and label:IsA("TextLabel") then
				label.Text = text
			end
		end
	end
	ResponsiveController.setPlayerScale(state.profile.settings.uiScale)
	AudioController.applySettings(state.profile.settings)
	if (balances[primaryId] or state.profile.coins) > previousPrimary then
		AudioController.play("cash")
	end
	local features = state.features
	if type(features) == "table" then
		navButtonsByScreen.Inventory.Visible = features.inventory ~= false
		navButtonsByScreen.Store.Visible = features.store ~= false
		navButtonsByScreen.Rewards.Visible = features.dailyRewards ~= false
			or features.offlineEarnings ~= false
		navButtonsByScreen.Profile.Visible = features.profiles ~= false
		moreButtonsByScreen.Codes.Visible = features.codes ~= false
		moreButtonsByScreen.Boards.Visible = features.leaderboards ~= false
		moreButtonsByScreen.Community.Visible = features.communityVerification ~= false
		moreButtonsByScreen.Feedback.Visible = features.feedback ~= false
		moreButtonsByScreen.Settings.Visible = features.settings ~= false
	end
	AfkController.setEnabled(state.profile.settings.afKRollOver)
	StageEnemyRenderer.apply(state.towerDefense)
	binder.apply(state)
end

stateRemote.OnClientEvent:Connect(function(packet)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "Snapshot" then
		applyState(packet.data)
	elseif packet.kind == "TowerEnemies" then
		StageEnemyRenderer.apply(packet.data)
		if state ~= nil then
			state.towerDefense = packet.data
			binder.apply(state)
		end
	elseif packet.kind == "TowerPlacements" then
		acceptTowerPlacements(packet.data, packet.revision)
	elseif packet.kind == "Result" then
		showToast(packet.message or if packet.ok then "Done" else "Request failed")
		if packet.ok then
			AudioController.play("reward")
		end
	elseif packet.kind == "Announcement" and state and state.profile.settings.announcements then
		AudioController.play("notification")
		showToast(packet.message)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local systemChannel = if channels then channels:FindFirstChild("RBXSystem") else nil
		if systemChannel and systemChannel:IsA("TextChannel") then
			systemChannel:DisplaySystemMessage(`[SYSTEM] {packet.message}`)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
		if moreMenu.Visible then
			moreMenu.Visible = false
		else
			registry:close()
		end
	end
end)

AfkController.initialize(function()
	request("AfkRollover", {}, "")
end, showToast)

task.spawn(function()
	for _ = 1, 30 do
		local response = query("InitialState", {}, "")
		if response.ok and response.data then
			applyState(response.data)
			return
		end
		task.wait(1)
	end
	showToast("Profile did not load. Rejoin to retry.")
end)

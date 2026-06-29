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
local UIFactory = require(script.UI.UIFactory)
local UIStyles = require(script.UI.UIStyles)
local ScreenRegistry = require(script.UI.ScreenRegistry)
local Screens = require(script.UI.Screens)

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
UIStyles.install(screenGui)

local root = screenGui:WaitForChild("Root") :: Frame
local uiScale = root:WaitForChild("InterfaceScale") :: UIScale
local hud = root:WaitForChild("CurrencyHUD") :: Frame
local coinLabel = hud:WaitForChild("CoinLabel") :: TextLabel
local boostLabel = hud:WaitForChild("BoostLabel") :: TextLabel
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
if IconCatalog.get("close") ~= "" then
	moreCloseButton.Text = ""
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

local function optionalScreenGui(name: string): ScreenGui?
	local candidate = playerGui:FindFirstChild(name)
	return if candidate and candidate:IsA("ScreenGui") then candidate else nil
end

local function ensureGalleryScreen(name: string): ScreenGui?
	local existing = optionalScreenGui(name)
	if existing then
		return existing
	end
	local source = StarterGui:FindFirstChild(name)
	if source and source:IsA("ScreenGui") then
		local clone = source:Clone()
		clone.Parent = playerGui
		return clone
	end
	return nil
end

local function setupGalleryMenu()
	local galleryMenu = ensureGalleryScreen("GalleryMenu")
	if not galleryMenu then
		return
	end
	galleryMenu.Enabled = true

	local packShowroom = ensureGalleryScreen("ZxglyV5Showroom")
	local notificationShowroom = ensureGalleryScreen("NotificationV2Showroom")
	local backdrop = ensureGalleryScreen("GalleryBackdrop")
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
			description = "UI Pack: a script-free component sheet. Edit ZxglyV5Showroom under StarterGui.",
			heading = "VISUAL UI PACK",
			detail = "Script-free reference screens arranged as one isolated component sheet.",
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
		screenGui.Enabled = modeName == "Connected"
		if packShowroom then
			packShowroom.Enabled = modeName == "Pack"
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

local function request(action: string, payload: any)
	AudioController.play("click")
	requestRemote:FireServer({ action = action, payload = payload })
end

local function query(action: string, payload: any): any
	local success, response = pcall(function()
		return queryRemote:InvokeServer(action, payload)
	end)
	return if success then response else { ok = false, message = "Server request failed" }
end

local rebuildScreens: () -> ()

local function context(): any
	return {
		state = state,
		request = request,
		query = query,
		close = function()
			registry:close()
		end,
		toast = showToast,
		promptNotifications = function()
			task.spawn(function()
				local _, message = NotificationController.prompt()
				showToast(message)
			end)
		end,
		promptProduct = function(productName: string)
			local productId = state.productIds[productName]
			if type(productId) == "number" and productId > 0 then
				MarketplaceService:PromptProductPurchase(player, productId)
			else
				showToast("Product is not configured")
			end
		end,
		promptExtendedOffline = function()
			local passId = state.productIds.extendedOffline
			if type(passId) == "number" and passId > 0 then
				MarketplaceService:PromptGamePassPurchase(player, passId)
			else
				showToast("Game pass is not configured")
			end
		end,
		promptPremium = function()
			MarketplaceService:PromptPremiumPurchase(player)
		end,
		showList = function(title: string, rows: { any })
			local dynamic = registry.screens.Dynamic
			if dynamic then
				dynamic:Destroy()
			end
			registry:register("Dynamic", Screens.simpleList(screensLayer, context(), title, rows))
			registry:open("Dynamic")
		end,
	}
end

rebuildScreens = function()
	local current = registry.current
	registry:destroy()
	registry = ScreenRegistry.new()
	local ctx = context()
	registry:register("Inventory", Screens.inventory(screensLayer, ctx))
	registry:register("Store", Screens.store(screensLayer, ctx))
	registry:register("Rewards", Screens.rewards(screensLayer, ctx))
	registry:register("Profile", Screens.profile(screensLayer, ctx))
	registry:register("Settings", Screens.settings(screensLayer, ctx))
	registry:register("Feedback", Screens.feedback(screensLayer, ctx))
	registry:register("Codes", Screens.codes(screensLayer, ctx))
	registry:register("Boards", Screens.leaderboards(screensLayer, ctx))
	registry:register("Community", Screens.verification(screensLayer, ctx))
	if current and registry.screens[current] then
		registry:open(current)
	end
end

local navItems = {
	{ "BagButton", "Inventory", "bag" },
	{ "ShopButton", "Store", "shop" },
	{ "GiftButton", "Rewards", "rewards" },
	{ "ProfileButton", "Profile", "profile" },
}
for _, item in navItems do
	local button = navScroll:WaitForChild(item[1]) :: TextButton
	local screenName = item[2]
	local iconName = item[3] :: IconName
	applyIcon(button:WaitForChild("IconBubble"), iconName, "PackIcon", "Icon")
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
for _, item in moreItems do
	local button = moreMenuButtons:WaitForChild(item[1]) :: TextButton
	local screenName = item[2]
	local iconName = item[3] :: IconName
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
	local previousCoins = if state and state.profile then state.profile.coins else nextState.profile.coins
	state = nextState
	coinLabel.Text = UIFactory.formatNumber(state.profile.coins)
	boostLabel.Text = `x{string.format(
		"%.2f",
		(1 + state.friendBonus + state.premiumBonus) * state.potionMultiplier
	)} BOOST  •  {state.profile.social.friendCountInServer} FRIENDS`
	uiScale.Scale = state.profile.settings.uiScale
	AudioController.applySettings(state.profile.settings)
	if state.profile.coins > previousCoins then
		AudioController.play("cash")
	end
	AfkController.setEnabled(state.profile.settings.afKRollOver)
	rebuildScreens()
end

stateRemote.OnClientEvent:Connect(function(packet)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "Snapshot" then
		applyState(packet.data)
	elseif packet.kind == "Result" then
		showToast(packet.message or if packet.ok then "Done" else "Request failed")
		if packet.ok then
			AudioController.play("reward")
		end
	elseif packet.kind == "Announcement" and state and state.profile.settings.announcements then
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
	request("AfkRollover", {})
end, showToast)

task.spawn(function()
	for _ = 1, 30 do
		local response = query("InitialState", {})
		if response.ok and response.data then
			applyState(response.data)
			return
		end
		task.wait(1)
	end
	showToast("Profile did not load. Rejoin to retry.")
end)

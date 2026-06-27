--!strict

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local RemoteNames = require(Shared.RemoteNames)
local Theme = require(Shared.Theme)

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

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TemplateUI"
screenGui.DisplayOrder = 20
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
end)
screenGui.Parent = player:WaitForChild("PlayerGui")
UIStyles.install(screenGui)

local root = UIFactory.frame(screenGui, "Root", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
})
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local hud = UIFactory.card(root, "CurrencyHUD", {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(240, 60),
	BackgroundColor3 = Theme.colors.background,
	ZIndex = 5,
})
local coinLabel = UIFactory.label(hud, "◆ 0 Coins", {
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 27),
	FontFace = Theme.fontBold,
	TextColor3 = Theme.colors.accent,
	TextSize = 20,
	ZIndex = 6,
})
local boostLabel = UIFactory.label(hud, "x1 boost", {
	Position = UDim2.fromOffset(14, 34),
	Size = UDim2.new(1, -28, 0, 18),
	TextColor3 = Theme.colors.textMuted,
	TextSize = 13,
	ZIndex = 6,
})

local nav = UIFactory.card(root, "Navigation", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(0.94, 0, 0, 64),
	BackgroundColor3 = Theme.colors.background,
	ZIndex = 10,
})
local navConstraint = Instance.new("UISizeConstraint")
navConstraint.MaxSize = Vector2.new(860, 64)
navConstraint.Parent = nav
local navScroll = UIFactory.scroll(nav, "Buttons", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 1, -16),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 0,
	CanvasSize = UDim2.new(),
})
local navLayout = UIFactory.list(navScroll, 8)
navLayout.FillDirection = Enum.FillDirection.Horizontal
navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

local screensLayer = UIFactory.frame(root, "Screens", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 20,
})
local toast = UIFactory.card(root, "Toast", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -90),
	Size = UDim2.new(0.8, 0, 0, 62),
	BackgroundColor3 = Theme.colors.background,
	ZIndex = 100,
})
local toastConstraint = Instance.new("UISizeConstraint")
toastConstraint.MaxSize = Vector2.new(560, 62)
toastConstraint.Parent = toast
local toastLabel = UIFactory.label(toast, "", {
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 1, -16),
	TextXAlignment = Enum.TextXAlignment.Center,
	FontFace = Theme.fontBold,
	ZIndex = 101,
})
local toastToken = 0

local function showToast(message: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	TweenService
		:Create(toast, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 12) })
		:Play()
	task.delay(3.5, function()
		if token == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
		end
	end)
end

AudioController.initialize()
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
	{ "BAG", "Inventory" },
	{ "SHOP", "Store" },
	{ "GIFT", "Rewards" },
	{ "PROFILE", "Profile" },
	{ "CODES", "Codes" },
	{ "TOP", "Boards" },
	{ "FEEDBACK", "Feedback" },
	{ "GROUP", "Community" },
	{ "SETTINGS", "Settings" },
}
for _, item in navItems do
	UIFactory.button(navScroll, item[1], function()
		AudioController.play("click")
		if registry.current == item[2] then
			registry:close()
		else
			registry:open(item[2])
		end
	end, { Size = UDim2.fromOffset(100, 48) })
end

local function applyState(nextState: any)
	if nextState == nil or nextState.profile == nil then
		return
	end
	local previousCoins = if state and state.profile then state.profile.coins else nextState.profile.coins
	state = nextState
	coinLabel.Text = `◆ {UIFactory.formatNumber(state.profile.coins)} Coins`
	boostLabel.Text = `x{string.format(
		"%.2f",
		(1 + state.friendBonus + state.premiumBonus) * state.potionMultiplier
	)} total • {state.profile.social.friendCountInServer} friends`
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
		local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(`[SYSTEM] {packet.message}`)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
		registry:close()
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

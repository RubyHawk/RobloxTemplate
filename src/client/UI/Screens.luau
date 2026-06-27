--!strict

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Theme = require(Shared.Theme)
local UIFactory = require(script.Parent.UIFactory)

local Screens = {}

local function base(parent: Instance, title: string, close: () -> ()): (Frame, ScrollingFrame)
	local root = UIFactory.card(parent, `{title}Screen`, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.9, 0.76),
		BackgroundColor3 = Theme.colors.surface,
		ZIndex = 20,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(280, 220)
	constraint.MaxSize = Vector2.new(760, 620)
	constraint.Parent = root

	UIFactory.label(root, title, {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -80, 0, 44),
		FontFace = Theme.fontBold,
		TextSize = 26,
	})
	UIFactory.button(root, "X", close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.colors.danger,
		TextSize = 24,
	})
	local content = UIFactory.scroll(root, "Content", {
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.new(1, -32, 1, -84),
		ZIndex = 21,
	})
	UIFactory.addPadding(content, 4)
	UIFactory.list(content, 10)
	return root, content
end

local function row(parent: Instance, title: string, body: string): Frame
	local card = UIFactory.card(parent, title, {
		Size = UDim2.new(1, -8, 0, 82),
		BackgroundColor3 = Theme.colors.surfaceRaised,
	})
	UIFactory.label(card, title, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 28),
		FontFace = Theme.fontBold,
	})
	UIFactory.label(card, body, {
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 38),
		TextColor3 = Theme.colors.textMuted,
		TextSize = 14,
	})
	return card
end

function Screens.inventory(parent: Instance, context: any): Frame
	local root, content = base(parent, "Inventory", context.close)
	local entries = context.state.profile.inventory
	local anyItem = false
	for itemId, entry in entries do
		if entry.quantity > 0 then
			anyItem = true
			local definition = context.state.catalog[itemId]
			if definition then
				local card = row(content, `{definition.name}  ×{entry.quantity}`, definition.description)
				local action = if definition.category == "Consumable" then "UseItem" else "ToggleEquip"
				local label = if definition.category == "Consumable"
					then "USE"
					else if entry.equipped then "UNEQUIP" else "EQUIP"
				UIFactory.button(card, label, function()
					context.request(action, { itemId = itemId })
				end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(106, 44),
				})
			end
		end
	end
	if not anyItem then
		row(content, "Inventory empty", "Items and consumables appear here.")
	end
	return root
end

function Screens.store(parent: Instance, context: any): Frame
	local root, content = base(parent, "Store", context.close)
	for itemId, definition in context.state.catalog do
		if definition.priceCoins then
			local card =
				row(content, definition.name, `{definition.description}  •  {definition.priceCoins} Coins`)
			UIFactory.button(card, "BUY", function()
				context.request("BuyItem", { itemId = itemId })
			end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(92, 44),
				BackgroundColor3 = Theme.colors.success,
			})
		end
	end
	if context.state.productAvailability.coinPackSmall then
		local card = row(content, "Small Coins Pack", "Direct developer product; Roblox confirms the price.")
		UIFactory.button(card, "ROBUX", function()
			context.promptProduct("coinPackSmall")
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(92, 44),
		})
	else
		row(content, "Robux products", "Disabled until product IDs are configured in TemplateConfig.")
	end
	if context.state.productAvailability.coinPackLarge then
		local card = row(content, "Large Coins Pack", "Direct developer product; Roblox confirms the price.")
		UIFactory.button(card, "ROBUX", function()
			context.promptProduct("coinPackLarge")
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(92, 44),
		})
	end
	local premiumText = if context.state.profile.entitlements.premium
		then "Active: permanent +10% Coins bonus."
		else "Roblox Premium members receive a permanent +10% Coins bonus."
	local premiumCard = row(content, "Roblox Premium", premiumText)
	if not context.state.profile.entitlements.premium then
		UIFactory.button(premiumCard, "VIEW", context.promptPremium, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(92, 44),
		})
	end
	return root
end

function Screens.rewards(parent: Instance, context: any): Frame
	local root, content = base(parent, "Rewards", context.close)
	row(
		content,
		`Daily streak: Day {context.state.profile.daily.streak}`,
		"Claims reset at midnight UTC. Missing a day resets the streak."
	)
	UIFactory.button(content, "CLAIM DAILY REWARD", function()
		context.request("ClaimDaily", {})
	end)
	local pending = context.state.offline
	row(
		content,
		"Offline earnings",
		`{UIFactory.formatNumber(pending.amount)} Coins ready from {math.floor(pending.elapsed / 60)} minutes.`
	)
	UIFactory.button(content, "CLAIM OFFLINE EARNINGS", function()
		context.request("ClaimOffline", {})
	end, { BackgroundColor3 = Theme.colors.success })
	if
		context.state.productAvailability.extendedOffline
		and not context.state.profile.entitlements.extendedOffline
	then
		UIFactory.button(content, "EXTEND OFFLINE CAP TO 12 HOURS", context.promptExtendedOffline)
	end
	return root
end

function Screens.profile(parent: Instance, context: any): Frame
	local root, content = base(parent, "Player Profile", context.close)
	local profile = context.state.profile
	row(
		content,
		Players.LocalPlayer.DisplayName,
		`Coins: {UIFactory.formatNumber(profile.coins)}  •  Joins: {profile.stats.joins}  •  Playtime: {math.floor(
			profile.stats.playSeconds / 60
		)}m`
	)
	local input = UIFactory.textBox(content, "Exact Roblox username")
	local resultLabel = UIFactory.label(content, "Search displays whitelisted public stats only.", {
		Size = UDim2.new(1, -8, 0, 54),
		TextColor3 = Theme.colors.textMuted,
	})
	UIFactory.button(content, "SEARCH PLAYER", function()
		resultLabel.Text = "Searching…"
		task.spawn(function()
			local response = context.query("SearchProfile", { username = input.Text })
			if response.ok and response.data then
				local found = response.data
				resultLabel.Text = `{found.displayName} (@{found.username}) • {UIFactory.formatNumber(
					found.coins
				)} Coins • {found.joins} joins`
			else
				resultLabel.Text = response.message or "Player was not found"
			end
		end)
	end)
	return root
end

function Screens.settings(parent: Instance, context: any): Frame
	local root, content = base(parent, "Settings", context.close)
	local settings = context.state.profile.settings
	local function toggle(label: string, key: string, value: boolean)
		UIFactory.button(content, `{label}: {if value then "ON" else "OFF"}`, function()
			if key == "notifications" and not value then
				context.promptNotifications()
			end
			context.request("UpdateSetting", { key = key, value = not value })
		end)
	end
	toggle("Reduced motion", "reducedMotion", settings.reducedMotion)
	toggle("Announcements", "announcements", settings.announcements)
	toggle("AFK rollover", "afKRollOver", settings.afKRollOver)
	toggle("Roblox reminders", "notifications", settings.notifications)
	UIFactory.button(content, `Music: {math.floor(settings.musicVolume * 100)}%`, function()
		context.request(
			"UpdateSetting",
			{ key = "musicVolume", value = (settings.musicVolume + 0.25) % 1.25 }
		)
	end)
	UIFactory.button(content, `SFX: {math.floor(settings.sfxVolume * 100)}%`, function()
		context.request("UpdateSetting", { key = "sfxVolume", value = (settings.sfxVolume + 0.25) % 1.25 })
	end)
	UIFactory.button(content, `UI Scale: {math.floor(settings.uiScale * 100)}%`, function()
		local nextScale = settings.uiScale + 0.1
		if nextScale > 1.2 then
			nextScale = 0.8
		end
		context.request("UpdateSetting", { key = "uiScale", value = nextScale })
	end)
	row(
		content,
		"Project defaults",
		"Streaming enabled; native chat enabled; HTTP, paid products, Discord, and live DataStores disabled until configured."
	)
	return root
end

function Screens.feedback(parent: Instance, context: any): Frame
	local root, content = base(parent, "Feedback & Bug Report", context.close)
	local categories = { "Bug", "Feedback", "Accessibility", "Other" }
	local categoryIndex = 1
	local categoryButton = UIFactory.button(content, "Category: Bug", nil)
	categoryButton.Activated:Connect(function()
		categoryIndex = (categoryIndex % #categories) + 1
		categoryButton.Text = `Category: {categories[categoryIndex]}`
	end)
	local input = UIFactory.textBox(content, "Describe the issue (3–500 characters)", {
		MultiLine = true,
		Size = UDim2.new(1, -8, 0, 140),
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	UIFactory.button(content, "SUBMIT", function()
		context.request("SubmitFeedback", { category = categories[categoryIndex], message = input.Text })
	end, { BackgroundColor3 = Theme.colors.success })
	return root
end

function Screens.codes(parent: Instance, context: any): Frame
	local root, content = base(parent, "Likes & Codes", context.close)
	local likes = context.state.likes
	row(
		content,
		`Likes: {UIFactory.formatNumber(likes.value or 0)}`,
		likes.reason or "Thanks for supporting the experience!"
	)
	for _, milestone in context.state.likesMilestones do
		local unlocked = (likes.value or 0) >= milestone.likes
		local detail = if unlocked
			then `{milestone.label} - Code: {milestone.code}`
			else `{milestone.label} - Locked`
		row(content, `{milestone.likes} Likes`, detail)
	end
	local input = UIFactory.textBox(content, "Enter code")
	UIFactory.button(content, "REDEEM CODE", function()
		context.request("RedeemCode", { code = input.Text })
	end)
	return root
end

local function leaderboardRows(content: Instance, rows: { any })
	for index, entry in rows do
		row(content, `#{entry.rank or index}  {entry.name}`, `{UIFactory.formatNumber(entry.value)} Coins`)
	end
	if #rows == 0 then
		row(content, "No players yet", "Leaderboard data appears after profiles load.")
	end
end

function Screens.leaderboards(parent: Instance, context: any): Frame
	local root, content = base(parent, "Leaderboards", context.close)
	UIFactory.label(content, "CURRENT SERVER", { Size = UDim2.new(1, -8, 0, 32), FontFace = Theme.fontBold })
	leaderboardRows(content, context.state.serverLeaderboard)
	UIFactory.button(content, "LOAD GLOBAL TOP 50", function()
		task.spawn(function()
			local response = context.query("GlobalLeaderboard", {})
			if response.ok and response.data then
				context.showList("Global Leaderboard", response.data)
			else
				context.toast(response.message or "Global leaderboard unavailable")
			end
		end)
	end)
	return root
end

function Screens.verification(parent: Instance, context: any): Frame
	local root, content = base(parent, "Community", context.close)
	local availability = context.state.integrationAvailability
	row(
		content,
		"Roblox Community",
		if availability.community
			then "Verification is enabled."
			else "Disabled until a community ID is configured."
	)
	row(
		content,
		"Discord",
		"Verification is scaffolded but disabled. Community link is available on the experience page after setup."
	)
	row(
		content,
		"Guilds / Clans",
		if availability.guilds then "Enabled" else "Provider contract reserved; no guild data is active."
	)
	return root
end

function Screens.simpleList(parent: Instance, context: any, title: string, rows: { any }): Frame
	local root, content = base(parent, title, context.close)
	leaderboardRows(content, rows)
	return root
end

return Screens

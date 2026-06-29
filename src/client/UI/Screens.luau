--!strict

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local IconCatalog = require(Shared.IconCatalog)
local Theme = require(Shared.Theme)
local UIFactory = require(script.Parent.UIFactory)

type IconName = IconCatalog.IconName

local Screens = {}

local function applyIcon(container: Instance, name: IconName)
	local icon = container:FindFirstChild("Icon")
	if not icon or not icon:IsA("ImageLabel") then
		return
	end
	local content = IconCatalog.get(name)
	if content == "" then
		return
	end
	icon.Image = content
	icon.Visible = true
	local fallback = container:FindFirstChild("Symbol") or container:FindFirstChild("Fallback")
	if fallback and fallback:IsA("GuiObject") then
		fallback.Visible = false
	end
end

local function authoredTemplate(parent: Instance, name: string, className: string): Instance
	local screenGui = parent:FindFirstAncestorWhichIsA("ScreenGui")
	local root = if screenGui then screenGui:FindFirstChild("Root") else nil
	local templates = if root then root:FindFirstChild("ComponentTemplates") else nil
	local template = if templates then templates:FindFirstChild(name) else nil
	assert(
		template and template.ClassName == className,
		`TemplateUI.Root.ComponentTemplates.{name} must be a {className}`
	)
	return template
end

local function base(parent: Instance, title: string, close: () -> ()): (Frame, ScrollingFrame)
	local template = parent.Parent and parent.Parent:FindFirstChild("ScreenTemplate")
	assert(template and template:IsA("Frame"), "TemplateUI.Root.ScreenTemplate must be a Frame")

	local root = template:Clone()
	root.Name = `{title}Screen`
	root.Visible = true
	local titleLabel = root:WaitForChild("Title") :: TextLabel
	titleLabel.Text = title
	local closeButton = root:WaitForChild("CloseButton") :: TextButton
	applyIcon(closeButton, "close")
	if IconCatalog.get("close") ~= "" then
		closeButton.Text = ""
	end
	closeButton.Activated:Connect(close)
	local content = root:WaitForChild("Content") :: ScrollingFrame
	root.Parent = parent
	return root, content
end

local function row(parent: Instance, title: string, body: string, iconName: IconName?): Frame
	local template = authoredTemplate(parent, "RowTemplate", "Frame") :: Frame
	local card = template:Clone()
	card.Name = title
	card.Visible = true
	local titleLabel = card:WaitForChild("Title") :: TextLabel
	titleLabel.Text = title
	local bodyLabel = card:WaitForChild("Body") :: TextLabel
	bodyLabel.Text = body
	local iconBadge = card:WaitForChild("IconBadge") :: Frame
	local symbol = iconBadge:WaitForChild("Symbol") :: TextLabel
	symbol.Text = string.upper(string.sub(title, 1, 1))
	if iconName then
		applyIcon(iconBadge, iconName)
	end
	card.Parent = parent
	return card
end

local function itemCard(
	parent: Instance,
	title: string,
	body: string,
	actionText: string,
	onActivated: () -> (),
	display: { glyph: string?, icon: string? }?
): Frame
	local template = authoredTemplate(parent, "ItemCardTemplate", "Frame") :: Frame
	local card = template:Clone()
	card.Name = title
	card.Visible = true
	local titleLabel = card:WaitForChild("Title") :: TextLabel
	titleLabel.Text = title
	local bodyLabel = card:WaitForChild("Body") :: TextLabel
	bodyLabel.Text = body
	local artwork = card:WaitForChild("Artwork") :: Frame
	local glyph = artwork:WaitForChild("Glyph") :: TextLabel
	local icon = artwork:WaitForChild("Icon") :: ImageLabel
	if display and display.icon and display.icon ~= "" then
		icon.Image = display.icon
		icon.Visible = true
		glyph.Visible = false
	else
		glyph.Text = if display and display.glyph
			then display.glyph
			else string.upper(string.sub(title, 1, 1))
	end
	local action = card:WaitForChild("ActionButton") :: TextButton
	action.Text = actionText
	action.AutoButtonColor = true
	action.Activated:Connect(onActivated)
	card.Parent = parent
	return card
end

local function rewardTile(parent: Instance, day: number, amount: number, nextDay: number): Frame
	local template = authoredTemplate(parent, "RewardTileTemplate", "Frame") :: Frame
	local tile = template:Clone()
	tile.Name = `Day{day}`
	tile.LayoutOrder = day
	tile.Visible = true
	local dayLabel = tile:WaitForChild("DayLabel") :: TextLabel
	dayLabel.Text = `DAY {day}`
	local amountLabel = tile:WaitForChild("AmountLabel") :: TextLabel
	amountLabel.Text = `+{UIFactory.formatNumber(amount)}`
	local stateLabel = tile:WaitForChild("StateLabel") :: TextLabel
	applyIcon(tile:WaitForChild("CoinBadge"), "coin")
	if day == nextDay then
		tile.BackgroundColor3 = Theme.colors.surfaceRaised
		stateLabel.Text = "NEXT REWARD"
		stateLabel.TextColor3 = Theme.colors.primary
	else
		stateLabel.Text = "COINS"
	end
	tile.Parent = parent
	return tile
end

function Screens.inventory(parent: Instance, context: any): Frame
	local root, content = base(parent, "My Bag", context.close)
	local entries = context.state.profile.inventory
	local anyItem = false
	for itemId, entry in entries do
		if entry.quantity > 0 then
			anyItem = true
			local definition = context.state.catalog[itemId]
			if definition then
				local action = if definition.category == "Consumable" then "UseItem" else "ToggleEquip"
				local label = if definition.category == "Consumable"
					then "USE"
					else if entry.equipped then "UNEQUIP" else "EQUIP"
				itemCard(
					content,
					`{definition.name}  ×{entry.quantity}`,
					definition.description,
					label,
					function()
						context.request(action, { itemId = itemId })
					end,
					{
						glyph = if definition.boostMultiplier then `x{definition.boostMultiplier}` else nil,
						icon = definition.icon,
					}
				)
			end
		end
	end
	if not anyItem then
		row(content, "Your bag is empty", "Items and boosts you collect will appear here.", "item")
	end
	return root
end

function Screens.store(parent: Instance, context: any): Frame
	local root, content = base(parent, "Shop", context.close)
	for itemId, definition in context.state.catalog do
		if definition.priceCoins then
			itemCard(
				content,
				definition.name,
				`{definition.description}  •  {UIFactory.formatNumber(definition.priceCoins)} Coins`,
				"BUY",
				function()
					context.request("BuyItem", { itemId = itemId })
				end,
				{
					glyph = if definition.boostMultiplier then `x{definition.boostMultiplier}` else nil,
					icon = definition.icon,
				}
			)
		end
	end
	if context.state.productAvailability.coinPackSmall then
		itemCard(
			content,
			"Small Coins Pack",
			"A quick coin top-up. Roblox shows the final price.",
			"VIEW",
			function()
				context.promptProduct("coinPackSmall")
			end,
			{ glyph = "C" }
		)
	else
		row(content, "Coin packs", "More shop options are coming soon!", "cart")
	end
	if context.state.productAvailability.coinPackLarge then
		itemCard(
			content,
			"Large Coins Pack",
			"A larger coin top-up. Roblox shows the final price.",
			"VIEW",
			function()
				context.promptProduct("coinPackLarge")
			end,
			{ glyph = "C" }
		)
	end
	local premiumText = if context.state.profile.entitlements.premium
		then "Active: permanent +10% Coins bonus."
		else "Roblox Premium members receive a permanent +10% Coins bonus."
	local premiumCard = row(content, "Roblox Premium", premiumText, "premium")
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
	local root, content = base(parent, "Daily Rewards", context.close)
	row(
		content,
		`Daily streak: Day {context.state.profile.daily.streak}`,
		"Come back tomorrow to keep your streak going!",
		"daily"
	)
	local rewardStrip = Instance.new("ScrollingFrame")
	rewardStrip.Name = "RewardStrip"
	rewardStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
	rewardStrip.BackgroundTransparency = 1
	rewardStrip.BorderSizePixel = 0
	rewardStrip.CanvasSize = UDim2.new()
	rewardStrip.ScrollingDirection = Enum.ScrollingDirection.X
	rewardStrip.ScrollBarImageColor3 = Theme.colors.primary
	rewardStrip.ScrollBarThickness = 4
	rewardStrip.Size = UDim2.new(1, -8, 0, 142)
	local rewardLayout = Instance.new("UIListLayout")
	rewardLayout.FillDirection = Enum.FillDirection.Horizontal
	rewardLayout.Padding = UDim.new(0, 8)
	rewardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rewardLayout.Parent = rewardStrip
	rewardStrip.Parent = content
	local nextRewardDay = math.clamp(context.state.profile.daily.streak + 1, 1, 7)
	for day, amount in context.state.dailyRewards do
		rewardTile(rewardStrip, day, amount, nextRewardDay)
	end
	UIFactory.button(content, "CLAIM DAILY REWARD", function()
		context.request("ClaimDaily", {})
	end)
	local pending = context.state.offline
	row(
		content,
		"Offline earnings",
		`{UIFactory.formatNumber(pending.amount)} Coins ready from {math.floor(pending.elapsed / 60)} minutes.`,
		"offline"
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
	local root, content = base(parent, "My Profile", context.close)
	local profile = context.state.profile
	row(
		content,
		Players.LocalPlayer.DisplayName,
		`Coins: {UIFactory.formatNumber(profile.coins)}  •  Joins: {profile.stats.joins}  •  Playtime: {math.floor(
			profile.stats.playSeconds / 60
		)}m`,
		"profile"
	)
	row(content, "Find a player", "Search an exact Roblox username to view public stats.", "search")
	local input = UIFactory.textBox(content, "Exact Roblox username")
	local resultLabel = UIFactory.label(content, "Search for a Roblox player to see their public stats.", {
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
	toggle("Game tips", "announcements", settings.announcements)
	toggle("Stay connected", "afKRollOver", settings.afKRollOver)
	toggle("Reminders", "notifications", settings.notifications)
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
		"You're all set!",
		"Your choices save automatically. You can change them again any time.",
		"settings"
	)
	return root
end

function Screens.feedback(parent: Instance, context: any): Frame
	local root, content = base(parent, "Send Feedback", context.close)
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
		likes.reason or "Thanks for supporting the experience!",
		"likes"
	)
	for _, milestone in context.state.likesMilestones do
		local unlocked = (likes.value or 0) >= milestone.likes
		local detail = if unlocked
			then `{milestone.label} - Code: {milestone.code}`
			else `{milestone.label} - Locked`
		row(content, `{milestone.likes} Likes`, detail, "codes")
	end
	local input = UIFactory.textBox(content, "Enter code")
	UIFactory.button(content, "REDEEM CODE", function()
		context.request("RedeemCode", { code = input.Text })
	end)
	return root
end

local function leaderboardRows(content: Instance, rows: { any })
	for index, entry in rows do
		row(
			content,
			`#{entry.rank or index}  {entry.name}`,
			`{UIFactory.formatNumber(entry.value)} Coins`,
			"leaderboard"
		)
	end
	if #rows == 0 then
		row(content, "No players yet", "Leaderboard data appears after profiles load.", "friends")
	end
end

function Screens.leaderboards(parent: Instance, context: any): Frame
	local root, content = base(parent, "Top Players", context.close)
	UIFactory.label(content, "CURRENT SERVER", { Size = UDim2.new(1, -8, 0, 32), FontFace = Theme.fontBold })
	leaderboardRows(content, context.state.serverLeaderboard)
	UIFactory.button(content, "SHOW GLOBAL TOP 50", function()
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
			then "Community rewards are ready!"
			else "Community rewards are coming soon.",
		"verification"
	)
	row(
		content,
		"Clubs",
		if availability.guilds then "Clubs are ready!" else "Team up with friends when clubs arrive later.",
		"community"
	)
	return root
end

function Screens.simpleList(parent: Instance, context: any, title: string, rows: { any }): Frame
	local root, content = base(parent, title, context.close)
	leaderboardRows(content, rows)
	return root
end

return Screens

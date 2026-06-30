--!strict

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local IconCatalog = require(Shared.IconCatalog)
local Theme = require(Shared.Theme)
local UIFactory = require(script.Parent.UIFactory)

type IconName = IconCatalog.IconName

local INVENTORY_SLOT_COUNT = 12
local STORE_SLOT_COUNT = 8
local SERVER_ROW_COUNT = 10
local GLOBAL_ROW_COUNT = 50

local Screens = {}

local function frame(parent: Instance, name: string): Frame
	local value = parent:WaitForChild(name)
	assert(value:IsA("Frame"), `{value:GetFullName()} must be a Frame`)
	return value
end

local function textButton(parent: Instance, name: string): TextButton
	local value = parent:WaitForChild(name)
	assert(value:IsA("TextButton"), `{value:GetFullName()} must be a TextButton`)
	return value
end

local function textLabel(parent: Instance, name: string): TextLabel
	local value = parent:WaitForChild(name)
	assert(value:IsA("TextLabel"), `{value:GetFullName()} must be a TextLabel`)
	return value
end

local function textBox(parent: Instance, name: string): TextBox
	local value = parent:WaitForChild(name)
	assert(value:IsA("TextBox"), `{value:GetFullName()} must be a TextBox`)
	return value
end

local function content(screen: Frame): ScrollingFrame
	local value = screen:WaitForChild("Content")
	assert(value:IsA("ScrollingFrame"), `{value:GetFullName()} must be a ScrollingFrame`)
	return value
end

local function numberedFrames(parent: Instance, prefix: string, count: number): { Frame }
	local values = {}
	for index = 1, count do
		table.insert(values, frame(parent, `{prefix}{string.format("%02d", index)}`))
	end
	return values
end

local function applyIcon(container: Instance, name: IconName)
	local icon = container:FindFirstChild("Icon")
	if not icon or not icon:IsA("ImageLabel") then
		return
	end
	local fallback = container:FindFirstChild("Symbol") or container:FindFirstChild("Fallback")
	local image = IconCatalog.get(name)
	icon.Image = image
	icon.Visible = image ~= ""
	if fallback and fallback:IsA("GuiObject") then
		fallback.Visible = image == ""
	end
end

local function setRow(card: Frame, title: string, body: string, iconName: IconName?)
	textLabel(card, "Title").Text = title
	textLabel(card, "Body").Text = body
	if iconName then
		applyIcon(frame(card, "IconBadge"), iconName)
	end
	card.Visible = true
end

local function setItemArtwork(slot: Frame, icon: string, glyphText: string)
	local artwork = frame(slot, "Artwork")
	local glyph = textLabel(artwork, "Glyph")
	local image = artwork:WaitForChild("Icon")
	assert(image:IsA("ImageLabel"), `{image:GetFullName()} must be an ImageLabel`)
	image.Image = icon
	image.Visible = icon ~= ""
	glyph.Text = glyphText
	glyph.Visible = icon == ""
end

local function setItemSlot(
	slot: Frame,
	title: string,
	body: string,
	quantityText: string,
	actionText: string,
	icon: string,
	glyph: string,
	action: string,
	value: string
)
	textLabel(slot, "Title").Text = title
	textLabel(slot, "Body").Text = body
	textLabel(slot, "Quantity").Text = quantityText
	textButton(slot, "ActionButton").Text = actionText
	setItemArtwork(slot, icon, glyph)
	slot:SetAttribute("Action", action)
	slot:SetAttribute("Value", value)
	slot.Visible = true
end

local function hideFrames(values: { Frame })
	for _, value in values do
		value.Visible = false
		value:SetAttribute("Action", nil)
		value:SetAttribute("Value", nil)
	end
end

local function sortedItemIds(catalog: { [string]: any }): { string }
	local ids = {}
	for itemId in catalog do
		table.insert(ids, itemId)
	end
	table.sort(ids, function(left, right)
		local leftDefinition = catalog[left]
		local rightDefinition = catalog[right]
		if leftDefinition.priceCoins and rightDefinition.priceCoins then
			return leftDefinition.priceCoins < rightDefinition.priceCoins
		end
		return leftDefinition.name < rightDefinition.name
	end)
	return ids
end

local function connectClose(screen: Frame, close: () -> ())
	local closeButton = textButton(screen, "CloseButton")
	applyIcon(closeButton, "close")
	if IconCatalog.get("close") ~= "" then
		closeButton.Text = ""
	end
	closeButton.Activated:Connect(close)
end

function Screens.bind(parent: Instance, context: any): any
	local screenMap: { [string]: Frame } = {
		Inventory = frame(parent, "InventoryScreen"),
		Store = frame(parent, "StoreScreen"),
		Rewards = frame(parent, "RewardsScreen"),
		Profile = frame(parent, "ProfileScreen"),
		Settings = frame(parent, "SettingsScreen"),
		Feedback = frame(parent, "FeedbackScreen"),
		Codes = frame(parent, "CodesScreen"),
		Boards = frame(parent, "BoardsScreen"),
		Community = frame(parent, "CommunityScreen"),
		Dynamic = frame(parent, "DynamicScreen"),
	}

	for _, screen in screenMap do
		connectClose(screen, context.close)
	end

	local state: any = nil
	local inventoryContent = content(screenMap.Inventory)
	local inventoryGrid = frame(inventoryContent, "ItemsGrid")
	local inventorySlots = numberedFrames(inventoryGrid, "ItemSlot", INVENTORY_SLOT_COUNT)
	local inventoryEmpty = frame(inventoryContent, "EmptyState")
	local inventoryToolbar = frame(inventoryContent, "Toolbar")
	local inventorySearch = textBox(inventoryToolbar, "SearchInput")
	local inventoryCategory = textButton(inventoryToolbar, "CategoryButton")
	local categories = { "All", "Consumable", "Equipment", "Misc" }
	local categoryIndex = 1

	local storeContent = content(screenMap.Store)
	local storeGrid = frame(storeContent, "ProductsGrid")
	local storeSlots = numberedFrames(storeGrid, "StoreSlot", STORE_SLOT_COUNT)
	local rewardsContent = content(screenMap.Rewards)
	local profileContent = content(screenMap.Profile)
	local settingsContent = content(screenMap.Settings)
	local feedbackContent = content(screenMap.Feedback)
	local codesContent = content(screenMap.Codes)
	local boardsContent = content(screenMap.Boards)
	local communityContent = content(screenMap.Community)
	local dynamicContent = content(screenMap.Dynamic)
	local serverRows = numberedFrames(boardsContent, "LeaderRow", SERVER_ROW_COUNT)
	local globalRows = numberedFrames(dynamicContent, "ListRow", GLOBAL_ROW_COUNT)

	local function refreshInventory()
		hideFrames(inventorySlots)
		if not state then
			inventoryEmpty.Visible = true
			return
		end
		local search = string.lower(inventorySearch.Text)
		local category = categories[categoryIndex]
		local visibleEntries = {}
		for _, itemId in sortedItemIds(state.catalog) do
			local entry = state.profile.inventory[itemId]
			local definition = state.catalog[itemId]
			if entry and entry.quantity > 0 then
				local categoryMatches = category == "All" or definition.category == category
				local nameMatches = search == ""
					or string.find(string.lower(definition.name), search, 1, true) ~= nil
				if categoryMatches and nameMatches then
					table.insert(visibleEntries, { itemId = itemId, entry = entry, definition = definition })
				end
			end
		end

		for index, data in visibleEntries do
			local slot = inventorySlots[index]
			if not slot then
				break
			end
			local action = if data.definition.category == "Consumable" then "UseItem" else "ToggleEquip"
			local actionText = if data.definition.category == "Consumable"
				then "USE"
				else if data.entry.equipped then "UNEQUIP" else "EQUIP"
			setItemSlot(
				slot,
				data.definition.name,
				data.definition.description,
				`x{data.entry.quantity}`,
				actionText,
				data.definition.icon,
				if data.definition.boostMultiplier then `x{data.definition.boostMultiplier}` else "ITEM",
				action,
				data.itemId
			)
		end
		inventoryEmpty.Visible = #visibleEntries == 0
		if inventoryEmpty.Visible then
			setRow(inventoryEmpty, "No matching items", "Try another search or category.", "item")
		end
	end

	for _, slot in inventorySlots do
		textButton(slot, "ActionButton").Activated:Connect(function()
			local action = slot:GetAttribute("Action")
			local itemId = slot:GetAttribute("Value")
			if type(action) == "string" and type(itemId) == "string" then
				context.request(action, { itemId = itemId })
			end
		end)
	end
	inventorySearch:GetPropertyChangedSignal("Text"):Connect(refreshInventory)
	inventoryCategory.Activated:Connect(function()
		categoryIndex = (categoryIndex % #categories) + 1
		inventoryCategory.Text = string.upper(categories[categoryIndex])
		refreshInventory()
	end)

	local function refreshStore()
		hideFrames(storeSlots)
		if not state then
			return
		end
		local slotIndex = 1
		for _, itemId in sortedItemIds(state.catalog) do
			local definition = state.catalog[itemId]
			if definition.priceCoins and storeSlots[slotIndex] then
				setItemSlot(
					storeSlots[slotIndex],
					definition.name,
					definition.description,
					`{UIFactory.formatNumber(definition.priceCoins)} C`,
					"BUY",
					definition.icon,
					if definition.boostMultiplier then `x{definition.boostMultiplier}` else "ITEM",
					"BuyItem",
					itemId
				)
				slotIndex += 1
			end
		end

		local productDefinitions = {
			{ key = "coinPackSmall", title = "Small Coins Pack", body = "A quick coin top-up." },
			{ key = "coinPackLarge", title = "Large Coins Pack", body = "A larger coin top-up." },
		}
		for _, product in productDefinitions do
			if state.productAvailability[product.key] and storeSlots[slotIndex] then
				setItemSlot(
					storeSlots[slotIndex],
					product.title,
					product.body,
					"ROBUX",
					"VIEW",
					IconCatalog.get("coin"),
					"C",
					"PromptProduct",
					product.key
				)
				slotIndex += 1
			end
		end

		if storeSlots[slotIndex] then
			setItemSlot(
				storeSlots[slotIndex],
				"Roblox Premium",
				if state.profile.entitlements.premium
					then "Active: permanent +10% Coins bonus."
					else "Premium members receive a permanent +10% Coins bonus.",
				if state.profile.entitlements.premium then "ACTIVE" else "+10%",
				if state.profile.entitlements.premium then "OWNED" else "VIEW",
				IconCatalog.get("premium"),
				"P",
				if state.profile.entitlements.premium then "None" else "PromptPremium",
				"premium"
			)
		end
	end

	for _, slot in storeSlots do
		textButton(slot, "ActionButton").Activated:Connect(function()
			local action = slot:GetAttribute("Action")
			local value = slot:GetAttribute("Value")
			if action == "BuyItem" and type(value) == "string" then
				context.request("BuyItem", { itemId = value })
			elseif action == "PromptProduct" and type(value) == "string" then
				context.promptProduct(value)
			elseif action == "PromptPremium" then
				context.promptPremium()
			end
		end)
	end

	local rewardStrip = rewardsContent:WaitForChild("RewardStrip")
	local rewardTiles = {}
	for day = 1, 7 do
		table.insert(rewardTiles, frame(rewardStrip, `Day{day}`))
	end
	textButton(rewardsContent, "ClaimDailyButton").Activated:Connect(function()
		context.request("ClaimDaily", {})
	end)
	textButton(rewardsContent, "ClaimOfflineButton").Activated:Connect(function()
		context.request("ClaimOffline", {})
	end)
	textButton(rewardsContent, "ExtendedOfflineButton").Activated:Connect(context.promptExtendedOffline)

	local profileSearch = textBox(profileContent, "SearchInput")
	local profileResult = frame(profileContent, "SearchResult")
	textButton(profileContent, "SearchButton").Activated:Connect(function()
		setRow(profileResult, "Searching…", "Looking up public player stats.", "search")
		task.spawn(function()
			local response = context.query("SearchProfile", { username = profileSearch.Text })
			if response.ok and response.data then
				local found = response.data
				setRow(
					profileResult,
					`{found.displayName} (@{found.username})`,
					`{UIFactory.formatNumber(found.coins)} Coins • {found.joins} joins`,
					"profile"
				)
			else
				setRow(
					profileResult,
					"Player not found",
					response.message or "Check the exact username.",
					"search"
				)
			end
		end)
	end)

	local settingsButtons = {
		reducedMotion = textButton(settingsContent, "ReducedMotionButton"),
		announcements = textButton(settingsContent, "AnnouncementsButton"),
		afKRollOver = textButton(settingsContent, "AfkButton"),
		notifications = textButton(settingsContent, "NotificationsButton"),
	}
	for key, settingsButton in settingsButtons do
		local settingKey = key
		settingsButton.Activated:Connect(function()
			if not state then
				return
			end
			local current = state.profile.settings[settingKey]
			if settingKey == "notifications" and not current then
				context.promptNotifications()
			end
			context.request("UpdateSetting", { key = settingKey, value = not current })
		end)
	end
	textButton(settingsContent, "MusicButton").Activated:Connect(function()
		if state then
			context.request(
				"UpdateSetting",
				{ key = "musicVolume", value = (state.profile.settings.musicVolume + 0.25) % 1.25 }
			)
		end
	end)
	textButton(settingsContent, "SfxButton").Activated:Connect(function()
		if state then
			context.request(
				"UpdateSetting",
				{ key = "sfxVolume", value = (state.profile.settings.sfxVolume + 0.25) % 1.25 }
			)
		end
	end)
	textButton(settingsContent, "ScaleButton").Activated:Connect(function()
		if state then
			local nextScale = state.profile.settings.uiScale + 0.1
			if nextScale > 1.2 then
				nextScale = 0.8
			end
			context.request("UpdateSetting", { key = "uiScale", value = nextScale })
		end
	end)

	local feedbackCategories = { "Bug", "Feedback", "Accessibility", "Other" }
	local feedbackCategoryIndex = 1
	local feedbackCategoryButton = textButton(feedbackContent, "CategoryButton")
	local feedbackInput = textBox(feedbackContent, "MessageInput")
	feedbackCategoryButton.Activated:Connect(function()
		feedbackCategoryIndex = (feedbackCategoryIndex % #feedbackCategories) + 1
		feedbackCategoryButton.Text = `CATEGORY: {string.upper(feedbackCategories[feedbackCategoryIndex])}`
	end)
	textButton(feedbackContent, "SubmitButton").Activated:Connect(function()
		context.request(
			"SubmitFeedback",
			{ category = feedbackCategories[feedbackCategoryIndex], message = feedbackInput.Text }
		)
	end)

	local codeInput = textBox(codesContent, "CodeInput")
	textButton(codesContent, "RedeemButton").Activated:Connect(function()
		context.request("RedeemCode", { code = codeInput.Text })
	end)

	local function showList(title: string, rows: { any })
		textLabel(screenMap.Dynamic, "Title").Text = title
		hideFrames(globalRows)
		for index, entry in rows do
			local rowValue = globalRows[index]
			if not rowValue then
				break
			end
			setRow(
				rowValue,
				`#{entry.rank or index}  {entry.name}`,
				`{UIFactory.formatNumber(entry.value)} Coins`,
				"leaderboard"
			)
		end
		context.open("Dynamic")
	end

	textButton(boardsContent, "GlobalButton").Activated:Connect(function()
		task.spawn(function()
			local response = context.query("GlobalLeaderboard", {})
			if response.ok and response.data then
				showList("Global Leaderboard", response.data)
			else
				context.toast(response.message or "Global leaderboard unavailable")
			end
		end)
	end)

	local function apply(nextState: any)
		state = nextState
		refreshInventory()
		refreshStore()

		local streakCard = frame(rewardsContent, "StreakCard")
		setRow(
			streakCard,
			`Daily streak: Day {state.profile.daily.streak}`,
			"Come back tomorrow to keep your streak going!",
			"daily"
		)
		local nextRewardDay = math.clamp(state.profile.daily.streak + 1, 1, 7)
		for day, tile in rewardTiles do
			textLabel(tile, "AmountLabel").Text = `+{UIFactory.formatNumber(state.dailyRewards[day])}`
			local stateLabel = textLabel(tile, "StateLabel")
			if day == nextRewardDay then
				tile.BackgroundColor3 = Theme.colors.surfaceRaised
				stateLabel.Text = "NEXT REWARD"
				stateLabel.TextColor3 = Theme.colors.primary
			else
				tile.BackgroundColor3 = Theme.colors.surface
				stateLabel.Text = "COINS"
				stateLabel.TextColor3 = Theme.colors.textMuted
			end
			applyIcon(frame(tile, "CoinBadge"), "coin")
		end
		setRow(
			frame(rewardsContent, "OfflineCard"),
			"Offline earnings",
			`{UIFactory.formatNumber(state.offline.amount)} Coins ready from {math.floor(
				state.offline.elapsed / 60
			)} minutes.`,
			"offline"
		)
		textButton(rewardsContent, "ExtendedOfflineButton").Visible = state.productAvailability.extendedOffline
			and not state.profile.entitlements.extendedOffline

		setRow(
			frame(profileContent, "StatsCard"),
			Players.LocalPlayer.DisplayName,
			`Coins: {UIFactory.formatNumber(state.profile.coins)} • Joins: {state.profile.stats.joins} • Playtime: {math.floor(
				state.profile.stats.playSeconds / 60
			)}m`,
			"profile"
		)
		setRow(
			frame(profileContent, "SearchIntro"),
			"Find a player",
			"Search an exact Roblox username to view public stats.",
			"search"
		)

		local settings = state.profile.settings
		settingsButtons.reducedMotion.Text =
			`REDUCED MOTION: {if settings.reducedMotion then "ON" else "OFF"}`
		settingsButtons.announcements.Text = `GAME TIPS: {if settings.announcements then "ON" else "OFF"}`
		settingsButtons.afKRollOver.Text = `STAY CONNECTED: {if settings.afKRollOver then "ON" else "OFF"}`
		settingsButtons.notifications.Text = `REMINDERS: {if settings.notifications then "ON" else "OFF"}`
		textButton(settingsContent, "MusicButton").Text = `MUSIC: {math.floor(settings.musicVolume * 100)}%`
		textButton(settingsContent, "SfxButton").Text = `SFX: {math.floor(settings.sfxVolume * 100)}%`
		textButton(settingsContent, "ScaleButton").Text = `UI SCALE: {math.floor(settings.uiScale * 100)}%`
		setRow(
			frame(settingsContent, "SavedCard"),
			"You're all set!",
			"Your choices save automatically. You can change them again any time.",
			"settings"
		)

		setRow(
			frame(codesContent, "LikesCard"),
			`Likes: {UIFactory.formatNumber(state.likes.value or 0)}`,
			state.likes.reason or "Thanks for supporting the experience!",
			"likes"
		)
		for index = 1, 4 do
			local milestoneCard = frame(codesContent, `Milestone{string.format("%02d", index)}`)
			local milestone = state.likesMilestones[index]
			if milestone then
				local unlocked = (state.likes.value or 0) >= milestone.likes
				setRow(
					milestoneCard,
					`{milestone.likes} Likes`,
					if unlocked
						then `{milestone.label} - Code: {milestone.code}`
						else `{milestone.label} - Locked`,
					"codes"
				)
			else
				milestoneCard.Visible = false
			end
		end

		hideFrames(serverRows)
		for index, entry in state.serverLeaderboard do
			local rowValue = serverRows[index]
			if not rowValue then
				break
			end
			setRow(
				rowValue,
				`#{entry.rank or index}  {entry.name}`,
				`{UIFactory.formatNumber(entry.value)} Coins`,
				"leaderboard"
			)
		end

		local availability = state.integrationAvailability
		setRow(
			frame(communityContent, "CommunityCard"),
			"Roblox Community",
			if availability.community
				then "Community rewards are ready!"
				else "Community rewards are coming soon.",
			"verification"
		)
		setRow(
			frame(communityContent, "ClubsCard"),
			"Clubs",
			if availability.guilds
				then "Clubs are ready!"
				else "Team up with friends when clubs arrive later.",
			"community"
		)
	end

	return {
		screens = screenMap,
		apply = apply,
		showList = showList,
	}
end

return Screens

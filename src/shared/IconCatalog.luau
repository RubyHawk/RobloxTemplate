--!strict

local Config = require(script.Parent.TemplateConfig)

export type IconName =
	"bag"
	| "shop"
	| "rewards"
	| "profile"
	| "more"
	| "codes"
	| "leaderboard"
	| "community"
	| "feedback"
	| "settings"
	| "coin"
	| "daily"
	| "offline"
	| "premium"
	| "search"
	| "close"
	| "likes"
	| "friends"
	| "notifications"
	| "cart"
	| "verification"
	| "item"
	| "starterTool"
	| "potionX2"
	| "potionX3"

export type SourceDefinition = {
	file: string,
	fallback: string,
}

local sources: { [IconName]: SourceDefinition } = {
	bag = { file = "bag.png", fallback = "rbxasset://textures/ui/TopBar/inventoryOff@3x.png" },
	shop = { file = "shop.png", fallback = "" },
	rewards = { file = "rewards.png", fallback = "rbxasset://textures/ui/InspectMenu/ico_favorite@3x.png" },
	profile = {
		file = "profile.png",
		fallback = "rbxasset://textures/ui/Settings/MenuBarIcons/PlayersTabIcon@2x.png",
	},
	more = { file = "more.png", fallback = "rbxasset://textures/ui/TopBar/moreOff@3x.png" },
	codes = { file = "codes.png", fallback = "" },
	leaderboard = { file = "leaderboard.png", fallback = "" },
	community = { file = "community.png", fallback = "" },
	feedback = { file = "feedback.png", fallback = "" },
	settings = { file = "settings.png", fallback = "" },
	coin = { file = "coin.png", fallback = "" },
	daily = { file = "daily.png", fallback = "" },
	offline = { file = "offline.png", fallback = "" },
	premium = { file = "premium.png", fallback = "" },
	search = { file = "search.png", fallback = "" },
	close = { file = "close.png", fallback = "" },
	likes = { file = "likes.png", fallback = "" },
	friends = { file = "friends.png", fallback = "" },
	notifications = { file = "notifications.png", fallback = "" },
	cart = { file = "cart.png", fallback = "" },
	verification = { file = "verification.png", fallback = "" },
	item = { file = "item.png", fallback = "" },
	starterTool = { file = "starter_tool.png", fallback = "" },
	potionX2 = { file = "potion_x2.png", fallback = "" },
	potionX3 = { file = "potion_x3.png", fallback = "" },
}

local configured: { [IconName]: string } = Config.icons

local function normalize(assetId: string): string
	if assetId == "" then
		return ""
	end
	if string.find(assetId, "^rbxasset") or string.find(assetId, "^rbxgameasset") then
		return assetId
	end
	return `rbxassetid://{assetId}`
end

local IconCatalog = {}

function IconCatalog.get(name: IconName): string
	local configuredId = normalize(configured[name])
	if configuredId ~= "" then
		return configuredId
	end
	return sources[name].fallback
end

function IconCatalog.isPackConfigured(name: IconName): boolean
	return configured[name] ~= ""
end

IconCatalog.sources = table.freeze(sources)

return table.freeze(IconCatalog)

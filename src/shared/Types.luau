--!strict

export type BoostState = {
	id: string,
	expiresAt: number,
	multiplier: number,
}

export type InventoryEntry = {
	quantity: number,
	equipped: boolean?,
}

export type PlayerSettings = {
	musicVolume: number,
	sfxVolume: number,
	uiScale: number,
	reducedMotion: boolean,
	announcements: boolean,
	afKRollOver: boolean,
	notifications: boolean,
}

export type GuildReservation = {
	guildId: string?,
	role: string?,
}

export type PlayerProfileV1 = {
	schemaVersion: number,
	coins: number,
	inventory: { [string]: InventoryEntry },
	boosts: { BoostState },
	settings: PlayerSettings,
	stats: {
		playSeconds: number,
		joins: number,
		totalCoinsEarned: number,
	},
	daily: {
		lastClaimDay: number,
		streak: number,
	},
	redemptions: { [string]: boolean },
	entitlements: {
		extendedOffline: boolean,
		premium: boolean,
	},
	social: {
		friendCountInServer: number,
		communityVerified: boolean,
		discordVerified: boolean,
	},
	guild: GuildReservation,
	lastSeenAt: number,
	offlineRateSnapshot: number,
	createdAt: number,
	updatedAt: number,
}

-- Schema v2 adds multi-currency, upgrade/unlock ledgers, progress and tutorial
-- flags, and the player's selected UI pack/theme. It is a strict superset of v1
-- so every existing reader (which only touches v1 fields) keeps working.
export type PlayerProfileV2 = PlayerProfileV1 & {
	currencies: { [string]: number },
	upgrades: { [string]: number },
	unlocks: { [string]: boolean },
	progress: {
		rebirths: number,
		prestige: number,
		objectives: { [string]: number },
	},
	tutorial: {
		completedSteps: { [string]: boolean },
		dismissed: boolean,
	},
	selectedPack: string,
}

-- Alias for "the current profile shape". Bump this when a new schema version
-- lands so callers can depend on the latest contract without churn.
export type PlayerProfile = PlayerProfileV2

export type PublicProfile = {
	userId: number,
	username: string,
	displayName: string,
	coins: number,
	joins: number,
	playSeconds: number,
	dailyStreak: number,
	updatedAt: number,
}

export type ClientSnapshot = {
	profile: PlayerProfile,
	friendBonus: number,
	premiumBonus: number,
	potionMultiplier: number,
	serverTime: number,
	features: { [string]: boolean },
	currencies: { [string]: number }?,
	packId: string?,
}

-- ===== UI pack contracts =====
-- A pack is frozen *data* (never behavior). It maps a finite pool of pre-authored
-- HUD widget slots inside a named physical root to state paths and actions.

export type StatBinding = {
	slot: number, -- StatWidget index (1..Config.ui.statWidgetPoolSize)
	path: string, -- dotted state path, e.g. "currencies.coins" / "local.health"
	icon: string?, -- IconCatalog IconName
	caption: string?, -- static caption shown under the value
	format: ("number" | "raw" | "percent" | "time" | "ratio")?,
	-- When present, render the slot's Bar with Fill = value / max. Provide either
	-- a literal `max` or a `maxPath` resolved from state (maxPath wins if both set).
	bar: { maxPath: string?, max: number?, color: string? }?,
	color: string?, -- Theme token name for the value/icon
	default: number?, -- safe fallback when the path is missing
}

export type ActionBinding = {
	slot: number, -- ActionSlot index (1..Config.ui.actionSlotPoolSize)
	action: string, -- "OpenScreen", "Ability", or a server request action
	label: string,
	icon: string?,
	screen: string?, -- screen to open when action == "OpenScreen"
	value: string?, -- payload value for request actions / ability id
	cooldown: number?, -- seconds; drives the slot's CooldownFill when action == "Ability"
}

export type CurrencyDefinition = {
	id: string,
	displayName: string,
	icon: string, -- IconCatalog IconName
	primary: boolean?,
}

export type NavItem = {
	screen: string,
	icon: string,
	label: string?,
}

export type PackDescriptor = {
	id: string,
	displayName: string,
	authoredRoot: string,
	currencies: { CurrencyDefinition },
	hud: {
		stats: { StatBinding },
		actions: { ActionBinding },
		progress: { StatBinding }?,
	},
	screens: { string },
	navigation: { NavItem },
	localFeeds: { [string]: boolean }?, -- client-local feeds to start (e.g. health)
	device: {
		portraitStatCount: number?,
		landscapeStatCount: number?,
		hideActionsOnPhone: boolean?,
	}?,
}

export type ProviderResult<T> = {
	status: "available" | "disabled" | "error",
	value: T?,
	reason: string?,
}

return {}

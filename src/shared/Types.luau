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
	profile: PlayerProfileV1,
	friendBonus: number,
	premiumBonus: number,
	potionMultiplier: number,
	serverTime: number,
	features: { [string]: boolean },
}

export type ProviderResult<T> = {
	status: "available" | "disabled" | "error",
	value: T?,
	reason: string?,
}

return {}

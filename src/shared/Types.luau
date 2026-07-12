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

export type RuneOwnedEntry = {
	count: number,
}

export type RuneSaveState = {
	owned: { [string]: RuneOwnedEntry },
	totalRolls: number,
	rollsSincePity: number,
}

export type TowerDefenseUnitEntry = {
	count: number,
}

export type TowerDefenseSaveState = {
	ownedUnits: { [string]: TowerDefenseUnitEntry },
	loadout: { string },
	stats: {
		wins: number,
		losses: number,
		bestWave: number,
	},
}

export type PlayerProfileV1 = {
	schemaVersion: number,
	coins: number,
	currencies: { [string]: number },
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
	runes: RuneSaveState,
	towerDefense: TowerDefenseSaveState,
	feedback: {
		lastSubmittedAt: number,
	},
	offline: {
		pendingAmount: number,
		pendingElapsed: number,
		preparedAt: number,
	},
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
	currencyDefinitions: { any },
	friendBonus: number,
	premiumBonus: number,
	potionMultiplier: number,
	runeMultiplier: number,
	runes: RuneClientState?,
	towerDefense: TowerDefenseClientState?,
	serverTime: number,
	features: { [string]: boolean },
}

export type RuneClientState = {
	owned: { [string]: RuneOwnedEntry },
	totalRolls: number,
	rollsSincePity: number,
	pityThreshold: number,
	nextCost: number,
	currencyId: string,
	totalBonusPercent: number,
	multiplier: number,
	restricted: boolean,
}

export type TowerDefensePlacementState = {
	id: string,
	unitId: string,
	cell: {
		column: number,
		row: number,
	},
}

export type TowerDefenseEnemyState = {
	id: string,
	health: number,
	maxHealth: number,
	progress: number,
}

export type TowerDefenseClientState = {
	ownedUnits: { [string]: TowerDefenseUnitEntry },
	loadout: { string },
	rollCost: number,
	loadoutSlots: number,
	baseHealth: number,
	maxBaseHealth: number,
	wave: number,
	waveRunning: boolean,
	placements: { TowerDefensePlacementState },
	enemies: { TowerDefenseEnemyState },
	autoPlaceCells: { { column: number, row: number } },
	portalCells: { { column: number, row: number } },
	goalCells: { { column: number, row: number } },
}

export type RuneRollResult = {
	runeId: string,
	rarityId: string,
	cost: number,
	ownedCount: number,
	isNew: boolean,
	pityTriggered: boolean,
	totalRolls: number,
	nextCost: number,
	totalBonusPercent: number,
	multiplier: number,
}

export type ProviderResult<T> = {
	status: "available" | "disabled" | "error",
	value: T?,
	reason: string?,
}

return {}

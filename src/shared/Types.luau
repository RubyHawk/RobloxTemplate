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
	selectedMode: string,
}

-- Live channeling state pushed by the server while a player stands in the
-- circle; nil in snapshots when the player is not channeling.
export type RuneChannelState = {
	active: boolean,
	modeId: string,
	kind: string,
	momentumSeconds: number,
	tierIndex: number,
	tierValue: number,
	nextTierAtSeconds: number?,
	effectiveWeights: { number }?,
}

export type RuneModeAvailability = {
	id: string,
	unlocked: boolean,
}

export type TowerDefenseUnitEntry = {
	count: number,
}

export type TowerDefenseStageProgress = {
	unlocked: boolean,
	clears: number,
	bestWave: number,
}

export type TowerDefenseSaveState = {
	ownedUnits: { [string]: TowerDefenseUnitEntry },
	loadout: { string },
	selectedStageId: string,
	stageProgress: { [string]: TowerDefenseStageProgress },
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
	channelMultiplier: number,
	temporaryMultiplier: number,
	runes: RuneClientState?,
	towerDefense: TowerDefenseClientState?,
	towerPlacements: { TowerDefensePresentationPlacement }?,
	towerPlacementRevision: number?,
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
	selectedMode: string,
	modes: { RuneModeAvailability },
	channel: RuneChannelState?,
}

export type TowerDefensePlacementState = {
	id: string,
	unitId: string,
	cell: {
		column: number,
		row: number,
	},
}

export type TowerDefensePresentationPlacement = {
	ownerUserId: number,
	slot: number,
	id: string,
	unitId: string,
	cell: {
		column: number,
		row: number,
	},
	frame: CFrame,
}

export type TowerDefenseEnemyState = {
	id: string,
	enemyTypeId: string?,
	isBoss: boolean?,
	health: number,
	maxHealth: number,
	progress: number,
	stageId: string?,
	graphId: string?,
	edgeId: string?,
	edgeDistance: number?,
	edgeLength: number?,
	speed: number?,
	laneIndex: number?,
	distanceTraveled: number?,
	serverTime: number?,
}

export type TowerDefenseClientState = {
	ownedUnits: { [string]: TowerDefenseUnitEntry },
	loadout: { string },
	rollCost: number,
	loadoutSlots: number,
	baseHealth: number,
	maxBaseHealth: number,
	activeStageId: string,
	stageOrigin: CFrame,
	wave: number,
	waveRunning: boolean,
	waveIsBoss: boolean?,
	waveCount: number?,
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

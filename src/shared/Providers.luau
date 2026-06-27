--!strict

export type EconomyRateProvider = {
	getRate: (player: Player) -> number,
}

export type LikesProvider = {
	getLikes: () -> { status: string, value: number?, reason: string? },
}

export type VerificationProvider = {
	verify: (player: Player) -> { status: string, value: boolean?, reason: string? },
}

export type NotificationScheduler = {
	schedule: (userId: number, kind: string, dueAt: number) -> { status: string, reason: string? },
	cancel: (userId: number) -> (),
}

export type PublicProfileProvider = {
	findByUserId: (userId: number) -> any,
}

return {}

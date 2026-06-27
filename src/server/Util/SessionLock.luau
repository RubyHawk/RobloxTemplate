--!strict

local SessionLock = {}

export type Lock = {
	jobId: string,
	placeId: number,
	touchedAt: number,
}

function SessionLock.canClaim(lock: Lock?, jobId: string, now: number, timeoutSeconds: number): boolean
	return lock == nil or lock.jobId == jobId or now - lock.touchedAt >= timeoutSeconds
end

function SessionLock.claim(jobId: string, placeId: number, now: number): Lock
	return {
		jobId = jobId,
		placeId = placeId,
		touchedAt = now,
	}
end

return SessionLock

--!strict

local SessionLock = {}

export type Lock = {
	jobId: string,
	placeId: number,
	touchedAt: number,
}

function SessionLock.canClaim(lock: Lock?, jobId: string, now: number, timeoutSeconds: number): boolean
	if lock == nil then
		return true
	end
	if
		type(lock) ~= "table"
		or type((lock :: any).jobId) ~= "string"
		or type((lock :: any).placeId) ~= "number"
		or type((lock :: any).touchedAt) ~= "number"
	then
		return false
	end
	return lock.jobId == jobId or now - lock.touchedAt >= timeoutSeconds
end

function SessionLock.claim(jobId: string, placeId: number, now: number): Lock
	return {
		jobId = jobId,
		placeId = placeId,
		touchedAt = now,
	}
end

return SessionLock

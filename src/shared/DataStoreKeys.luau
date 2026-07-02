--!strict

local DataStoreKeys = {}

function DataStoreKeys.profile(userId: number): string
	return `player:{userId}`
end

function DataStoreKeys.publicProfile(userId: number): string
	return `user:{userId}`
end

function DataStoreKeys.feedback(userId: number, createdAt: number, uniqueId: string): string
	return `user:{userId}:report:{createdAt}:{uniqueId}`
end

function DataStoreKeys.leaderboard(userId: number): string
	return tostring(userId)
end

return table.freeze(DataStoreKeys)

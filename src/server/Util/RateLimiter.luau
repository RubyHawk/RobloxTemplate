--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		buckets: { [Player]: { [string]: { tokens: number, updatedAt: number } } },
	},
	RateLimiter
))

function RateLimiter.new(): RateLimiter
	return setmetatable({ buckets = {} }, RateLimiter)
end

function RateLimiter.allow(
	self: RateLimiter,
	player: Player,
	action: string,
	capacity: number,
	refillPerSecond: number
): boolean
	local now = os.clock()
	local playerBuckets = self.buckets[player]
	if playerBuckets == nil then
		playerBuckets = {}
		self.buckets[player] = playerBuckets
	end

	local bucket = playerBuckets[action]
	if bucket == nil then
		bucket = { tokens = capacity, updatedAt = now }
		playerBuckets[action] = bucket
	end

	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.updatedAt) * refillPerSecond)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimiter.forget(self: RateLimiter, player: Player)
	self.buckets[player] = nil
end

return RateLimiter

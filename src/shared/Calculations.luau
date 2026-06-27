--!strict

local Calculations = {}

function Calculations.utcDay(timestamp: number): number
	return math.floor(timestamp / 86400)
end

function Calculations.dailyClaim(
	lastClaimDay: number,
	streak: number,
	now: number,
	rewardCount: number
): (boolean, number)
	local today = Calculations.utcDay(now)
	if lastClaimDay == today then
		return false, streak
	end
	if lastClaimDay == today - 1 then
		return true, (streak % rewardCount) + 1
	end
	return true, 1
end

function Calculations.potionMultiplier(boosts: { any }, now: number): number
	local strongest = 1
	for _, boost in boosts do
		if type(boost) == "table" and boost.expiresAt > now and boost.multiplier > strongest then
			strongest = boost.multiplier
		end
	end
	return strongest
end

function Calculations.friendBonus(friendCount: number, perFriend: number, cap: number): number
	return math.min(math.max(friendCount, 0) * perFriend, cap)
end

function Calculations.earningsMultiplier(
	friendCount: number,
	isPremium: boolean,
	boosts: { any },
	now: number,
	perFriend: number,
	friendCap: number,
	premiumBonus: number
): number
	local social = Calculations.friendBonus(friendCount, perFriend, friendCap)
	local premium = if isPremium then premiumBonus else 0
	return (1 + social + premium) * Calculations.potionMultiplier(boosts, now)
end

function Calculations.offlineEarnings(
	lastSeenAt: number,
	now: number,
	ratePerSecond: number,
	capHours: number,
	permanentMultiplier: number
): (number, number)
	local elapsed = math.clamp(now - lastSeenAt, 0, capHours * 3600)
	local amount = math.floor(math.max(ratePerSecond, 0) * elapsed * math.max(permanentMultiplier, 0))
	return amount, elapsed
end

function Calculations.normalizeCode(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local normalized = string.upper(string.gsub(value, "%s+", ""))
	if #normalized < 1 or #normalized > 32 or string.match(normalized, "^[A-Z0-9_-]+$") == nil then
		return nil
	end
	return normalized
end

return Calculations

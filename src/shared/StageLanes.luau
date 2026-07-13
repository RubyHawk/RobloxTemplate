--!strict

local StageLanes = {}

StageLanes.MIN_COUNT = 1
StageLanes.MAX_COUNT = 3
StageLanes.DEFAULT_COUNT = 2
StageLanes.DEFAULT_SPACING = 4
StageLanes.DEFAULT_HALF_WIDTH = 2

function StageLanes.offsets(laneCount: number, spacing: number?): { number }
	assert(laneCount % 1 == 0, "lane count must be an integer")
	assert(
		laneCount >= StageLanes.MIN_COUNT and laneCount <= StageLanes.MAX_COUNT,
		`lane count must be between {StageLanes.MIN_COUNT} and {StageLanes.MAX_COUNT}`
	)
	local resolvedSpacing = spacing or StageLanes.DEFAULT_SPACING
	assert(
		resolvedSpacing == resolvedSpacing and resolvedSpacing > 0 and resolvedSpacing < math.huge,
		"lane spacing must be a positive finite number"
	)
	local result: { number } = {}
	local center = (laneCount + 1) * 0.5
	for laneIndex = 1, laneCount do
		result[laneIndex] = (laneIndex - center) * resolvedSpacing
	end
	return result
end

function StageLanes.index(sequence: number, laneCount: number): number
	assert(sequence % 1 == 0 and sequence >= 1, "lane sequence must be a positive integer")
	assert(laneCount % 1 == 0 and laneCount >= 1, "lane count must be a positive integer")
	return ((sequence - 1) % laneCount) + 1
end

function StageLanes.sequenceForSpawn(enemySequence: number, spawnCount: number): number
	assert(enemySequence % 1 == 0 and enemySequence >= 1, "enemy sequence must be a positive integer")
	assert(spawnCount % 1 == 0 and spawnCount >= 1, "spawn count must be a positive integer")
	return math.floor((enemySequence - 1) / spawnCount) + 1
end

function StageLanes.clearanceRadius(offsets: { number }, halfWidth: number?): number
	local furthestOffset = 0
	for _, offset in offsets do
		furthestOffset = math.max(furthestOffset, math.abs(offset))
	end
	return furthestOffset + (halfWidth or StageLanes.DEFAULT_HALF_WIDTH)
end

return table.freeze(StageLanes)

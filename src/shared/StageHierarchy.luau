--!strict

local StageHierarchy = {}

export type Address = {
	groupId: string,
	stageNumber: number,
	levelNumber: number,
}

local function positiveInteger(value: any, fallback: number): number
	return if type(value) == "number" and value % 1 == 0 and value > 0 then value else fallback
end

function StageHierarchy.address(stage: any): Address
	local displayOrder = positiveInteger(if type(stage) == "table" then stage.displayOrder else nil, 1)
	local stageNumber =
		positiveInteger(if type(stage) == "table" then stage.stageNumber else nil, displayOrder)
	local levelNumber = positiveInteger(if type(stage) == "table" then stage.levelNumber else nil, 1)
	local groupId = if type(stage) == "table"
			and type(stage.stageGroupId) == "string"
			and stage.stageGroupId ~= ""
		then stage.stageGroupId
		else `legacy_stage_group_{stageNumber}`
	return {
		groupId = groupId,
		stageNumber = stageNumber,
		levelNumber = levelNumber,
	}
end

function StageHierarchy.assign(stage: any, groupId: string, stageNumber: number, levelNumber: number)
	stage.stageGroupId = groupId
	stage.stageNumber = math.max(math.floor(stageNumber), 1)
	stage.levelNumber = math.max(math.floor(levelNumber), 1)
end

function StageHierarchy.less(left: any, right: any): boolean
	local leftAddress = StageHierarchy.address(left)
	local rightAddress = StageHierarchy.address(right)
	if leftAddress.stageNumber ~= rightAddress.stageNumber then
		return leftAddress.stageNumber < rightAddress.stageNumber
	end
	if leftAddress.levelNumber ~= rightAddress.levelNumber then
		return leftAddress.levelNumber < rightAddress.levelNumber
	end
	local leftOrder = positiveInteger(if type(left) == "table" then left.displayOrder else nil, 1)
	local rightOrder = positiveInteger(if type(right) == "table" then right.displayOrder else nil, 1)
	if leftOrder ~= rightOrder then
		return leftOrder < rightOrder
	end
	return tostring(if type(left) == "table" then left.id else "")
		< tostring(if type(right) == "table" then right.id else "")
end

function StageHierarchy.sortedIds(stages: { [string]: any }): { string }
	local ids: { string } = {}
	for id in stages do
		table.insert(ids, id)
	end
	table.sort(ids, function(leftId, rightId)
		return StageHierarchy.less(stages[leftId], stages[rightId])
	end)
	return ids
end

function StageHierarchy.nextStageNumber(stages: { [string]: any }): number
	local maximum = 0
	for _, stage in stages do
		maximum = math.max(maximum, StageHierarchy.address(stage).stageNumber)
	end
	return maximum + 1
end

function StageHierarchy.nextLevelNumber(stages: { [string]: any }, groupId: string): number
	local maximum = 0
	for _, stage in stages do
		local address = StageHierarchy.address(stage)
		if address.groupId == groupId then
			maximum = math.max(maximum, address.levelNumber)
		end
	end
	return maximum + 1
end

function StageHierarchy.label(stage: any): string
	local address = StageHierarchy.address(stage)
	return `Stage {address.stageNumber} · Level {address.levelNumber}`
end

return table.freeze(StageHierarchy)

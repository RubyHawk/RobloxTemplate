--!strict

local StageHierarchy = {}

StageHierarchy.LEGACY_MAP_ID = "map_legacy_1"

export type Address = {
	mapId: string,
	groupId: string,
	stageNumber: number,
	levelNumber: number,
}

local function positiveInteger(value: any, fallback: number): number
	return if type(value) == "number" and value % 1 == 0 and value > 0 then value else fallback
end

local function stableMapId(stage: any): string
	return if type(stage) == "table"
			and type(stage.mapId) == "string"
			and stage.mapId ~= ""
		then stage.mapId
		else StageHierarchy.LEGACY_MAP_ID
end

local function mapOrder(maps: { [string]: any }?, mapId: string): number
	local definition = if type(maps) == "table" then maps[mapId] else nil
	return positiveInteger(if type(definition) == "table" then definition.displayOrder else nil, 1)
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
		mapId = stableMapId(stage),
		groupId = groupId,
		stageNumber = stageNumber,
		levelNumber = levelNumber,
	}
end

function StageHierarchy.assign(
	stage: any,
	groupId: string,
	stageNumber: number,
	levelNumber: number,
	mapId: string?
)
	stage.stageGroupId = groupId
	stage.stageNumber = math.max(math.floor(stageNumber), 1)
	stage.levelNumber = math.max(math.floor(levelNumber), 1)
	if mapId ~= nil then
		stage.mapId = mapId
	end
end

function StageHierarchy.less(left: any, right: any, maps: { [string]: any }?): boolean
	local leftAddress = StageHierarchy.address(left)
	local rightAddress = StageHierarchy.address(right)
	local leftMapOrder = mapOrder(maps, leftAddress.mapId)
	local rightMapOrder = mapOrder(maps, rightAddress.mapId)
	if leftMapOrder ~= rightMapOrder then
		return leftMapOrder < rightMapOrder
	end
	if leftAddress.mapId ~= rightAddress.mapId then
		return leftAddress.mapId < rightAddress.mapId
	end
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

function StageHierarchy.sortedIds(stages: { [string]: any }, maps: { [string]: any }?): { string }
	local ids: { string } = {}
	for id in stages do
		table.insert(ids, id)
	end
	table.sort(ids, function(leftId, rightId)
		return StageHierarchy.less(stages[leftId], stages[rightId], maps)
	end)
	return ids
end

function StageHierarchy.mapIds(maps: { [string]: any }): { string }
	local ids: { string } = {}
	for id in maps do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(leftId, rightId)
		local leftOrder = mapOrder(maps, leftId)
		local rightOrder = mapOrder(maps, rightId)
		return if leftOrder == rightOrder then leftId < rightId else leftOrder < rightOrder
	end)
	return ids
end

function StageHierarchy.nextMapDisplayOrder(maps: { [string]: any }): number
	local maximum = 0
	for _, map in maps do
		maximum =
			math.max(maximum, positiveInteger(if type(map) == "table" then map.displayOrder else nil, 0))
	end
	return maximum + 1
end

function StageHierarchy.nextStageNumber(stages: { [string]: any }, mapId: string?): number
	local maximum = 0
	for _, stage in stages do
		local address = StageHierarchy.address(stage)
		if mapId == nil or address.mapId == mapId then
			maximum = math.max(maximum, address.stageNumber)
		end
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

function StageHierarchy.stageGroupIds(
	stages: { [string]: any },
	mapId: string,
	maps: { [string]: any }?
): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, stageId in StageHierarchy.sortedIds(stages, maps) do
		local address = StageHierarchy.address(stages[stageId])
		if address.mapId == mapId and not seen[address.groupId] then
			seen[address.groupId] = true
			table.insert(result, address.groupId)
		end
	end
	return result
end

function StageHierarchy.firstLevelId(
	stages: { [string]: any },
	mapId: string?,
	groupId: string?,
	maps: { [string]: any }?
): string?
	for _, stageId in StageHierarchy.sortedIds(stages, maps) do
		local address = StageHierarchy.address(stages[stageId])
		if (mapId == nil or address.mapId == mapId) and (groupId == nil or address.groupId == groupId) then
			return stageId
		end
	end
	return nil
end

function StageHierarchy.label(stage: any): string
	local address = StageHierarchy.address(stage)
	return `Stage {address.stageNumber} · Level {address.levelNumber}`
end

return table.freeze(StageHierarchy)

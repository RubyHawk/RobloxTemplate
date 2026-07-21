--!strict

local StageHierarchy = require(script.Parent.StageHierarchy)
local StageTypes = require(script.Parent.StageTypes)

type RuntimeStageBundle = StageTypes.RuntimeStageBundle
type RuntimeStageDefinition = StageTypes.RuntimeStageDefinition

local bundle: any = require(script.Parent["StageCatalog.generated"]) :: RuntimeStageBundle
local StageCatalog = {}
local stages: { [string]: RuntimeStageDefinition } = bundle.stages
local maps: { [string]: StageTypes.RuntimeMapDefinition } = if type(bundle.maps) == "table"
	then bundle.maps
	else {
		[StageHierarchy.LEGACY_MAP_ID] = {
			id = StageHierarchy.LEGACY_MAP_ID,
			name = "Map 1",
			displayOrder = 1,
			metadata = {},
		},
	}
local mapOrder: { string } = if type(bundle.mapOrder) == "table"
	then bundle.mapOrder
	else StageHierarchy.mapIds(maps)

function StageCatalog.get(stageId: string): RuntimeStageDefinition?
	return stages[stageId]
end

function StageCatalog.defaultStageId(): string
	return bundle.startingStageId
end

function StageCatalog.getMap(mapId: string): StageTypes.RuntimeMapDefinition?
	return maps[mapId]
end

function StageCatalog.mapIds(): { string }
	return table.clone(mapOrder)
end

function StageCatalog.address(stageId: string): StageHierarchy.Address?
	local stage = stages[stageId]
	return if stage ~= nil then StageHierarchy.address(stage) else nil
end

function StageCatalog.levelIds(stageNumber: number?, mapId: string?): { string }
	local result: { string } = {}
	for _, stageId in bundle.stageOrder do
		local stage = stages[stageId]
		local address = if stage ~= nil then StageHierarchy.address(stage) else nil
		if
			address ~= nil
			and (mapId == nil or address.mapId == mapId)
			and (stageNumber == nil or address.stageNumber == stageNumber)
		then
			table.insert(result, stageId)
		end
	end
	return result
end

function StageCatalog.stageGroupIds(mapId: string): { string }
	return StageHierarchy.stageGroupIds(stages, mapId, maps)
end

function StageCatalog.nextLevelId(stageId: string): string?
	local currentIndex = table.find(bundle.stageOrder, stageId)
	return if currentIndex ~= nil then bundle.stageOrder[currentIndex + 1] else nil
end

StageCatalog.stages = table.freeze(stages)
StageCatalog.maps = table.freeze(maps)
StageCatalog.mapOrder = table.freeze(mapOrder)
StageCatalog.stageOrder = table.freeze(bundle.stageOrder)
StageCatalog.bundleChecksum = bundle.checksum

return table.freeze(StageCatalog)

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
-- Older generated bundles predate the wave-authoring collections; fall back to
-- empty registries so consumers can detect the absence and use legacy data.
local enemyTypes: { [string]: StageTypes.EnemyTypeDefinition } = if type(bundle.enemyTypes) == "table"
	then bundle.enemyTypes
	else {}
local waveSets: { [string]: StageTypes.WaveSetDefinition } = if type(bundle.waveSets) == "table"
	then bundle.waveSets
	else {}
local enemyTypeOrder: { string } = if type(bundle.enemyTypeOrder) == "table"
	then bundle.enemyTypeOrder
	else {}
local waveSetOrder: { string } = if type(bundle.waveSetOrder) == "table" then bundle.waveSetOrder else {}

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

function StageCatalog.enemyType(enemyTypeId: string): StageTypes.EnemyTypeDefinition?
	return enemyTypes[enemyTypeId]
end

function StageCatalog.waveSet(waveSetId: string): StageTypes.WaveSetDefinition?
	return waveSets[waveSetId]
end

function StageCatalog.waveSetForStage(stageId: string): StageTypes.WaveSetDefinition?
	local stage = stages[stageId]
	local waveSetId = if stage ~= nil then stage.waveSetId else nil
	if waveSetId ~= nil and waveSets[waveSetId] ~= nil then
		return waveSets[waveSetId]
	end
	return waveSets.default
end

StageCatalog.stages = table.freeze(stages)
StageCatalog.maps = table.freeze(maps)
StageCatalog.mapOrder = table.freeze(mapOrder)
StageCatalog.stageOrder = table.freeze(bundle.stageOrder)
StageCatalog.enemyTypes = table.freeze(enemyTypes)
StageCatalog.enemyTypeOrder = table.freeze(enemyTypeOrder)
StageCatalog.waveSets = table.freeze(waveSets)
StageCatalog.waveSetOrder = table.freeze(waveSetOrder)
StageCatalog.bundleChecksum = bundle.checksum

return table.freeze(StageCatalog)

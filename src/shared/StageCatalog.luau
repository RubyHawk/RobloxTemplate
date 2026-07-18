--!strict

local StageHierarchy = require(script.Parent.StageHierarchy)
local StageTypes = require(script.Parent.StageTypes)

type RuntimeStageBundle = StageTypes.RuntimeStageBundle
type RuntimeStageDefinition = StageTypes.RuntimeStageDefinition

local bundle = require(script.Parent["StageCatalog.generated"]) :: RuntimeStageBundle
local StageCatalog = {}
local stages: { [string]: RuntimeStageDefinition } = bundle.stages

function StageCatalog.get(stageId: string): RuntimeStageDefinition?
	return stages[stageId]
end

function StageCatalog.defaultStageId(): string
	return bundle.startingStageId
end

function StageCatalog.address(stageId: string): StageHierarchy.Address?
	local stage = stages[stageId]
	return if stage ~= nil then StageHierarchy.address(stage) else nil
end

function StageCatalog.levelIds(stageNumber: number?): { string }
	local result: { string } = {}
	for _, stageId in bundle.stageOrder do
		local stage = stages[stageId]
		if
			stage ~= nil and (stageNumber == nil or StageHierarchy.address(stage).stageNumber == stageNumber)
		then
			table.insert(result, stageId)
		end
	end
	return result
end

function StageCatalog.nextLevelId(stageId: string): string?
	local currentIndex = table.find(bundle.stageOrder, stageId)
	return if currentIndex ~= nil then bundle.stageOrder[currentIndex + 1] else nil
end

StageCatalog.stages = table.freeze(stages)
StageCatalog.stageOrder = table.freeze(bundle.stageOrder)
StageCatalog.bundleChecksum = bundle.checksum

return table.freeze(StageCatalog)

--!strict

local bundle = require(script.Parent["StageCatalog.generated"])
local StageCatalog = {}
local stages = bundle.stages

function StageCatalog.get(stageId: string): any?
	return stages[stageId]
end

function StageCatalog.defaultStageId(): string
	return bundle.startingStageId
end

StageCatalog.stages = table.freeze(stages)
StageCatalog.bundleChecksum = bundle.checksum

return table.freeze(StageCatalog)

--!strict

-- Shared, pure description of the Studio-only Stagewright playtest artifact.
-- The plugin owns Instance writes; runtime code only reads the stored strings
-- and delegates chunk assembly here so Lune can exercise the same format.

local StagePayload = if script ~= nil then require(script.Parent.StagePayload) else require("./StagePayload")

local StagePlaytestArtifact = {}

StagePlaytestArtifact.ROOT_NAME = "StagewrightPlaytestRuntime"
StagePlaytestArtifact.VALUE_NAME = "Runtime"
StagePlaytestArtifact.FORMAT = "StagewrightPlaytest:v1"
StagePlaytestArtifact.FORMAT_ATTRIBUTE = "StagewrightPlaytestFormat"
StagePlaytestArtifact.SOURCE_CHECKSUM_ATTRIBUTE = "SourceChecksum"
StagePlaytestArtifact.RUNTIME_CHECKSUM_ATTRIBUTE = "RuntimeChecksum"
StagePlaytestArtifact.SELECTED_STAGE_ATTRIBUTE = "SelectedStageId"

function StagePlaytestArtifact.selectCatalog(
	generatedBundle: any,
	preparedBundle: any?,
	isStudio: boolean
): (any, boolean)
	if isStudio and type(preparedBundle) == "table" then
		return preparedBundle, true
	end
	return generatedBundle, false
end

function StagePlaytestArtifact.decode(value: any, chunksByName: { [string]: any }?): (string?, string?)
	if type(value) ~= "string" then
		return nil, "Playtest runtime payload is missing"
	end
	local manifest = StagePayload.parseManifest(value)
	if manifest == nil then
		if #value > StagePayload.MAX_PAYLOAD_SIZE then
			return nil, "Playtest runtime payload is too large"
		end
		return value, nil
	end
	local chunks: { string } = {}
	local source = chunksByName or {}
	for index = 1, manifest.chunkCount do
		local chunk = source[StagePayload.chunkName(index)]
		if type(chunk) ~= "string" then
			return nil, `Playtest runtime chunk {index} is missing`
		end
		chunks[index] = chunk
	end
	return StagePayload.join(chunks, manifest.chunkCount, manifest.length)
end

return table.freeze(StagePlaytestArtifact)

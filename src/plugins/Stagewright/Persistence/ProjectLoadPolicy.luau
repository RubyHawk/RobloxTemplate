--!strict

local StagePayload = if script ~= nil
	then require(script.Parent.Parent.Shared.StagePayload)
	else require("../../../shared/StagePayload")
local StageSchema = if script ~= nil
	then require(script.Parent.Parent.Shared.StageSchema)
	else require("../../../shared/StageSchema")

local ProjectLoadPolicy = {}

export type SnapshotState = "Missing" | "Invalid" | "Present"

export type ChunkSnapshot = {
	name: string,
	className: string,
	value: string?,
}

export type PayloadSnapshot = {
	containerState: SnapshotState,
	containerClassName: string?,
	valueState: SnapshotState,
	valueClassName: string?,
	value: string?,
	chunksState: SnapshotState,
	chunksClassName: string?,
	chunks: { ChunkSnapshot },
	chunkCountAttribute: any?,
	payloadLengthAttribute: any?,
	payloadChecksumAttribute: any?,
	workingChecksumAttribute: any?,
	schemaVersionAttribute: any?,
}

export type EncodedPayload = {
	kind: "Encoded",
	encoded: string,
	expectedChecksum: string?,
}

export type MissingPayload = {
	kind: "Missing",
	code: string,
	message: string,
}

export type CorruptPayload = {
	kind: "Corrupt",
	code: string,
	message: string,
}

export type PayloadResult = EncodedPayload | MissingPayload | CorruptPayload

export type Ready = {
	kind: "Ready",
	project: any,
	sourceVersion: number,
	persistedChecksum: string,
}

export type Initialize = {
	kind: "Initialize",
}

export type LegacyMigratedInMemory = {
	kind: "LegacyMigratedInMemory",
	project: any,
	sourceVersion: number,
	persistedChecksum: string,
}

export type Corrupt = {
	kind: "Corrupt",
	code: string,
	message: string,
}

export type UnsupportedFutureVersion = {
	kind: "UnsupportedFutureVersion",
	foundVersion: number,
	supportedVersion: number,
	message: string,
}

export type LoadResult = Ready | LegacyMigratedInMemory | Corrupt | UnsupportedFutureVersion

export type PlanResult = LoadResult | Initialize

local function corrupt(code: string, message: string): Corrupt
	return {
		kind = "Corrupt",
		code = code,
		message = message,
	}
end

local function corruptPayload(code: string, message: string): CorruptPayload
	return {
		kind = "Corrupt",
		code = code,
		message = message,
	}
end

local function missingPayload(code: string, message: string): MissingPayload
	return {
		kind = "Missing",
		code = code,
		message = message,
	}
end

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local MAX_SPATIAL_MAGNITUDE = 1_000_000
local MAX_GRAPH_SCALAR_MAGNITUDE = 1_000_000
local MAX_PREDICATE_MAGNITUDE = 1_000_000_000_000
local MAX_ROUTE_CELL_RADIUS = 64

local function boundedNumber(value: any, maximumMagnitude: number): boolean
	return finiteNumber(value) and math.abs(value) <= maximumMagnitude
end

local function vectorShape(value: any): boolean
	return type(value) == "table"
		and boundedNumber(value.x, MAX_SPATIAL_MAGNITUDE)
		and boundedNumber(value.y, MAX_SPATIAL_MAGNITUDE)
		and boundedNumber(value.z, MAX_SPATIAL_MAGNITUDE)
end

local function optionalBoundedNumber(value: any, maximumMagnitude: number): boolean
	return value == nil or boundedNumber(value, maximumMagnitude)
end

local function denseArrayLength(value: any): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	local maximumIndex = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end
		count += 1
		maximumIndex = math.max(maximumIndex, key)
	end
	return if maximumIndex == count then count else nil
end

local function predicateShapeError(predicate: any): string?
	if type(predicate) ~= "table" or type(predicate.kind) ~= "string" then
		return "predicate must be a table with a string kind"
	end
	local kind = predicate.kind
	if kind == "WaveRange" then
		-- The runtime deliberately defaults a missing minimum/maximum, but any authored value must
		-- be bounded and numeric before StageGraph compares it with the current wave.
		if
			not optionalBoundedNumber(predicate.minimum, MAX_PREDICATE_MAGNITUDE)
			or not optionalBoundedNumber(predicate.maximum, MAX_PREDICATE_MAGNITUDE)
		then
			return "WaveRange minimum and maximum must be bounded numbers when present"
		end
	elseif kind == "StageFlagEquals" then
		if type(predicate.key) ~= "string" or type(predicate.value) ~= "boolean" then
			return "StageFlagEquals needs a string key and boolean value"
		end
	elseif kind == "EnemyTag" then
		if type(predicate.tag) ~= "string" then
			return "EnemyTag needs a string tag"
		end
	elseif kind == "VisitCountBelow" then
		if
			type(predicate.nodeId) ~= "string"
			or not boundedNumber(predicate.maximum, MAX_PREDICATE_MAGNITUDE)
		then
			return "VisitCountBelow needs a string node ID and bounded numeric maximum"
		end
	elseif kind == "StageUnlocked" then
		if type(predicate.stageId) ~= "string" then
			return "StageUnlocked needs a string stage ID"
		end
	elseif kind == "UpgradeLevelAtLeast" then
		if
			type(predicate.upgradeId) ~= "string"
			or not boundedNumber(predicate.level, MAX_PREDICATE_MAGNITUDE)
		then
			return "UpgradeLevelAtLeast needs a string upgrade ID and bounded numeric level"
		end
	elseif kind == "CurrencyAtLeast" then
		if
			type(predicate.currencyId) ~= "string"
			or not boundedNumber(predicate.amount, MAX_PREDICATE_MAGNITUDE)
		then
			return "CurrencyAtLeast needs a string currency ID and bounded numeric amount"
		end
	end
	return nil
end

local function unlockRequirementShapeError(requirement: any): string?
	if type(requirement) ~= "table" or type(requirement.kind) ~= "string" then
		return "requirement must be a table with a string kind"
	end
	if requirement.kind == "StageUnlocked" then
		if type(requirement.stageId) ~= "string" then
			return "StageUnlocked needs a string stage ID"
		end
	elseif requirement.kind == "UpgradeLevelAtLeast" then
		if
			type(requirement.upgradeId) ~= "string"
			or not boundedNumber(requirement.level, MAX_PREDICATE_MAGNITUDE)
		then
			return "UpgradeLevelAtLeast needs a string upgrade ID and bounded numeric level"
		end
	elseif requirement.kind == "CurrencyAtLeast" then
		if
			type(requirement.currencyId) ~= "string"
			or not boundedNumber(requirement.amount, MAX_PREDICATE_MAGNITUDE)
		then
			return "CurrencyAtLeast needs a string currency ID and bounded numeric amount"
		end
	else
		return `unsupported unlock requirement kind {requirement.kind}`
	end
	return nil
end

local function projectShapeError(project: any): string?
	if type(project.startingStageId) ~= "string" then
		return "startingStageId must be a string"
	end
	if project.selectedStageId ~= nil and type(project.selectedStageId) ~= "string" then
		return "selectedStageId must be a string when present"
	end
	if project.metadata ~= nil and type(project.metadata) ~= "table" then
		return "project metadata must be a table when present"
	end
	if type(project.maps) ~= "table" then
		return "maps must be a table"
	end
	local hasMap = false
	local mapHasLevel: { [string]: boolean } = {}
	for mapId, map in project.maps do
		hasMap = true
		if type(mapId) ~= "string" or type(map) ~= "table" then
			return "every Map entry must use a string ID and table value"
		end
		if
			type(map.id) ~= "string"
			or map.id ~= mapId
			or type(map.name) ~= "string"
			or type(map.backdropImageId) ~= "string"
			or type(map.metadata) ~= "table"
			or not finiteNumber(map.displayOrder)
			or map.displayOrder % 1 ~= 0
			or map.displayOrder < 1
			or map.displayOrder > 999
		then
			return `Map {mapId} is malformed`
		end
		mapHasLevel[mapId] = false
	end
	if not hasMap then
		return "project must contain at least one Map"
	end
	if type(project.enemyTypes) ~= "table" then
		return "enemyTypes must be a table"
	end
	local hasEnemyType = false
	local enemyTypeIds: { [string]: boolean } = {}
	for enemyTypeId, enemyType in project.enemyTypes do
		hasEnemyType = true
		if type(enemyTypeId) ~= "string" or type(enemyType) ~= "table" then
			return "every enemy type entry must use a string ID and table value"
		end
		if
			type(enemyType.id) ~= "string"
			or enemyType.id ~= enemyTypeId
			or type(enemyType.name) ~= "string"
			or type(enemyType.modelId) ~= "string"
			or denseArrayLength(enemyType.tags) == nil
			or not boundedNumber(enemyType.health, MAX_PREDICATE_MAGNITUDE)
			or not boundedNumber(enemyType.speed, MAX_PREDICATE_MAGNITUDE)
			or not boundedNumber(enemyType.reward, MAX_PREDICATE_MAGNITUDE)
			or not boundedNumber(enemyType.baseDamage, MAX_PREDICATE_MAGNITUDE)
			or not boundedNumber(enemyType.renderScale, MAX_PREDICATE_MAGNITUDE)
		then
			return `enemy type {enemyTypeId} is malformed`
		end
		for _, tag in enemyType.tags do
			if type(tag) ~= "string" then
				return `enemy type {enemyTypeId} has a non-string tag`
			end
		end
		local tint = enemyType.tint
		if tint ~= nil then
			if
				type(tint) ~= "table"
				or not boundedNumber(tint.r, 1)
				or not boundedNumber(tint.g, 1)
				or not boundedNumber(tint.b, 1)
			then
				return `enemy type {enemyTypeId} has a malformed tint`
			end
		end
		enemyTypeIds[enemyTypeId] = true
	end
	if not hasEnemyType then
		return "project must contain at least one enemy type"
	end
	if type(project.waveSets) ~= "table" then
		return "waveSets must be a table"
	end
	if type(project.waveSets.default) ~= "table" then
		return "waveSets must contain the default wave set"
	end
	for waveSetId, waveSet in project.waveSets do
		if type(waveSetId) ~= "string" or type(waveSet) ~= "table" then
			return "every wave set entry must use a string ID and table value"
		end
		if
			type(waveSet.id) ~= "string"
			or waveSet.id ~= waveSetId
			or type(waveSet.name) ~= "string"
			or denseArrayLength(waveSet.waves) == nil
		then
			return `wave set {waveSetId} is malformed`
		end
		for waveIndex, wave in waveSet.waves do
			if
				type(wave) ~= "table"
				or (wave.isBoss ~= nil and type(wave.isBoss) ~= "boolean")
				or denseArrayLength(wave.entries) == nil
			then
				return `wave set {waveSetId} wave {waveIndex} is malformed`
			end
			for entryIndex, waveEntry in wave.entries do
				if
					type(waveEntry) ~= "table"
					or type(waveEntry.enemyTypeId) ~= "string"
					or enemyTypeIds[waveEntry.enemyTypeId] ~= true
					or not boundedNumber(waveEntry.count, MAX_PREDICATE_MAGNITUDE)
					or not boundedNumber(waveEntry.spacingSeconds, MAX_PREDICATE_MAGNITUDE)
					or not boundedNumber(waveEntry.startDelaySeconds, MAX_PREDICATE_MAGNITUDE)
					or not optionalBoundedNumber(waveEntry.healthScale, MAX_PREDICATE_MAGNITUDE)
					or not optionalBoundedNumber(waveEntry.rewardScale, MAX_PREDICATE_MAGNITUDE)
					or not optionalBoundedNumber(waveEntry.speedScale, MAX_PREDICATE_MAGNITUDE)
				then
					return `wave set {waveSetId} wave {waveIndex} entry {entryIndex} is malformed`
				end
			end
		end
	end
	local hasStage = false
	local mapByStageGroup: { [string]: string } = {}
	for stageId, stage in project.stages do
		hasStage = true
		if type(stageId) ~= "string" or type(stage) ~= "table" then
			return "every stage entry must use a string ID and table value"
		end
		if
			type(stage.id) ~= "string"
			or type(stage.mapId) ~= "string"
			or type(stage.stageGroupId) ~= "string"
			or type(stage.name) ~= "string"
			or type(stage.waveSetId) ~= "string"
			or type(stage.themeId) ~= "string"
		then
			return `stage {stageId} is missing required string fields`
		end
		if project.maps[stage.mapId] == nil then
			return `stage {stageId} references missing Map {stage.mapId}`
		end
		if project.waveSets[stage.waveSetId] == nil then
			return `stage {stageId} references missing wave set {stage.waveSetId}`
		end
		mapHasLevel[stage.mapId] = true
		if
			not finiteNumber(stage.stageNumber)
			or stage.stageNumber % 1 ~= 0
			or stage.stageNumber < 1
			or stage.stageNumber > 999
			or not finiteNumber(stage.levelNumber)
			or stage.levelNumber % 1 ~= 0
			or stage.levelNumber < 1
			or stage.levelNumber > 999
		then
			return `stage {stageId} has an unsafe hierarchy address`
		end
		local existingMapId = mapByStageGroup[stage.stageGroupId]
		if existingMapId ~= nil and existingMapId ~= stage.mapId then
			return `stage group {stage.stageGroupId} belongs to more than one Map`
		end
		mapByStageGroup[stage.stageGroupId] = stage.mapId
		if
			type(stage.metadata) ~= "table"
			or denseArrayLength(stage.modifierIds) == nil
			or denseArrayLength(stage.unlockRequirements) == nil
		then
			return `stage {stageId} is missing required collection fields`
		end
		for _, modifierId in stage.modifierIds do
			if type(modifierId) ~= "string" then
				return `stage {stageId} has a non-string modifier ID`
			end
		end
		for _, requirement in stage.unlockRequirements do
			local requirementError = unlockRequirementShapeError(requirement)
			if requirementError ~= nil then
				return `stage {stageId} has a malformed unlock requirement: {requirementError}`
			end
		end

		local grid = stage.grid
		if type(grid) ~= "table" or type(grid.defaultCell) ~= "table" or type(grid.cells) ~= "table" then
			return `stage {stageId} has a malformed grid`
		end
		if grid.defaultCell.roles ~= nil and type(grid.defaultCell.roles) ~= "table" then
			return `stage {stageId} has malformed default cell roles`
		end
		if grid.defaultCell.metadata ~= nil and type(grid.defaultCell.metadata) ~= "table" then
			return `stage {stageId} has malformed default cell metadata`
		end
		if
			not finiteNumber(grid.columns)
			or grid.columns % 1 ~= 0
			or grid.columns < 1
			or grid.columns > 512
			or not finiteNumber(grid.rows)
			or grid.rows % 1 ~= 0
			or grid.rows < 1
			or grid.rows > 512
			or not finiteNumber(grid.cellSize)
			or grid.cellSize <= 0
			or grid.cellSize > 128
		then
			return `stage {stageId} has unsafe grid dimensions`
		end
		for cellKey, cell in grid.cells do
			if type(cellKey) ~= "string" or type(cell) ~= "table" then
				return `stage {stageId} has a malformed cell override`
			end
			if cell.roles ~= nil and type(cell.roles) ~= "table" then
				return `stage {stageId} cell {cellKey} has malformed roles`
			end
			if cell.metadata ~= nil and type(cell.metadata) ~= "table" then
				return `stage {stageId} cell {cellKey} has malformed metadata`
			end
		end

		if type(stage.pathGraphs) ~= "table" then
			return `stage {stageId} has malformed path graphs`
		end
		for graphId, graph in stage.pathGraphs do
			if
				type(graphId) ~= "string"
				or type(graph) ~= "table"
				or type(graph.id) ~= "string"
				or type(graph.name) ~= "string"
				or type(graph.nodes) ~= "table"
				or type(graph.edges) ~= "table"
				or type(graph.laneProfiles) ~= "table"
				or not boundedNumber(graph.maxNodeVisitsPerEnemy, MAX_GRAPH_SCALAR_MAGNITUDE)
				or not boundedNumber(graph.maxTravelDistance, MAX_GRAPH_SCALAR_MAGNITUDE)
			then
				return `stage {stageId} has malformed graph {tostring(graphId)}`
			end
			for nodeId, node in graph.nodes do
				if
					type(nodeId) ~= "string"
					or type(node) ~= "table"
					or type(node.id) ~= "string"
					or type(node.name) ~= "string"
					or type(node.kind) ~= "string"
					or not vectorShape(node.position)
					or denseArrayLength(node.tags) == nil
				then
					return `graph {graphId} has malformed node {tostring(nodeId)}`
				end
				for _, tag in node.tags do
					if type(tag) ~= "string" then
						return `graph {graphId} node {nodeId} has a non-string tag`
					end
				end
			end
			for edgeId, edge in graph.edges do
				if
					type(edgeId) ~= "string"
					or type(edge) ~= "table"
					or type(edge.id) ~= "string"
					or type(edge.fromNodeId) ~= "string"
					or type(edge.toNodeId) ~= "string"
					or type(edge.laneProfileId) ~= "string"
					or not boundedNumber(edge.priority, MAX_GRAPH_SCALAR_MAGNITUDE)
					or denseArrayLength(edge.predicates) == nil
					or not vectorShape(edge.outHandleOffset)
					or not vectorShape(edge.inHandleOffset)
				then
					return `graph {graphId} has malformed edge {tostring(edgeId)}`
				end
				for _, predicate in edge.predicates do
					local predicateError = predicateShapeError(predicate)
					if predicateError ~= nil then
						return `graph {graphId} edge {edgeId} has a malformed predicate: {predicateError}`
					end
				end
			end
			for profileId, profile in graph.laneProfiles do
				if
					type(profileId) ~= "string"
					or type(profile) ~= "table"
					or type(profile.id) ~= "string"
					or denseArrayLength(profile.offsets) == nil
					or not boundedNumber(profile.clearanceRadius, MAX_SPATIAL_MAGNITUDE)
					or profile.clearanceRadius / grid.cellSize > MAX_ROUTE_CELL_RADIUS
				then
					return `graph {graphId} has malformed lane profile {tostring(profileId)}`
				end
				for _, offset in profile.offsets do
					if not boundedNumber(offset, MAX_SPATIAL_MAGNITUDE) then
						return `graph {graphId} lane profile {profileId} has a malformed offset`
					end
				end
			end
		end
	end
	for mapId, ownsLevel in mapHasLevel do
		if not ownsLevel then
			return `Map {mapId} must contain at least one Level`
		end
	end
	if not hasStage then
		return "project must contain at least one stage"
	end
	if project.stages[project.startingStageId] == nil then
		return "startingStageId must reference a stored stage"
	end
	return nil
end

local function hasAnyChunkMetadata(snapshot: PayloadSnapshot): boolean
	return snapshot.chunkCountAttribute ~= nil
		or snapshot.payloadLengthAttribute ~= nil
		or snapshot.payloadChecksumAttribute ~= nil
end

local function validateWorkingChecksum(value: any, expectedChecksum: string): CorruptPayload?
	if value == nil then
		return nil
	end
	if type(value) ~= "string" then
		return corruptPayload(
			"InvalidWorkingChecksum",
			"Stagewright WorkingChecksum attribute must be a string"
		)
	end
	if value ~= expectedChecksum then
		return corruptPayload(
			"WorkingChecksumMismatch",
			"Stagewright WorkingChecksum attribute does not match the payload"
		)
	end
	return nil
end

local function directPayload(snapshot: PayloadSnapshot, value: string): PayloadResult
	if string.sub(value, 1, #"StagewrightChunked:") == "StagewrightChunked:" then
		return corruptPayload("InvalidManifest", "Stagewright payload has a malformed chunk manifest")
	end
	if #value > StagePayload.MAX_PAYLOAD_SIZE then
		return corruptPayload("PayloadTooLarge", "Stagewright payload exceeds the supported size")
	end
	if snapshot.chunksState == "Invalid" then
		return corruptPayload("InvalidChunks", "Stagewright payload chunks use an unexpected Instance class")
	end
	if snapshot.chunksState == "Present" then
		return corruptPayload(
			"UnexpectedChunks",
			"Stagewright payload has chunk data but no valid chunk manifest"
		)
	end
	if hasAnyChunkMetadata(snapshot) then
		return corruptPayload(
			"UnexpectedChunkMetadata",
			"Stagewright payload has chunk metadata but no chunk folder"
		)
	end
	local expectedChecksum = snapshot.workingChecksumAttribute
	if expectedChecksum ~= nil and type(expectedChecksum) ~= "string" then
		return corruptPayload(
			"InvalidWorkingChecksum",
			"Stagewright WorkingChecksum attribute must be a string"
		)
	end
	return {
		kind = "Encoded",
		encoded = value,
		expectedChecksum = expectedChecksum,
	}
end

local function chunkedPayload(snapshot: PayloadSnapshot, manifest: StagePayload.Manifest): PayloadResult
	if snapshot.chunksState == "Missing" then
		return corruptPayload("MissingChunks", "Stagewright payload chunk folder is missing")
	end
	if snapshot.chunksState == "Invalid" then
		return corruptPayload("InvalidChunks", "Stagewright payload chunk folder has the wrong class")
	end
	if snapshot.chunksClassName ~= "Folder" then
		return corruptPayload("InvalidChunks", "Stagewright payload chunk folder has the wrong class")
	end
	if
		type(snapshot.chunkCountAttribute) ~= "number"
		or snapshot.chunkCountAttribute ~= manifest.chunkCount
		or type(snapshot.payloadLengthAttribute) ~= "number"
		or snapshot.payloadLengthAttribute ~= manifest.length
		or type(snapshot.payloadChecksumAttribute) ~= "string"
		or snapshot.payloadChecksumAttribute ~= manifest.checksum
	then
		return corruptPayload(
			"ChunkMetadataMismatch",
			"Stagewright payload chunk attributes do not match the manifest"
		)
	end
	local workingChecksumError = validateWorkingChecksum(snapshot.workingChecksumAttribute, manifest.checksum)
	if workingChecksumError ~= nil then
		return workingChecksumError
	end

	local chunks: { string } = {}
	local seen: { [number]: boolean } = {}
	for _, child in snapshot.chunks do
		if child.className ~= "StringValue" or type(child.value) ~= "string" then
			return corruptPayload(
				"InvalidChunkClass",
				`Stagewright payload chunk {child.name} must be a StringValue`
			)
		end
		local indexText = string.match(child.name, "^Chunk_(%d+)$")
		local index = if indexText ~= nil then tonumber(indexText) else nil
		if
			index == nil
			or index < 1
			or index > manifest.chunkCount
			or StagePayload.chunkName(index) ~= child.name
		then
			return corruptPayload("UnexpectedChunk", `Stagewright payload has unexpected chunk {child.name}`)
		end
		if seen[index] then
			return corruptPayload("DuplicateChunk", `Stagewright payload has duplicate chunk {child.name}`)
		end
		seen[index] = true
		chunks[index] = child.value
	end

	local encoded, joinError = StagePayload.join(chunks, manifest.chunkCount, manifest.length)
	if encoded == nil then
		local code = if joinError ~= nil and string.find(joinError, "is missing", 1, true) ~= nil
			then "MissingChunk"
			elseif
				joinError ~= nil and string.find(joinError, "invalid length", 1, true) ~= nil
			then "InvalidChunkLength"
			else "PayloadLengthMismatch"
		return corruptPayload(code, joinError or "Stagewright payload chunks could not be joined")
	end
	return {
		kind = "Encoded",
		encoded = encoded,
		expectedChecksum = manifest.checksum,
	}
end

function ProjectLoadPolicy.readPayload(snapshot: PayloadSnapshot): PayloadResult
	if snapshot.containerState == "Missing" then
		return missingPayload("MissingContainer", "Stagewright project storage is missing")
	end
	if snapshot.containerState == "Invalid" then
		return corruptPayload(
			"InvalidContainer",
			`Stagewright project storage must be a Folder, not {snapshot.containerClassName or "unknown"}`
		)
	end
	if snapshot.containerClassName ~= "Folder" then
		return corruptPayload("InvalidContainer", "Stagewright project storage must be a Folder")
	end
	if snapshot.valueState == "Missing" then
		return corruptPayload("MissingPayload", "Stagewright project payload is missing")
	end
	if snapshot.valueState == "Invalid" then
		return corruptPayload(
			"InvalidPayloadValue",
			`Stagewright project payload must be a StringValue, not {snapshot.valueClassName or "unknown"}`
		)
	end
	if snapshot.valueClassName ~= "StringValue" then
		return corruptPayload("InvalidPayloadValue", "Stagewright project payload must be a StringValue")
	end
	local value = snapshot.value or ""
	if value == "" then
		return corruptPayload("EmptyPayload", "Stagewright project payload is empty")
	end
	local manifest = StagePayload.parseManifest(value)
	if manifest == nil then
		return directPayload(snapshot, value)
	end
	return chunkedPayload(snapshot, manifest)
end

function ProjectLoadPolicy.planEncoded(
	encoded: string,
	expectedChecksum: string?,
	decodeJson: (string) -> any
): LoadResult
	if #encoded > StagePayload.MAX_PAYLOAD_SIZE then
		return corrupt("PayloadTooLarge", "Stagewright project payload exceeds the supported size")
	end
	if expectedChecksum ~= nil and type(expectedChecksum) ~= "string" then
		return corrupt("InvalidExpectedChecksum", "Stagewright payload checksum must be a string")
	end
	local decodeSuccess, decoded = pcall(decodeJson, encoded)
	if not decodeSuccess or type(decoded) ~= "table" then
		return corrupt("InvalidJson", "Stagewright project payload is not valid JSON")
	end

	local versionValue = decoded.schemaVersion
	local sourceVersion = 0
	if versionValue ~= nil then
		if
			type(versionValue) ~= "number"
			or versionValue ~= versionValue
			or versionValue < 0
			or versionValue % 1 ~= 0
		then
			return corrupt("InvalidSchemaVersion", "Stagewright project schema version is invalid")
		end
		sourceVersion = versionValue
	end
	local persistedChecksum = StageSchema.checksumEncoded(encoded)
	if expectedChecksum ~= nil and persistedChecksum ~= expectedChecksum then
		return corrupt("ChecksumMismatch", "Stagewright project checksum does not match stored data")
	end
	if sourceVersion > StageSchema.AUTHORING_VERSION then
		return {
			kind = "UnsupportedFutureVersion",
			foundVersion = sourceVersion,
			supportedVersion = StageSchema.AUTHORING_VERSION,
			message = `Stagewright project schema {sourceVersion} is newer than supported schema {StageSchema.AUTHORING_VERSION}`,
		}
	end
	if type(decoded.stages) ~= "table" then
		return corrupt("InvalidProjectShape", "Stagewright project stages must be a table")
	end

	local migrationSuccess, migrated = pcall(function()
		return StageSchema.migrateProject(decoded)
	end)
	if not migrationSuccess or type(migrated) ~= "table" then
		return corrupt("MigrationFailed", `Stagewright project migration failed: {tostring(migrated)}`)
	end
	if migrated.schemaVersion ~= StageSchema.AUTHORING_VERSION or type(migrated.stages) ~= "table" then
		return corrupt("MigrationFailed", "Stagewright project migration produced an invalid project")
	end
	local shapeError = projectShapeError(migrated)
	if shapeError ~= nil then
		return corrupt(
			if sourceVersion < StageSchema.AUTHORING_VERSION then "MigrationFailed" else "InvalidProjectShape",
			`Stagewright project structure is unsafe to edit: {shapeError}`
		)
	end
	if sourceVersion < StageSchema.AUTHORING_VERSION then
		return {
			kind = "LegacyMigratedInMemory",
			project = migrated,
			sourceVersion = sourceVersion,
			persistedChecksum = persistedChecksum,
		}
	end
	return {
		kind = "Ready",
		project = migrated,
		sourceVersion = sourceVersion,
		persistedChecksum = persistedChecksum,
	}
end

function ProjectLoadPolicy.plan(snapshot: PayloadSnapshot, decodeJson: (string) -> any): PlanResult
	local payload = ProjectLoadPolicy.readPayload(snapshot)
	if payload.kind == "Missing" then
		if payload.code == "MissingContainer" then
			return { kind = "Initialize" }
		end
		return corrupt(payload.code, payload.message)
	end
	if payload.kind == "Corrupt" then
		return corrupt(payload.code, payload.message)
	end
	local planned = ProjectLoadPolicy.planEncoded(payload.encoded, payload.expectedChecksum, decodeJson)
	local schemaVersionAttribute = snapshot.schemaVersionAttribute
	-- Older valid stores may not have this root attribute. The embedded payload remains authoritative,
	-- and the next explicit save can backfill metadata without causing a write during plugin startup.
	if planned.kind == "Corrupt" or schemaVersionAttribute == nil then
		return planned
	end
	if
		type(schemaVersionAttribute) ~= "number"
		or schemaVersionAttribute ~= schemaVersionAttribute
		or schemaVersionAttribute < 0
		or schemaVersionAttribute % 1 ~= 0
	then
		return corrupt("InvalidSchemaAttribute", "Stagewright SchemaVersion attribute is invalid")
	end
	local payloadVersion = if planned.kind == "UnsupportedFutureVersion"
		then planned.foundVersion
		else planned.sourceVersion
	if schemaVersionAttribute ~= payloadVersion then
		return corrupt(
			"SchemaVersionMismatch",
			"Stagewright SchemaVersion attribute does not match the payload"
		)
	end
	return planned
end

return table.freeze(ProjectLoadPolicy)

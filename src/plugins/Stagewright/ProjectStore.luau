--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AuthoringArea = require(script.Parent.AuthoringArea)
local Shared = script.Parent.Shared
local StageExport = require(Shared.StageExport)
local StageHierarchy = require(Shared.StageHierarchy)
local StageLegacy = require(Shared.StageLegacy)
local StageLanes = require(Shared.StageLanes)
local StagePayload = require(Shared.StagePayload)
local StageSchema = require(Shared.StageSchema)
local StageStarterProject = require(Shared.StageStarterProject)

local ProjectStore = {}

local PROJECT_NAME = "StagewrightProject"
local PAYLOAD_NAME = "Payload"
local project: any = nil
local recording: any = nil
local writingPayload = false
local previewCache: { [string]: { signature: string, stage: any } } = {}

local function configuredStarterLevelCount(): number
	local template = ReplicatedStorage:FindFirstChild("Template")
	local shared = if template ~= nil then template:FindFirstChild("Shared") else nil
	local module = if shared ~= nil then shared:FindFirstChild("TemplateConfig") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return 1
	end
	local success, config = pcall(require, module)
	local value = if success
			and type(config) == "table"
			and type(config.towerDefense) == "table"
		then config.towerDefense.starterLevelsPerStage
		else nil
	return if type(value) == "number" then math.clamp(math.floor(value), 1, 100) else 1
end

local function guid(prefix: string): string
	return `{prefix}_{string.lower(HttpService:GenerateGUID(false))}`
end

local function clone(value: any, seen: { [table]: table }?): any
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	if visited[value] ~= nil then
		return visited[value]
	end
	local result = {}
	visited[value] = result
	for key, child in value do
		result[clone(key, visited)] = clone(child, visited)
	end
	return result
end

local function container(): (Folder, StringValue)
	local folder = ServerStorage:FindFirstChild(PROJECT_NAME)
	if folder == nil or not folder:IsA("Folder") then
		if folder ~= nil then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = PROJECT_NAME
		folder.Parent = ServerStorage
	end
	local payload = folder:FindFirstChild(PAYLOAD_NAME)
	if payload == nil or not payload:IsA("StringValue") then
		if payload ~= nil then
			payload:Destroy()
		end
		payload = Instance.new("StringValue")
		payload.Name = PAYLOAD_NAME
		payload.Parent = folder
	end
	return folder, payload
end

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder == nil or not folder:IsA("Folder") then
		if folder ~= nil then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

function ProjectStore.writePayload(
	parent: Instance,
	valueName: string,
	encoded: string,
	checksum: string
): StringValue
	local value = parent:FindFirstChild(valueName)
	if value == nil or not value:IsA("StringValue") then
		if value ~= nil then
			value:Destroy()
		end
		value = Instance.new("StringValue")
		value.Name = valueName
		value.Parent = parent
	end
	local chunksName = StagePayload.chunksName(valueName)
	local existingChunks = parent:FindFirstChild(chunksName)
	if #encoded <= StagePayload.CHUNK_SIZE then
		value.Value = encoded
		if existingChunks ~= nil then
			existingChunks:Destroy()
		end
		return value
	end

	local chunksFolder = ensureFolder(parent, chunksName)
	local chunks = StagePayload.split(encoded)
	for index, chunk in chunks do
		local chunkName = StagePayload.chunkName(index)
		local child = chunksFolder:FindFirstChild(chunkName)
		if child == nil or not child:IsA("StringValue") then
			if child ~= nil then
				child:Destroy()
			end
			child = Instance.new("StringValue")
			child.Name = chunkName
			child.Parent = chunksFolder
		end
		child.Value = chunk
	end
	for _, child in chunksFolder:GetChildren() do
		local indexText = string.match(child.Name, "^Chunk_(%d+)$")
		local index = if indexText ~= nil then tonumber(indexText) else nil
		if index == nil or index < 1 or index > #chunks or not child:IsA("StringValue") then
			child:Destroy()
		end
	end
	chunksFolder:SetAttribute("ChunkCount", #chunks)
	chunksFolder:SetAttribute("PayloadLength", #encoded)
	chunksFolder:SetAttribute("PayloadChecksum", checksum)
	value.Value = StagePayload.manifest(checksum, #chunks, #encoded)
	return value
end

function ProjectStore.readPayload(
	parent: Instance,
	valueName: string
): (string?, string?, StagePayload.Manifest?)
	local value = parent:FindFirstChild(valueName)
	if value == nil or not value:IsA("StringValue") then
		return nil, `{valueName} is missing`, nil
	end
	local manifest = StagePayload.parseManifest(value.Value)
	if manifest == nil then
		return value.Value, nil, nil
	end
	local chunksFolder = parent:FindFirstChild(StagePayload.chunksName(valueName))
	if chunksFolder == nil or not chunksFolder:IsA("Folder") then
		return nil, `{StagePayload.chunksName(valueName)} is missing`, manifest
	end
	local chunks: { string } = {}
	for index = 1, manifest.chunkCount do
		local child = chunksFolder:FindFirstChild(StagePayload.chunkName(index))
		if child ~= nil and child:IsA("StringValue") then
			chunks[index] = child.Value
		end
	end
	local encoded, message = StagePayload.join(chunks, manifest.chunkCount, manifest.length)
	if encoded ~= nil then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(encoded)
		end)
		if success and type(decoded) == "table" and StageSchema.checksum(decoded) ~= manifest.checksum then
			return nil, "Payload checksum does not match its chunk manifest", manifest
		end
	end
	return encoded, message, manifest
end

local function storedProject(folder: Folder): (any?, string?)
	local encoded, readError = ProjectStore.readPayload(folder, PAYLOAD_NAME)
	if encoded == nil or encoded == "" then
		return nil, readError
	end
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not success or type(decoded) ~= "table" or type(decoded.stages) ~= "table" then
		return nil, "Payload JSON is invalid; preserved for manual recovery"
	end
	return decoded, nil
end

local function intValue(parent: Instance?, name: string, fallback: number): number
	local value = if parent ~= nil then parent:FindFirstChild(name) else nil
	return if value ~= nil and value:IsA("IntValue") and value.Value > 0 then value.Value else fallback
end

local function legacyRows(platform: Instance?): ({ string }, number, number, number)
	local rows: { string } = {}
	local map = if platform ~= nil then platform:FindFirstChild("CellMap") else nil
	local rowCount = intValue(platform, "Rows", 27)
	local rowWidth = 0
	if map ~= nil then
		for row = 1, rowCount do
			local child = map:FindFirstChild(`Row_{string.format("%02d", row)}`)
			local value = if child ~= nil and child:IsA("StringValue") then child.Value else ""
			rows[row] = value
			rowWidth = math.max(rowWidth, #value)
		end
	end
	return rows,
		intValue(platform, "Columns", math.max(rowWidth, 32)),
		rowCount,
		intValue(platform, "CellSize", 4)
end

local function legacyControlPositions(platform: Instance?): { any }
	local result: { any } = {}
	local base = if platform ~= nil then platform:FindFirstChild("PlatformBase") else nil
	local origin = if platform ~= nil then platform:FindFirstChild("PlatformOrigin") else nil
	local points = if platform ~= nil then platform:FindFirstChild("PathPoints") else nil
	local coordinateFrame = if origin ~= nil and origin:IsA("BasePart")
		then origin.CFrame
		elseif base ~= nil and base:IsA("BasePart") then base.CFrame
		else nil
	if coordinateFrame == nil or points == nil then
		return result
	end
	local parts: { BasePart } = {}
	for _, child in points:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(left, right)
		return left.Name < right.Name
	end)
	for _, part in parts do
		local position = coordinateFrame:PointToObjectSpace(part.CFrame.Position)
		table.insert(result, { x = position.X, y = position.Y, z = position.Z })
	end
	return result
end

local function defaultProject(platformOverride: Instance?): any
	local platform = platformOverride or AuthoringArea.findPlatform()
	local rows, columns, rowCount, cellSize = legacyRows(platform)
	local controls = legacyControlPositions(platform)
	local hasAuthoredCells = false
	for _, row in rows do
		if string.find(row, "[^.]") ~= nil then
			hasAuthoredCells = true
			break
		end
	end
	local imported = StageLegacy.project({
		columns = columns,
		rows = rowCount,
		cellSize = cellSize,
		rowValues = rows,
		controlPositions = controls,
		stageId = "stage_default",
		graphId = "graph_main",
		stageName = "Level 1",
		blankFallback = not hasAuthoredCells and #controls == 0,
	})
	return imported
end

function ProjectStore.load(platformOverride: Instance?): any
	local folder, payload = container()
	if payload.Value ~= "" then
		local decoded, loadError = storedProject(folder)
		if decoded ~= nil then
			project = StageSchema.migrateProject(decoded)
			if StageStarterProject.isRecognizedLegacyTestProject(project) then
				project = StageStarterProject.build(
					configuredStarterLevelCount(),
					guid,
					"stage_default",
					"stage_group_1"
				)
				folder:SetAttribute("AuthorizedStarterReplacementRevision", StageStarterProject.REVISION)
				folder:SetAttribute(
					"AuthorizedStarterReplacementStatus",
					"Replaced recognized legacy test data"
				)
			else
				ProjectStore.ensureStarterLevels(configuredStarterLevelCount())
			end
			ProjectStore.save()
			return project
		end
		folder:SetAttribute("LoadError", loadError)
	end
	project = StageSchema.migrateProject(defaultProject(platformOverride))
	ProjectStore.ensureStarterLevels(configuredStarterLevelCount())
	ProjectStore.save()
	return project
end

function ProjectStore.get(): any
	return project or ProjectStore.load()
end

function ProjectStore.save(): string
	local folder = container()
	local encoded = StageSchema.encodeCanonical(ProjectStore.get())
	local checksum = StageSchema.checksum(ProjectStore.get())
	writingPayload = true
	local success, message = pcall(function()
		ProjectStore.writePayload(folder, PAYLOAD_NAME, encoded, checksum)
	end)
	writingPayload = false
	if not success then
		error(message)
	end
	folder:SetAttribute("SchemaVersion", StageSchema.AUTHORING_VERSION)
	folder:SetAttribute("WorkingChecksum", checksum)
	return checksum
end

function ProjectStore.preview(stageId: string): any?
	local source = ProjectStore.get().stages[stageId]
	if source == nil then
		return nil
	end
	local signature = StageSchema.checksum({
		grid = {
			columns = source.grid.columns,
			rows = source.grid.rows,
			cellSize = source.grid.cellSize,
		},
		pathGraphs = source.pathGraphs,
	})
	local cached = previewCache[stageId]
	if cached ~= nil and cached.signature == signature then
		return cached.stage
	end
	local preview = StageExport.preview(source)
	if preview ~= nil then
		preview.routePreviewSignature = signature
		previewCache[stageId] = { signature = signature, stage = preview }
	end
	return preview
end

function ProjectStore.workingChecksum(): string
	local folder = container()
	local checksum = folder:GetAttribute("WorkingChecksum")
	return if type(checksum) == "string" then checksum else ProjectStore.save()
end

function ProjectStore.observe(callback: () -> ()): RBXScriptConnection
	local folder, payload = container()
	local revision = 0
	return payload:GetPropertyChangedSignal("Value"):Connect(function()
		if writingPayload then
			return
		end
		revision += 1
		local requestedRevision = revision
		task.defer(function()
			if requestedRevision ~= revision then
				return
			end
			local decoded, loadError = storedProject(folder)
			if decoded ~= nil then
				project = StageSchema.migrateProject(decoded)
				folder:SetAttribute("LoadError", nil)
				callback()
			else
				folder:SetAttribute("LoadError", loadError)
			end
		end)
	end)
end

function ProjectStore.begin(name: string): boolean
	if recording ~= nil then
		return true
	end
	recording = ChangeHistoryService:TryBeginRecording(name, name)
	return recording ~= nil
end

function ProjectStore.finish(commit: boolean)
	if recording == nil then
		return
	end
	ProjectStore.save()
	ChangeHistoryService:FinishRecording(
		recording,
		if commit then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
	recording = nil
end

function ProjectStore.mutate(name: string, callback: () -> ())
	ProjectStore.begin(name)
	local success, message = pcall(callback)
	ProjectStore.finish(success)
	if not success then
		error(message)
	end
end

function ProjectStore.stageIds(): { string }
	return StageHierarchy.sortedIds(ProjectStore.get().stages)
end

function ProjectStore.address(stageId: string): StageHierarchy.Address?
	local definition = ProjectStore.get().stages[stageId]
	return if definition ~= nil then StageHierarchy.address(definition) else nil
end

local function refreshDisplayOrder()
	for order, id in ProjectStore.stageIds() do
		project.stages[id].displayOrder = order
	end
end

local function copiedDefinition(
	source: any,
	blank: boolean,
	groupId: string,
	stageNumber: number,
	levelNumber: number
): any
	local stage = clone(source)
	if blank then
		local graphId = guid("graph")
		local laneOffsets = StageLanes.offsets(StageLanes.DEFAULT_COUNT)
		stage.grid.cells = {}
		stage.pathGraphs = {
			[graphId] = {
				id = graphId,
				name = "Main Route",
				nodes = {},
				edges = {},
				laneProfiles = {
					lane_default = {
						id = "lane_default",
						offsets = laneOffsets,
						clearanceRadius = StageLanes.clearanceRadius(laneOffsets),
					},
				},
				maxNodeVisitsPerEnemy = 64,
				maxTravelDistance = 10_000,
			},
		}
	end
	local stageId = guid("stage")
	stage.id = stageId
	stage.schemaVersion = StageSchema.AUTHORING_VERSION
	StageHierarchy.assign(stage, groupId, stageNumber, levelNumber)
	stage.name = `Level {levelNumber}`
	stage.displayOrder = #ProjectStore.stageIds() + 1
	local rewrittenGraphs: { [string]: any } = {}
	for _, oldGraph in stage.pathGraphs do
		local graph = clone(oldGraph)
		local graphId = guid("graph")
		graph.id = graphId
		local nodeIds: { [string]: string } = {}
		local nodes: { [string]: any } = {}
		for oldNodeId, node in graph.nodes do
			local nodeId = guid("node")
			nodeIds[oldNodeId] = nodeId
			node.id = nodeId
			nodes[nodeId] = node
		end
		local edges: { [string]: any } = {}
		for _, edge in graph.edges do
			local edgeId = guid("edge")
			edge.id = edgeId
			edge.fromNodeId = nodeIds[edge.fromNodeId]
			edge.toNodeId = nodeIds[edge.toNodeId]
			for _, predicate in edge.predicates do
				if predicate.kind == "VisitCountBelow" then
					predicate.nodeId = nodeIds[predicate.nodeId] or predicate.nodeId
				end
			end
			edge.samples = nil
			edge.length = nil
			edges[edgeId] = edge
		end
		graph.nodes = nodes
		graph.edges = edges
		graph.outgoingEdgeIds = nil
		rewrittenGraphs[graphId] = graph
	end
	stage.pathGraphs = rewrittenGraphs
	return stage
end

function ProjectStore.createStage(copyFromId: string?): string
	local source = if copyFromId ~= nil then project.stages[copyFromId] else nil
	source = source or project.stages[ProjectStore.stageIds()[1]]
	assert(source ~= nil, "A Stagewright project needs a source definition")
	local stage = copiedDefinition(
		source,
		copyFromId == nil,
		guid("stage_group"),
		StageHierarchy.nextStageNumber(project.stages),
		1
	)
	stage.unlockRequirements = {}
	local stageId = stage.id
	project.stages[stageId] = stage
	refreshDisplayOrder()
	return stageId
end

function ProjectStore.createLevel(copyFromId: string): string
	local source = project.stages[copyFromId]
	assert(source ~= nil, "Select a level to copy first")
	local sourceAddress = StageHierarchy.address(source)
	local levelNumber = StageHierarchy.nextLevelNumber(project.stages, sourceAddress.groupId)
	local previousId = copyFromId
	for id, definition in project.stages do
		local address = StageHierarchy.address(definition)
		if address.groupId == sourceAddress.groupId and address.levelNumber == levelNumber - 1 then
			previousId = id
			break
		end
	end
	local stage =
		copiedDefinition(source, false, sourceAddress.groupId, sourceAddress.stageNumber, levelNumber)
	stage.unlockRequirements = { { kind = "StageUnlocked", stageId = previousId } }
	project.stages[stage.id] = stage
	refreshDisplayOrder()
	return stage.id
end

function ProjectStore.ensureStarterLevels(levelCount: any): boolean
	local requested = if type(levelCount) == "number" then math.clamp(math.floor(levelCount), 1, 100) else 1
	local ids = ProjectStore.stageIds()
	if #ids ~= 1 or requested <= 1 then
		return false
	end
	project.metadata = project.metadata or {}
	local alreadySeeded = project.metadata["stagewright.starterLevelCount"]
	if type(alreadySeeded) == "number" and alreadySeeded >= requested then
		return false
	end
	local firstId = ids[1]
	local first = project.stages[firstId]
	local firstAddress = StageHierarchy.address(first)
	first.name = "Level 1"
	for _ = 2, requested do
		ProjectStore.createLevel(firstId)
	end
	project.metadata["stagewright.starterLevelCount"] = requested
	project.metadata["stagewright.starterStageGroupId"] = firstAddress.groupId
	refreshDisplayOrder()
	return true
end

function ProjectStore.inboundReferences(stageId: string): { string }
	local references: { string } = {}
	for ownerId, stage in project.stages do
		for _, requirement in stage.unlockRequirements do
			if requirement.kind == "StageUnlocked" and requirement.stageId == stageId then
				table.insert(references, `{ownerId}: unlock requirement`)
			end
		end
		for key, cell in stage.grid.cells do
			if cell.metadata ~= nil and cell.metadata.transitionStageId == stageId then
				table.insert(references, `{ownerId}: cell {key}`)
			end
		end
	end
	return references
end

function ProjectStore.deleteStage(stageId: string): (boolean, string)
	if #ProjectStore.stageIds() <= 1 then
		return false, "A project must contain at least one stage"
	end
	local inbound = ProjectStore.inboundReferences(stageId)
	if #inbound > 0 then
		return false, `Stage has inbound references: {table.concat(inbound, ", ")}`
	end
	project.stages[stageId] = nil
	if project.startingStageId == stageId then
		project.startingStageId = ProjectStore.stageIds()[1]
	end
	refreshDisplayOrder()
	return true, "Stage deleted"
end

function ProjectStore.moveStage(stageId: string, offset: number)
	local selected = project.stages[stageId]
	if selected == nil then
		return
	end
	local selectedAddress = StageHierarchy.address(selected)
	local ids: { string } = {}
	for _, id in ProjectStore.stageIds() do
		if StageHierarchy.address(project.stages[id]).groupId == selectedAddress.groupId then
			table.insert(ids, id)
		end
	end
	local current = table.find(ids, stageId)
	if current == nil then
		return
	end
	local destination = math.clamp(current + offset, 1, #ids)
	local destinationAddress = StageHierarchy.address(project.stages[ids[destination]])
	selected.levelNumber = destinationAddress.levelNumber
	project.stages[ids[destination]].levelNumber = selectedAddress.levelNumber
	refreshDisplayOrder()
end

function ProjectStore.validate(): { StageSchema.Issue }
	local result = StageExport.bake(ProjectStore.get())
	return result.issues
end

function ProjectStore.export(): StageExport.ExportResult
	return StageExport.bake(ProjectStore.get())
end

function ProjectStore.importPayload(encoded: string): (boolean, string)
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not success or type(decoded) ~= "table" or type(decoded.stages) ~= "table" then
		return false, "Selected bundle has invalid authoring JSON"
	end
	local previous = project
	project = StageSchema.migrateProject(decoded)
	local result = StageExport.bake(project)
	if result.bundle == nil then
		project = previous
		return false, "Selected bundle did not pass Stagewright validation"
	end
	ProjectStore.save()
	return true, `Imported {#ProjectStore.stageIds()} stage(s)`
end

function ProjectStore.cleanup()
	ProjectStore.finish(true)
end

return ProjectStore

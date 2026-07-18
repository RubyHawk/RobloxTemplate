--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuthoringArea = require(script.Parent.AuthoringArea)
local ProjectLoadPolicy = require(script.Parent.Persistence.ProjectLoadPolicy)
local ProjectStorage = require(script.Parent.Persistence.ProjectStorage)
local Shared = script.Parent.Shared
local StageExport = require(Shared.StageExport)
local StageHierarchy = require(Shared.StageHierarchy)
local StageLegacy = require(Shared.StageLegacy)
local StageLanes = require(Shared.StageLanes)
local StageSchema = require(Shared.StageSchema)
local StageStarterProject = require(Shared.StageStarterProject)

local ProjectStore = {}

type LoadResult = ProjectLoadPolicy.PlanResult
export type Transaction = number

local project: any = nil
local loadResult: LoadResult? = nil
local recording: any = nil
local recordingSnapshot: any = nil
local activeTransaction: Transaction? = nil
local nextTransactionId = 0
local writingPayload = false
local writesSuspended = false
local previewCache: { [string]: { signature: string, stage: any } } = {}
local observerCallback: (() -> ())? = nil
local observerRevision = 0
local ensureStarterLevels: (any) -> boolean
local finishActiveTransaction: (boolean) -> boolean

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

local function decodeJson(encoded: string): any
	return HttpService:JSONDecode(encoded)
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

local function recoveryPlaceholder(): any
	return StageStarterProject.build(1, guid, "stage_recovery", "stage_group_recovery")
end

local function initializeInMemory(platformOverride: Instance?, state: ProjectLoadPolicy.Initialize)
	local success, initialized = pcall(function()
		return StageSchema.migrateProject(defaultProject(platformOverride))
	end)
	if success and type(initialized) == "table" then
		project = initialized
		loadResult = state
		local seedSuccess, seedError = pcall(function()
			ensureStarterLevels(configuredStarterLevelCount())
		end)
		if seedSuccess then
			return
		end
		initialized = seedError
	end
	project = recoveryPlaceholder()
	loadResult = {
		kind = "Corrupt",
		code = "InitializationFailed",
		message = `Stagewright could not initialize an in-memory project: {tostring(initialized)}`,
	}
end

local function applyLoadedPlan(state: ProjectLoadPolicy.Ready | ProjectLoadPolicy.LegacyMigratedInMemory)
	project = state.project
	loadResult = state
	local original = clone(project)
	local normalizeSuccess, changed = pcall(function()
		if StageStarterProject.isRecognizedLegacyTestProject(project) then
			project = StageStarterProject.build(
				configuredStarterLevelCount(),
				guid,
				"stage_default",
				"stage_group_1"
			)
			return true
		end
		return ensureStarterLevels(configuredStarterLevelCount())
	end)
	if not normalizeSuccess then
		project = original
		state.project = original
		loadResult = state
		return
	end
	if changed then
		loadResult = {
			kind = "LegacyMigratedInMemory",
			project = project,
			sourceVersion = state.sourceVersion,
			persistedChecksum = state.persistedChecksum,
		}
	end
end

function ProjectStore.load(platformOverride: Instance?): any
	local planned = ProjectLoadPolicy.plan(ProjectStorage.projectSnapshot(), decodeJson)
	writesSuspended = false
	if planned.kind == "Ready" or planned.kind == "LegacyMigratedInMemory" then
		applyLoadedPlan(planned)
	elseif planned.kind == "Initialize" then
		initializeInMemory(platformOverride, planned)
	else
		project = recoveryPlaceholder()
		loadResult = planned
	end
	table.clear(previewCache)
	return project
end

function ProjectStore.get(): any
	return project or ProjectStore.load()
end

local function currentLoadState(): LoadResult
	if loadResult == nil then
		ProjectStore.load()
	end
	return assert(loadResult, "Stagewright load state was not initialized")
end

function ProjectStore.isWritable(): boolean
	if writesSuspended then
		return false
	end
	local state = currentLoadState()
	return state.kind == "Ready" or state.kind == "Initialize" or state.kind == "LegacyMigratedInMemory"
end

function ProjectStore.recoveryMessage(): string?
	if writesSuspended then
		return "Stagewright is verifying an external project update"
	end
	local state = currentLoadState()
	if state.kind == "Corrupt" or state.kind == "UnsupportedFutureVersion" then
		return state.message
	end
	return nil
end

local refreshObserverConnections: () -> ()

local function saveUnchecked(): string
	local current = ProjectStore.get()
	local encoded = StageSchema.encodeCanonical(current)
	local checksum = StageSchema.checksum(current)
	writingPayload = true
	local success, message = pcall(function()
		ProjectStorage.writeProject(encoded, checksum, StageSchema.AUTHORING_VERSION)
	end)
	writingPayload = false
	if not success then
		error(message)
	end
	loadResult = {
		kind = "Ready",
		project = current,
		sourceVersion = StageSchema.AUTHORING_VERSION,
		persistedChecksum = checksum,
	}
	writesSuspended = false
	refreshObserverConnections()
	return checksum
end

function ProjectStore.save(): string
	assert(ProjectStore.isWritable(), "Stagewright project is read-only until recovery succeeds")
	return saveUnchecked()
end

function ProjectStore.preview(stageId: string): any?
	if not ProjectStore.isWritable() then
		return nil
	end
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
	return StageSchema.checksum(ProjectStore.get())
end

local function applyObservedPlan(planned: LoadResult)
	if planned.kind == "Ready" or planned.kind == "LegacyMigratedInMemory" then
		applyLoadedPlan(planned)
	elseif planned.kind == "Initialize" then
		local previous = loadResult
		if previous == nil then
			initializeInMemory(nil, planned)
		elseif previous.kind == "Initialize" then
			loadResult = planned
		else
			loadResult = {
				kind = "Corrupt",
				code = "ProjectStorageRemoved",
				message = "Stagewright project storage was removed after loading. Restore it to continue editing.",
			}
		end
	else
		if project == nil then
			project = recoveryPlaceholder()
		end
		loadResult = planned
	end
	writesSuspended = false
	table.clear(previewCache)
end

local function isSamePersistedRevision(left: LoadResult?, right: LoadResult): boolean
	if left == nil then
		return false
	end
	if left.kind == "Initialize" or right.kind == "Initialize" then
		return left.kind == "Initialize" and right.kind == "Initialize"
	end
	if left.kind ~= "Ready" and left.kind ~= "LegacyMigratedInMemory" then
		return false
	end
	if right.kind ~= "Ready" and right.kind ~= "LegacyMigratedInMemory" then
		return false
	end
	return left.persistedChecksum == right.persistedChecksum and left.sourceVersion == right.sourceVersion
end

local function scheduleObservation()
	if writingPayload then
		return
	end
	writesSuspended = true
	if activeTransaction ~= nil then
		finishActiveTransaction(false)
	end
	observerRevision += 1
	local requestedRevision = observerRevision
	task.defer(function()
		if requestedRevision ~= observerRevision or writingPayload then
			return
		end
		local planned = ProjectLoadPolicy.plan(ProjectStorage.projectSnapshot(), decodeJson)
		applyObservedPlan(planned)
		refreshObserverConnections()
		if observerCallback ~= nil then
			observerCallback()
		end
	end)
end

refreshObserverConnections = function()
	ProjectStorage.refreshRelevantConnections(scheduleObservation)
end

function ProjectStore.observe(callback: () -> ())
	observerCallback = callback
	refreshObserverConnections()
	local planned = ProjectLoadPolicy.plan(ProjectStorage.projectSnapshot(), decodeJson)
	if not isSamePersistedRevision(loadResult, planned) then
		applyObservedPlan(planned)
	end
	callback()
end

function ProjectStore.begin(name: string): Transaction?
	if not ProjectStore.isWritable() then
		return nil
	end
	if recording ~= nil then
		return nil
	end
	recording = ChangeHistoryService:TryBeginRecording(name, name)
	if recording ~= nil then
		recordingSnapshot = clone(ProjectStore.get())
		nextTransactionId += 1
		activeTransaction = nextTransactionId
	end
	return activeTransaction
end

local function restoreRecordingProject(snapshot: any)
	if snapshot == nil then
		return
	end
	project = snapshot
	local state = loadResult
	if state ~= nil and (state.kind == "Ready" or state.kind == "LegacyMigratedInMemory") then
		state.project = snapshot
	end
	table.clear(previewCache)
end

finishActiveTransaction = function(commit: boolean): boolean
	if recording == nil or activeTransaction == nil then
		return false
	end
	local activeRecording = recording
	local snapshot = recordingSnapshot
	if commit and not ProjectStore.isWritable() then
		commit = false
	end
	recording = nil
	recordingSnapshot = nil
	activeTransaction = nil
	if not commit then
		restoreRecordingProject(snapshot)
		ChangeHistoryService:FinishRecording(activeRecording, Enum.FinishRecordingOperation.Cancel)
		return false
	end
	local success, message = pcall(saveUnchecked)
	if not success then
		restoreRecordingProject(snapshot)
		ChangeHistoryService:FinishRecording(activeRecording, Enum.FinishRecordingOperation.Cancel)
		error(message)
	end
	ChangeHistoryService:FinishRecording(activeRecording, Enum.FinishRecordingOperation.Commit)
	return true
end

function ProjectStore.finish(transaction: Transaction, commit: boolean): boolean
	if transaction ~= activeTransaction then
		return false
	end
	return finishActiveTransaction(commit)
end

function ProjectStore.mutate(name: string, callback: () -> ()): boolean
	local transaction = ProjectStore.begin(name)
	if transaction == nil then
		return false
	end
	local success, message = pcall(callback)
	local committed = ProjectStore.finish(transaction, success)
	if not success then
		error(message)
	end
	return committed
end

function ProjectStore.stageIds(): { string }
	return StageHierarchy.sortedIds(ProjectStore.get().stages)
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

ensureStarterLevels = function(levelCount: any): boolean
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

local function inboundReferences(stageId: string): { string }
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
	local inbound = inboundReferences(stageId)
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
	assert(ProjectStore.isWritable(), "Stagewright export is disabled during recovery")
	return StageExport.bake(ProjectStore.get())
end

local function validatedImportPlan(encoded: string, expectedChecksum: string?): (any?, string?)
	local planned = ProjectLoadPolicy.planEncoded(encoded, expectedChecksum, decodeJson)
	if planned.kind == "Corrupt" or planned.kind == "UnsupportedFutureVersion" then
		return nil, planned.message
	end
	local candidate = planned.project
	local bakeSuccess, baked = pcall(function()
		return StageExport.bake(candidate)
	end)
	if not bakeSuccess or type(baked) ~= "table" or baked.bundle == nil then
		return nil, "Selected bundle did not pass Stagewright validation"
	end
	return planned, nil
end

function ProjectStore.importIdentity(encoded: string, expectedChecksum: string?): (string?, string?)
	local planned, message = validatedImportPlan(encoded, expectedChecksum)
	if planned == nil then
		return nil, message
	end
	return planned.persistedChecksum, nil
end

function ProjectStore.importPayload(encoded: string, expectedChecksum: string?): (boolean, string)
	local planned, validationMessage = validatedImportPlan(encoded, expectedChecksum)
	if planned == nil then
		return false, validationMessage or "Selected bundle did not pass Stagewright validation"
	end
	local candidate = planned.project
	if recording ~= nil then
		return false, "Finish the active Stagewright edit before importing a bundle"
	end

	local activeRecording =
		ChangeHistoryService:TryBeginRecording("ImportStagewrightBundle", "Import Stagewright bundle")
	if activeRecording == nil then
		return false, "Studio could not start an import recording"
	end
	local previousProject = project
	local previousLoadResult = loadResult
	project = candidate
	loadResult = planned
	local saveSuccess, saveMessage = pcall(saveUnchecked)
	if not saveSuccess then
		project = previousProject
		loadResult = previousLoadResult
		ChangeHistoryService:FinishRecording(activeRecording, Enum.FinishRecordingOperation.Cancel)
		return false, `Stagewright could not save the imported bundle: {tostring(saveMessage)}`
	end
	ChangeHistoryService:FinishRecording(activeRecording, Enum.FinishRecordingOperation.Commit)
	return true, `Imported {#ProjectStore.stageIds()} stage(s)`
end

function ProjectStore.cleanup()
	if activeTransaction ~= nil then
		finishActiveTransaction(false)
	end
	observerCallback = nil
	observerRevision += 1
	writesSuspended = false
	ProjectStorage.disconnectRelevantConnections()
end

return ProjectStore

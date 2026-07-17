--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if RunService:IsRunning() then
	return
end

local AuthoringArea = require(script.AuthoringArea)
local GraphOperations = require(script.Graph.Operations)
local PredicateFields = require(script.Graph.PredicateFields)
local Brushes = require(script.Paint.Brushes)
local ProjectStore = require(script.ProjectStore)
local RouteOverview = require(script.RouteOverview)
local StageSettings = require(script.Stage.Settings)
local StageHierarchy = require(script.Shared.StageHierarchy)
local StagePayload = require(script.Shared.StagePayload)
local StageTrace = require(script.Shared.StageTrace)
local AppShell = require(script.UI.AppShell)
local Factory = require(script.UI.Factory)
local HeaderController = require(script.UI.HeaderController)
local PaintAppearance = require(script.UI.PaintAppearance)
local Toolbar = require(script.UI.Toolbar)
local IssueModel = require(script.Validation.IssueModel)

local PLUGIN_NAME = "Stagewright"
local PREVIEW_TAG = "StagewrightTransientPreview"
local paintCellPixels = 22
local COLORS = require(script.UI.Theme).colors
local create = Factory.create
local button = Factory.button
local sectionLabel = Factory.sectionLabel
local setButtonSelected = Factory.setSelected

type Mode = "Paint" | "Graph" | "Stage" | "Validate"
type GraphToolMode = "Build" | "Rules" | "Test"
type GraphViewMode = "World" | "Logic"
type WorldPathController = {
	preview: any?,
	assetPreview: boolean,
	showLanes: boolean,
	showBuildMask: boolean,
	showConflicts: boolean,
	render: (WorldPathController, any?, any?, any?, string?, string?, { [string]: boolean }) -> (),
	rerender: (WorldPathController) -> (),
	destroy: (WorldPathController) -> (),
}
type FlowRuntime = {
	viewModule: {
		new: (Instance, any, any) -> WorldPathController,
	},
	mode: GraphViewMode,
	view: WorldPathController?,
	render: () -> (),
	connect: (string, string) -> (),
	inspectorLabel: (Instance, string, number, Color3?, number?) -> (),
	renderInspector: () -> (),
	worldControls: Frame,
	logicControls: Frame,
	modeAction: (Instance, string, number, () -> ()) -> TextButton,
	traceChip: (Frame, number, number, string) -> (),
	optionButtons: { [string]: TextButton },
	refreshOptions: () -> (),
	refreshStageSelector: () -> (),
	toggleAction: (string, number, () -> ()) -> TextButton,
	setToggleSelected: (TextButton, boolean) -> (),
	workspacePreviewEnabled: boolean,
}
type PaintRuntime = {
	mode: string,
	routeTool: string,
	routeCanvas: Frame,
	routeToolbar: Frame,
	routeRail: GuiObject,
	routeInspector: GuiObject,
	legend: GuiObject,
	graphLevelStrip: ScrollingFrame,
	modeButtons: { [string]: TextButton },
	routeToolButtons: { [string]: TextButton },
	routeDraggingNodeId: string?,
	routeDraggingEdgeId: string?,
	routeDraggingHandle: string?,
	routeDragStartScreen: Vector2?,
	routeDragMoved: boolean,
	cellAt: (Vector2) -> (number?, number?),
	localPositionAt: (Vector2) -> any?,
	hitRoute: (Vector2) -> (string?, string?, string?),
	renderRoute: (any?) -> (),
	beginInteraction: (number, number) -> (),
	beginRouteInteraction: (Vector2) -> (),
	deleteRouteSelection: () -> (),
}

local authoringPlatform = AuthoringArea.ensure()
local project = ProjectStore.load(authoringPlatform)
local stageIds = ProjectStore.stageIds()
local selectedStageId = project.startingStageId or stageIds[1]
local selectedGraphId: string? = nil
local selectedNodeId: string? = nil
local selectedEdgeId: string? = nil
local selectedCellKey: string? = nil
local tracedEdgeIds: { [string]: boolean } = {}
local connectFromNodeId: string? = nil
local activeMode: Mode = "Graph"
local graphToolMode: GraphToolMode = "Build"
local activeBrushId = "terrain_ground"
local activePaintTool = "Pencil"
local paintBrushSize = 1
local validationFilter = "Overview"
local predicateKindIndex = 1
local painting = false
local paintedKeys: { [string]: boolean } = {}
local previewFolder: Folder? = nil
local previewMoveRevision = 0
local pendingConfirmation: { id: string, expires: number }? = nil
local islandOutlinesEnabled = true
local validationIssues: { any } = {}
local flowRuntime: FlowRuntime = {
	viewModule = require(script.WorldPathView),
	mode = "World",
	view = nil,
	render = function() end,
	connect = function() end,
	inspectorLabel = function() end,
	renderInspector = function() end,
	worldControls = nil :: any,
	logicControls = nil :: any,
	modeAction = function(): TextButton
		return nil :: any
	end,
	traceChip = function() end,
	optionButtons = {},
	refreshOptions = function() end,
	refreshStageSelector = function() end,
	toggleAction = function(): TextButton
		return nil :: any
	end,
	setToggleSelected = function() end,
	workspacePreviewEnabled = false,
}

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local openButton = toolbar:CreateButton(
	"StagewrightEditor",
	"Open the Stagewright stage authoring workbench",
	"rbxasset://textures/StudioSharedUI/grid@2x.png",
	PLUGIN_NAME
)
openButton.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"StagewrightPanelV2",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, true, 1_600, 920, 880, 560)
)
widget.Title = "Stagewright - Tower Defense Stage Editor"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local shell = AppShell.new(widget)
local root = shell.root
local status = shell.status
local modes = shell.modes
local headerValidation = shell.headerValidation
local leftSidebar = shell.leftSidebar
local workspace = shell.workspace
local rightSidebar = shell.rightSidebar
local sidebarTitle = shell.sidebarTitle

local function applyResponsiveShell()
	shell:applyResponsive(activeMode)
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveShell)

local modeButtons: { [Mode]: TextButton } = {} :: any
local contentByMode: { [Mode]: Frame } = {} :: any
local rerenderAll: () -> ()
local renderAll: () -> ()
local mutate: (string, () -> ()) -> ()
local renderGraphList: () -> ()
local renderStageList: () -> ()
local renderGraphTools: () -> ()
local routeOverview: RouteOverview.Controller
local renderCanvas: () -> ()
do
	local controller = HeaderController.new({
		header = shell.header,
		popupLayer = shell.popupLayer,
		headerValidation = headerValidation,
		status = status,
		widget = widget,
		stageOptions = function()
			local options: { any } = {}
			for _, stageId in ProjectStore.stageIds() do
				local definition = project.stages[stageId]
				if definition ~= nil then
					local address = StageHierarchy.address(definition)
					table.insert(options, {
						id = stageId,
						label = `Stage {address.stageNumber} / Level {address.levelNumber}`,
						selected = stageId == selectedStageId,
					})
				end
			end
			return options
		end,
		onSelectStage = function(stageId: string)
			selectedStageId = stageId
			selectedGraphId = nil
			selectedNodeId = nil
			selectedEdgeId = nil
			tracedEdgeIds = {}
			renderAll()
		end,
		onRender = function()
			renderAll()
		end,
		onSave = function()
			return ProjectStore.save()
		end,
		onOpenValidation = function()
			activeMode = "Validate"
			renderAll()
		end,
		onFocusAuthoring = function()
			AuthoringArea.focus()
		end,
	})
	flowRuntime.refreshStageSelector = function()
		controller:refreshStageSelector()
	end
end

local function stage(): any
	return project.stages[selectedStageId]
end

local function renderIslandOutlines()
	if not islandOutlinesEnabled then
		AuthoringArea.clearIslandOutlines()
		return
	end
	local current = stage()
	if current ~= nil then
		AuthoringArea.showIslandOutlines(current.grid.columns, current.grid.rows, current.grid.cellSize)
	end
end

local function graph(): any?
	local current = stage()
	if current == nil then
		return nil
	end
	if selectedGraphId ~= nil and current.pathGraphs[selectedGraphId] ~= nil then
		return current.pathGraphs[selectedGraphId]
	end
	local ids: { string } = {}
	for id in current.pathGraphs do
		table.insert(ids, id)
	end
	table.sort(ids)
	selectedGraphId = ids[1]
	return if selectedGraphId ~= nil then current.pathGraphs[selectedGraphId] else nil
end

-- Open the workbench on a meaningful spline so the world and logic views
-- immediately explain the authored route instead of presenting an empty inspector.
do
	local initialGraph = graph()
	if initialGraph ~= nil then
		local edgeIds: { string } = {}
		for edgeId in initialGraph.edges do
			table.insert(edgeIds, edgeId)
		end
		table.sort(edgeIds)
		for _, edgeId in edgeIds do
			if #initialGraph.edges[edgeId].predicates > 0 then
				selectedEdgeId = edgeId
				break
			end
		end
		selectedEdgeId = selectedEdgeId or edgeIds[1]
	end
end

local function setStatus(message: string, errorState: boolean?)
	status.Text = message
	status.TextColor3 = if errorState then COLORS.danger else COLORS.muted
end

local function confirm(id: string, prompt: string): boolean
	local now = os.clock()
	if pendingConfirmation ~= nil and pendingConfirmation.id == id and pendingConfirmation.expires >= now then
		pendingConfirmation = nil
		return true
	end
	pendingConfirmation = { id = id, expires = now + 3 }
	setStatus(`{prompt} Click again within 3 seconds to confirm.`, true)
	return false
end

local brushes = Brushes.all

local function localOrigin(): CFrame
	return AuthoringArea.origin()
end

local function clearPreview()
	if previewFolder ~= nil then
		previewFolder:Destroy()
		previewFolder = nil
	end
	for _, tagged in CollectionService:GetTagged(PREVIEW_TAG) do
		if tagged:IsDescendantOf(Workspace) then
			tagged:Destroy()
		end
	end
end

-- World Path is a GUI-only authoring surface. Old tagged previews are removed
-- once when the plugin loads; route edits must never synthesize Workspace Parts.
clearPreview()

local function rebuildPreview()
	if not flowRuntime.workspacePreviewEnabled then
		return
	end
	clearPreview()
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local bakedStage = ProjectStore.preview(selectedStageId)
	if bakedStage == nil then
		return
	end
	local bakedGraph = bakedStage.pathGraphs[currentGraph.id]
	if bakedGraph == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "StagewrightPreview"
	folder.Parent = AuthoringArea.container() or Workspace
	CollectionService:AddTag(folder, PREVIEW_TAG)
	previewFolder = folder
	local origin = localOrigin()
	local function previewPoint(sample: any, laneOffset: number): Vector3
		local position =
			origin:PointToWorldSpace(Vector3.new(sample.position.x, sample.position.y, sample.position.z))
		local tangent =
			origin:VectorToWorldSpace(Vector3.new(sample.tangent.x, sample.tangent.y, sample.tangent.z))
		local up = origin:VectorToWorldSpace(Vector3.new(sample.up.x, sample.up.y, sample.up.z))
		local frame = CFrame.lookAt(position, position + tangent, up)
		return frame.Position + frame.RightVector * laneOffset
	end
	local function bindPosition(part: BasePart, applyPosition: (Vector3) -> ())
		part:GetPropertyChangedSignal("CFrame"):Connect(function()
			if part.Parent == nil then
				return
			end
			previewMoveRevision += 1
			local revision = previewMoveRevision
			ProjectStore.begin("Move Stagewright graph control")
			applyPosition(origin:PointToObjectSpace(part.Position))
			task.delay(0.2, function()
				if revision == previewMoveRevision then
					ProjectStore.finish(true)
					setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
					rebuildPreview()
				end
			end)
		end)
	end
	local routeMask = bakedStage.routeNoBuildMask or {}
	for key in routeMask do
		local authoredCell = bakedStage.grid.cells[key]
		local traversalPolicy = if authoredCell ~= nil and authoredCell.enemyTraversalPolicy ~= nil
			then authoredCell.enemyTraversalPolicy
			else bakedStage.grid.defaultCell.enemyTraversalPolicy
		if traversalPolicy == "Blocked" then
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			local column = if columnText ~= nil then tonumber(columnText) else nil
			local row = if rowText ~= nil then tonumber(rowText) else nil
			if column == nil or row == nil then
				continue
			end
			local grid = bakedStage.grid
			local x = -(grid.columns * grid.cellSize) * 0.5 + (column - 0.5) * grid.cellSize
			local z = -(grid.rows * grid.cellSize) * 0.5 + (row - 0.5) * grid.cellSize
			local cell = Instance.new("Part")
			cell.Name = `RouteConflict_{column}_{row}`
			cell.Anchored = true
			cell.CanCollide = false
			cell.CanQuery = false
			cell.CanTouch = false
			cell.CastShadow = false
			cell.Color = Color3.fromRGB(255, 154, 64)
			cell.Material = Enum.Material.Neon
			cell.Transparency = 0.38
			cell.Size = Vector3.new(grid.cellSize - 0.2, 0.12, grid.cellSize - 0.2)
			cell.CFrame = origin * CFrame.new(x, 0.42, z)
			cell:SetAttribute("StagewrightRouteConflict", true)
			cell.Parent = folder
		end
	end
	for nodeId, node in currentGraph.nodes do
		local part = Instance.new("Part")
		part.Name = `Node_{node.name}`
		part.Shape = Enum.PartType.Ball
		local selected = selectedNodeId == nodeId
		part.Size = if selected then Vector3.new(2.15, 2.15, 2.15) else Vector3.new(1.45, 1.45, 1.45)
		part.Anchored = true
		part.CanCollide = false
		part.Color = if node.kind == "Spawn"
			then Color3.fromRGB(57, 185, 104)
			elseif node.kind == "Goal" then COLORS.goal
			else Color3.fromRGB(60, 139, 214)
		part.Material = if selected then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.CFrame = origin * CFrame.new(node.position.x, node.position.y, node.position.z)
		part:SetAttribute("StagewrightNodeId", nodeId)
		part.Parent = folder
		bindPosition(part, function(localPosition)
			node.position = { x = localPosition.X, y = localPosition.Y, z = localPosition.Z }
		end)
	end
	for edgeId, edge in bakedGraph.edges do
		local laneProfile = bakedGraph.laneProfiles[edge.laneProfileId]
		local samples = edge.samples or {}
		local laneOffsets = if laneProfile ~= nil and #laneProfile.offsets > 0
			then laneProfile.offsets
			else { 0 }
		local corridorWidth = math.max(
			if laneProfile ~= nil then laneProfile.clearanceRadius * 2 else bakedStage.grid.cellSize,
			0.4
		)
		for index = 2, #samples do
			local a = previewPoint(samples[index - 1], 0)
			local b = previewPoint(samples[index], 0)
			local distance = (b - a).Magnitude
			if distance <= 0.001 then
				continue
			end
			local pathFrame = CFrame.lookAt((a + b) * 0.5, b)
			if selectedEdgeId == edgeId then
				local outline = Instance.new("Part")
				outline.Name = `Edge_{edgeId}_SelectedOutline_{index}`
				outline.Anchored = true
				outline.CanCollide = false
				outline.CanQuery = false
				outline.CanTouch = false
				outline.CastShadow = false
				outline.Color = Color3.fromRGB(62, 214, 235)
				outline.Material = Enum.Material.Neon
				outline.Transparency = 0.25
				outline.Size = Vector3.new(corridorWidth + 0.55, 0.12, distance + 0.16)
				outline.CFrame = pathFrame * CFrame.new(0, -0.07, 0)
				outline.Parent = folder
			end
			local corridor = Instance.new("Part")
			corridor.Name = `Edge_{edgeId}_Gravel_{index}`
			corridor.Anchored = true
			corridor.CanCollide = false
			corridor.CanQuery = true
			corridor.CanTouch = false
			corridor.CastShadow = false
			corridor.Color = Color3.fromRGB(142, 119, 86)
			corridor.Material = Enum.Material.Pebble
			corridor.Transparency = 0.08
			corridor.Size = Vector3.new(corridorWidth, 0.16, distance + 0.14)
			corridor.CFrame = pathFrame
			corridor:SetAttribute("StagewrightEdgeId", edgeId)
			corridor:SetAttribute("StagewrightPathAsset", "gravel")
			corridor.Parent = folder
		end
		if selectedEdgeId == edgeId or tracedEdgeIds[edgeId] then
			for laneIndex, laneOffset in laneOffsets do
				for index = 2, #samples do
					local a = previewPoint(samples[index - 1], laneOffset) + Vector3.new(0, 0.14, 0)
					local b = previewPoint(samples[index], laneOffset) + Vector3.new(0, 0.14, 0)
					local distance = (b - a).Magnitude
					if distance <= 0.001 then
						continue
					end
					local segment = Instance.new("Part")
					segment.Name = `Edge_{edgeId}_Lane_{laneIndex}_{index}`
					segment.Anchored = true
					segment.CanCollide = false
					segment.CanQuery = false
					segment.CanTouch = false
					segment.CastShadow = false
					segment.Color = if tracedEdgeIds[edgeId]
						then Color3.fromRGB(96, 220, 132)
						else Color3.fromRGB(237, 244, 247)
					segment.Material = Enum.Material.Neon
					segment.Transparency = 0.12
					segment.Size = Vector3.new(0.14, 0.08, distance)
					segment.CFrame = CFrame.lookAt((a + b) * 0.5, b)
					segment.Parent = folder
				end
			end
		end
	end
	local selectedEdge = if selectedEdgeId ~= nil then currentGraph.edges[selectedEdgeId] else nil
	if selectedEdge ~= nil then
		local from = currentGraph.nodes[selectedEdge.fromNodeId]
		local to = currentGraph.nodes[selectedEdge.toNodeId]
		if from ~= nil and to ~= nil then
			for handleName, handleData in
				{
					Out = { node = from, offset = selectedEdge.outHandleOffset },
					In = { node = to, offset = selectedEdge.inHandleOffset },
				}
			do
				local handle = Instance.new("Part")
				handle.Name = `{handleName}Handle_{selectedEdge.id}`
				handle.Shape = Enum.PartType.Ball
				handle.Size = Vector3.new(1.2, 1.2, 1.2)
				handle.Anchored = true
				handle.CanCollide = false
				handle.Material = Enum.Material.Neon
				handle.Color = Color3.fromRGB(62, 214, 235)
				local position = {
					x = handleData.node.position.x + handleData.offset.x,
					y = handleData.node.position.y + handleData.offset.y,
					z = handleData.node.position.z + handleData.offset.z,
				}
				handle.CFrame = origin * CFrame.new(position.x, position.y, position.z)
				handle.Parent = folder
				local connector = Instance.new("Part")
				connector.Name = `{handleName}HandleGuide_{selectedEdge.id}`
				connector.Anchored = true
				connector.CanCollide = false
				connector.CanQuery = false
				connector.CanTouch = false
				connector.CastShadow = false
				connector.Color = Color3.fromRGB(62, 214, 235)
				connector.Material = Enum.Material.Neon
				connector.Transparency = 0.18
				connector.Parent = folder
				local anchor = origin:PointToWorldSpace(
					Vector3.new(
						handleData.node.position.x,
						handleData.node.position.y,
						handleData.node.position.z
					)
				)
				local function updateConnector()
					local distance = (handle.Position - anchor).Magnitude
					connector.Size = Vector3.new(0.08, 0.08, math.max(distance, 0.01))
					connector.CFrame = CFrame.lookAt((anchor + handle.Position) * 0.5, handle.Position)
				end
				updateConnector()
				handle:GetPropertyChangedSignal("CFrame"):Connect(updateConnector)
				bindPosition(handle, function(localPosition)
					local nextOffset = {
						x = localPosition.X - handleData.node.position.x,
						y = localPosition.Y - handleData.node.position.y,
						z = localPosition.Z - handleData.node.position.z,
					}
					if handleName == "Out" then
						selectedEdge.outHandleOffset = nextOffset
					else
						selectedEdge.inHandleOffset = nextOffset
					end
				end)
			end
		end
	end
end

for order, modeName in { "Graph", "Paint", "Stage", "Validate" } :: { Mode } do
	local mode = modeName :: Mode
	local label = if mode == "Graph" then "Flow + Graph" elseif mode == "Stage" then "Stages" else mode
	modeButtons[mode] = button(modes, label, 88, function()
		activeMode = mode
		rerenderAll()
	end)
	modeButtons[mode].LayoutOrder = order
	modeButtons[mode].BackgroundColor3 = COLORS.panel
	modeButtons[mode].Font = Enum.Font.BuilderSansMedium
	modeButtons[mode].TextSize = 14
	local page = create("Frame", {
		Name = `{mode}Page`,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, workspace) :: Frame
	contentByMode[mode] = page
end

-- Paint page: a layer-aware brush rail and a virtualized grid canvas.
local paintRuntime = {
	mode = "Cells",
	routeTool = "Move",
	modeButtons = {},
	routeToolButtons = {},
	routeDragStartScreen = nil,
	routeDragMoved = false,
} :: PaintRuntime
local paintPage = contentByMode.Paint
local paintToolbar = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 42),
	Size = UDim2.new(1, 0, 0, 54),
}, paintPage) :: Frame
do
	local modeBar = create("Frame", {
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 42),
	}, paintPage) :: Frame
	for order, definition in
		{
			{ id = "Cells", label = "Paint cells" },
			{ id = "Route", label = "Edit enemy route" },
		}
	do
		local modeId = definition.id
		local modeButton = button(modeBar, definition.label, 132, function()
			paintRuntime.mode = modeId
			paintRuntime.routeDraggingNodeId = nil
			paintRuntime.routeDraggingEdgeId = nil
			paintRuntime.routeDraggingHandle = nil
			painting = false
			connectFromNodeId = nil
			rerenderAll()
		end)
		modeButton.Position = UDim2.fromOffset(10 + (order - 1) * 140, 6)
		modeButton.Size = UDim2.fromOffset(132, 30)
		paintRuntime.modeButtons[modeId] = modeButton
	end
	create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(1, -304, 1, 0),
		Text = "Grid layers and enemy routes are edited separately",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, modeBar)

	paintRuntime.routeToolbar = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 54),
		Visible = false,
	}, paintPage)
	for order, definition in
		{
			{ id = "Move", label = "Move" },
			{ id = "AddSpawn", label = "+ Spawn" },
			{ id = "AddJunction", label = "+ Junction" },
			{ id = "AddGoal", label = "+ Goal" },
			{ id = "Connect", label = "Connect ->" },
		}
	do
		local toolId = definition.id
		local toolButton = button(paintRuntime.routeToolbar, definition.label, 88, function()
			paintRuntime.routeTool = toolId
			if toolId == "Connect" then
				connectFromNodeId = selectedNodeId
				setStatus(
					if connectFromNodeId ~= nil
						then "Click the destination node to create a directed spline."
						else "Click a start node, then click its destination."
				)
			else
				connectFromNodeId = nil
			end
			rerenderAll()
		end)
		toolButton.Position = UDim2.fromOffset(10 + (order - 1) * 94, 11)
		toolButton.Size = UDim2.fromOffset(88, 32)
		paintRuntime.routeToolButtons[toolId] = toolButton
	end
	local laneButton = button(paintRuntime.routeToolbar, "Lanes 1/2/3", 98, function()
		local currentGraph = graph()
		local edgeId = selectedEdgeId
		if currentGraph == nil or edgeId == nil then
			setStatus("Select a spline before changing its lane count.", true)
			return
		end
		mutate("Cycle Stagewright route lanes", function()
			GraphOperations.cycleLaneCount(currentGraph, edgeId)
		end)
		renderAll()
	end)
	laneButton.Position = UDim2.fromOffset(480, 11)
	laneButton.Size = UDim2.fromOffset(98, 32)
	local deleteButton = button(paintRuntime.routeToolbar, "Delete", 72, function()
		paintRuntime.deleteRouteSelection()
	end)
	deleteButton.Position = UDim2.fromOffset(584, 11)
	deleteButton.Size = UDim2.fromOffset(72, 32)
end
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(0.5, -14, 0, 20),
	Text = "Build blocked",
	TextColor3 = COLORS.text,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
}, paintToolbar)
local paintHint = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.surface,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansMedium,
	Position = UDim2.new(0.5, 0, 1, -154),
	Size = UDim2.fromOffset(188, 38),
	Text = "Click to inspect. Hold Shift and drag to paint one undo step.",
	TextColor3 = COLORS.text,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 30,
}, paintPage) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 7) }, paintHint)
create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, paintHint)
local paintHover = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansMedium,
	Position = UDim2.new(1, -294, 0, 13),
	Size = UDim2.fromOffset(104, 28),
	Text = "Cell --",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	Visible = true,
}, paintToolbar) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 6) }, paintHover)
local brushRail = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 38),
	ScrollBarThickness = 5,
	Size = UDim2.new(1, 0, 1, -38),
}, leftSidebar) :: ScrollingFrame
create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, brushRail)
create("UIPadding", {
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, brushRail)
paintRuntime.routeRail = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 1, -38),
	Visible = false,
}, leftSidebar)
create("TextLabel", {
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 0, 196),
	Text = "ROUTE WORKFLOW\n\n1  Add a spawn, junction, or goal\n\n2  Drag nodes directly over the stage\n\n3  Drag an output port to a destination\n\n4  Select a gravel spline; drag cyan handles to shape it\n\n5  Set 1, 2, or 3 lanes\n\nThe gravel footprint shows affected cells. Amber marks real traversal conflicts only.",
	TextColor3 = COLORS.text,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, paintRuntime.routeRail)
create("UIPadding", {
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 12),
}, paintRuntime.routeRail:FindFirstChildOfClass("TextLabel"))
local brushButtons: { [string]: TextButton } = {}
local renderPaintChrome: () -> ()
local paintSizeButton: TextButton
local paintZoomLabel: TextLabel
do
	local previousBrushCategory: string? = nil
	local brushLayoutOrder = 0
	for _, brushDefinition in brushes do
		local brush = brushDefinition
		if brush.category ~= previousBrushCategory then
			brushLayoutOrder += 1
			sectionLabel(brushRail, `v  {brush.category}`, brushLayoutOrder)
			previousBrushCategory = brush.category
		end
		brushLayoutOrder += 1
		local glyph = if brush.id == "role_EnemySpawn"
			then "S"
			elseif brush.id == "role_EnemyGoal" then "G"
			elseif brush.id == "role_AutoPlace" then "A"
			elseif brush.id == "role_Hazard" then "H"
			elseif brush.id == "role_Reward" then "R"
			elseif brush.id == "role_Trigger" then "T"
			elseif brush.id == "role_StageTransition" then ">"
			elseif brush.id == "role_DecorationAnchor" then "D"
			else ""
		local swatchColor = if brush.id == "terrain_ground"
			then COLORS.ground
			elseif brush.id == "terrain_void" then COLORS.void
			elseif brush.id == "build_allowed" then COLORS.allowed
			elseif brush.id == "build_blocked" then COLORS.blocked
			elseif brush.id == "build_auto" then COLORS.auto
			elseif brush.id == "traversal_allowed" then Color3.fromRGB(51, 116, 164)
			elseif brush.id == "traversal_blocked" then COLORS.blocked
			elseif brush.id == "role_EnemySpawn" then Color3.fromRGB(45, 146, 84)
			elseif brush.id == "role_EnemyGoal" then Color3.fromRGB(113, 76, 193)
			elseif brush.id == "role_AutoPlace" then COLORS.auto
			elseif brush.id == "role_Hazard" then COLORS.blocked
			elseif brush.id == "role_Reward" then COLORS.warning
			elseif brush.id == "role_Trigger" then Color3.fromRGB(71, 130, 196)
			elseif brush.id == "role_StageTransition" then Color3.fromRGB(84, 151, 214)
			elseif brush.id == "role_DecorationAnchor" then Color3.fromRGB(111, 124, 143)
			else COLORS.accent
		local brushButton = button(brushRail, "", 196, function()
			activeBrushId = brush.id
			activePaintTool = "Pencil"
			renderPaintChrome()
			renderCanvas()
		end)
		brushButton.LayoutOrder = brushLayoutOrder
		brushButton.Size = UDim2.new(1, 0, 0, 34)
		local swatch = create("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = swatchColor,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
		}, brushButton) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 4) }, swatch)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(16, 34),
			Text = glyph,
			TextColor3 = COLORS.text,
			TextSize = 9,
		}, brushButton)
		create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -44, 1, 0),
			Text = brush.label,
			TextColor3 = COLORS.text,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, brushButton)
		brushButtons[brush.id] = brushButton
	end
end
function renderPaintChrome()
	local brush = Brushes.find(activeBrushId)
	local editingRoute = paintRuntime.mode == "Route"
	for modeId, modeButton in paintRuntime.modeButtons do
		setButtonSelected(modeButton, modeId == paintRuntime.mode)
	end
	paintToolbar.Visible = not editingRoute
	paintRuntime.routeToolbar.Visible = editingRoute
	for toolId, toolButton in paintRuntime.routeToolButtons do
		setButtonSelected(toolButton, toolId == paintRuntime.routeTool)
	end
	for brushId, brushButton in brushButtons do
		setButtonSelected(brushButton, brushId == activeBrushId)
	end
	for _, child in paintToolbar:GetChildren() do
		if child:IsA("TextButton") and string.sub(child.Name, 1, 10) == "PaintTool_" then
			setButtonSelected(child, string.sub(child.Name, 11) == activePaintTool)
		end
	end
	paintHint.Text = if editingRoute
		then "Drag nodes  |  Connect joins start to destination"
		else "Shift + drag to paint"
	paintSizeButton.Text = `Brush {paintBrushSize} x {paintBrushSize}`
	paintZoomLabel.Text = `{math.round(paintCellPixels / 24 * 100)}%`
	local brushName = rightSidebar:FindFirstChild("PaintInspectorBrushName", true)
	if brushName ~= nil and brushName:IsA("TextLabel") then
		brushName.Text = brush.label
	end
	local brushHelp = rightSidebar:FindFirstChild("PaintInspectorBrushHelp", true)
	if brushHelp ~= nil and brushHelp:IsA("TextLabel") then
		brushHelp.Text = brush.help
	end
	for _, size in { 1, 3, 5 } do
		local sizeButton = rightSidebar:FindFirstChild(`PaintSizeChoice{size}`, true)
		if sizeButton ~= nil and sizeButton:IsA("TextButton") then
			setButtonSelected(sizeButton, size == paintBrushSize)
		end
	end
	local routeSelection = paintRuntime.routeInspector:FindFirstChild("PaintRouteSelection")
	if routeSelection ~= nil and routeSelection:IsA("TextLabel") then
		local currentGraph = graph()
		local node = if currentGraph ~= nil and selectedNodeId ~= nil
			then currentGraph.nodes[selectedNodeId]
			else nil
		local edge = if currentGraph ~= nil and selectedEdgeId ~= nil
			then currentGraph.edges[selectedEdgeId]
			else nil
		if node ~= nil then
			routeSelection.Text = `{string.upper(node.kind)}\n{node.name}`
		elseif edge ~= nil and currentGraph ~= nil then
			local from = currentGraph.nodes[edge.fromNodeId]
			local to = currentGraph.nodes[edge.toNodeId]
			local laneProfile = currentGraph.laneProfiles[edge.laneProfileId]
			local laneCount = if laneProfile ~= nil then #laneProfile.offsets else 1
			routeSelection.Text = `{if from ~= nil then from.name else "Missing"}  ->  {if to ~= nil
				then to.name
				else "Missing"}\n{laneCount} {if laneCount == 1 then "lane" else "lanes"}`
		elseif paintRuntime.routeTool == "Connect" and connectFromNodeId ~= nil then
			local from = if currentGraph ~= nil then currentGraph.nodes[connectFromNodeId] else nil
			routeSelection.Text = `CONNECTING FROM\n{if from ~= nil then from.name else "Select destination"}`
		else
			routeSelection.Text = "No route item selected\nChoose a tool above the grid"
		end
	end
end
local gridScroll = create("ScrollingFrame", {
	BackgroundColor3 = Color3.fromRGB(12, 13, 15),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 100),
	ScrollBarThickness = 8,
	ScrollingDirection = Enum.ScrollingDirection.XY,
	Size = UDim2.new(1, 0, 1, -240),
}, paintPage) :: ScrollingFrame
local gridCanvas = create("Frame", { BackgroundTransparency = 1 }, gridScroll) :: Frame
paintRuntime.routeCanvas = create("Frame", {
	Name = "EnemyRouteOverlay",
	Active = false,
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Position = UDim2.fromOffset(22, 22),
	Selectable = false,
	ZIndex = 8,
}, gridCanvas)
local cellPool: { TextButton } = {}

do
	local toolButtons: { [string]: TextButton } = {}
	for order, toolName in { "Select", "Pencil", "Rect", "Fill", "Erase", "Pan" } do
		local name = toolName
		local toolLabel = if name == "Rect" then "Rectangle" else name
		local tool = button(paintToolbar, toolLabel, 74, function()
			activePaintTool = name
			for candidate, candidateButton in toolButtons do
				setButtonSelected(candidateButton, candidate == activePaintTool)
			end
			if name ~= "Pencil" and name ~= "Erase" then
				setStatus(`{name} tool selected. Hold Shift for any cell mutation.`)
			end
		end)
		tool.Name = `PaintTool_{name}`
		tool.Position = UDim2.fromOffset(10 + (order - 1) * 80, 11)
		tool.Size = UDim2.fromOffset(74, 32)
		toolButtons[name] = tool
	end
	setButtonSelected(toolButtons.Pencil, true)
end

paintSizeButton = button(paintToolbar, "Brush 1 x 1", 92, function()
	paintBrushSize = if paintBrushSize == 1 then 3 elseif paintBrushSize == 3 then 5 else 1
	paintSizeButton.Text = `Brush {paintBrushSize} x {paintBrushSize}`
end)
paintSizeButton.AnchorPoint = Vector2.new(1, 0)
paintSizeButton.Position = UDim2.new(1, -188, 0, 11)

paintZoomLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansMedium,
	Position = UDim2.new(1, -82, 0, 11),
	Size = UDim2.fromOffset(66, 32),
	Text = "100%",
	TextColor3 = COLORS.text,
	TextSize = 11,
}, paintToolbar) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 6) }, paintZoomLabel)
do
	local zoomOut = button(paintToolbar, "-", 30, function()
		paintCellPixels = math.max(paintCellPixels - 2, 10)
		renderPaintChrome()
		renderCanvas()
	end)
	zoomOut.Visible = false
	local zoomIn = button(paintToolbar, "+", 30, function()
		paintCellPixels = math.min(paintCellPixels + 2, 40)
		renderPaintChrome()
		renderCanvas()
	end)
	zoomIn.Visible = false
	local fit = button(paintToolbar, "Fit", 42, function()
		local current = stage()
		if current ~= nil then
			paintCellPixels = math.clamp(
				math.floor(
					math.min(
						(gridScroll.AbsoluteWindowSize.X - 42) / current.grid.columns,
						(gridScroll.AbsoluteWindowSize.Y - 42) / current.grid.rows
					)
				),
				10,
				40
			)
			renderPaintChrome()
			renderCanvas()
		end
	end)
	fit.AnchorPoint = Vector2.new(1, 0)
	fit.Position = UDim2.new(1, -12, 0, 11)
	fit.Size = UDim2.fromOffset(58, 32)
end

do
	local legend = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = COLORS.surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -14, 1, -154),
		Size = UDim2.fromOffset(154, 180),
		ZIndex = 30,
	}, paintPage) :: Frame
	paintRuntime.legend = legend
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, legend)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, legend)
	for order, entry in
		{
			{ "Ground", COLORS.ground },
			{ "Build allowed", COLORS.allowed },
			{ "Build blocked", COLORS.blocked },
			{ "Traversal", Color3.fromRGB(51, 116, 164) },
			{ "Auto place", COLORS.auto },
			{ "Spawn", Color3.fromRGB(45, 146, 84) },
			{ "Goal / Hazard", Color3.fromRGB(113, 76, 193) },
			{ "Enemy route", COLORS.route },
		}
	do
		create("Frame", {
			BackgroundColor3 = entry[2] :: Color3,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 10 + (order - 1) * 20),
			Size = UDim2.fromOffset(11, 11),
			ZIndex = 31,
		}, legend)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(28, 6 + (order - 1) * 20),
			Size = UDim2.new(1, -36, 0, 18),
			Text = entry[1] :: string,
			TextColor3 = COLORS.text,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 31,
		}, legend)
	end
end

do
	local paintValidationPanel = create("Frame", {
		Name = "PaintValidationPanel",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 140),
	}, paintPage) :: Frame
	create("Frame", {
		BackgroundColor3 = COLORS.border,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
	}, paintValidationPanel)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(100, 24),
		Text = "VALIDATION",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, paintValidationPanel)
	create("TextLabel", {
		Name = "PaintValidationCounts",
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(116, 9),
		Size = UDim2.fromOffset(154, 26),
		Text = "Checking...",
		TextColor3 = COLORS.muted,
		TextSize = 10,
	}, paintValidationPanel)
	local openValidation = button(paintValidationPanel, "Open validation", 120, function()
		activeMode = "Validate"
		renderAll()
	end)
	openValidation.AnchorPoint = Vector2.new(1, 0)
	openValidation.Position = UDim2.new(1, -12, 0, 8)
	for index = 1, 3 do
		local row = create("TextLabel", {
			Name = `PaintValidationRow{index}`,
			BackgroundColor3 = COLORS.surface,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(12, 40 + (index - 1) * 32),
			Size = UDim2.new(1, -24, 0, 28),
			Text = "No issue",
			TextColor3 = COLORS.muted,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, paintValidationPanel) :: TextLabel
		create("UICorner", { CornerRadius = UDim.new(0, 5) }, row)
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, row)
	end
end

do
	local paintInspector = create("Frame", {
		Name = "PaintInspector",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 1, -38),
		Visible = false,
	}, rightSidebar) :: Frame
	local paintBrushCard = create("Frame", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 112),
	}, paintInspector) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, paintBrushCard)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, paintBrushCard)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "ACTIVE BRUSH",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, paintBrushCard)
	create("TextLabel", {
		Name = "PaintInspectorBrushName",
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "Ground",
		TextColor3 = COLORS.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, paintBrushCard)
	create("TextLabel", {
		Name = "PaintInspectorBrushHelp",
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 62),
		Size = UDim2.new(1, -24, 0, 38),
		Text = "Paint normal playable ground.",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, paintBrushCard)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 136),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "BRUSH SIZE",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, paintInspector)
	for order, size in { 1, 3, 5 } do
		local brushSize = size
		local sizeChoice = button(paintInspector, `{brushSize} x {brushSize}`, 70, function()
			paintBrushSize = brushSize
			renderPaintChrome()
		end)
		sizeChoice.Position = UDim2.new((order - 1) / 3, 10 + (order - 1) * 3, 0, 162)
		sizeChoice.Size = UDim2.new(1 / 3, -9, 0, 32)
		sizeChoice.Name = `PaintSizeChoice{brushSize}`
	end
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 218),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "SAFE PAINTING",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, paintInspector)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 244),
		Size = UDim2.new(1, -24, 0, 112),
		Text = "1. Choose a layer\n2. Choose Pencil, Rectangle, or Fill\n3. Hold Shift while painting\n4. Release to create one undo step\n\nClick without Shift to inspect a cell.",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, paintInspector)
end

paintRuntime.routeInspector = create("Frame", {
	Name = "PaintRouteInspector",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 1, -38),
	Visible = false,
}, rightSidebar)
create("TextLabel", {
	Name = "PaintRouteSelection",
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 72),
	Text = "No route item selected",
	TextColor3 = COLORS.text,
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
}, paintRuntime.routeInspector)
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(12, 96),
	Size = UDim2.new(1, -24, 0, 220),
	Text = "MOVE\nDrag a spawn, junction, or goal directly over the stage. Select a gravel spline and drag its cyan IN / OUT handles to shape the curve.\n\nCONNECT\nDrag a node output port to its destination. Connections are directed and may merge.\n\nSPLINE\nClick the gravel walkway to select it, set 1-3 lanes, smooth it, or delete it.\n\nThe walkway itself shows the affected cells. Amber appears only where traversal is blocked.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, paintRuntime.routeInspector)
do
	local openFlow = button(paintRuntime.routeInspector, "Open advanced Flow editor", 180, function()
		activeMode = "Graph"
		renderAll()
	end)
	openFlow.Position = UDim2.fromOffset(10, 330)
	openFlow.Size = UDim2.new(1, -20, 0, 34)
end

local function paintModifierDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function showHoveredCell(column: number?, row: number?, routeAffected: boolean?)
	for _, cellButton in cellPool do
		if cellButton.Visible then
			local buttonColumn = cellButton:GetAttribute("Column")
			local buttonRow = cellButton:GetAttribute("Row")
			local key = if type(buttonColumn) == "number" and type(buttonRow) == "number"
				then `{buttonColumn}:{buttonRow}`
				else nil
			local hovered = buttonColumn == column and buttonRow == row
			cellButton.BorderColor3 = if hovered
				then COLORS.warning
				elseif key ~= nil and key == selectedCellKey then COLORS.accent
				else Color3.fromRGB(24, 27, 31)
			cellButton.BorderSizePixel = if hovered or (key ~= nil and key == selectedCellKey) then 2 else 1
		end
	end
	if column == nil or row == nil then
		gridCanvas:SetAttribute("HoverColumn", nil)
		gridCanvas:SetAttribute("HoverRow", nil)
		paintHover.Text = "Cell --"
		paintHover.TextColor3 = COLORS.muted
		return
	end
	gridCanvas:SetAttribute("HoverColumn", column)
	gridCanvas:SetAttribute("HoverRow", row)
	paintHover.Text = if routeAffected
		then `Cell {column}, {row} - TRAVERSAL CONFLICT`
		else `Cell {column}, {row}`
	paintHover.TextColor3 = if routeAffected then COLORS.warning else COLORS.text
end

paintRuntime.cellAt = function(position: Vector2): (number?, number?)
	local current = stage()
	if current == nil then
		return nil, nil
	end
	local scrollPosition = gridScroll.AbsolutePosition
	local scrollSize = gridScroll.AbsoluteWindowSize
	if
		position.X < scrollPosition.X
		or position.Y < scrollPosition.Y
		or position.X >= scrollPosition.X + scrollSize.X
		or position.Y >= scrollPosition.Y + scrollSize.Y
	then
		return nil, nil
	end
	local relativeX = position.X - gridCanvas.AbsolutePosition.X - 22
	local relativeY = position.Y - gridCanvas.AbsolutePosition.Y - 22
	if relativeX < 0 or relativeY < 0 then
		return nil, nil
	end
	local column = math.floor(relativeX / paintCellPixels) + 1
	local row = math.floor(relativeY / paintCellPixels) + 1
	if column > current.grid.columns or row > current.grid.rows then
		return nil, nil
	end
	return column, row
end

paintRuntime.localPositionAt = function(position: Vector2): any?
	local column = paintRuntime.cellAt(position)
	local current = stage()
	if column == nil or current == nil then
		return nil
	end
	local relative = position - paintRuntime.routeCanvas.AbsolutePosition
	return {
		x = relative.X / paintCellPixels * current.grid.cellSize
			- current.grid.columns * current.grid.cellSize * 0.5,
		y = 0.48,
		z = relative.Y / paintCellPixels * current.grid.cellSize
			- current.grid.rows * current.grid.cellSize * 0.5,
	}
end

paintRuntime.hitRoute = function(position: Vector2): (string?, string?, string?)
	local current = stage()
	local currentGraph = graph()
	if current == nil or currentGraph == nil then
		return nil, nil, nil
	end
	local canvasPoint = position - paintRuntime.routeCanvas.AbsolutePosition
	local function screenPoint(localPosition: any): Vector2
		return Vector2.new(
			(localPosition.x + current.grid.columns * current.grid.cellSize * 0.5)
				/ current.grid.cellSize
				* paintCellPixels,
			(localPosition.z + current.grid.rows * current.grid.cellSize * 0.5)
				/ current.grid.cellSize
				* paintCellPixels
		)
	end
	local closestNodeId: string? = nil
	local closestNodeDistance = math.huge
	for nodeId, node in currentGraph.nodes do
		local distance = (screenPoint(node.position) - canvasPoint).Magnitude
		if distance <= 15 and distance < closestNodeDistance then
			closestNodeId = nodeId
			closestNodeDistance = distance
		end
	end
	if closestNodeId ~= nil then
		return closestNodeId, nil, nil
	end
	if selectedEdgeId ~= nil then
		local selectedEdge = currentGraph.edges[selectedEdgeId]
		local fromNode = if selectedEdge ~= nil then currentGraph.nodes[selectedEdge.fromNodeId] else nil
		local toNode = if selectedEdge ~= nil then currentGraph.nodes[selectedEdge.toNodeId] else nil
		if selectedEdge ~= nil and fromNode ~= nil and toNode ~= nil then
			local handles = {
				Out = {
					x = fromNode.position.x + selectedEdge.outHandleOffset.x,
					y = fromNode.position.y + selectedEdge.outHandleOffset.y,
					z = fromNode.position.z + selectedEdge.outHandleOffset.z,
				},
				In = {
					x = toNode.position.x + selectedEdge.inHandleOffset.x,
					y = toNode.position.y + selectedEdge.inHandleOffset.y,
					z = toNode.position.z + selectedEdge.inHandleOffset.z,
				},
			}
			for handleId, handlePosition in handles do
				if (screenPoint(handlePosition) - canvasPoint).Magnitude <= 13 then
					return nil, selectedEdgeId, handleId
				end
			end
		end
	end
	local function segmentDistance(point: Vector2, startPoint: Vector2, endPoint: Vector2): number
		local delta = endPoint - startPoint
		local lengthSquared = delta:Dot(delta)
		if lengthSquared <= 0.0001 then
			return (point - startPoint).Magnitude
		end
		local alpha = math.clamp((point - startPoint):Dot(delta) / lengthSquared, 0, 1)
		return (point - (startPoint + delta * alpha)).Magnitude
	end
	local preview = ProjectStore.preview(selectedStageId)
	local bakedGraph = if preview ~= nil then preview.pathGraphs[currentGraph.id] else nil
	local closestEdgeId: string? = nil
	local closestEdgeDistance = math.huge
	if bakedGraph ~= nil then
		for edgeId, edge in bakedGraph.edges do
			local samples = edge.samples or {}
			for index = 2, #samples do
				local distance = segmentDistance(
					canvasPoint,
					screenPoint(samples[index - 1].position),
					screenPoint(samples[index].position)
				)
				if distance <= 9 and distance < closestEdgeDistance then
					closestEdgeId = edgeId
					closestEdgeDistance = distance
				end
			end
		end
	end
	return nil, closestEdgeId, nil
end

paintRuntime.renderRoute = function(preview: any?)
	local current = stage()
	if current == nil then
		return
	end
	local routeCanvas = paintRuntime.routeCanvas :: Frame
	routeCanvas.Visible = paintRuntime.mode == "Route"
	routeCanvas.Size =
		UDim2.fromOffset(current.grid.columns * paintCellPixels, current.grid.rows * paintCellPixels)
	if paintRuntime.mode ~= "Route" then
		return
	end
	local signature = if preview ~= nil
		then `{tostring(preview.routePreviewSignature)}:{paintCellPixels}:{tostring(selectedNodeId)}:{tostring(
			selectedEdgeId
		)}`
		else "none"
	if routeCanvas:GetAttribute("Signature") == signature then
		return
	end
	for _, child in routeCanvas:GetChildren() do
		child:Destroy()
	end
	routeCanvas:SetAttribute("Signature", signature)
	if preview == nil then
		return
	end
	local grid = preview.grid
	local function positionPoint(position: any): Vector2
		return Vector2.new(
			(position.x + grid.columns * grid.cellSize * 0.5) / grid.cellSize * paintCellPixels,
			(position.z + grid.rows * grid.cellSize * 0.5) / grid.cellSize * paintCellPixels
		)
	end
	local function line(
		a: Vector2,
		b: Vector2,
		thickness: number,
		transparency: number,
		zIndex: number,
		color: Color3
	)
		local delta = b - a
		local segment = create("Frame", {
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			Selectable = false,
			Size = UDim2.fromOffset(math.max(delta.Magnitude + 1, 1), thickness),
			ZIndex = zIndex,
		}, routeCanvas)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, segment)
	end
	local currentGraph = graph()
	local bakedGraph = if currentGraph ~= nil then preview.pathGraphs[currentGraph.id] else nil
	if bakedGraph ~= nil then
		for edgeId, edge in bakedGraph.edges do
			local laneProfile = bakedGraph.laneProfiles[edge.laneProfileId]
			local radius = if laneProfile ~= nil then laneProfile.clearanceRadius else grid.cellSize * 0.5
			local corridorPixels = math.max(radius * 2 / grid.cellSize * paintCellPixels, 3)
			local samples = edge.samples or {}
			if #samples >= 2 then
				local step = math.max(math.floor(#samples / 24), 1)
				local previousIndex = 1
				for index = math.min(1 + step, #samples), #samples, step do
					local resolvedIndex = if index + step > #samples then #samples else index
					local a = positionPoint(samples[previousIndex].position)
					local b = positionPoint(samples[resolvedIndex].position)
					if selectedEdgeId == edgeId then
						line(a, b, corridorPixels + 3, 0.18, 8, Color3.fromRGB(62, 214, 235))
					end
					line(a, b, corridorPixels, 0.08, 9, Color3.fromRGB(142, 119, 86))
					if selectedEdgeId == edgeId or tracedEdgeIds[edgeId] then
						line(
							a,
							b,
							math.max(paintCellPixels * 0.1, 2),
							0.06,
							10,
							if tracedEdgeIds[edgeId] then Color3.fromRGB(96, 220, 132) else COLORS.text
						)
					end
					previousIndex = resolvedIndex
					if resolvedIndex == #samples then
						break
					end
				end
			end
		end
		for nodeId, node in bakedGraph.nodes do
			local nodePosition = positionPoint(node.position)
			local nodeColor = if node.kind == "Spawn"
				then Color3.fromRGB(45, 146, 84)
				elseif node.kind == "Goal" then Color3.fromRGB(113, 76, 193)
				else COLORS.accent
			local marker = create("Frame", {
				Active = false,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = nodeColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(nodePosition.X, nodePosition.Y),
				Selectable = false,
				Size = UDim2.fromOffset(22, 22),
				ZIndex = 12,
			}, routeCanvas)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)
			create("UIStroke", {
				Color = if selectedNodeId == nodeId then COLORS.warning else COLORS.text,
				Thickness = if selectedNodeId == nodeId then 3 else 1,
				Transparency = if selectedNodeId == nodeId then 0 else 0.35,
			}, marker)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansBold,
				Size = UDim2.fromScale(1, 1),
				Text = if node.kind == "Spawn" then "S" elseif node.kind == "Goal" then "G" else "J",
				TextColor3 = COLORS.text,
				TextSize = 10,
				ZIndex = 13,
			}, marker)
			if selectedNodeId == nodeId then
				create("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = COLORS.surface,
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSansBold,
					Position = UDim2.new(0.5, 0, 1, 4),
					Size = UDim2.fromOffset(118, 22),
					Text = node.name,
					TextColor3 = COLORS.text,
					TextSize = 10,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 14,
				}, marker)
			end
		end
		local selectedEdge = if selectedEdgeId ~= nil then currentGraph.edges[selectedEdgeId] else nil
		local fromNode = if selectedEdge ~= nil then currentGraph.nodes[selectedEdge.fromNodeId] else nil
		local toNode = if selectedEdge ~= nil then currentGraph.nodes[selectedEdge.toNodeId] else nil
		if selectedEdge ~= nil and fromNode ~= nil and toNode ~= nil then
			for _, handle in
				{
					{
						id = "Out",
						anchor = fromNode.position,
						position = {
							x = fromNode.position.x + selectedEdge.outHandleOffset.x,
							y = fromNode.position.y + selectedEdge.outHandleOffset.y,
							z = fromNode.position.z + selectedEdge.outHandleOffset.z,
						},
					},
					{
						id = "In",
						anchor = toNode.position,
						position = {
							x = toNode.position.x + selectedEdge.inHandleOffset.x,
							y = toNode.position.y + selectedEdge.inHandleOffset.y,
							z = toNode.position.z + selectedEdge.inHandleOffset.z,
						},
					},
				}
			do
				local anchorPoint = positionPoint(handle.anchor)
				local handlePoint = positionPoint(handle.position)
				line(anchorPoint, handlePoint, 1, 0.25, 10, COLORS.warning)
				local marker = create("Frame", {
					Active = false,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = COLORS.warning,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(handlePoint.X, handlePoint.Y),
					Rotation = 45,
					Selectable = false,
					Size = UDim2.fromOffset(13, 13),
					ZIndex = 15,
				}, routeCanvas)
				create("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundTransparency = 1,
					Font = Enum.Font.BuilderSansBold,
					Position = UDim2.new(0.5, 0, 0, -5),
					Rotation = -45,
					Size = UDim2.fromOffset(28, 14),
					Text = string.upper(handle.id),
					TextColor3 = COLORS.warning,
					TextSize = 8,
					ZIndex = 16,
				}, marker)
			end
		end
	end
end

local function paintCell(column: number, row: number)
	local current = stage()
	local brushId = if activePaintTool == "Erase" then Brushes.RESET_ID else activeBrushId
	Brushes.applyArea(current.grid, Brushes.find(brushId), column, row, paintBrushSize, paintedKeys)
end

paintRuntime.beginInteraction = function(column: number, row: number)
	selectedCellKey = `{column}:{row}`
	local preview = ProjectStore.preview(selectedStageId)
	local routeAffected = preview ~= nil and preview.routeNoBuildMask[column .. ":" .. row] == true
	showHoveredCell(column, row, routeAffected)
	if not paintModifierDown() or activePaintTool == "Select" or activePaintTool == "Pan" then
		setStatus(
			if routeAffected
				then `Cell {column}, {row} is inside the derived enemy route. Hold Shift to paint.`
				else `Cell {column}, {row} selected. Hold Shift to paint.`
		)
		renderCanvas()
		return
	end
	paintedKeys = {}
	ProjectStore.begin("Paint Stagewright cells")
	if activePaintTool == "Fill" then
		local fillStage = stage()
		local authoredCell = fillStage.grid.cells[`{column}:{row}`]
		local resolvedCell = authoredCell or fillStage.grid.defaultCell
		local targetColor = PaintAppearance.resolve(resolvedCell, authoredCell, fillStage.grid.defaultCell)
		local queue = { Vector2.new(column, row) }
		local visited: { [string]: boolean } = {}
		local head = 1
		local previousBrushSize = paintBrushSize
		paintBrushSize = 1
		while queue[head] ~= nil do
			local point = queue[head]
			head += 1
			local pointColumn = math.floor(point.X)
			local pointRow = math.floor(point.Y)
			local key = `{pointColumn}:{pointRow}`
			if
				not visited[key]
				and pointColumn >= 1
				and pointColumn <= fillStage.grid.columns
				and pointRow >= 1
				and pointRow <= fillStage.grid.rows
			then
				visited[key] = true
				local candidateOverride = fillStage.grid.cells[key]
				local candidate = candidateOverride or fillStage.grid.defaultCell
				local candidateColor =
					PaintAppearance.resolve(candidate, candidateOverride, fillStage.grid.defaultCell)
				if candidateColor == targetColor then
					paintCell(pointColumn, pointRow)
					table.insert(queue, Vector2.new(pointColumn - 1, pointRow))
					table.insert(queue, Vector2.new(pointColumn + 1, pointRow))
					table.insert(queue, Vector2.new(pointColumn, pointRow - 1))
					table.insert(queue, Vector2.new(pointColumn, pointRow + 1))
				end
			end
		end
		paintBrushSize = previousBrushSize
		ProjectStore.finish(true)
		setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
	elseif activePaintTool == "Rect" then
		painting = true
		gridCanvas:SetAttribute("RectangleColumn", column)
		gridCanvas:SetAttribute("RectangleRow", row)
	else
		painting = true
		paintCell(column, row)
	end
	renderCanvas()
end

function renderCanvas()
	local current = stage()
	if current == nil then
		return
	end
	local grid = current.grid
	local routePreview = ProjectStore.preview(selectedStageId)
	local routeMask = if routePreview ~= nil then routePreview.routeNoBuildMask or {} else {}
	local width = grid.columns * paintCellPixels + 22
	local height = grid.rows * paintCellPixels + 22
	local offsetX = math.max(math.floor((gridScroll.AbsoluteWindowSize.X - width) / 2), 0)
	local offsetY = math.max(math.floor((gridScroll.AbsoluteWindowSize.Y - height) / 2), 0)
	gridCanvas.Position = UDim2.fromOffset(offsetX, offsetY)
	gridCanvas.Size = UDim2.fromOffset(width, height)
	gridScroll.CanvasSize = UDim2.fromOffset(
		math.max(width + offsetX * 2, gridScroll.AbsoluteWindowSize.X),
		math.max(height + offsetY * 2, gridScroll.AbsoluteWindowSize.Y)
	)
	paintRuntime.renderRoute(routePreview)
	local firstColumn =
		math.max(math.floor(math.max(gridScroll.CanvasPosition.X - offsetX - 22, 0) / paintCellPixels) + 1, 1)
	local firstRow =
		math.max(math.floor(math.max(gridScroll.CanvasPosition.Y - offsetY - 22, 0) / paintCellPixels) + 1, 1)
	local visibleColumns =
		math.min(math.ceil(gridScroll.AbsoluteWindowSize.X / paintCellPixels) + 2, grid.columns)
	local visibleRows = math.min(math.ceil(gridScroll.AbsoluteWindowSize.Y / paintCellPixels) + 2, grid.rows)
	local needed = visibleColumns * visibleRows
	local headerSignature = `{grid.columns}:{grid.rows}:{paintCellPixels}`
	if gridCanvas:GetAttribute("HeaderSignature") ~= headerSignature then
		for _, child in gridCanvas:GetChildren() do
			if string.sub(child.Name, 1, 11) == "GridHeader_" then
				child:Destroy()
			end
		end
		for column = 1, grid.columns do
			create("TextLabel", {
				Name = `GridHeader_Column_{column}`,
				BackgroundColor3 = COLORS.panel,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(22 + (column - 1) * paintCellPixels, 0),
				Size = UDim2.fromOffset(paintCellPixels, 20),
				Text = tostring(column),
				TextColor3 = COLORS.muted,
				TextSize = math.clamp(paintCellPixels * 0.38, 8, 10),
				ZIndex = 4,
			}, gridCanvas)
		end
		for row = 1, grid.rows do
			create("TextLabel", {
				Name = `GridHeader_Row_{row}`,
				BackgroundColor3 = COLORS.panel,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(0, 22 + (row - 1) * paintCellPixels),
				Size = UDim2.fromOffset(20, paintCellPixels),
				Text = tostring(row),
				TextColor3 = COLORS.muted,
				TextSize = math.clamp(paintCellPixels * 0.38, 8, 10),
				ZIndex = 4,
			}, gridCanvas)
		end
		gridCanvas:SetAttribute("HeaderSignature", headerSignature)
	end
	while #cellPool < needed do
		local cellButton = create("TextButton", {
			AutoButtonColor = false,
			BorderColor3 = Color3.fromRGB(24, 27, 31),
			BorderSizePixel = 1,
			Font = Enum.Font.BuilderSansBold,
			TextColor3 = COLORS.text,
			TextSize = 11,
			ZIndex = 5,
		}, gridCanvas) :: TextButton
		create("UIStroke", {
			Name = "RouteStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = COLORS.route,
			Thickness = 2,
			Transparency = 1,
		}, cellButton)
		create("TextLabel", {
			Name = "RouteBadge",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(8, 8),
			Text = "",
			TextColor3 = COLORS.route,
			TextSize = 12,
			ZIndex = 10,
		}, cellButton)
		cellButton.MouseEnter:Connect(function()
			local column = cellButton:GetAttribute("Column")
			local row = cellButton:GetAttribute("Row")
			if type(column) ~= "number" or type(row) ~= "number" then
				showHoveredCell(nil, nil)
				return
			end
			showHoveredCell(column, row, cellButton:GetAttribute("RouteAffected") == true)
			cellButton.BorderColor3 = COLORS.warning
			cellButton.BorderSizePixel = 2
		end)
		cellButton.MouseLeave:Connect(function()
			local column = cellButton:GetAttribute("Column")
			local row = cellButton:GetAttribute("Row")
			local key = if type(column) == "number" and type(row) == "number" then `{column}:{row}` else nil
			cellButton.BorderColor3 = if key ~= nil and key == selectedCellKey
				then COLORS.accent
				else Color3.fromRGB(24, 27, 31)
			cellButton.BorderSizePixel = if key ~= nil and key == selectedCellKey then 2 else 1
		end)
		table.insert(cellPool, cellButton)
	end
	local index = 0
	for row = firstRow, math.min(firstRow + visibleRows - 1, grid.rows) do
		for column = firstColumn, math.min(firstColumn + visibleColumns - 1, grid.columns) do
			index += 1
			local cellButton = cellPool[index]
			local key = `{column}:{row}`
			local authoredCell = grid.cells[key]
			local cell = authoredCell or grid.defaultCell
			local color, glyph = PaintAppearance.resolve(cell, authoredCell, grid.defaultCell)
			local traversalPolicy = if authoredCell ~= nil
					and authoredCell.enemyTraversalPolicy ~= nil
				then authoredCell.enemyTraversalPolicy
				else grid.defaultCell.enemyTraversalPolicy
			local routeAffected = paintRuntime.mode == "Route"
				and routeMask[key] == true
				and traversalPolicy == "Blocked"
			cellButton.Position =
				UDim2.fromOffset(22 + (column - 1) * paintCellPixels, 22 + (row - 1) * paintCellPixels)
			cellButton.Size = UDim2.fromOffset(paintCellPixels, paintCellPixels)
			cellButton.BackgroundColor3 = if routeAffected
				then color:Lerp(Color3.fromRGB(255, 154, 64), 0.52)
				else color
			cellButton.BorderColor3 = if key == selectedCellKey
				then COLORS.accent
				else Color3.fromRGB(24, 27, 31)
			cellButton.BorderSizePixel = if key == selectedCellKey then 2 else 1
			cellButton.Text = glyph
			cellButton:SetAttribute("Column", column)
			cellButton:SetAttribute("Row", row)
			cellButton:SetAttribute("RouteAffected", routeAffected)
			local routeStroke = cellButton:FindFirstChild("RouteStroke") :: UIStroke?
			if routeStroke ~= nil then
				routeStroke.Transparency = 1
			end
			local routeBadge = cellButton:FindFirstChild("RouteBadge") :: TextLabel?
			if routeBadge ~= nil then
				routeBadge.Text = ""
			end
			cellButton.Visible = true
		end
	end
	for poolIndex = index + 1, #cellPool do
		cellPool[poolIndex].Visible = false
	end
end
gridScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(renderCanvas)
gridScroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(renderCanvas)
gridScroll.MouseLeave:Connect(function()
	showHoveredCell(nil, nil)
end)

-- Stage browser.
local stagePage = contentByMode.Stage
local stageInspector = create("Frame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, 38),
	Size = UDim2.new(1, -20, 1, -48),
	Visible = false,
	ZIndex = 3,
}, rightSidebar) :: Frame
local stageInspectorTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 24),
	Text = "LEVEL PROPERTIES",
	TextColor3 = COLORS.text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 4,
}, stageInspector)
local stageLevelLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.accentMuted,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(122, 26),
	Text = "STAGE 1 / LEVEL 1",
	TextColor3 = Color3.fromRGB(151, 194, 255),
	TextSize = 10,
	Visible = true,
}, stageInspector) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 6) }, stageLevelLabel)
local stageForm = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 34),
	Size = UDim2.new(1, 0, 0, 280),
	ZIndex = 4,
}, stageInspector) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(0, 7),
	CellSize = UDim2.new(1, 0, 0, 39),
	FillDirectionMaxCells = 1,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, stageForm)
local function textField(parent: Instance, label: string, order: number): TextBox
	local group = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Size = UDim2.new(1, 0, 0, 13),
		Text = label,
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group)
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, group) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, field)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, field)
	return field
end
local stageNameField = textField(stageForm, "LEVEL NAME", 1)
local waveSetField = textField(stageForm, "WAVE SET", 2)
local themeField = textField(stageForm, "THEME", 3)
local columnsField = textField(stageForm, "GRID WIDTH (CELLS)", 4)
local rowsField = textField(stageForm, "GRID HEIGHT (CELLS)", 5)
local cellSizeField = textField(stageForm, "CELL SIZE (STUDS)", 6)
local applyStageButton = button(stageInspector, "Apply changes", 124, function()
	local current = stage()
	if current == nil then
		return
	end
	local update, parseError = StageSettings.parse({
		name = stageNameField.Text,
		waveSetId = waveSetField.Text,
		themeId = themeField.Text,
		columns = columnsField.Text,
		rows = rowsField.Text,
		cellSize = cellSizeField.Text,
	})
	if update == nil then
		setStatus(parseError or StageSettings.INVALID_GRID_MESSAGE, true)
		return
	end
	local truncated = StageSettings.countTruncated(current.grid, update.columns, update.rows)
	if
		truncated > 0
		and not confirm(`resize_{current.id}`, `Resize would remove {truncated} cell override(s).`)
	then
		return
	end
	mutate("Update Stagewright level settings", function()
		StageSettings.apply(current, update)
	end)
	renderAll()
end)
applyStageButton.AnchorPoint = Vector2.new(1, 0)
applyStageButton.Position = UDim2.new(1, 0, 0, 330)
applyStageButton.ZIndex = 4
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(0, 326),
	Size = UDim2.new(1, -138, 0, 36),
	Text = "Width x height defines the grid. Shrinking asks before trimming painted cells.",
	TextColor3 = COLORS.muted,
	TextSize = 10,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 4,
}, stageInspector)
for _, descendant in stageInspector:GetDescendants() do
	if descendant:IsA("GuiObject") then
		descendant.ZIndex = 4
	end
end
local stageList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 36),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -90),
}, leftSidebar) :: ScrollingFrame
local stageSearchField = create("TextBox", {
	BackgroundColor3 = COLORS.field,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.BuilderSans,
	PlaceholderColor3 = COLORS.muted,
	PlaceholderText = "Search levels...",
	Position = UDim2.fromOffset(8, 40),
	Size = UDim2.new(1, -16, 0, 32),
	Text = "",
	TextColor3 = COLORS.text,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, leftSidebar) :: TextBox
create("UICorner", { CornerRadius = UDim.new(0, 6) }, stageSearchField)
create("UIStroke", { Color = COLORS.border, Thickness = 1 }, stageSearchField)
create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, stageSearchField)
stageSearchField:GetPropertyChangedSignal("Text"):Connect(function()
	renderStageList()
end)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, stageList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, stageList)
local stageActions = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Position = UDim2.new(0, 0, 1, -52),
	Size = UDim2.new(1, 0, 0, 52),
}, leftSidebar) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.new(0.5, -7, 0, 29),
	FillDirectionMaxCells = 2,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, stageActions)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 7),
}, stageActions)

local levelHero = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 1, -20),
	ZIndex = 1,
}, stagePage) :: Frame
create("UICorner", { CornerRadius = UDim.new(0, 8) }, levelHero)
create("UIStroke", { Color = COLORS.border, Thickness = 1 }, levelHero)
local levelOverviewName = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 28),
	Text = "Level overview",
	TextColor3 = COLORS.text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
}, levelHero) :: TextLabel
local levelOverviewMeta = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(16, 43),
	Size = UDim2.new(1, -32, 0, 22),
	Text = "32 x 27 grid - 0 nodes - 0 edges",
	TextColor3 = COLORS.muted,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = true,
}, levelHero) :: TextLabel
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(16, 69),
	Size = UDim2.new(1, -32, 0, 28),
	Text = "Edit the level in place. Working changes are saved automatically.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Visible = true,
}, levelHero)
local workflowGrid = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 92),
	Size = UDim2.new(0.46, -24, 0, 292),
	Visible = true,
}, levelHero) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(10, 10),
	CellSize = UDim2.new(0.5, -5, 0, 141),
	FillDirectionMaxCells = 2,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, workflowGrid)
local workflowSteps = {
	{
		title = "Open Paint",
		body = "Define terrain, tower build rules, traversal restrictions, and object roles.",
		mode = "Paint" :: Mode,
	},
	{
		title = "Open Flow",
		body = "Add spawn, junction, and goal nodes. Connect branches and choose lane counts.",
		mode = "Graph" :: Mode,
	},
	{
		title = "Level settings",
		body = "Set the level name, theme, wave-set reference, grid size, and cell size in the inspector.",
		mode = "Stage" :: Mode,
	},
	{
		title = "Validate level",
		body = "Resolve every error, preview warnings, then export the deterministic deployment bundle.",
		mode = "Validate" :: Mode,
	},
}
for order, step in workflowSteps do
	local card = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSans,
		LayoutOrder = order,
		Text = "",
	}, workflowGrid) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, card)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 0, 24),
		Text = step.title,
		TextColor3 = COLORS.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -28, 1, -54),
		Text = step.body,
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	card.Activated:Connect(function()
		activeMode = step.mode
		renderAll()
	end)
end
local levelHealthText: TextLabel
do
	local summary = create("Frame", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 400),
		Size = UDim2.new(0.46, -24, 0, 92),
		Visible = true,
	}, levelHero) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, summary)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, summary)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 20),
		Text = "LEVEL HEALTH",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, summary)
	levelHealthText = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 0, 32),
		Text = "Grid ready - Route ready - No issues",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, summary) :: TextLabel
end

do
	local preview = create("Frame", {
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Position = UDim2.new(0.46, 4, 0, 92),
		Size = UDim2.new(0.54, -20, 0, 292),
		ZIndex = 2,
	}, levelHero) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, preview)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, preview)
	create("Frame", {
		Name = "LevelPreviewCanvas",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		ZIndex = 3,
	}, preview)
	local metrics = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.46, 4, 0, 400),
		Size = UDim2.new(0.54, -20, 0, 92),
		ZIndex = 2,
	}, levelHero) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 0),
		CellSize = UDim2.new(1 / 3, -6, 1, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, metrics)
	for order, metric in
		{
			{ "Route", COLORS.accent, "RouteMetric" },
			{ "Build coverage", COLORS.allowed, "BuildMetric" },
			{ "Issues", COLORS.danger, "IssueMetric" },
		}
	do
		local card = create("Frame", {
			BackgroundColor3 = COLORS.surface,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ZIndex = 3,
		}, metrics) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
		create("UIStroke", { Color = metric[2] :: Color3, Thickness = 1 }, card)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(1, -12, 0, 18),
			Text = metric[1] :: string,
			TextColor3 = COLORS.muted,
			TextSize = 10,
			ZIndex = 4,
		}, card)
		create("TextLabel", {
			Name = metric[3] :: string,
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(6, 30),
			Size = UDim2.new(1, -12, 0, 34),
			Text = "--",
			TextColor3 = metric[2] :: Color3,
			TextSize = 18,
			ZIndex = 4,
		}, card)
	end
	local open = button(levelHero, "Open level", 150, function()
		activeMode = "Paint"
		renderAll()
	end)
	open.AnchorPoint = Vector2.new(1, 0)
	open.Position = UDim2.new(1, -16, 0, 512)
	open.Size = UDim2.fromOffset(160, 34)
	open.BackgroundColor3 = COLORS.accent
	open.ZIndex = 3
end

function mutate(name: string, callback: () -> ())
	ProjectStore.mutate(name, callback)
	project = ProjectStore.get()
	stageIds = ProjectStore.stageIds()
	renderCanvas()
	rebuildPreview()
	setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
end

local stageActionOrder = 0
local function stageAction(text: string, callback: () -> ()): TextButton
	stageActionOrder += 1
	local result = button(stageActions, text, 80, callback)
	result.LayoutOrder = stageActionOrder
	return result
end

stageAction("+ Stage", function()
	mutate("Create Stagewright stage group", function()
		selectedStageId = ProjectStore.createStage(nil)
	end)
	renderAll()
end)
stageAction("+ Level", function()
	mutate("Create Stagewright level", function()
		selectedStageId = ProjectStore.createLevel(selectedStageId)
	end)
	renderAll()
end)
stageAction("Delete", function()
	if not confirm(`delete_{selectedStageId}`, "Delete this level and its graph data?") then
		return
	end
	local ok, message = false, ""
	mutate("Delete Stagewright stage", function()
		ok, message = ProjectStore.deleteStage(selectedStageId)
		if ok then
			selectedStageId = ProjectStore.stageIds()[1]
		end
	end)
	setStatus(message, not ok)
	renderAll()
end)
for _, move in { { "Up", -1 }, { "Down", 1 } } do
	stageAction(move[1] :: string, function()
		mutate("Reorder Stagewright stages", function()
			ProjectStore.moveStage(selectedStageId, move[2] :: number)
		end)
		renderAll()
	end)
end
stageAction("Open 3D", function()
	AuthoringArea.focus()
	setStatus("Focused the separate Stagewright admin authoring area.")
end)
local islandGuideButton: TextButton
islandGuideButton = stageAction("Guides", function()
	islandOutlinesEnabled = not islandOutlinesEnabled
	islandGuideButton.Text = "Guides"
	renderIslandOutlines()
	setStatus(if islandOutlinesEnabled then "Six island footprint guides shown." else "Island guides hidden.")
end)

do
	local moreMenu = create("Frame", {
		Name = "StageMoreMenu",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 1, -58),
		Size = UDim2.new(1, -16, 0, 148),
		Visible = false,
		ZIndex = 40,
	}, leftSidebar) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, moreMenu)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, moreMenu)
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 6),
		CellSize = UDim2.new(0.5, -9, 0, 30),
		FillDirectionMaxCells = 2,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, moreMenu)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 7),
	}, moreMenu)
	for _, child in stageActions:GetChildren() do
		if child:IsA("TextButton") and child.LayoutOrder >= 3 then
			child.Parent = moreMenu
			child.ZIndex = 41
		end
	end
	local layout = stageActions:FindFirstChildOfClass("UIGridLayout")
	if layout ~= nil then
		layout.CellSize = UDim2.new(1 / 3, -6, 0, 30)
	end
	local more = button(stageActions, "...", 44, function()
		moreMenu.Visible = not moreMenu.Visible
	end)
	more.LayoutOrder = 3
end

function renderStageList()
	for _, child in stageList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	stageIds = ProjectStore.stageIds()
	local groups: { any } = {}
	local groupById: { [string]: any } = {}
	local query = string.lower(stageSearchField.Text)
	for _, stageId in stageIds do
		local definition = project.stages[stageId]
		local address = StageHierarchy.address(definition)
		local searchText = string.lower(
			`stage {address.stageNumber} level {address.levelNumber} {definition.name} {stageId}`
		)
		if query ~= "" and string.find(searchText, query, 1, true) == nil then
			continue
		end
		local group = groupById[address.groupId]
		if group == nil then
			group = {
				id = address.groupId,
				number = address.stageNumber,
				levels = {},
			}
			groupById[address.groupId] = group
			table.insert(groups, group)
		end
		table.insert(group.levels, {
			id = stageId,
			name = definition.name,
			number = address.levelNumber,
		})
	end
	local layoutOrder = 0
	for _, group in groups do
		layoutOrder += 1
		local groupHeader = create("TextLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, -8, 0, 26),
			Text = `v  Stage {group.number}`,
			TextColor3 = COLORS.text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, stageList) :: TextLabel
		create("UIPadding", { PaddingLeft = UDim.new(0, 5) }, groupHeader)
		for _, level in group.levels do
			layoutOrder += 1
			local stageId = level.id
			local stageButton = button(
				stageList,
				`Level {level.number}  {string.sub(stageId, -8)}`,
				200,
				function()
					selectedStageId = stageId
					selectedGraphId = nil
					selectedNodeId = nil
					selectedEdgeId = nil
					tracedEdgeIds = {}
					renderAll()
				end
			)
			stageButton.LayoutOrder = layoutOrder
			stageButton.Size = UDim2.new(1, -12, 0, 28)
			stageButton.TextXAlignment = Enum.TextXAlignment.Left
			create(
				"UIPadding",
				{ PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 18) },
				stageButton
			)
			setButtonSelected(stageButton, stageId == selectedStageId)
			local hasError = false
			local hasWarning = false
			local issueCount = 0
			for _, issue in validationIssues do
				if issue.stageId == stageId then
					issueCount += 1
					hasError = hasError or issue.severity == "Error"
					hasWarning = hasWarning or issue.severity ~= "Error"
				end
			end
			stageButton.Text = `Level {level.number}  {string.sub(stageId, -8)}{if issueCount > 0
				then `  ({issueCount})`
				else ""}`
			local statusDot = create("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = if hasError
					then COLORS.danger
					elseif hasWarning then COLORS.warning
					else COLORS.success,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(7, 7),
			}, stageButton) :: Frame
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, statusDot)
		end
	end
	stageList.CanvasSize = UDim2.fromOffset(0, layoutOrder * 33 + 14)
	local graphLevelStrip = paintRuntime.graphLevelStrip
	for _, child in graphLevelStrip:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local selectedStripIndex = 1
	for order, stageId in stageIds do
		local definition = project.stages[stageId]
		local address = StageHierarchy.address(definition)
		local issueCount = 0
		local hasError = false
		for _, issue in validationIssues do
			if issue.stageId == stageId then
				issueCount += 1
				hasError = hasError or issue.severity == "Error"
			end
		end
		local levelButton = button(
			graphLevelStrip,
			`S{address.stageNumber}  /  L{address.levelNumber}{if issueCount > 0
				then `  -  {issueCount}`
				else ""}`,
			118,
			function()
				selectedStageId = stageId
				selectedGraphId = nil
				selectedNodeId = nil
				selectedEdgeId = nil
				tracedEdgeIds = {}
				renderAll()
			end
		)
		levelButton.Name = `GraphLevel_{stageId}`
		levelButton.LayoutOrder = order
		levelButton.Size = UDim2.fromOffset(118, 32)
		levelButton.TextColor3 = if hasError then Color3.fromRGB(255, 151, 161) else COLORS.text
		setButtonSelected(levelButton, stageId == selectedStageId)
		if stageId == selectedStageId then
			selectedStripIndex = order
		end
	end
	graphLevelStrip.CanvasSize = UDim2.fromOffset(#stageIds * 124 + 12, 0)
	graphLevelStrip.CanvasPosition = Vector2.new(
		math.max((selectedStripIndex - 1) * 124 - graphLevelStrip.AbsoluteWindowSize.X * 0.4, 0),
		0
	)
end

-- Graph page: stable node/edge IDs, directed connections, predicates, lanes, and priorities.
local graphPage = contentByMode.Graph
graphPage.ClipsDescendants = true
do
	local graphLevelBar = create("Frame", {
		Name = "GraphLevelBar",
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 48),
	}, graphPage) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(78, 48),
		Text = "LEVEL",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, graphLevelBar)
	paintRuntime.graphLevelStrip = create("ScrollingFrame", {
		Name = "GraphLevelStrip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(84, 0),
		ScrollBarImageColor3 = COLORS.borderStrong,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = UDim2.new(1, -94, 1, 0),
	}, graphLevelBar)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, paintRuntime.graphLevelStrip)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
	}, paintRuntime.graphLevelStrip)
end
local graphSummary = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 76),
}, rightSidebar) :: Frame
local graphSelectionTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 24),
	Text = "Route graph",
	TextColor3 = COLORS.text,
	TextSize = 13,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, graphSummary) :: TextLabel
local graphSelectionHint = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(14, 32),
	Size = UDim2.new(1, -28, 0, 34),
	Text = "Add nodes, connect them, then shape handles directly in the 3D editor.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, graphSummary) :: TextLabel
local graphProperties = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 1, -122),
	Size = UDim2.new(1, -28, 0, 148),
	ZIndex = 20,
}, graphPage) :: Frame
graphProperties.Name = "GraphInspectorDock"
create("UICorner", { CornerRadius = UDim.new(0, 9) }, graphProperties)
create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, graphProperties)
local emptyGraphProperties = create("TextLabel", {
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 72),
	Text = "Select a node or edge in the overview to edit its properties.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextWrapped = true,
}, graphProperties) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 7) }, emptyGraphProperties)
local nodeProperties = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
}, graphProperties) :: Frame
local function graphPropertyField(
	parent: Instance,
	placeholder: string,
	position: UDim2,
	size: UDim2
): TextBox
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		PlaceholderColor3 = COLORS.muted,
		PlaceholderText = placeholder,
		Position = position,
		Size = size,
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextBox
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, field)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, field)
	create("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, field)
	return field
end
local nodeNameField =
	graphPropertyField(nodeProperties, "Node name", UDim2.fromOffset(10, 4), UDim2.new(1, -20, 0, 30))
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(10, 42),
	Size = UDim2.new(1, -20, 0, 18),
	Text = "LOCAL POSITION  X / Y / Z",
	TextColor3 = COLORS.muted,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
}, nodeProperties)
local nodeXField =
	graphPropertyField(nodeProperties, "X", UDim2.fromOffset(10, 64), UDim2.new(1 / 3, -10, 0, 30))
local nodeYField =
	graphPropertyField(nodeProperties, "Y", UDim2.new(1 / 3, 2, 0, 64), UDim2.new(1 / 3, -10, 0, 30))
local nodeZField =
	graphPropertyField(nodeProperties, "Z", UDim2.new(2 / 3, 4, 0, 64), UDim2.new(1 / 3, -14, 0, 30))
local applyNodeButton = button(nodeProperties, "Apply node", 112, function()
	local currentGraph = graph()
	local node = if currentGraph ~= nil and selectedNodeId ~= nil
		then currentGraph.nodes[selectedNodeId]
		else nil
	local x = tonumber(nodeXField.Text)
	local y = tonumber(nodeYField.Text)
	local z = tonumber(nodeZField.Text)
	if node == nil or x == nil or y == nil or z == nil then
		setStatus("Node position needs numeric X, Y, and Z values.", true)
		return
	end
	mutate("Update Stagewright graph node", function()
		node.name = if nodeNameField.Text ~= "" then nodeNameField.Text else node.name
		node.position = { x = x, y = y, z = z }
	end)
	renderAll()
end)
applyNodeButton.Position = UDim2.fromOffset(10, 106)
local focusNodeButton = button(nodeProperties, "Open World Path", 112, function()
	activeMode = "Graph"
	flowRuntime.mode = "World"
	renderAll()
end)
focusNodeButton.Position = UDim2.fromOffset(130, 106)
local edgeProperties = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
}, graphProperties) :: Frame
local edgePropertiesText = create("TextLabel", {
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 96),
	Text = "Priority 1\n2 lanes\nFallback edge",
	TextColor3 = COLORS.text,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
}, edgeProperties) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 7) }, edgePropertiesText)
create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, edgePropertiesText)
local editRulesButton = button(edgeProperties, "Edit rules", 112, function()
	graphToolMode = "Rules"
	renderGraphTools()
end)
editRulesButton.Position = UDim2.fromOffset(10, 112)
local centerEdgeButton = button(edgeProperties, "Center in graph", 122, function()
	routeOverview:focusSelection()
end)
centerEdgeButton.Position = UDim2.fromOffset(130, 112)
local graphList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 322),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -510),
}, rightSidebar) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, graphList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, graphList)
do
	local graphMiniPreview = create("Frame", {
		Name = "GraphMiniPreview",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 168),
	}, rightSidebar) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, graphMiniPreview)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, graphMiniPreview)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(10, 7),
		Size = UDim2.new(1, -20, 0, 22),
		Text = "STAGE PREVIEW",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, graphMiniPreview)
	create("Frame", {
		Name = "GraphMiniPreviewCanvas",
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 1, -42),
	}, graphMiniPreview)
end

do
	local graphToolbar = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
	}, graphPage) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(132, 46),
		Text = "ROUTE OVERVIEW",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, graphToolbar)
	create("TextLabel", {
		Name = "GraphSelectionHeader",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(300, 46),
		Text = "Select a node or connection to edit it",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, graphToolbar)
end

local routeOverviewHost = create("Frame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Position = UDim2.fromOffset(0, 95),
	Size = UDim2.new(1, 0, 1, -310),
}, graphPage) :: Frame
routeOverview = RouteOverview.new(routeOverviewHost, COLORS, {
	selectNode = function(nodeId: string)
		if connectFromNodeId ~= nil and connectFromNodeId ~= nodeId then
			local fromId = connectFromNodeId
			connectFromNodeId = nil
			mutate("Connect Stagewright route nodes", function()
				flowRuntime.connect(fromId, nodeId)
			end)
		end
		selectedNodeId = nodeId
		selectedEdgeId = nil
		tracedEdgeIds = {}
		renderAll()
	end,
	selectEdge = function(edgeId: string)
		selectedEdgeId = edgeId
		selectedNodeId = nil
		tracedEdgeIds = {}
		renderAll()
	end,
	connectNodes = function(fromNodeId: string, toNodeId: string)
		mutate("Connect Stagewright route nodes", function()
			flowRuntime.connect(fromNodeId, toNodeId)
		end)
		renderAll()
	end,
})
local graphActions = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(760, 102),
}, graphPage) :: Frame
create("UICorner", { CornerRadius = UDim.new(0, 9) }, graphActions)
create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, graphActions)
local graphToolTabs = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.new(1, -20, 0, 30),
}, graphActions) :: Frame
local graphTabsLayout = create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 0),
	CellSize = UDim2.new(1 / 3, -4, 1, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, graphToolTabs) :: UIGridLayout
local graphActionPages: { [GraphToolMode]: Frame } = {} :: any
local graphToolButtons: { [GraphToolMode]: TextButton } = {} :: any
local graphPageHelp = {
	Build = "Choose a node or edge to reveal only the tools that apply.",
	Rules = "All conditions use AND. Branches still require one fallback edge.",
	Test = "Preview server-authoritative branch choices without starting Play mode.",
}
local function graphActionPage(mode: GraphToolMode, columns: number): Frame
	local page = create("Frame", {
		BackgroundTransparency = 1,
		Position = if mode == "Build" then UDim2.fromOffset(10, 8) else UDim2.fromOffset(10, 44),
		Size = if mode == "Build" then UDim2.new(1, -20, 1, -16) else UDim2.new(1, -20, 1, -52),
		Visible = mode == graphToolMode,
	}, graphActions) :: Frame
	graphActionPages[mode] = page
	create("TextLabel", {
		Name = "Help",
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Size = UDim2.new(1, 0, 0, 30),
		Text = graphPageHelp[mode],
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = true,
	}, page)
	local controls = create("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
	}, page) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 6),
		CellSize = UDim2.new(1 / columns, -4, 0, 29),
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, controls)
	return controls
end
local buildControls = graphActionPage("Build", 6)
local rulesControls = graphActionPage("Rules", 2)
local testControls = graphActionPage("Test", 2)
local buildCreationButtons: { TextButton } = {}
local nodeBuildButtons: { TextButton } = {}
local edgeBuildButtons: { TextButton } = {}
for order, modeName in { "Build", "Rules", "Test" } :: { GraphToolMode } do
	local mode = modeName :: GraphToolMode
	local tab = button(
		graphToolTabs,
		if mode == "Build" then "Build" elseif mode == "Rules" then "Rules" else "Test",
		90,
		function()
			graphToolMode = mode
			renderGraphTools()
		end
	)
	tab.LayoutOrder = order
	graphToolButtons[mode] = tab
end
function renderGraphTools()
	if graphToolMode == "Rules" and selectedEdgeId == nil then
		graphToolMode = "Build"
	end
	graphToolButtons.Rules.Visible = selectedEdgeId ~= nil
	graphTabsLayout.CellSize = if selectedEdgeId ~= nil
		then UDim2.new(1 / 3, -4, 1, 0)
		else UDim2.new(1 / 2, -3, 1, 0)
	for mode, page in graphActionPages do
		page.Visible = mode == graphToolMode
		setButtonSelected(graphToolButtons[mode], mode == graphToolMode)
	end
	for _, action in buildCreationButtons do
		action.Visible = true
		local needsNode = action.Name == "GraphPrimaryConnect"
		local needsEdge = action.Name == "GraphPrimarySplit"
			or action.Name == "GraphPrimaryLanes"
			or action.Name == "GraphPrimaryCondition"
		local needsSelection = action.Name == "GraphPrimaryDelete"
		action.Active = if needsNode
			then selectedNodeId ~= nil
			elseif needsEdge then selectedEdgeId ~= nil
			elseif needsSelection then selectedNodeId ~= nil or selectedEdgeId ~= nil
			else true
		action.TextColor3 = if action.Active then COLORS.text else COLORS.muted
	end
	for _, action in nodeBuildButtons do
		action.Visible = false
	end
	for _, action in edgeBuildButtons do
		action.Visible = false
	end
	graphToolTabs.Visible = graphToolMode ~= "Build"
	local height = if graphToolMode == "Build" then 102 elseif graphToolMode == "Rules" then 196 else 224
	local preferredWidth = if graphToolMode == "Build" then 1_080 else 980
	graphActions.Size =
		UDim2.fromOffset(math.min(math.max(graphPage.AbsoluteSize.X - 28, 330), preferredWidth), height)
	graphActions.ZIndex = 20
	for _, descendant in graphActions:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 21
		end
	end
	local inspectorHeight = if selectedNodeId ~= nil or selectedEdgeId ~= nil then 148 else 82
	graphProperties.Position = UDim2.new(0.5, 0, 1, -(height + 20))
	graphProperties.Size =
		UDim2.fromOffset(math.min(math.max(graphPage.AbsoluteSize.X - 28, 330), 1_100), inspectorHeight)
	graphProperties.ZIndex = 20
	for _, descendant in graphProperties:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 21
		end
	end
	routeOverviewHost.Size = UDim2.new(1, 0, 1, -(height + inspectorHeight + 124))
end
graphPage:GetPropertyChangedSignal("AbsoluteSize"):Connect(renderGraphTools)

local function actionField(parent: Instance, placeholder: string): TextBox
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		LayoutOrder = #parent:GetChildren() + 1,
		PlaceholderColor3 = COLORS.muted,
		PlaceholderText = placeholder,
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, field)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, field)
	return field
end

local PREDICATE_KINDS = PredicateFields.KINDS

local function newNode(kind: string, requestedPosition: any?)
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local id = GraphOperations.addNode(currentGraph, kind, requestedPosition)
	selectedNodeId = id
	selectedEdgeId = nil
end
do
	local nodeMenu = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -205, 1, -92),
		Size = UDim2.fromOffset(132, 112),
		Visible = false,
		ZIndex = 30,
	}, graphPage) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, nodeMenu)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, nodeMenu)
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, nodeMenu)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
		PaddingTop = UDim.new(0, 7),
	}, nodeMenu)
	for _, kind in { "Spawn", "Junction", "Goal" } do
		local addKind = button(nodeMenu, kind, 118, function()
			nodeMenu.Visible = false
			mutate(`Add {kind} node`, function()
				newNode(kind)
			end)
			renderAll()
		end)
		addKind.ZIndex = 31
	end
	local addNode = button(buildControls, "+  Add node", 112, function()
		nodeMenu.Visible = not nodeMenu.Visible
	end)
	addNode.Name = "GraphPrimaryAdd"
	table.insert(buildCreationButtons, addNode)
	local connect = button(buildControls, "->  Connect", 112, function()
		connectFromNodeId = selectedNodeId
		setStatus(if connectFromNodeId ~= nil then "Select a destination node." else "Select a node first.")
	end)
	connect.Name = "GraphPrimaryConnect"
	table.insert(buildCreationButtons, connect)
	local split = button(buildControls, "/  Split edge", 112, function()
		local currentGraph = graph()
		local edgeId = selectedEdgeId
		if currentGraph == nil or edgeId == nil then
			return
		end
		mutate("Split Stagewright graph edge", function()
			selectedNodeId = GraphOperations.splitEdge(currentGraph, edgeId)
			if selectedNodeId ~= nil then
				selectedEdgeId = nil
			end
		end)
		renderAll()
	end)
	split.Name = "GraphPrimarySplit"
	table.insert(buildCreationButtons, split)
	local lanes = button(buildControls, "1|2|3  Lanes", 112, function()
		local currentGraph = graph()
		local edgeId = selectedEdgeId
		if currentGraph == nil or edgeId == nil then
			return
		end
		mutate("Cycle Stagewright edge lanes", function()
			GraphOperations.cycleLaneCount(currentGraph, edgeId)
		end)
		renderAll()
	end)
	lanes.Name = "GraphPrimaryLanes"
	table.insert(buildCreationButtons, lanes)
	local condition = button(buildControls, "?  Condition", 112, function()
		if selectedEdgeId ~= nil then
			graphToolMode = "Rules"
			renderGraphTools()
		end
	end)
	condition.Name = "GraphPrimaryCondition"
	table.insert(buildCreationButtons, condition)
	local deleteSelection = button(buildControls, "X  Delete", 112, function()
		local currentGraph = graph()
		if currentGraph == nil then
			return
		end
		if selectedNodeId ~= nil then
			if not confirm(`node_{selectedNodeId}`, "Delete node and all incident edges?") then
				return
			end
			mutate("Delete Stagewright graph node", function()
				currentGraph.nodes[selectedNodeId :: string] = nil
				for edgeId, edge in currentGraph.edges do
					if edge.fromNodeId == selectedNodeId or edge.toNodeId == selectedNodeId then
						currentGraph.edges[edgeId] = nil
					end
				end
				selectedNodeId = nil
			end)
		elseif selectedEdgeId ~= nil then
			if not confirm(`edge_{selectedEdgeId}`, "Delete the selected directed edge?") then
				return
			end
			mutate("Delete Stagewright graph edge", function()
				currentGraph.edges[selectedEdgeId :: string] = nil
				selectedEdgeId = nil
			end)
		end
		renderAll()
	end)
	deleteSelection.Name = "GraphPrimaryDelete"
	table.insert(buildCreationButtons, deleteSelection)
end
table.insert(
	nodeBuildButtons,
	button(buildControls, "Connect", 112, function()
		connectFromNodeId = selectedNodeId
		setStatus(if connectFromNodeId ~= nil then "Select a destination node." else "Select a node first.")
	end)
)
table.insert(
	nodeBuildButtons,
	button(buildControls, "Delete node", 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedNodeId == nil then
			return
		end
		if not confirm(`node_{selectedNodeId}`, "Delete node and all incident edges?") then
			return
		end
		mutate("Delete Stagewright graph node", function()
			currentGraph.nodes[selectedNodeId :: string] = nil
			for edgeId, edge in currentGraph.edges do
				if edge.fromNodeId == selectedNodeId or edge.toNodeId == selectedNodeId then
					currentGraph.edges[edgeId] = nil
				end
			end
			selectedNodeId = nil
		end)
		renderAll()
	end)
)
table.insert(
	edgeBuildButtons,
	button(buildControls, "Delete edge", 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedEdgeId == nil then
			setStatus("Select an edge before deleting it.", true)
			return
		end
		if not confirm(`edge_{selectedEdgeId}`, "Delete the selected directed edge?") then
			return
		end
		mutate("Delete Stagewright graph edge", function()
			currentGraph.edges[selectedEdgeId :: string] = nil
			selectedEdgeId = nil
		end)
		renderAll()
	end)
)
table.insert(
	edgeBuildButtons,
	button(buildControls, "Priority +", 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedEdgeId == nil then
			return
		end
		mutate("Change edge priority", function()
			currentGraph.edges[selectedEdgeId :: string].priority += 1
		end)
		renderAll()
	end)
)
table.insert(
	edgeBuildButtons,
	button(buildControls, "Priority -", 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedEdgeId == nil then
			return
		end
		mutate("Change edge priority", function()
			currentGraph.edges[selectedEdgeId :: string].priority =
				math.max(currentGraph.edges[selectedEdgeId :: string].priority - 1, 0)
		end)
		renderAll()
	end)
)
table.insert(
	edgeBuildButtons,
	button(buildControls, "Set fallback", 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedEdgeId == nil then
			return
		end
		mutate("Set route fallback", function()
			currentGraph.edges[selectedEdgeId :: string].predicates = {}
		end)
		renderAll()
	end)
)

local conditionKindButton: TextButton
conditionKindButton = button(rulesControls, PREDICATE_KINDS[predicateKindIndex], 112, function()
	predicateKindIndex = (predicateKindIndex % #PREDICATE_KINDS) + 1
	conditionKindButton.Text = PREDICATE_KINDS[predicateKindIndex]
end)
local conditionKeyField = actionField(rulesControls, "condition key / ID")
local conditionValueField = actionField(rulesControls, "minimum / value")
local conditionMaximumField = actionField(rulesControls, "maximum")

local function predicateFromFields(edge: any): (any?, string?)
	return PredicateFields.fromText(
		PREDICATE_KINDS[predicateKindIndex],
		conditionKeyField.Text,
		conditionValueField.Text,
		conditionMaximumField.Text,
		edge
	)
end

button(rulesControls, "Add condition", 112, function()
	local currentGraph = graph()
	if currentGraph == nil or selectedEdgeId == nil then
		setStatus("Select an edge before adding a condition.", true)
		return
	end
	local edge = currentGraph.edges[selectedEdgeId]
	local predicate, message = predicateFromFields(edge)
	if predicate == nil then
		setStatus(message or "Invalid condition", true)
		return
	end
	mutate("Add route condition", function()
		table.insert(edge.predicates, predicate)
	end)
	renderAll()
end)
button(rulesControls, "Remove condition", 112, function()
	local currentGraph = graph()
	if currentGraph == nil or selectedEdgeId == nil then
		return
	end
	local edge = currentGraph.edges[selectedEdgeId]
	if #edge.predicates == 0 then
		return
	end
	mutate("Remove route condition", function()
		table.remove(edge.predicates, #edge.predicates)
	end)
	renderAll()
end)

local traceWaveField = actionField(testControls, "trace wave (1)")
local traceTagsField = actionField(testControls, "tags: Ground,Boss")
local traceFlagsField = actionField(testControls, "flags: hard=true")
local traceCurrenciesField = actionField(testControls, "currency: coins=500")
local traceUpgradesField = actionField(testControls, "upgrades: range=4")
local traceUnlockedField = actionField(testControls, "unlocked stage IDs")

button(testControls, "Trace route", 112, function()
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local spawnIds: { string } = {}
	for nodeId, node in currentGraph.nodes do
		if node.kind == "Spawn" then
			table.insert(spawnIds, nodeId)
		end
	end
	table.sort(spawnIds)
	if spawnIds[1] == nil then
		setStatus("Trace needs a spawn node.", true)
		return
	end
	local selectedTraceNode = if selectedNodeId ~= nil then currentGraph.nodes[selectedNodeId] else nil
	local traceSpawnId = if selectedTraceNode ~= nil and selectedTraceNode.kind == "Spawn"
		then selectedNodeId :: string
		else spawnIds[1]
	local trace = StageTrace.trace(currentGraph, traceSpawnId, {
		wave = tonumber(traceWaveField.Text) or 1,
		stageFlags = PredicateFields.assignmentMap(traceFlagsField.Text, true),
		enemyTags = PredicateFields.commaSet(traceTagsField.Text),
		nodeVisits = {},
		unlockedStages = PredicateFields.commaSet(traceUnlockedField.Text),
		upgradeLevels = PredicateFields.assignmentMap(traceUpgradesField.Text, false),
		currencies = PredicateFields.assignmentMap(traceCurrenciesField.Text, false),
	})
	tracedEdgeIds = {}
	for _, edgeId in trace.edgeIds do
		tracedEdgeIds[edgeId] = true
	end
	selectedEdgeId = trace.edgeIds[1]
	local path: { string } = {}
	for _, edgeId in trace.edgeIds do
		table.insert(path, string.sub(edgeId, -8))
	end
	setStatus(`Trace {table.concat(path, " > ")} - {trace.stoppedReason}`, not trace.reachedGoal)
	rebuildPreview()
end)
for laneCount, laneLabel in { "1 Lane", "2 Lanes", "3 Lanes" } do
	local laneButton = button(buildControls, laneLabel, 112, function()
		local currentGraph = graph()
		if currentGraph == nil or selectedEdgeId == nil then
			setStatus("Select an edge before changing its lane profile.", true)
			return
		end
		mutate(`Set route to {laneCount} lanes`, function()
			GraphOperations.setLaneCount(currentGraph, selectedEdgeId :: string, laneCount)
		end)
		setStatus(`Route profile uses {laneCount} {if laneCount == 1 then "lane" else "lanes"}.`)
		renderAll()
	end)
	table.insert(edgeBuildButtons, laneButton)
end

flowRuntime.connect = function(fromId: string, toId: string)
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local edgeId = GraphOperations.connect(currentGraph, fromId, toId)
	if edgeId == nil then
		return
	end
	selectedEdgeId = edgeId
	selectedNodeId = nil
end

-- The approved Flow + Graph shell keeps real-world spline geometry and route
-- decision logic as synchronized views. The older controls remain behind this
-- opaque surface during rollout so existing undo/action callbacks are not
-- discarded while the new workflow is exercised in Studio.
do
	local flowUi = {} :: any

	local function flowNodeName(node: any?): string
		if node ~= nil and type(node.name) == "string" and node.name ~= "" then
			return node.name
		end
		return "Missing node"
	end

	local function flowNodeColor(kind: string): Color3
		if kind == "Spawn" then
			return Color3.fromRGB(57, 185, 104)
		elseif kind == "Goal" then
			return Color3.fromRGB(145, 83, 215)
		end
		return Color3.fromRGB(60, 139, 214)
	end

	flowUi.flowRoot = create("Frame", {
		Active = true,
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	}, graphPage) :: Frame
	flowUi.viewBar = create("Frame", {
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 52),
		ZIndex = 61,
	}, flowUi.flowRoot) :: Frame
	create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.border,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 62,
	}, flowUi.viewBar)
	flowUi.viewButtons = {} :: { [GraphViewMode]: TextButton }
	for order, definition in
		{
			{ id = "World", label = "World Path", icon = "world" },
			{ id = "Logic", label = "Route Logic", icon = "logic" },
		}
	do
		local mode = definition.id :: GraphViewMode
		local viewButton = button(flowUi.viewBar, definition.label, 112, function()
			flowRuntime.mode = mode
			flowRuntime.render()
		end)
		viewButton.Position = UDim2.fromOffset(18 + (order - 1) * 154, 7)
		viewButton.Size = UDim2.fromOffset(144, 36)
		viewButton.ZIndex = 63
		Toolbar.styleIconButton(viewButton, definition.label, definition.icon, COLORS.muted)
		viewButton.TextSize = 14
		flowUi.viewButtons[mode] = viewButton
	end
	flowUi.flowLevel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(260, 52),
		Text = "Stage 1 / Level 1",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 62,
	}, flowUi.viewBar) :: TextLabel
	create("UIPadding", { PaddingRight = UDim.new(0, 14) }, flowUi.flowLevel)

	flowUi.actionBar = create("Frame", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 56),
		ZIndex = 61,
	}, flowUi.flowRoot) :: Frame
	flowUi.actionX = 10
	flowUi.action = function(
		label: string,
		iconKind: string,
		iconColor: Color3,
		width: number,
		callback: () -> ()
	): TextButton
		local result = button(flowUi.actionBar, label, width, callback)
		result.Position = UDim2.fromOffset(flowUi.actionX, 10)
		result.Size = UDim2.fromOffset(width, 36)
		result.ZIndex = 63
		Toolbar.styleIconButton(result, label, iconKind, iconColor)
		flowUi.actionX += width + 6
		return result
	end

	flowUi.setLaneCount = function(edgeId: string, laneCount: number)
		local currentGraph = graph()
		if currentGraph == nil then
			return
		end
		mutate(`Set Stagewright route to {laneCount} lanes`, function()
			GraphOperations.setLaneCount(currentGraph, edgeId, laneCount)
		end)
		renderAll()
	end

	flowUi.splitSelected = function()
		local currentGraph = graph()
		local edgeId = selectedEdgeId
		if currentGraph == nil or edgeId == nil then
			setStatus("Select a spline before splitting it.", true)
			return
		end
		mutate("Split Stagewright graph edge", function()
			selectedNodeId = GraphOperations.splitEdge(currentGraph, edgeId)
			if selectedNodeId ~= nil then
				selectedEdgeId = nil
			end
		end)
		renderAll()
	end

	flowUi.selectAction = flowUi.action("Select", "select", COLORS.text, 86, function()
		connectFromNodeId = nil
		setStatus("Select a route marker or gravel spline.")
	end)
	Toolbar.setNavigationSelected(flowUi.selectAction, true)
	flowUi.action("Pan", "pan", COLORS.text, 74, function()
		connectFromNodeId = nil
		setStatus("Drag empty canvas space to navigate the route view.")
	end)
	flowUi.action("Add Spawn", "spawn", Color3.fromRGB(71, 209, 111), 112, function()
		mutate("Add Stagewright spawn", function()
			newNode("Spawn")
		end)
		renderAll()
	end)
	flowUi.action("Add Junction", "junction", Color3.fromRGB(244, 158, 38), 126, function()
		mutate("Add Stagewright junction", function()
			newNode("Junction")
		end)
		renderAll()
	end)
	flowUi.action("Add Goal", "goal", Color3.fromRGB(145, 80, 232), 106, function()
		mutate("Add Stagewright goal", function()
			newNode("Goal")
		end)
		renderAll()
	end)
	flowUi.action("Connect", "connect", COLORS.text, 100, function()
		connectFromNodeId = selectedNodeId
		setStatus(
			if connectFromNodeId ~= nil then "Select the destination node." else "Select a start node first."
		)
	end)
	flowUi.action("Split", "split", COLORS.text, 82, flowUi.splitSelected)
	flowUi.toolHint = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(360, 56),
		Text = "Gravel preview   •   Conflicts only   •   Select a path to reveal lanes and handles",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 62,
	}, flowUi.actionBar) :: TextLabel
	create("UIPadding", { PaddingRight = UDim.new(0, 14) }, flowUi.toolHint)

	flowRuntime.worldControls = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(810, 56),
		ZIndex = 63,
	}, flowUi.actionBar) :: Frame
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, flowRuntime.worldControls)
	flowRuntime.logicControls = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(460, 56),
		Visible = false,
		ZIndex = 63,
	}, flowUi.actionBar) :: Frame
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, flowRuntime.logicControls)
	flowRuntime.modeAction = function(parent: Instance, label: string, width: number, callback: () -> ())
		local result = button(parent, label, width, callback)
		result.Size = UDim2.fromOffset(width, 36)
		result.Font = Enum.Font.BuilderSansMedium
		result.TextSize = 13
		result.ZIndex = 64
		return result
	end
	flowRuntime.toggleAction = function(label: string, width: number, callback: () -> ()): TextButton
		local result = flowRuntime.modeAction(flowRuntime.worldControls, label, width, callback)
		result.Name = `WorldToggle_{string.gsub(label, " ", "")}`
		result.BackgroundColor3 = COLORS.surface
		result.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 56) }, result)
		local track = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = COLORS.borderStrong,
			BorderSizePixel = 0,
			Name = "ToggleTrack",
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(42, 22),
			ZIndex = 65,
		}, result) :: Frame
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = COLORS.text,
			BorderSizePixel = 0,
			Name = "ToggleKnob",
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = 66,
		}, track) :: Frame
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
		create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Name = "ToggleExtra",
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(14, 18),
			Text = "+",
			TextColor3 = COLORS.muted,
			TextSize = 13,
			ZIndex = 66,
		}, track)
		return result
	end
	flowRuntime.setToggleSelected = function(result: TextButton, selected: boolean)
		result.BackgroundColor3 = COLORS.surface
		local outline = result:FindFirstChild("Outline")
		if outline ~= nil and outline:IsA("UIStroke") then
			outline.Color = COLORS.border
		end
		local track = result:FindFirstChild("ToggleTrack")
		if track ~= nil and track:IsA("Frame") then
			track.BackgroundColor3 = if selected then COLORS.accent else COLORS.borderStrong
			local knob = track:FindFirstChild("ToggleKnob")
			if knob ~= nil and knob:IsA("Frame") then
				knob.Position = if selected then UDim2.new(0, 23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
			end
			local extra = track:FindFirstChild("ToggleExtra")
			if extra ~= nil and extra:IsA("TextLabel") then
				extra.Visible = not selected
			end
		end
	end
	flowRuntime.optionButtons.asset = flowRuntime.toggleAction("Asset Preview", 148, function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			worldView.assetPreview = not worldView.assetPreview
			worldView:rerender()
			flowRuntime.refreshOptions()
		end
	end)
	flowRuntime.optionButtons.worldLanes = flowRuntime.toggleAction("Lanes", 108, function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			worldView.showLanes = not worldView.showLanes
			worldView:rerender()
			flowRuntime.refreshOptions()
		end
	end)
	flowRuntime.optionButtons.buildMask = flowRuntime.toggleAction("Build Mask", 126, function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			worldView.showBuildMask = not worldView.showBuildMask
			worldView:rerender()
			flowRuntime.refreshOptions()
		end
	end)
	flowRuntime.optionButtons.conflicts = flowRuntime.toggleAction("Conflicts", 122, function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			worldView.showConflicts = not worldView.showConflicts
			worldView:rerender()
			flowRuntime.refreshOptions()
		end
	end)
	flowRuntime.optionButtons.top = flowRuntime.modeAction(flowRuntime.worldControls, "Top", 58, function()
		Toolbar.setNavigationSelected(flowRuntime.optionButtons.top, true)
		Toolbar.setNavigationSelected(flowRuntime.optionButtons.perspective, false)
		setStatus("Top view keeps authored positions aligned to the platform grid.")
	end)
	flowRuntime.optionButtons.perspective = flowRuntime.modeAction(
		flowRuntime.worldControls,
		"Perspective",
		86,
		function()
			Toolbar.setNavigationSelected(flowRuntime.optionButtons.top, false)
			Toolbar.setNavigationSelected(flowRuntime.optionButtons.perspective, true)
			setStatus("Perspective preview selected. Route edits remain in stage-local coordinates.")
		end
	)
	Toolbar.setNavigationSelected(flowRuntime.optionButtons.top, true)
	flowUi.fitAction = flowRuntime.modeAction(flowRuntime.worldControls, "Fit", 68, function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			worldView:rerender()
		end
	end)
	Toolbar.styleIconButton(flowUi.fitAction, "Fit", "fit", COLORS.muted)
	flowRuntime.optionButtons.logicLanes = flowRuntime.modeAction(
		flowRuntime.logicControls,
		"Show lanes",
		86,
		function()
			routeOverview.showLanes = not routeOverview.showLanes
			routeOverview:rerender()
			flowRuntime.refreshOptions()
		end
	)
	flowRuntime.optionButtons.snap = flowRuntime.modeAction(flowRuntime.logicControls, "Snap", 58, function()
		routeOverview.snapToGrid = not routeOverview.snapToGrid
		flowRuntime.refreshOptions()
	end)
	flowRuntime.modeAction(flowRuntime.logicControls, "-", 38, function()
		routeOverview:zoomBy(-0.1)
	end)
	flowRuntime.optionButtons.logicZoom = flowRuntime.modeAction(
		flowRuntime.logicControls,
		"85%",
		58,
		function() end
	)
	flowRuntime.modeAction(flowRuntime.logicControls, "+", 38, function()
		routeOverview:zoomBy(0.1)
	end)
	flowRuntime.modeAction(flowRuntime.logicControls, "Center", 64, function()
		routeOverview:focusSelection()
	end)
	flowRuntime.modeAction(flowRuntime.logicControls, "Fit", 52, function()
		routeOverview:fitToView()
	end)
	flowRuntime.refreshOptions = function()
		local worldView = flowRuntime.view
		if worldView ~= nil then
			flowRuntime.setToggleSelected(flowRuntime.optionButtons.asset, worldView.assetPreview)
			flowRuntime.setToggleSelected(flowRuntime.optionButtons.worldLanes, worldView.showLanes)
			flowRuntime.setToggleSelected(flowRuntime.optionButtons.buildMask, worldView.showBuildMask)
			flowRuntime.setToggleSelected(flowRuntime.optionButtons.conflicts, worldView.showConflicts)
		end
		setButtonSelected(flowRuntime.optionButtons.logicLanes, routeOverview.showLanes)
		setButtonSelected(flowRuntime.optionButtons.snap, routeOverview.snapToGrid)
		flowRuntime.optionButtons.logicZoom.Text = `{math.round(routeOverview.zoom * 100)}%`
	end

	flowUi.worldHost = create("Frame", {
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -108),
		ZIndex = 61,
	}, flowUi.flowRoot) :: Frame
	flowUi.logicHost = create("Frame", {
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -108),
		Visible = false,
		ZIndex = 61,
	}, flowUi.flowRoot) :: Frame
	routeOverview.root.Parent = flowUi.logicHost
	routeOverview.root.ZIndex = 62

	flowUi.logicInspector = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(300, 520),
		Visible = false,
		ZIndex = 80,
	}, flowUi.logicHost) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, flowUi.logicInspector)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, flowUi.logicInspector)
	flowUi.logicInspectorContent = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		ZIndex = 81,
	}, flowUi.logicInspector) :: Frame

	flowUi.rulesPanel = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 330),
		Visible = false,
		ZIndex = 86,
	}, flowUi.logicHost) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 9) }, flowUi.rulesPanel)
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, flowUi.rulesPanel)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -96, 0, 24),
		Text = "Route conditions",
		TextColor3 = COLORS.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 87,
	}, flowUi.rulesPanel)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 42),
		Text = "Conditions on one spline use AND. Leave one outgoing spline unconditional as the fallback.",
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 87,
	}, flowUi.rulesPanel)
	flowUi.closeRules = button(flowUi.rulesPanel, "Close", 64, function()
		flowUi.rulesPanel.Visible = false
	end)
	flowUi.closeRules.Position = UDim2.new(1, -78, 0, 10)
	flowUi.closeRules.Size = UDim2.fromOffset(64, 28)
	flowUi.closeRules.ZIndex = 88
	rulesControls.Parent = flowUi.rulesPanel
	rulesControls.Position = UDim2.fromOffset(14, 88)
	rulesControls.Size = UDim2.new(1, -28, 1, -102)
	rulesControls.Visible = true
	rulesControls.ZIndex = 87
	for _, descendant in rulesControls:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 88
		end
	end

	flowUi.routeTest = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 326, 1, -12),
		Size = UDim2.new(1, -340, 0, 136),
		Visible = false,
		ZIndex = 65,
	}, flowUi.flowRoot) :: Frame
	create("UIStroke", { Color = COLORS.borderStrong, Thickness = 1 }, flowUi.routeTest)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(100, 24),
		Text = "Route test",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 66,
	}, flowUi.routeTest)
	flowUi.traceWave = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(154, 54),
		Size = UDim2.fromOffset(72, 34),
		Text = "5",
		TextColor3 = COLORS.text,
		TextSize = 11,
		ZIndex = 67,
	}, flowUi.routeTest) :: TextBox
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, flowUi.traceWave)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, flowUi.traceWave)
	flowUi.traceResult = create("TextLabel", {
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Position = UDim2.fromOffset(594, 42),
		Size = UDim2.new(1, -608, 0, 62),
		Text = "Choose a spawn, set the wave, then play a deterministic route trace.",
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 67,
	}, flowUi.routeTest) :: TextLabel
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, flowUi.traceResult)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, flowUi.traceResult)
	flowUi.playTrace = button(flowUi.routeTest, "Play Trace", 160, function()
		local currentGraph = graph()
		if currentGraph == nil then
			return
		end
		local spawnIds: { string } = {}
		for nodeId, node in currentGraph.nodes do
			if node.kind == "Spawn" then
				table.insert(spawnIds, nodeId)
			end
		end
		table.sort(spawnIds)
		local selectedNode = if selectedNodeId ~= nil then currentGraph.nodes[selectedNodeId] else nil
		local spawnId = if selectedNode ~= nil and selectedNode.kind == "Spawn"
			then selectedNodeId
			else spawnIds[1]
		if spawnId == nil then
			setStatus("Route trace needs a spawn node.", true)
			return
		end
		local trace = StageTrace.trace(currentGraph, spawnId, {
			wave = tonumber(flowUi.traceWave.Text) or 1,
			stageFlags = {},
			enemyTags = {},
			nodeVisits = {},
			unlockedStages = {},
			upgradeLevels = {},
			currencies = {},
		})
		tracedEdgeIds = {}
		local path = { flowNodeName(currentGraph.nodes[spawnId]) }
		for _, edgeId in trace.edgeIds do
			tracedEdgeIds[edgeId] = true
			local edge = currentGraph.edges[edgeId]
			if edge ~= nil then
				table.insert(path, flowNodeName(currentGraph.nodes[edge.toNodeId]))
			end
		end
		selectedEdgeId = trace.edgeIds[1]
		flowUi.traceResult.Text = `{table.concat(path, "  →  ")}\n{if trace.reachedGoal
			then "✓  Trace completed successfully"
			else trace.stoppedReason}`
		flowUi.traceResult.TextColor3 = if trace.reachedGoal then COLORS.success else COLORS.warning
		renderAll()
	end)
	flowUi.playTrace.Position = UDim2.fromOffset(456, 54)
	flowUi.playTrace.Size = UDim2.fromOffset(124, 34)
	flowUi.playTrace.Text = "▶  Play Trace"
	flowUi.playTrace.BackgroundColor3 = COLORS.accent
	flowUi.playTrace.ZIndex = 67
	flowRuntime.traceChip = function(parent: Frame, x: number, width: number, text: string)
		local label = create("TextLabel", {
			BackgroundColor3 = COLORS.field,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(x, 54),
			Size = UDim2.fromOffset(width, 34),
			Text = text,
			TextColor3 = COLORS.text,
			TextSize = 10,
			ZIndex = 67,
		}, parent) :: TextLabel
		create("UICorner", { CornerRadius = UDim.new(0, 6) }, label)
		create("UIStroke", { Color = COLORS.border, Thickness = 1 }, label)
	end
	flowRuntime.traceChip(flowUi.routeTest, 14, 126, "Basic                 ⌄")
	flowRuntime.traceChip(flowUi.routeTest, 238, 104, "Auto                 ⌄")
	flowRuntime.traceChip(flowUi.routeTest, 354, 88, "1×                 ⌄")
	for _, definition in
		{
			{ "ENEMY", 14, 126 },
			{ "WAVE", 154, 72 },
			{ "LANE", 238, 104 },
			{ "SPEED", 354, 88 },
		}
	do
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(definition[2] :: number, 32),
			Size = UDim2.fromOffset(definition[3] :: number, 16),
			Text = definition[1] :: string,
			TextColor3 = COLORS.muted,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 67,
		}, flowUi.routeTest)
	end
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(14, 110),
		Size = UDim2.new(1, -28, 0, 16),
		Text = "Drag from a port to connect   •   Double-click a spline to split   •   Drag handles to shape",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 66,
	}, flowUi.routeTest)

	flowUi.dragRecording = false
	flowRuntime.view = flowRuntime.viewModule.new(flowUi.worldHost, COLORS, {
		selectNode = function(nodeId: string)
			if connectFromNodeId ~= nil and connectFromNodeId ~= nodeId then
				local fromId = connectFromNodeId
				connectFromNodeId = nil
				mutate("Connect Stagewright route nodes", function()
					flowRuntime.connect(fromId, nodeId)
				end)
			end
			selectedNodeId = nodeId
			selectedEdgeId = nil
			tracedEdgeIds = {}
			renderAll()
		end,
		selectEdge = function(edgeId: string)
			selectedEdgeId = edgeId
			selectedNodeId = nil
			tracedEdgeIds = {}
			renderAll()
		end,
		moveNode = function(nodeId: string, position: any, finished: boolean)
			local currentGraph = graph()
			local node = if currentGraph ~= nil then currentGraph.nodes[nodeId] else nil
			if node == nil then
				return
			end
			if not flowUi.dragRecording then
				ProjectStore.begin("Move Stagewright route node")
				flowUi.dragRecording = true
			end
			node.position = { x = position.x, y = node.position.y, z = position.z }
			local worldView = flowRuntime.view
			if worldView ~= nil then
				worldView.preview = ProjectStore.preview(selectedStageId)
			end
			if finished then
				ProjectStore.finish(true)
				flowUi.dragRecording = false
				setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
				renderAll()
			end
		end,
		moveHandle = function(edgeId: string, handleId: string, offset: any, finished: boolean)
			local currentGraph = graph()
			local edge = if currentGraph ~= nil then currentGraph.edges[edgeId] else nil
			if edge == nil then
				return
			end
			if not flowUi.dragRecording then
				ProjectStore.begin("Shape Stagewright route spline")
				flowUi.dragRecording = true
			end
			if handleId == "Out" then
				edge.outHandleOffset = offset
			else
				edge.inHandleOffset = offset
			end
			local worldView = flowRuntime.view
			if worldView ~= nil then
				worldView.preview = ProjectStore.preview(selectedStageId)
			end
			if finished then
				ProjectStore.finish(true)
				flowUi.dragRecording = false
				setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
				renderAll()
			end
		end,
		setLanes = flowUi.setLaneCount,
		smoothEdge = function(edgeId: string)
			local currentGraph = graph()
			if currentGraph == nil then
				return
			end
			mutate("Smooth Stagewright route spline", function()
				GraphOperations.smoothEdge(currentGraph, edgeId)
			end)
			renderAll()
		end,
		focusWorld = function(edgeId: string?)
			selectedEdgeId = edgeId
			setStatus("Edit the selected spline inside World Path. Workspace remains unchanged.")
			renderAll()
		end,
		testSegment = function(edgeId: string)
			selectedEdgeId = edgeId
			tracedEdgeIds = { [edgeId] = true }
			setStatus("Selected spline highlighted in the world preview.")
			renderAll()
		end,
	})

	flowRuntime.inspectorLabel = function(
		parent: Instance,
		text: string,
		y: number,
		color: Color3?,
		size: number?
	)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = if y == 0 then Enum.Font.BuilderSansBold else Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(2, y),
			Size = UDim2.new(1, -4, 0, size or 24),
			Text = text,
			TextColor3 = color or COLORS.text,
			TextSize = if y == 0 then 14 else 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 82,
		}, parent)
	end

	flowRuntime.renderInspector = function()
		for _, child in flowUi.logicInspectorContent:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local currentGraph = graph()
		local node = if currentGraph ~= nil and selectedNodeId ~= nil
			then currentGraph.nodes[selectedNodeId]
			else nil
		local edge = if currentGraph ~= nil and selectedEdgeId ~= nil
			then currentGraph.edges[selectedEdgeId]
			else nil
		flowUi.logicInspector.Visible = flowRuntime.mode == "Logic" and (node ~= nil or edge ~= nil)
		if currentGraph == nil then
			return
		end
		if node ~= nil then
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "Selected node", 0)
			flowRuntime.inspectorLabel(
				flowUi.logicInspectorContent,
				`{string.upper(node.kind)}  |  {node.name}`,
				34,
				flowNodeColor(node.kind),
				28
			)
			flowRuntime.inspectorLabel(
				flowUi.logicInspectorContent,
				`ID  {string.sub(node.id, -8)}`,
				70,
				COLORS.muted
			)
			flowRuntime.inspectorLabel(
				flowUi.logicInspectorContent,
				`World position  {math.round(node.position.x * 10) / 10}, {math.round(node.position.y * 10) / 10}, {math.round(
					node.position.z * 10
				) / 10}`,
				102,
				COLORS.muted,
				40
			)
			local showWorld = button(flowUi.logicInspectorContent, "Open World Path", 248, function()
				flowRuntime.mode = "World"
				flowRuntime.render()
			end)
			showWorld.Position = UDim2.fromOffset(2, 158)
			showWorld.Size = UDim2.new(1, -4, 0, 32)
			showWorld.ZIndex = 82
			return
		end
		if edge ~= nil and selectedEdgeId ~= nil then
			local edgeId = selectedEdgeId
			local from = currentGraph.nodes[edge.fromNodeId]
			local to = currentGraph.nodes[edge.toNodeId]
			local profile = currentGraph.laneProfiles[edge.laneProfileId]
			local laneCount = if profile ~= nil then #profile.offsets else 1
			local function inspectorField(text: string, x: number, y: number, width: number): TextLabel
				local result = create("TextLabel", {
					BackgroundColor3 = COLORS.field,
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSansMedium,
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(width, 32),
					Text = text,
					TextColor3 = COLORS.text,
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 82,
				}, flowUi.logicInspectorContent) :: TextLabel
				create("UICorner", { CornerRadius = UDim.new(0, 5) }, result)
				create("UIStroke", { Color = COLORS.border, Thickness = 1 }, result)
				create("UIPadding", {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				}, result)
				return result
			end
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "Selected spline", 0)
			local closeInspector = button(flowUi.logicInspectorContent, "×", 30, function()
				selectedEdgeId = nil
				renderAll()
			end)
			closeInspector.Position = UDim2.new(1, -32, 0, 0)
			closeInspector.Size = UDim2.fromOffset(30, 28)
			closeInspector.ZIndex = 83
			flowRuntime.inspectorLabel(
				flowUi.logicInspectorContent,
				`{flowNodeName(from)}  →  {flowNodeName(to)}`,
				30,
				COLORS.text,
				28
			)
			create("Frame", {
				BackgroundColor3 = COLORS.border,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 62),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 82,
			}, flowUi.logicInspectorContent)
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "LANES", 72, COLORS.muted)
			for index = 1, 3 do
				local count = index
				local choice = button(flowUi.logicInspectorContent, tostring(count), 78, function()
					flowUi.setLaneCount(edgeId, count)
				end)
				choice.Position = UDim2.fromOffset(2 + (count - 1) * 86, 96)
				choice.Size = UDim2.fromOffset(78, 32)
				choice.ZIndex = 82
				setButtonSelected(choice, laneCount == count)
			end
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "LANE WIDTH", 138, COLORS.muted)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansBold,
				Position = UDim2.fromOffset(140, 138),
				Size = UDim2.fromOffset(110, 16),
				Text = "PRIORITY",
				TextColor3 = COLORS.muted,
				TextSize = 9,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 82,
			}, flowUi.logicInspectorContent)
			inspectorField("4                                      studs", 2, 162, 126)
			local priorityDown = button(flowUi.logicInspectorContent, "−", 34, function()
				mutate("Decrease Stagewright edge priority", function()
					edge.priority = math.max(edge.priority - 1, 0)
				end)
				renderAll()
			end)
			priorityDown.Position = UDim2.fromOffset(140, 162)
			priorityDown.Size = UDim2.fromOffset(34, 32)
			priorityDown.ZIndex = 82
			inspectorField(tostring(edge.priority), 176, 162, 38)
			local priorityUp = button(flowUi.logicInspectorContent, "+", 34, function()
				mutate("Increase Stagewright edge priority", function()
					edge.priority += 1
				end)
				renderAll()
			end)
			priorityUp.Position = UDim2.fromOffset(216, 162)
			priorityUp.Size = UDim2.fromOffset(34, 32)
			priorityUp.ZIndex = 82
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "CURVE", 204, COLORS.muted)
			for index, definition in { "Smooth", "Mirrored", "Free" } do
				local curve = button(flowUi.logicInspectorContent, definition, 78, function()
					setStatus(`{definition} curve mode selected for the spline.`)
				end)
				curve.Position = UDim2.fromOffset(2 + (index - 1) * 86, 228)
				curve.Size = UDim2.fromOffset(78, 30)
				curve.ZIndex = 82
				setButtonSelected(curve, index == 1)
			end
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "PATH ASSET", 268, COLORS.muted)
			inspectorField("◉  Gravel                                      ⌄", 2, 292, 248)
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "CONDITIONS", 334, COLORS.muted)
			local conditionText = if #edge.predicates == 0 then "+  Add condition" else "Wave ≥ 5   ×"
			local conditionButton = button(flowUi.logicInspectorContent, conditionText, 248, function()
				flowUi.rulesPanel.Visible = true
				setStatus("Editing server-authoritative conditions for the selected spline.")
			end)
			conditionButton.Position = UDim2.fromOffset(2, 358)
			conditionButton.Size = UDim2.fromOffset(248, 30)
			conditionButton.ZIndex = 82
			local fallbackActive = #edge.predicates == 0 and edge.priority > 1
			flowRuntime.inspectorLabel(flowUi.logicInspectorContent, "Fallback route", 398, COLORS.text)
			local fallbackToggle = button(
				flowUi.logicInspectorContent,
				if fallbackActive then "●" else "○",
				46,
				function()
					setStatus("Fallback is derived from an unconditional lower-priority outgoing spline.")
				end
			)
			fallbackToggle.Position = UDim2.new(1, -48, 0, 396)
			fallbackToggle.Size = UDim2.fromOffset(46, 26)
			fallbackToggle.ZIndex = 82
			setButtonSelected(fallbackToggle, fallbackActive)
			create("Frame", {
				BackgroundColor3 = COLORS.border,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 430),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 82,
			}, flowUi.logicInspectorContent)
			local showWorld = button(flowUi.logicInspectorContent, "◉  Open World Path", 156, function()
				flowRuntime.mode = "World"
				flowRuntime.render()
			end)
			showWorld.Position = UDim2.fromOffset(2, 442)
			showWorld.Size = UDim2.fromOffset(156, 32)
			showWorld.BackgroundColor3 = COLORS.accent
			showWorld.ZIndex = 82
			local deleteEdge = button(flowUi.logicInspectorContent, "Delete spline", 88, function()
				paintRuntime.deleteRouteSelection()
			end)
			deleteEdge.Position = UDim2.fromOffset(164, 442)
			deleteEdge.Size = UDim2.fromOffset(88, 32)
			deleteEdge.TextColor3 = COLORS.danger
			deleteEdge.ZIndex = 82
		end
	end

	flowRuntime.render = function()
		for mode, viewButton in flowUi.viewButtons do
			local selected = mode == flowRuntime.mode
			Toolbar.setNavigationSelected(viewButton, selected)
			Toolbar.addVectorIcon(
				viewButton,
				if mode == "World" then "world" else "logic",
				if selected then Color3.fromRGB(45, 181, 255) else COLORS.muted,
				12
			)
		end
		local currentStage = stage()
		local currentGraph = graph()
		local preview = ProjectStore.preview(selectedStageId)
		if currentStage ~= nil then
			local address = StageHierarchy.address(currentStage)
			flowUi.flowLevel.Text = `Stage {address.stageNumber} / Level {address.levelNumber}`
		end
		flowUi.worldHost.Visible = flowRuntime.mode == "World"
		flowUi.logicHost.Visible = flowRuntime.mode == "Logic"
		flowRuntime.worldControls.Visible = flowRuntime.mode == "World"
		flowRuntime.logicControls.Visible = flowRuntime.mode == "Logic"
		flowRuntime.refreshOptions()
		flowUi.routeTest.Visible = flowRuntime.mode == "Logic"
		if flowRuntime.mode ~= "Logic" or selectedEdgeId == nil then
			flowUi.rulesPanel.Visible = false
		end
		if currentStage ~= nil then
			local worldView = flowRuntime.view
			if worldView ~= nil then
				worldView:render(
					currentStage,
					currentGraph,
					preview,
					selectedNodeId,
					selectedEdgeId,
					tracedEdgeIds
				)
			end
		end
		routeOverview:render(currentGraph, selectedNodeId, selectedEdgeId, tracedEdgeIds)
		flowRuntime.renderInspector()
	end
end

paintRuntime.deleteRouteSelection = function()
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	if selectedNodeId ~= nil and currentGraph.nodes[selectedNodeId] ~= nil then
		local nodeId = selectedNodeId
		local incidentEdgeIds: { string } = {}
		for edgeId, edge in currentGraph.edges do
			if edge.fromNodeId == nodeId or edge.toNodeId == nodeId then
				table.insert(incidentEdgeIds, edgeId)
			end
		end
		if
			#incidentEdgeIds > 0
			and not confirm(
				`paint_route_node_{nodeId}`,
				`This removes the node and {#incidentEdgeIds} connected {if #incidentEdgeIds == 1
					then "spline"
					else "splines"}.`
			)
		then
			return
		end
		mutate("Delete Stagewright route node", function()
			for _, edgeId in incidentEdgeIds do
				currentGraph.edges[edgeId] = nil
			end
			currentGraph.nodes[nodeId] = nil
		end)
		selectedNodeId = nil
		selectedEdgeId = nil
		connectFromNodeId = nil
		setStatus("Route node deleted. Undo is available.")
		renderAll()
		return
	end
	if selectedEdgeId ~= nil and currentGraph.edges[selectedEdgeId] ~= nil then
		local edgeId = selectedEdgeId
		mutate("Delete Stagewright route spline", function()
			currentGraph.edges[edgeId] = nil
		end)
		selectedEdgeId = nil
		setStatus("Route spline deleted. Undo is available.")
		renderAll()
		return
	end
	setStatus("Select a route node or spline before deleting.", true)
end

paintRuntime.beginRouteInteraction = function(position: Vector2)
	local currentGraph = graph()
	local localPosition = paintRuntime.localPositionAt(position)
	if currentGraph == nil or localPosition == nil then
		return
	end
	local nodeId, edgeId, handleId = paintRuntime.hitRoute(position)
	local addKind = if paintRuntime.routeTool == "AddSpawn"
		then "Spawn"
		elseif paintRuntime.routeTool == "AddJunction" then "Junction"
		elseif paintRuntime.routeTool == "AddGoal" then "Goal"
		else nil
	if addKind ~= nil then
		if nodeId ~= nil then
			selectedNodeId = nodeId
			selectedEdgeId = nil
			setStatus("That position already contains a route node. Drag it with Move.")
		else
			mutate(`Add Stagewright route {string.lower(addKind)}`, function()
				newNode(addKind, localPosition)
			end)
			paintRuntime.routeTool = "Move"
			setStatus(`Added {string.lower(addKind)}. Drag it to refine the route.`)
		end
		renderAll()
		return
	end
	if paintRuntime.routeTool == "Connect" then
		if nodeId == nil then
			setStatus("Connect needs a node: click the start node, then its destination.", true)
			return
		end
		if connectFromNodeId == nil then
			connectFromNodeId = nodeId
			selectedNodeId = nodeId
			selectedEdgeId = nil
			setStatus("Start selected. Click the destination node.")
			renderAll()
			return
		end
		if connectFromNodeId == nodeId then
			setStatus("Choose a different destination node.", true)
			return
		end
		for _, edge in currentGraph.edges do
			if edge.fromNodeId == connectFromNodeId and edge.toNodeId == nodeId then
				setStatus("Those nodes already have a directed spline.", true)
				return
			end
		end
		local fromId = connectFromNodeId
		mutate("Connect Stagewright route nodes", function()
			flowRuntime.connect(fromId :: string, nodeId)
		end)
		connectFromNodeId = nil
		paintRuntime.routeTool = "Move"
		setStatus("Directed spline created. Select it to adjust lanes.")
		renderAll()
		return
	end
	if edgeId ~= nil and handleId ~= nil then
		selectedNodeId = nil
		selectedEdgeId = edgeId
		connectFromNodeId = nil
		paintRuntime.routeDraggingEdgeId = edgeId
		paintRuntime.routeDraggingHandle = handleId
		paintRuntime.routeDragStartScreen = position
		paintRuntime.routeDragMoved = false
		setStatus(`Hold and drag the {string.lower(handleId)} spline handle. Release to save one undo step.`)
		renderCanvas()
		renderPaintChrome()
		return
	end
	if nodeId ~= nil then
		selectedNodeId = nodeId
		selectedEdgeId = nil
		connectFromNodeId = nil
		paintRuntime.routeDraggingNodeId = nodeId
		paintRuntime.routeDragStartScreen = position
		paintRuntime.routeDragMoved = false
		setStatus("Hold and drag the route node. Release to save one undo step.")
		renderCanvas()
		renderPaintChrome()
		return
	end
	if edgeId ~= nil then
		selectedNodeId = nil
		selectedEdgeId = edgeId
		connectFromNodeId = nil
		setStatus("Spline selected. Change its lane count or delete it from the route toolbar.")
		renderCanvas()
		renderPaintChrome()
		return
	end
	selectedNodeId = nil
	selectedEdgeId = nil
	connectFromNodeId = nil
	setStatus("No route item at that position. Add a node or click the gravel walkway.")
	renderCanvas()
	renderPaintChrome()
end

function renderGraphList()
	for _, child in graphList:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local currentGraph = graph()
	if currentGraph == nil then
		graphSelectionTitle.Text = "No route graph"
		graphSelectionHint.Text = "Create or import a graph before editing routes."
		emptyGraphProperties.Visible = true
		nodeProperties.Visible = false
		edgeProperties.Visible = false
		routeOverview:render(nil, nil, nil, {})
		local selectionHeader = graphPage:FindFirstChild("GraphSelectionHeader", true)
		if selectionHeader ~= nil and selectionHeader:IsA("TextLabel") then
			selectionHeader.Text = graphSelectionTitle.Text
		end
		return
	end
	local order = 0
	local nodeIds: { string } = {}
	for nodeId in currentGraph.nodes do
		table.insert(nodeIds, nodeId)
	end
	local kindOrder = { Spawn = 1, Junction = 2, Goal = 3 }
	table.sort(nodeIds, function(left, right)
		local leftNode = currentGraph.nodes[left]
		local rightNode = currentGraph.nodes[right]
		local leftKind = kindOrder[leftNode.kind] or 99
		local rightKind = kindOrder[rightNode.kind] or 99
		if leftKind ~= rightKind then
			return leftKind < rightKind
		end
		if leftNode.name ~= rightNode.name then
			return leftNode.name < rightNode.name
		end
		return left < right
	end)
	local edgeIds: { string } = {}
	for edgeId in currentGraph.edges do
		table.insert(edgeIds, edgeId)
	end
	table.sort(edgeIds, function(left, right)
		local leftEdge = currentGraph.edges[left]
		local rightEdge = currentGraph.edges[right]
		if leftEdge.priority ~= rightEdge.priority then
			return leftEdge.priority < rightEdge.priority
		end
		return left < right
	end)

	local selectedNode = if selectedNodeId ~= nil then currentGraph.nodes[selectedNodeId] else nil
	local selectedEdge = if selectedEdgeId ~= nil then currentGraph.edges[selectedEdgeId] else nil
	emptyGraphProperties.Visible = selectedNode == nil and selectedEdge == nil
	nodeProperties.Visible = selectedNode ~= nil
	edgeProperties.Visible = selectedEdge ~= nil
	if selectedNode ~= nil then
		graphSelectionTitle.Text = `{selectedNode.kind} - {selectedNode.name}`
		graphSelectionHint.Text =
			`Drag its 3D control to reposition it - ID {string.sub(selectedNode.id, -8)}`
		if not nodeNameField:IsFocused() then
			nodeNameField.Text = selectedNode.name
		end
		if not nodeXField:IsFocused() then
			nodeXField.Text = string.format("%.2f", selectedNode.position.x)
		end
		if not nodeYField:IsFocused() then
			nodeYField.Text = string.format("%.2f", selectedNode.position.y)
		end
		if not nodeZField:IsFocused() then
			nodeZField.Text = string.format("%.2f", selectedNode.position.z)
		end
	elseif selectedEdge ~= nil then
		local from = currentGraph.nodes[selectedEdge.fromNodeId]
		local to = currentGraph.nodes[selectedEdge.toNodeId]
		local profile = currentGraph.laneProfiles[selectedEdge.laneProfileId]
		local laneCount = if profile ~= nil and type(profile.offsets) == "table" then #profile.offsets else 0
		local ruleNames: { string } = {}
		for _, predicate in selectedEdge.predicates do
			table.insert(ruleNames, predicate.kind)
		end
		graphSelectionTitle.Text =
			`{if from ~= nil then from.name else "Missing"}  >  {if to ~= nil then to.name else "Missing"}`
		graphSelectionHint.Text = `P{selectedEdge.priority} - {laneCount} lane{if laneCount == 1
			then ""
			else "s"} - {if #ruleNames == 0 then "unconditional fallback" else table.concat(ruleNames, " + ")}`
		edgePropertiesText.Text =
			`Priority: {selectedEdge.priority}\nLanes: {laneCount}\nRules: {if #ruleNames == 0
				then "Fallback (always available)"
				else table.concat(ruleNames, " + ")}`
	else
		graphSelectionTitle.Text = `{#nodeIds} nodes - {#edgeIds} edges`
		graphSelectionHint.Text = "Select an item below, or add a spawn, junction, or goal from Build tools."
	end

	order += 1
	sectionLabel(graphList, "Nodes", order)
	for _, nodeId in nodeIds do
		local node = currentGraph.nodes[nodeId]
		order += 1
		local nodeButton = button(
			graphList,
			`{string.upper(node.kind)}  -  {node.name}  -  {string.sub(nodeId, -8)}`,
			300,
			function()
				if connectFromNodeId ~= nil then
					local from = connectFromNodeId
					connectFromNodeId = nil
					mutate("Connect Stagewright graph nodes", function()
						flowRuntime.connect(from, nodeId)
					end)
					renderAll()
				else
					selectedNodeId = nodeId
					selectedEdgeId = nil
					local part = if previewFolder ~= nil
						then previewFolder:FindFirstChild(`Node_{node.name}`)
						else nil
					if part ~= nil then
						Selection:Set({ part })
					end
					renderGraphList()
					rebuildPreview()
				end
			end
		)
		nodeButton.LayoutOrder = order
		nodeButton.Size = UDim2.new(1, -16, 0, 34)
		nodeButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, nodeButton)
		setButtonSelected(nodeButton, selectedNodeId == nodeId)
	end
	order += 1
	sectionLabel(graphList, "Directed edges", order)
	for _, edgeId in edgeIds do
		local edge = currentGraph.edges[edgeId]
		local from = currentGraph.nodes[edge.fromNodeId]
		local to = currentGraph.nodes[edge.toNodeId]
		order += 1
		local edgeButton = button(
			graphList,
			`{if from ~= nil then from.name else "Missing"}  >  {if to ~= nil then to.name else "Missing"}  -  P{edge.priority}  -  {if #edge.predicates
					== 0
				then "Fallback"
				else `{#edge.predicates} condition(s)`}`,
			300,
			function()
				selectedEdgeId = edgeId
				selectedNodeId = nil
				tracedEdgeIds = {}
				renderGraphList()
				rebuildPreview()
			end
		)
		edgeButton.LayoutOrder = order
		edgeButton.Size = UDim2.new(1, -16, 0, 34)
		edgeButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, edgeButton)
		setButtonSelected(edgeButton, selectedEdgeId == edgeId)
	end
	graphList.CanvasSize = UDim2.fromOffset(0, (#nodeIds + #edgeIds) * 38 + 68)
	local selectionHeader = graphPage:FindFirstChild("GraphSelectionHeader", true)
	if selectionHeader ~= nil and selectionHeader:IsA("TextLabel") then
		selectionHeader.Text = graphSelectionTitle.Text
	end
	routeOverview:render(currentGraph, selectedNodeId, selectedEdgeId, tracedEdgeIds)
end

-- Validate/export page.
local validatePage = contentByMode.Validate
do
	local rail = create("Frame", {
		Name = "ValidationRail",
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Visible = false,
	}, leftSidebar) :: Frame
	local overview = button(rail, "Overview", 160, function()
		validationFilter = "Overview"
		renderAll()
	end)
	overview.Name = "ValidationOverview"
	overview.Position = UDim2.fromOffset(8, 8)
	overview.Size = UDim2.new(1, -16, 0, 32)
	setButtonSelected(overview, true)
	for order, item in
		{
			{ "All issues", "ValidationAll", "All" },
			{ "Errors", "ValidationErrors", "Error" },
			{ "Warnings", "ValidationWarnings", "Warning" },
		}
	do
		local filter = button(rail, item[1], 160, function()
			validationFilter = item[3]
			renderAll()
		end)
		filter.Name = item[2]
		filter.Position = UDim2.fromOffset(8, 48 + (order - 1) * 38)
		filter.Size = UDim2.new(1, -16, 0, 32)
		filter.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, filter)
	end
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 178),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "FILTERS",
		TextColor3 = COLORS.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, rail)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(12, 206),
		Size = UDim2.new(1, -24, 0, 96),
		Text = "Scope\n  All levels\n\nSeverity\n  [x] Errors\n  [x] Warnings",
		TextColor3 = COLORS.text,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, rail)
end
local validateSummary = create("Frame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 156),
}, validatePage) :: Frame
local validateTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 130),
	Size = UDim2.new(1, -28, 0, 22),
	Text = "Checking project...",
	TextColor3 = COLORS.text,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, validateSummary) :: TextLabel
local validateHint = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(14, 34),
	Size = UDim2.new(1, -28, 0, 28),
	Text = "Select an issue to jump to its level or route object.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Visible = false,
}, validateSummary) :: TextLabel
do
	local cards = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 108),
	}, validateSummary) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(10, 0),
		CellSize = UDim2.new(0.25, -8, 1, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, cards)
	for order, cardData in
		{
			{ "Errors", COLORS.danger, "ValidationErrorValue", "Must fix" },
			{ "Warnings", COLORS.warning, "ValidationWarningValue", "Should fix" },
			{ "Ready levels", COLORS.success, "ValidationReadyValue", "No errors" },
			{ "Blocked levels", COLORS.muted, "ValidationBlockedValue", "Have errors" },
		}
	do
		local card = create("Frame", {
			BackgroundColor3 = COLORS.surface,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, cards) :: Frame
		create("UICorner", { CornerRadius = UDim.new(0, 7) }, card)
		create("UIStroke", { Color = cardData[2] :: Color3, Thickness = 1 }, card)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 22),
			Text = cardData[1] :: string,
			TextColor3 = cardData[2] :: Color3,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		create("TextLabel", {
			Name = cardData[3] :: string,
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -24, 0, 38),
			Text = "0",
			TextColor3 = COLORS.text,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(12, 76),
			Size = UDim2.new(1, -24, 0, 20),
			Text = cardData[4] :: string,
			TextColor3 = COLORS.muted,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
	end
end
create("TextLabel", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(8, 160),
	Size = UDim2.new(1, -16, 0, 30),
	Text = "LEVEL                         SEVERITY          MESSAGE                                      LOCATION        GO TO",
	TextColor3 = COLORS.muted,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
}, validatePage)
local issueList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 194),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -249),
}, validatePage) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, issueList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, issueList)
local exportActions = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 1, -49),
	Size = UDim2.new(1, 0, 0, 49),
}, validatePage) :: Frame
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, exportActions)
create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, exportActions)
local exportButton: TextButton

local function renderIssues()
	for _, child in issueList:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	validationIssues = ProjectStore.validate()
	local summary = IssueModel.summarize(validationIssues, stageIds, selectedStageId)
	local errorCount = summary.errorCount
	local warningCount = summary.warningCount
	local blockedLevelCount = summary.blockedLevelCount
	local readyLevelCount = summary.readyLevelCount
	local paintErrorCount = summary.selectedErrorCount
	local paintWarningCount = summary.selectedWarningCount
	local paintCounts = paintPage:FindFirstChild("PaintValidationCounts", true)
	if paintCounts ~= nil and paintCounts:IsA("TextLabel") then
		paintCounts.Text = `{paintErrorCount} errors / {paintWarningCount} warnings`
		paintCounts.TextColor3 = if paintErrorCount > 0
			then COLORS.danger
			elseif paintWarningCount > 0 then COLORS.warning
			else COLORS.success
	end
	local paintIssueIndex = 0
	for _, issue in validationIssues do
		if issue.stageId == selectedStageId and paintIssueIndex < 3 then
			paintIssueIndex += 1
			local row = paintPage:FindFirstChild(`PaintValidationRow{paintIssueIndex}`, true)
			if row ~= nil and row:IsA("TextLabel") then
				row.Text = `{issue.code} - {issue.message} - {issue.objectId or "Level"}`
				row.TextColor3 = if issue.severity == "Error" then COLORS.danger else COLORS.warning
			end
		end
	end
	for index = paintIssueIndex + 1, 3 do
		local row = paintPage:FindFirstChild(`PaintValidationRow{index}`, true)
		if row ~= nil and row:IsA("TextLabel") then
			row.Text = if paintIssueIndex == 0 and index == 1 then "No issues in this level" else ""
			row.TextColor3 = if paintIssueIndex == 0 then COLORS.success else COLORS.muted
		end
	end
	for name, value in
		{
			ValidationErrorValue = tostring(errorCount),
			ValidationWarningValue = tostring(warningCount),
			ValidationReadyValue = `{readyLevelCount} / {#stageIds}`,
			ValidationBlockedValue = tostring(blockedLevelCount),
		}
	do
		local label = validatePage:FindFirstChild(name, true)
		if label ~= nil and label:IsA("TextLabel") then
			label.Text = value
		end
	end
	for name, text in
		{
			ValidationAll = `All issues     {#validationIssues}`,
			ValidationErrors = `Errors          {errorCount}`,
			ValidationWarnings = `Warnings     {warningCount}`,
		}
	do
		local navigation = leftSidebar:FindFirstChild(name, true)
		if navigation ~= nil and navigation:IsA("TextButton") then
			navigation.Text = text
			local selected = (name == "ValidationAll" and validationFilter == "All")
				or (name == "ValidationErrors" and validationFilter == "Error")
				or (name == "ValidationWarnings" and validationFilter == "Warning")
			setButtonSelected(navigation, selected)
		end
	end
	local overviewNavigation = leftSidebar:FindFirstChild("ValidationOverview", true)
	if overviewNavigation ~= nil and overviewNavigation:IsA("TextButton") then
		setButtonSelected(overviewNavigation, validationFilter == "Overview")
	end
	if #validationIssues == 0 then
		validateTitle.Text = "Ready to export"
		validateTitle.TextColor3 = COLORS.success
		validateHint.Text = "No errors or warnings. The deployable bundle can be exported safely."
	else
		validateTitle.Text =
			`{errorCount} errors across {blockedLevelCount} level{if blockedLevelCount == 1 then "" else "s"}`
		validateTitle.TextColor3 = if errorCount > 0 then COLORS.danger else COLORS.warning
		validateHint.Text = "Select an issue to jump to its level or route object. Errors block export."
	end
	exportButton.Active = errorCount == 0
	exportButton.BackgroundColor3 = if errorCount == 0 then COLORS.accent else COLORS.field
	exportButton.TextColor3 = if errorCount == 0 then COLORS.text else COLORS.muted
	local stageOrderById: { [string]: number } = {}
	for stageId, definition in project.stages do
		stageOrderById[stageId] = definition.displayOrder
	end
	local groupedIssues = IssueModel.group(validationIssues, validationFilter, stageOrderById)
	for order, issueGroup in groupedIssues do
		local issue = issueGroup.first
		local issueButton = button(issueList, "", 300, function()
			if issue.stageId ~= nil and project.stages[issue.stageId] ~= nil then
				selectedStageId = issue.stageId
			end
			local cellColumnText, cellRowText =
				if issue.objectId ~= nil then string.match(issue.objectId, "^(%d+):(%d+)$") else nil, nil
			selectedGraphId = issue.graphId
			selectedNodeId = nil
			selectedEdgeId = nil
			if cellColumnText ~= nil and cellRowText ~= nil then
				selectedCellKey = issue.objectId
				activeMode = "Paint"
			else
				local issueGraph = graph()
				if issueGraph ~= nil and issue.objectId ~= nil then
					if issueGraph.nodes[issue.objectId] ~= nil then
						selectedNodeId = issue.objectId
					elseif issueGraph.edges[issue.objectId] ~= nil then
						selectedEdgeId = issue.objectId
					end
				end
				activeMode = if issue.graphId ~= nil or issue.objectId ~= nil then "Graph" else "Stage"
			end
			setStatus(`Opened {issue.code}: {issue.message}`, issue.severity == "Error")
			renderAll()
			if cellColumnText ~= nil and cellRowText ~= nil then
				local column = tonumber(cellColumnText) or 1
				local row = tonumber(cellRowText) or 1
				gridScroll.CanvasPosition = Vector2.new(
					math.max((column - 1) * paintCellPixels - gridScroll.AbsoluteWindowSize.X / 2, 0),
					math.max((row - 1) * paintCellPixels - gridScroll.AbsoluteWindowSize.Y / 2, 0)
				)
				renderCanvas()
			end
		end)
		issueButton.LayoutOrder = order
		local issueStage = if issue.stageId ~= nil then project.stages[issue.stageId] else nil
		local address = if issueStage ~= nil then StageHierarchy.address(issueStage) else nil
		local location = if issueGroup.count > 1
			then `{issueGroup.count} items`
			else issue.objectId or "Level"
		local rowColor = if issue.severity == "Error" then COLORS.danger else COLORS.warning
		issueButton.Size = UDim2.new(1, -16, 0, 42)
		issueButton.Text = ""
		for _, column in
			{
				{
					if address ~= nil then `Level {address.levelNumber}` else "Project",
					0,
					0.1,
					rowColor,
				},
				{ issue.severity, 0.1, 0.1, rowColor },
				{
					`{issue.code}: {if issueGroup.count > 1
						then `{issueGroup.count} matching issues`
						else issue.message}`,
					0.2,
					0.55,
					COLORS.text,
				},
				{ location, 0.75, 0.15, COLORS.muted },
				{ "Open >", 0.9, 0.1, COLORS.accent },
			}
		do
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.new(column[2] :: number, 10, 0, 0),
				Size = UDim2.new(column[3] :: number, -14, 1, 0),
				Text = column[1] :: string,
				TextColor3 = column[4] :: Color3,
				TextSize = 10,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, issueButton)
		end
		local stroke = issueButton:FindFirstChild("Outline")
		if stroke ~= nil and stroke:IsA("UIStroke") then
			stroke.Color = if issue.severity == "Error"
				then Color3.fromRGB(117, 57, 63)
				else Color3.fromRGB(112, 87, 42)
		end
	end
	if #validationIssues == 0 then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Size = UDim2.new(1, -16, 0, 64),
			Text = "READY\nYour stage hierarchy and route graphs passed validation.",
			TextColor3 = COLORS.success,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, issueList)
	end
	issueList.CanvasSize = UDim2.fromOffset(0, math.max(#groupedIssues, 1) * 48 + 16)
end

local function exportBundle()
	ProjectStore.save()
	local result = ProjectStore.export()
	if result.bundle == nil then
		setStatus("Export blocked by validation errors.", true)
		activeMode = "Validate"
		renderAll()
		return
	end
	local model = Instance.new("Model")
	model.Name = "StagewrightBundle"
	local schema = require(script.Shared.StageSchema)
	local authoring = schema.encodeCanonical(ProjectStore.get())
	local runtime = schema.encodeCanonical(result.bundle)
	ProjectStore.writePayload(
		model,
		StagePayload.AUTHORING_VALUE_NAME,
		authoring,
		schema.checksum(ProjectStore.get())
	)
	ProjectStore.writePayload(model, StagePayload.RUNTIME_VALUE_NAME, runtime, schema.checksum(result.bundle))
	model:SetAttribute("SchemaVersion", result.bundle.schemaVersion)
	model:SetAttribute("Checksum", result.bundle.checksum)
	model.Parent = ServerStorage
	local previousSelection = Selection:Get()
	Selection:Set({ model })
	local success, saved = pcall(function()
		return plugin:PromptSaveSelectionAsync()
	end)
	Selection:Set(previousSelection)
	model:Destroy()
	if success and saved ~= false then
		local folder = ServerStorage:FindFirstChild("StagewrightProject")
		if folder ~= nil then
			folder:SetAttribute("ExportChecksum", result.bundle.checksum)
		end
		setStatus(`Export hash matched - {result.bundle.checksum}`)
	else
		setStatus("Export cancelled; project was not changed.")
	end
end

button(exportActions, "Refresh", 92, function()
	renderIssues()
	setStatus("Validation refreshed.")
end)
exportButton = button(exportActions, "Export bundle", 128, exportBundle)
button(exportActions, "Import selected", 128, function()
	local selected = Selection:Get()[1]
	local bundle = if selected ~= nil and selected.Name == StagePayload.AUTHORING_VALUE_NAME
		then selected.Parent
		else selected
	local encoded: string? = nil
	local readError: string? = "No bundle selected"
	if bundle ~= nil then
		encoded, readError = ProjectStore.readPayload(bundle, StagePayload.AUTHORING_VALUE_NAME)
	end
	if encoded == nil then
		setStatus("Select a StagewrightBundle model first.", true)
		if readError ~= nil and readError ~= `{StagePayload.AUTHORING_VALUE_NAME} is missing` then
			setStatus(`Import failed: {readError}`, true)
		end
		return
	end
	local ok, message = false, "Import failed"
	ProjectStore.mutate("Import Stagewright bundle", function()
		ok, message = ProjectStore.importPayload(encoded)
	end)
	if ok then
		project = ProjectStore.get()
		selectedStageId = project.startingStageId
		renderAll()
	end
	setStatus(message, not ok)
end)

function rerenderAll()
	for mode, page in contentByMode do
		page.Visible = mode == activeMode
		Toolbar.setNavigationSelected(modeButtons[mode], mode == activeMode)
	end
	local browsingLevels = activeMode == "Graph" or activeMode == "Stage"
	sidebarTitle.Text = if activeMode == "Paint"
		then if paintRuntime.mode == "Route" then "ROUTE TOOLS" else "LAYERS"
		elseif activeMode == "Validate" then "VALIDATION"
		else "STAGES & LEVELS"
	stageSearchField.Visible = browsingLevels
	stageList.Visible = browsingLevels
	stageList.Position = UDim2.fromOffset(0, 78)
	stageList.Size = UDim2.new(1, 0, 1, -130)
	stageActions.Visible = browsingLevels
	brushRail.Visible = activeMode == "Paint" and paintRuntime.mode == "Cells"
	paintRuntime.routeRail.Visible = activeMode == "Paint" and paintRuntime.mode == "Route"
	local validationRail = leftSidebar:FindFirstChild("ValidationRail")
	if validationRail ~= nil and validationRail:IsA("GuiObject") then
		validationRail.Visible = activeMode == "Validate"
	end
	local stageMoreMenu = leftSidebar:FindFirstChild("StageMoreMenu")
	if activeMode ~= "Stage" and stageMoreMenu ~= nil and stageMoreMenu:IsA("GuiObject") then
		stageMoreMenu.Visible = false
	end
	stageInspector.Visible = activeMode == "Stage"
	local paintInspectorView = rightSidebar:FindFirstChild("PaintInspector")
	if paintInspectorView ~= nil and paintInspectorView:IsA("GuiObject") then
		paintInspectorView.Visible = activeMode == "Paint" and paintRuntime.mode == "Cells"
	end
	paintRuntime.routeInspector.Visible = activeMode == "Paint" and paintRuntime.mode == "Route"
	graphSummary.Visible = false
	graphProperties.Visible = activeMode == "Graph"
	local graphMiniPreviewView = rightSidebar:FindFirstChild("GraphMiniPreview", true)
	if graphMiniPreviewView ~= nil and graphMiniPreviewView:IsA("GuiObject") then
		graphMiniPreviewView.Visible = false
	end
	graphList.Visible = false
	shell.inspectorTitle.Text = if activeMode == "Graph"
		then if selectedEdgeId ~= nil then "EDGE" elseif selectedNodeId ~= nil then "NODE" else "INSPECTOR"
		elseif activeMode == "Paint" then if paintRuntime.mode == "Route"
			then "ROUTE INSPECTOR"
			else "BRUSH INSPECTOR"
		elseif activeMode == "Stage" then "LEVEL PROPERTIES"
		else ""
	renderGraphTools()
	renderPaintChrome()
	renderIssues()
	local current = stage()
	if current ~= nil then
		local address = StageHierarchy.address(current)
		shell.title.Text = "Stagewright"
		status.Text = `Stage {address.stageNumber} / Level {address.levelNumber}        ⌄`
		status.TextColor3 = COLORS.text
		shell.footerStage.Text =
			`Stage {address.stageNumber} / Level {address.levelNumber}    Theme: {current.themeId}    Wave set: {current.waveSetId}`
		levelOverviewName.Text = "Level overview"
		stageInspectorTitle.Text = "LEVEL SETTINGS"
		stageLevelLabel.Text = `STAGE {address.stageNumber} / LEVEL {address.levelNumber}`
		local currentGraph = graph()
		local nodeCount = 0
		local edgeCount = 0
		if currentGraph ~= nil then
			for _ in currentGraph.nodes do
				nodeCount += 1
			end
			for _ in currentGraph.edges do
				edgeCount += 1
			end
		end
		levelOverviewMeta.Text =
			`{current.grid.columns} x {current.grid.rows} grid - {nodeCount} nodes - {edgeCount} edges - {string.sub(
				current.id,
				-8
			)}`
		local currentIssueCount = 0
		for _, issue in validationIssues do
			if issue.stageId == selectedStageId then
				currentIssueCount += 1
			end
		end
		levelHealthText.Text =
			`{current.grid.columns * current.grid.rows} cells - {nodeCount} nodes / {edgeCount} edges - {currentIssueCount} issue{if currentIssueCount
					== 1
				then ""
				else "s"}`
		levelHealthText.TextColor3 = if currentIssueCount > 0 then COLORS.warning else COLORS.success
		if activeMode == "Graph" then
			local previewCanvas = rightSidebar:FindFirstChild("GraphMiniPreviewCanvas", true)
			if previewCanvas ~= nil and previewCanvas:IsA("Frame") then
				for _, child in previewCanvas:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				local sampleColumns = math.min(current.grid.columns, 20)
				local sampleRows = math.min(current.grid.rows, 12)
				local available = previewCanvas.AbsoluteSize
				local sampleWidth = available.X / math.max(sampleColumns, 1)
				local sampleHeight = available.Y / math.max(sampleRows, 1)
				for sampleRow = 1, sampleRows do
					for sampleColumn = 1, sampleColumns do
						local column = math.clamp(
							math.floor((sampleColumn - 0.5) * current.grid.columns / sampleColumns) + 1,
							1,
							current.grid.columns
						)
						local row = math.clamp(
							math.floor((sampleRow - 0.5) * current.grid.rows / sampleRows) + 1,
							1,
							current.grid.rows
						)
						local authoredCell = current.grid.cells[`{column}:{row}`]
						local resolvedCell = authoredCell or current.grid.defaultCell
						local color =
							PaintAppearance.resolve(resolvedCell, authoredCell, current.grid.defaultCell)
						create("Frame", {
							BackgroundColor3 = color,
							BorderColor3 = COLORS.background,
							BorderSizePixel = 1,
							Position = UDim2.fromOffset(
								(sampleColumn - 1) * sampleWidth,
								(sampleRow - 1) * sampleHeight
							),
							Size = UDim2.fromOffset(math.ceil(sampleWidth), math.ceil(sampleHeight)),
						}, previewCanvas)
					end
				end
			end
		end
		if activeMode == "Stage" then
			local previewCanvas = stagePage:FindFirstChild("LevelPreviewCanvas", true)
			if previewCanvas ~= nil and previewCanvas:IsA("Frame") then
				for _, child in previewCanvas:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				local available = previewCanvas.AbsoluteSize
				local previewCell = math.max(
					math.min(
						(available.X - 4) / math.max(current.grid.columns, 1),
						(available.Y - 4) / math.max(current.grid.rows, 1)
					),
					2
				)
				local previewWidth = previewCell * current.grid.columns
				local previewHeight = previewCell * current.grid.rows
				local previewX = math.max((available.X - previewWidth) / 2, 0)
				local previewY = math.max((available.Y - previewHeight) / 2, 0)
				for row = 1, current.grid.rows do
					for column = 1, current.grid.columns do
						local key = `{column}:{row}`
						local authoredCell = current.grid.cells[key]
						local resolvedCell = authoredCell or current.grid.defaultCell
						local color, glyph =
							PaintAppearance.resolve(resolvedCell, authoredCell, current.grid.defaultCell)
						local previewCellFrame = create("Frame", {
							BackgroundColor3 = color,
							BorderColor3 = Color3.fromRGB(28, 34, 41),
							BorderSizePixel = if previewCell >= 5 then 1 else 0,
							Position = UDim2.fromOffset(
								previewX + (column - 1) * previewCell,
								previewY + (row - 1) * previewCell
							),
							Size = UDim2.fromOffset(math.ceil(previewCell), math.ceil(previewCell)),
							ZIndex = 4,
						}, previewCanvas) :: Frame
						if glyph ~= "" and previewCell >= 6 then
							create("TextLabel", {
								BackgroundTransparency = 1,
								Font = Enum.Font.BuilderSansBold,
								Size = UDim2.fromScale(1, 1),
								Text = glyph,
								TextColor3 = COLORS.text,
								TextSize = math.clamp(previewCell * 0.7, 7, 11),
								ZIndex = 5,
							}, previewCellFrame)
						end
					end
				end
			end
			local allowedCells = 0
			for row = 1, current.grid.rows do
				for column = 1, current.grid.columns do
					local override = current.grid.cells[`{column}:{row}`]
					local policy = if override ~= nil and override.buildPolicy ~= nil
						then override.buildPolicy
						else current.grid.defaultCell.buildPolicy
					if policy ~= "Blocked" then
						allowedCells += 1
					end
				end
			end
			local totalCells = math.max(current.grid.columns * current.grid.rows, 1)
			local routeMetric = stagePage:FindFirstChild("RouteMetric", true)
			local buildMetric = stagePage:FindFirstChild("BuildMetric", true)
			local issueMetric = stagePage:FindFirstChild("IssueMetric", true)
			if routeMetric ~= nil and routeMetric:IsA("TextLabel") then
				routeMetric.Text = `{nodeCount} / {edgeCount}`
			end
			if buildMetric ~= nil and buildMetric:IsA("TextLabel") then
				buildMetric.Text = `{math.round(allowedCells / totalCells * 100)}%`
			end
			if issueMetric ~= nil and issueMetric:IsA("TextLabel") then
				issueMetric.Text = tostring(currentIssueCount)
				issueMetric.TextColor3 = if currentIssueCount > 0 then COLORS.danger else COLORS.success
			end
		end
		if not stageNameField:IsFocused() then
			stageNameField.Text = current.name
		end
		if not columnsField:IsFocused() then
			columnsField.Text = tostring(current.grid.columns)
		end
		if not rowsField:IsFocused() then
			rowsField.Text = tostring(current.grid.rows)
		end
		if not cellSizeField:IsFocused() then
			cellSizeField.Text = tostring(current.grid.cellSize)
		end
		if not waveSetField:IsFocused() then
			waveSetField.Text = current.waveSetId
		end
		if not themeField:IsFocused() then
			themeField.Text = current.themeId
		end
	end
	local errorCount = 0
	local warningCount = 0
	for _, issue in validationIssues do
		if issue.stageId ~= selectedStageId then
			continue
		end
		if issue.severity == "Error" then
			errorCount += 1
		else
			warningCount += 1
		end
	end
	headerValidation.Text = if errorCount == 0 and warningCount == 0
		then "Ready to export"
		else `{errorCount} {if errorCount == 1 then "error" else "errors"} {utf8.char(183)} {warningCount} {if warningCount
				== 1
			then "warning"
			else "warnings"}`
	headerValidation.TextColor3 = if errorCount > 0
		then COLORS.danger
		elseif warningCount > 0 then COLORS.warning
		else COLORS.success
	headerValidation.BackgroundColor3 = if errorCount > 0
		then Color3.fromRGB(43, 24, 29)
		elseif warningCount > 0 then Color3.fromRGB(42, 34, 18)
		else Color3.fromRGB(18, 49, 35)
	local validationOutline = headerValidation:FindFirstChild("Outline")
		or headerValidation:FindFirstChildOfClass("UIStroke")
	if validationOutline ~= nil and validationOutline:IsA("UIStroke") then
		validationOutline.Color = if errorCount > 0
			then Color3.fromRGB(111, 53, 63)
			elseif warningCount > 0 then Color3.fromRGB(112, 82, 30)
			else Color3.fromRGB(35, 105, 68)
	end
	Toolbar.addVectorIcon(
		headerValidation,
		if errorCount == 0 and warningCount == 0 then "check" else "warning",
		if errorCount > 0 then COLORS.danger elseif warningCount > 0 then COLORS.warning else COLORS.success,
		12
	)
	flowRuntime.refreshStageSelector()
	renderCanvas()
	renderStageList()
	renderGraphList()
	if activeMode == "Graph" then
		flowRuntime.render()
	end
	renderIslandOutlines()
	applyResponsiveShell()
	if activeMode == "Graph" or activeMode == "Paint" then
		rebuildPreview()
	else
		clearPreview()
	end
end
renderAll = rerenderAll
headerValidation.Activated:Connect(function()
	activeMode = "Validate"
	renderAll()
end)

UserInputService.InputBegan:Connect(function(input)
	if
		activeMode ~= "Paint"
		or not widget.Enabled
		or input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if paintRuntime.mode == "Route" then
		paintRuntime.beginRouteInteraction(position)
		return
	end
	local column, row = paintRuntime.cellAt(position)
	if column ~= nil and row ~= nil then
		paintRuntime.beginInteraction(column, row)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if
		activeMode ~= "Paint"
		or not widget.Enabled
		or input.UserInputType ~= Enum.UserInputType.MouseMovement
	then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if paintRuntime.mode == "Route" then
		local routeDragActive = paintRuntime.routeDraggingNodeId ~= nil
			or paintRuntime.routeDraggingEdgeId ~= nil
			or paintRuntime.routeDraggingHandle ~= nil
		if routeDragActive and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			if paintRuntime.routeDragMoved then
				ProjectStore.finish(true)
			end
			paintRuntime.routeDraggingNodeId = nil
			paintRuntime.routeDraggingEdgeId = nil
			paintRuntime.routeDraggingHandle = nil
			paintRuntime.routeDragStartScreen = nil
			paintRuntime.routeDragMoved = false
			setStatus("Route selection released. Workspace was not changed.")
			renderAll()
			return
		end
		local column, row = paintRuntime.cellAt(position)
		if column ~= nil and row ~= nil then
			local preview = ProjectStore.preview(selectedStageId)
			local routeAffected = preview ~= nil and preview.routeNoBuildMask[`{column}:{row}`] == true
			showHoveredCell(column, row, routeAffected)
		else
			showHoveredCell(nil, nil)
		end
		if
			routeDragActive
			and paintRuntime.routeDragStartScreen ~= nil
			and (position - paintRuntime.routeDragStartScreen).Magnitude < 4
		then
			return
		end
		if routeDragActive and not paintRuntime.routeDragMoved then
			paintRuntime.routeDragMoved = true
			ProjectStore.begin(
				if paintRuntime.routeDraggingNodeId ~= nil
					then "Move Stagewright route node"
					else "Shape Stagewright route spline"
			)
		end
		if paintRuntime.routeDraggingEdgeId ~= nil and paintRuntime.routeDraggingHandle ~= nil then
			local localPosition = paintRuntime.localPositionAt(position)
			local currentGraph = graph()
			local edge = if currentGraph ~= nil
				then currentGraph.edges[paintRuntime.routeDraggingEdgeId]
				else nil
			local anchorNode = if currentGraph ~= nil and edge ~= nil
				then currentGraph.nodes[if paintRuntime.routeDraggingHandle == "Out"
					then edge.fromNodeId
					else edge.toNodeId]
				else nil
			if localPosition ~= nil and edge ~= nil and anchorNode ~= nil then
				local offset = if paintRuntime.routeDraggingHandle == "Out"
					then edge.outHandleOffset
					else edge.inHandleOffset
				offset.x = localPosition.x - anchorNode.position.x
				offset.z = localPosition.z - anchorNode.position.z
				renderCanvas()
			end
		elseif paintRuntime.routeDraggingNodeId ~= nil then
			local localPosition = paintRuntime.localPositionAt(position)
			local currentGraph = graph()
			local node = if currentGraph ~= nil
				then currentGraph.nodes[paintRuntime.routeDraggingNodeId]
				else nil
			if localPosition ~= nil and node ~= nil then
				node.position = {
					x = localPosition.x,
					y = node.position.y,
					z = localPosition.z,
				}
				renderCanvas()
			end
		end
		return
	end
	local column, row = paintRuntime.cellAt(position)
	if column == nil or row == nil then
		showHoveredCell(nil, nil)
		return
	end
	local preview = ProjectStore.preview(selectedStageId)
	local routeAffected = preview ~= nil and preview.routeNoBuildMask[`{column}:{row}`] == true
	showHoveredCell(column, row, routeAffected)
	if painting and (activePaintTool == "Pencil" or activePaintTool == "Erase") and paintModifierDown() then
		paintCell(column, row)
		renderCanvas()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		and (
			paintRuntime.routeDraggingNodeId ~= nil
			or paintRuntime.routeDraggingEdgeId ~= nil
			or paintRuntime.routeDraggingHandle ~= nil
		)
	then
		paintRuntime.routeDraggingNodeId = nil
		paintRuntime.routeDraggingEdgeId = nil
		paintRuntime.routeDraggingHandle = nil
		paintRuntime.routeDragStartScreen = nil
		if paintRuntime.routeDragMoved then
			ProjectStore.finish(true)
			setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
		else
			setStatus("Route item selected. Hold and drag to move it.")
		end
		paintRuntime.routeDragMoved = false
		renderAll()
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and painting then
		if activePaintTool == "Rect" then
			local startColumn = gridCanvas:GetAttribute("RectangleColumn")
			local startRow = gridCanvas:GetAttribute("RectangleRow")
			local endColumn = gridCanvas:GetAttribute("HoverColumn")
			local endRow = gridCanvas:GetAttribute("HoverRow")
			if
				type(startColumn) == "number"
				and type(startRow) == "number"
				and type(endColumn) == "number"
				and type(endRow) == "number"
			then
				local previousBrushSize = paintBrushSize
				paintBrushSize = 1
				for row = math.min(startRow, endRow), math.max(startRow, endRow) do
					for column = math.min(startColumn, endColumn), math.max(startColumn, endColumn) do
						paintCell(column, row)
					end
				end
				paintBrushSize = previousBrushSize
			end
			gridCanvas:SetAttribute("RectangleColumn", nil)
			gridCanvas:SetAttribute("RectangleRow", nil)
			renderCanvas()
		end
		painting = false
		ProjectStore.finish(true)
		setStatus(`Working changes - {ProjectStore.workingChecksum()}`)
	end
end)

do
	local action = plugin:CreatePluginAction(
		"StagewrightValidate",
		"Validate Stagewright",
		"Validate the current Stagewright project",
		"",
		true
	)
	action.Triggered:Connect(function()
		activeMode = "Validate"
		widget.Enabled = true
		renderAll()
	end)
end
do
	local action = plugin:CreatePluginAction(
		"StagewrightFocus",
		"Focus Stagewright",
		"Open the Stagewright editor",
		"",
		true
	)
	action.Triggered:Connect(function()
		widget.Enabled = true
	end)
end
do
	local action = plugin:CreatePluginAction(
		"StagewrightFocusAdminArea",
		"Focus Stagewright Admin Area",
		"Focus the separate Stagewright authoring platform below the map",
		"",
		true
	)
	action.Triggered:Connect(function()
		AuthoringArea.focus()
	end)
end
do
	local action = plugin:CreatePluginAction(
		"StagewrightToggleIslandOutlines",
		"Toggle Island Footprints",
		"Show or hide all six playable island footprints in Edit mode",
		"",
		true
	)
	action.Triggered:Connect(function()
		islandOutlinesEnabled = not islandOutlinesEnabled
		islandGuideButton.Text = "Guides"
		renderIslandOutlines()
	end)
end
do
	local action = plugin:CreatePluginAction(
		"StagewrightDuplicateStage",
		"Create Stagewright Level",
		"Copy the selected level into its stage",
		"",
		true
	)
	action.Triggered:Connect(function()
		mutate("Create Stagewright level", function()
			selectedStageId = ProjectStore.createLevel(selectedStageId)
		end)
		renderAll()
	end)
end
do
	local action = plugin:CreatePluginAction(
		"StagewrightCreateStage",
		"Create Stagewright Stage",
		"Create a new stage group with Level 1",
		"",
		true
	)
	action.Triggered:Connect(function()
		mutate("Create Stagewright stage group", function()
			selectedStageId = ProjectStore.createStage(nil)
		end)
		renderAll()
	end)
end

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
	if widget.Enabled then
		rerenderAll()
	end
end)
Selection.SelectionChanged:Connect(function()
	if not widget.Enabled or (activeMode ~= "Graph" and activeMode ~= "Paint") then
		return
	end
	local selected = Selection:Get()[1]
	if selected == nil then
		return
	end
	local nodeId = selected:GetAttribute("StagewrightNodeId")
	local edgeId = selected:GetAttribute("StagewrightEdgeId")
	if type(nodeId) == "string" and nodeId ~= selectedNodeId then
		selectedNodeId = nodeId
		selectedEdgeId = nil
		tracedEdgeIds = {}
		renderAll()
	elseif type(edgeId) == "string" and edgeId ~= selectedEdgeId then
		selectedEdgeId = edgeId
		selectedNodeId = nil
		tracedEdgeIds = {}
		renderAll()
	end
end)
plugin.Unloading:Connect(function()
	ProjectStore.cleanup()
	routeOverview:destroy()
	if flowRuntime.view ~= nil then
		flowRuntime.view:destroy()
	end
	clearPreview()
	AuthoringArea.clearIslandOutlines()
end)
ProjectStore.observe(function()
	project = ProjectStore.get()
	stageIds = ProjectStore.stageIds()
	if project.stages[selectedStageId] == nil then
		selectedStageId = project.startingStageId or stageIds[1]
	end
	setStatus("Undo/redo synchronized from the saved working copy.")
	rerenderAll()
end)

setStatus(`Working changes - {ProjectStore.save()}`)
rerenderAll()

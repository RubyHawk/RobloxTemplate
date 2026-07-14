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
local ProjectStore = require(script.ProjectStore)
local RouteOverview = require(script.RouteOverview)
local StageHierarchy = require(script.Shared.StageHierarchy)
local StageLanes = require(script.Shared.StageLanes)
local StagePayload = require(script.Shared.StagePayload)
local StageTrace = require(script.Shared.StageTrace)

local PLUGIN_NAME = "Stagewright"
local PREVIEW_TAG = "StagewrightTransientPreview"
local paintCellPixels = 28
local COLORS = {
	background = Color3.fromRGB(15, 17, 21),
	panel = Color3.fromRGB(22, 25, 31),
	surface = Color3.fromRGB(27, 31, 38),
	field = Color3.fromRGB(32, 37, 45),
	hover = Color3.fromRGB(40, 47, 58),
	border = Color3.fromRGB(55, 64, 77),
	borderStrong = Color3.fromRGB(76, 89, 106),
	text = Color3.fromRGB(239, 242, 247),
	muted = Color3.fromRGB(157, 168, 184),
	accent = Color3.fromRGB(77, 139, 230),
	accentMuted = Color3.fromRGB(38, 67, 105),
	allowed = Color3.fromRGB(91, 76, 157),
	traversal = Color3.fromRGB(47, 105, 84),
	success = Color3.fromRGB(87, 196, 128),
	warning = Color3.fromRGB(238, 181, 72),
	danger = Color3.fromRGB(239, 103, 112),
	ground = Color3.fromRGB(75, 132, 91),
	void = Color3.fromRGB(28, 30, 35),
	blocked = Color3.fromRGB(157, 76, 76),
	spawn = Color3.fromRGB(116, 96, 181),
	goal = Color3.fromRGB(195, 123, 65),
	auto = Color3.fromRGB(60, 145, 166),
}

type Mode = "Paint" | "Graph" | "Stage" | "Validate"
type GraphToolMode = "Build" | "Rules" | "Test"
type Brush = {
	id: string,
	label: string,
	category: string,
	help: string,
	apply: (cell: any) -> (),
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
local paintBrushSize = 1
local predicateKindIndex = 1
local painting = false
local paintedKeys: { [string]: boolean } = {}
local previewFolder: Folder? = nil
local previewMoveRevision = 0
local pendingConfirmation: { id: string, expires: number }? = nil
local islandOutlinesEnabled = true
local validationIssues: { any } = {}

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
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, true, 1_220, 820, 780, 560)
)
widget.Title = "Stagewright · Tower Defense Stage Editor"

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local root = create("Frame", {
	Name = "Root",
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
}, widget) :: Frame
local header = create("Frame", {
	Name = "ToolHeader",
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 78),
}, root) :: Frame
create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = COLORS.border,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 1),
}, header)
local title = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(16, 9),
	Size = UDim2.fromOffset(276, 24),
	Text = "Stagewright",
	TextColor3 = COLORS.text,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header) :: TextLabel
local status = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(16, 35),
	Size = UDim2.fromOffset(276, 18),
	Text = "Loading your versioned stage project…",
	TextColor3 = COLORS.muted,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header) :: TextLabel
local modes = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(300, 20),
	Size = UDim2.fromOffset(430, 36),
}, header) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 0),
	CellSize = UDim2.new(0.25, -5, 1, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, modes)
local body = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 78),
	Size = UDim2.new(1, 0, 1, -112),
}, root) :: Frame
local footer = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 1, -34),
	Size = UDim2.new(1, 0, 0, 34),
}, root) :: Frame
local footerStage = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(0.65, -14, 1, 0),
	Text = "Stage 1 · Level 1",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, footer) :: TextLabel
create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(180, 34),
	Text = "Stagewright 2.3 · Edit mode only",
	TextColor3 = COLORS.muted,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Right,
}, footer)
local headerValidation = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	AutoButtonColor = false,
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.new(1, -14, 0, 16),
	Size = UDim2.fromOffset(176, 42),
	Text = "Checking project…",
	TextColor3 = COLORS.muted,
	TextSize = 11,
}, header) :: TextButton
create("UICorner", { CornerRadius = UDim.new(0, 7) }, headerValidation)
create("UIStroke", { Color = COLORS.border, Thickness = 1 }, headerValidation)

local leftSidebar = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(0, 242, 1, 0),
}, body) :: Frame
local workspace = create("Frame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(250, 0),
	Size = UDim2.new(1, -550, 1, 0),
}, body) :: Frame
local rightSidebar = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 292, 1, 0),
}, body) :: Frame
local sidebarTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 24),
	Text = "STAGES & LEVELS",
	TextColor3 = COLORS.text,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
}, leftSidebar) :: TextLabel
local inspectorTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 24),
	Text = "INSPECTOR",
	TextColor3 = COLORS.text,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
}, rightSidebar) :: TextLabel

local function applyResponsiveShell()
	local width = root.AbsoluteSize.X
	local wantsInspector = activeMode == "Graph" or activeMode == "Stage"
	if width >= 1_050 then
		leftSidebar.Visible = true
		rightSidebar.Visible = wantsInspector
		leftSidebar.Size = UDim2.new(0, 242, 1, 0)
		workspace.Position = UDim2.fromOffset(250, 0)
		workspace.Size = UDim2.new(1, if wantsInspector then -550 else -250, 1, 0)
		title.Visible = true
		status.Visible = true
		modes.Position = UDim2.fromOffset(300, 20)
		modes.Size = UDim2.fromOffset(430, 36)
		headerValidation.Visible = true
	elseif width >= 760 then
		leftSidebar.Visible = true
		rightSidebar.Visible = false
		leftSidebar.Size = UDim2.new(0, 200, 1, 0)
		workspace.Position = UDim2.fromOffset(208, 0)
		workspace.Size = UDim2.new(1, -208, 1, 0)
		title.Visible = true
		status.Visible = true
		modes.Position = UDim2.fromOffset(218, 20)
		modes.Size = UDim2.new(1, -232, 0, 36)
		headerValidation.Visible = false
	else
		leftSidebar.Visible = false
		rightSidebar.Visible = false
		workspace.Position = UDim2.fromOffset(0, 0)
		workspace.Size = UDim2.fromScale(1, 1)
		title.Visible = false
		status.Visible = false
		modes.Position = UDim2.fromOffset(12, 20)
		modes.Size = UDim2.new(1, -24, 0, 36)
		headerValidation.Visible = false
	end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveShell)

local function button(parent: Instance, text: string, width: number?, callback: () -> ()): TextButton
	local result = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		LayoutOrder = #parent:GetChildren() + 1,
		Size = UDim2.fromOffset(width or 110, 30),
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, result)
	local stroke = create("UIStroke", {
		Name = "Outline",
		Color = COLORS.border,
		Thickness = 1,
	}, result) :: UIStroke
	result.MouseEnter:Connect(function()
		if result.Active and result.BackgroundColor3 == COLORS.field then
			result.BackgroundColor3 = COLORS.hover
			stroke.Color = COLORS.borderStrong
		end
	end)
	result.MouseLeave:Connect(function()
		if result.Active and result.BackgroundColor3 == COLORS.hover then
			result.BackgroundColor3 = COLORS.field
			stroke.Color = COLORS.border
		end
	end)
	result.Activated:Connect(callback)
	return result
end

local function setButtonSelected(result: TextButton, selected: boolean)
	result.BackgroundColor3 = if selected then COLORS.accent else COLORS.field
	local stroke = result:FindFirstChild("Outline")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = if selected then Color3.fromRGB(123, 174, 245) else COLORS.border
	end
end

local function sectionLabel(parent: Instance, text: string, order: number?): TextLabel
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		LayoutOrder = order or 0,
		Size = UDim2.new(1, -8, 0, 22),
		Text = string.upper(text),
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
end

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

local brushes: { Brush } = {
	{
		id = "reset_cell",
		label = "Reset to default",
		category = "Quick tools",
		help = "Remove authored overrides so the cell inherits the level default.",
		apply = function(cell)
			for key in cell do
				cell[key] = nil
			end
		end,
	},
	{
		id = "terrain_ground",
		label = "Ground",
		category = "Terrain",
		help = "Paint normal playable ground.",
		apply = function(cell)
			cell.terrainId = "ground"
		end,
	},
	{
		id = "terrain_void",
		label = "Void",
		category = "Terrain",
		help = "Paint empty terrain outside the playable surface.",
		apply = function(cell)
			cell.terrainId = "void"
		end,
	},
	{
		id = "build_allowed",
		label = "Build allowed",
		category = "Build policy",
		help = "Allow players to place towers in this cell.",
		apply = function(cell)
			cell.buildPolicy = "Allowed"
		end,
	},
	{
		id = "build_blocked",
		label = "Build blocked",
		category = "Build policy",
		help = "Prevent tower placement without changing terrain.",
		apply = function(cell)
			cell.buildPolicy = "Blocked"
		end,
	},
	{
		id = "build_auto",
		label = "Auto-place only",
		category = "Build policy",
		help = "Reserve this cell for automatic placement systems.",
		apply = function(cell)
			cell.buildPolicy = "AutoOnly"
		end,
	},
	{
		id = "traversal_allowed",
		label = "Traversal allowed",
		category = "Enemy traversal",
		help = "Allow route corridors to cross this cell.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Allowed"
		end,
	},
	{
		id = "traversal_blocked",
		label = "Traversal blocked",
		category = "Enemy traversal",
		help = "Prevent route corridors from crossing this cell.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Blocked"
		end,
	},
}
for _, role in
	{
		"EnemySpawn",
		"EnemyGoal",
		"AutoPlace",
		"Hazard",
		"Reward",
		"Trigger",
		"StageTransition",
		"DecorationAnchor",
	}
do
	table.insert(brushes, {
		id = `role_{role}`,
		label = string.gsub(role, "(%l)(%u)", "%1 %2"),
		category = "Cell roles",
		help = `Toggle the {string.gsub(role, "(%l)(%u)", "%1 %2")} role on painted cells.`,
		apply = function(cell)
			cell.roles = cell.roles or {}
			cell.roles[role] = not cell.roles[role]
			if role == "EnemySpawn" or role == "EnemyGoal" then
				cell.buildPolicy = "Blocked"
			elseif role == "AutoPlace" and cell.buildPolicy == "Blocked" then
				cell.buildPolicy = "Allowed"
			end
		end,
	})
end

local function activeBrush(): Brush
	for _, brush in brushes do
		if brush.id == activeBrushId then
			return brush
		end
	end
	return brushes[1]
end

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

local function rebuildPreview()
	clearPreview()
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local export = ProjectStore.export()
	if export.bundle == nil then
		return
	end
	local bakedStage = export.bundle.stages[selectedStageId]
	local bakedGraph = if bakedStage ~= nil then bakedStage.pathGraphs[currentGraph.id] else nil
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
					setStatus(`Working changes · {ProjectStore.workingChecksum()}`)
					rebuildPreview()
				end
			end)
		end)
	end
	for nodeId, node in currentGraph.nodes do
		local part = Instance.new("Part")
		part.Name = `Node_{node.name}`
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.8, 1.8, 1.8)
		part.Anchored = true
		part.CanCollide = false
		part.Color = if node.kind == "Spawn"
			then COLORS.spawn
			elseif node.kind == "Goal" then COLORS.goal
			else COLORS.accent
		part.CFrame = origin * CFrame.new(node.position.x, node.position.y, node.position.z)
		part:SetAttribute("StagewrightNodeId", nodeId)
		part.Parent = folder
		bindPosition(part, function(localPosition)
			node.position = { x = localPosition.X, y = localPosition.Y, z = localPosition.Z }
		end)
	end
	for edgeId, edge in bakedGraph.edges do
		local laneProfile = bakedGraph.laneProfiles[edge.laneProfileId]
		local laneOffsets = if laneProfile ~= nil and #laneProfile.offsets > 0
			then laneProfile.offsets
			else { 0 }
		for laneIndex, laneOffset in laneOffsets do
			for index = 2, #edge.samples do
				local a = previewPoint(edge.samples[index - 1], laneOffset)
				local b = previewPoint(edge.samples[index], laneOffset)
				local segment = Instance.new("Part")
				segment.Name = `Edge_{edgeId}_Lane_{laneIndex}_{index}`
				segment.Anchored = true
				segment.CanCollide = false
				segment.CanQuery = false
				segment.CanTouch = false
				segment.Color = if selectedEdgeId == edgeId
					then Color3.fromRGB(255, 202, 72)
					elseif tracedEdgeIds[edgeId] then Color3.fromRGB(96, 220, 132)
					else COLORS.accent
				segment.Material = Enum.Material.Neon
				segment.Size = Vector3.new(0.18, 0.18, (b - a).Magnitude)
				segment.CFrame = CFrame.lookAt((a + b) * 0.5, b)
				segment.Parent = folder
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
				handle.Color = Color3.fromRGB(255, 202, 72)
				local position = {
					x = handleData.node.position.x + handleData.offset.x,
					y = handleData.node.position.y + handleData.offset.y,
					z = handleData.node.position.z + handleData.offset.z,
				}
				handle.CFrame = origin * CFrame.new(position.x, position.y, position.z)
				handle.Parent = folder
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

local MODE_LABELS: { [Mode]: string } = {
	Paint = "✎  Paint",
	Graph = "⌁  Flow",
	Stage = "▦  Levels",
	Validate = "✓  Check",
}

for order, modeName in { "Graph", "Paint", "Stage", "Validate" } :: { Mode } do
	local mode = modeName :: Mode
	modeButtons[mode] = button(modes, MODE_LABELS[mode], 88, function()
		activeMode = mode
		rerenderAll()
	end)
	modeButtons[mode].LayoutOrder = order
	local page = create("Frame", {
		Name = `{mode}Page`,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, workspace) :: Frame
	contentByMode[mode] = page
end

-- Paint page: a layer-aware brush rail and a virtualized grid canvas.
local paintPage = contentByMode.Paint
local paintToolbar = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 58),
}, paintPage) :: Frame
local paintBrushTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(0.5, -14, 0, 20),
	Text = "Build blocked",
	TextColor3 = COLORS.text,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, paintToolbar) :: TextLabel
local paintHint = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(14, 29),
	Size = UDim2.new(1, -250, 0, 18),
	Text = "Click to inspect. Hold Shift and drag to paint one undo step.",
	TextColor3 = COLORS.muted,
	TextSize = 11,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, paintToolbar) :: TextLabel
local paintHover = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansMedium,
	Position = UDim2.new(1, -12, 0, 13),
	Size = UDim2.fromOffset(116, 28),
	Text = "Cell —",
	TextColor3 = COLORS.muted,
	TextSize = 11,
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
			sectionLabel(brushRail, brush.category, brushLayoutOrder)
			previousBrushCategory = brush.category
		end
		brushLayoutOrder += 1
		local glyph = if brush.id == "reset_cell"
			then "↺"
			elseif brush.id == "terrain_ground" then "■"
			elseif brush.id == "terrain_void" then "□"
			elseif brush.id == "build_allowed" then "✓"
			elseif brush.id == "build_blocked" then "×"
			elseif brush.id == "build_auto" then "A"
			elseif brush.id == "traversal_allowed" then "→"
			elseif brush.id == "traversal_blocked" then "⊘"
			elseif brush.id == "role_spawn" then "S"
			elseif brush.id == "role_goal" then "G"
			elseif brush.id == "role_hazard" then "H"
			elseif brush.id == "role_reward" then "★"
			elseif brush.id == "role_trigger" then "⚡"
			else "◆"
		local brushButton = button(brushRail, `{glyph}   {brush.label}`, 156, function()
			activeBrushId = brush.id
			renderPaintChrome()
			renderCanvas()
		end)
		brushButton.LayoutOrder = brushLayoutOrder
		brushButton.Size = UDim2.new(1, -4, 0, 30)
		brushButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 10) }, brushButton)
		brushButtons[brush.id] = brushButton
	end
end
function renderPaintChrome()
	for brushId, brushButton in brushButtons do
		setButtonSelected(brushButton, brushId == activeBrushId)
	end
	local brush = activeBrush()
	paintBrushTitle.Text = brush.label
	paintHint.Text = `Shift + drag to paint  ·  {brush.help}`
	paintSizeButton.Text = `Brush {paintBrushSize} × {paintBrushSize}`
	paintZoomLabel.Text = `{math.round(paintCellPixels / 28 * 100)}%`
end
local gridScroll = create("ScrollingFrame", {
	BackgroundColor3 = Color3.fromRGB(12, 13, 15),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 62),
	ScrollBarThickness = 8,
	ScrollingDirection = Enum.ScrollingDirection.XY,
	Size = UDim2.new(1, 0, 1, -62),
}, paintPage) :: ScrollingFrame
local gridCanvas = create("Frame", { BackgroundTransparency = 1 }, gridScroll) :: Frame
local cellPool: { TextButton } = {}

paintSizeButton = button(paintToolbar, "Brush 1 × 1", 92, function()
	paintBrushSize = if paintBrushSize == 1 then 3 elseif paintBrushSize == 3 then 5 else 1
	paintSizeButton.Text = `Brush {paintBrushSize} × {paintBrushSize}`
end)
paintSizeButton.AnchorPoint = Vector2.new(1, 0)
paintSizeButton.Position = UDim2.new(1, -136, 0, 12)

paintZoomLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansMedium,
	Position = UDim2.new(1, -326, 0, 12),
	Size = UDim2.fromOffset(54, 30),
	Text = "100%",
	TextColor3 = COLORS.text,
	TextSize = 11,
}, paintToolbar) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 6) }, paintZoomLabel)
do
	local zoomOut = button(paintToolbar, "−", 30, function()
		paintCellPixels = math.max(paintCellPixels - 2, 10)
		renderPaintChrome()
		renderCanvas()
	end)
	zoomOut.AnchorPoint = Vector2.new(1, 0)
	zoomOut.Position = UDim2.new(1, -384, 0, 12)
	local zoomIn = button(paintToolbar, "+", 30, function()
		paintCellPixels = math.min(paintCellPixels + 2, 40)
		renderPaintChrome()
		renderCanvas()
	end)
	zoomIn.AnchorPoint = Vector2.new(1, 0)
	zoomIn.Position = UDim2.new(1, -292, 0, 12)
	local fit = button(paintToolbar, "Fit", 42, function()
		local current = stage()
		if current ~= nil then
			paintCellPixels = math.clamp(
				math.floor(
					math.min(
						(gridScroll.AbsoluteWindowSize.X - 20) / current.grid.columns,
						(gridScroll.AbsoluteWindowSize.Y - 20) / current.grid.rows
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
	fit.Position = UDim2.new(1, -238, 0, 12)
end

local function paintModifierDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function cellAtScreenPoint(screenPoint: Vector2): (number?, number?)
	local origin = gridScroll.AbsolutePosition
	local window = gridScroll.AbsoluteWindowSize
	local relative = screenPoint - origin
	if relative.X < 0 or relative.Y < 0 or relative.X >= window.X or relative.Y >= window.Y then
		return nil, nil
	end
	local canvasPoint = screenPoint - gridCanvas.AbsolutePosition
	local column = math.floor(canvasPoint.X / paintCellPixels) + 1
	local row = math.floor(canvasPoint.Y / paintCellPixels) + 1
	local current = stage()
	if
		current == nil
		or column < 1
		or row < 1
		or column > current.grid.columns
		or row > current.grid.rows
	then
		return nil, nil
	end
	return column, row
end

local function showHoveredCell(column: number?, row: number?)
	if column == nil or row == nil then
		paintHover.Text = "Cell —"
		paintHover.TextColor3 = COLORS.muted
		return
	end
	paintHover.Text = `Cell {column}, {row}`
	paintHover.TextColor3 = COLORS.text
end

local function cellVisual(cell: any): (Color3, string)
	local roles = cell.roles or {}
	local category = activeBrush().category
	if category == "Terrain" then
		if cell.terrainId == "void" then
			return COLORS.void, ""
		end
		return COLORS.ground, ""
	elseif category == "Build policy" then
		if cell.buildPolicy == "Blocked" then
			return COLORS.blocked, "×"
		elseif cell.buildPolicy == "AutoOnly" then
			return COLORS.auto, "A"
		end
		return COLORS.allowed, "✓"
	elseif category == "Enemy traversal" then
		if cell.enemyTraversalPolicy == "Blocked" then
			return COLORS.blocked, "×"
		end
		return COLORS.traversal, "✓"
	end
	if roles.EnemySpawn then
		return COLORS.spawn, "S"
	elseif roles.EnemyGoal then
		return COLORS.goal, "G"
	elseif roles.AutoPlace then
		return COLORS.auto, "A"
	elseif roles.Hazard then
		return COLORS.blocked, "H"
	elseif roles.Reward then
		return COLORS.warning, "R"
	elseif roles.Trigger then
		return COLORS.accent, "T"
	elseif roles.StageTransition then
		return COLORS.accentMuted, "→"
	elseif roles.DecorationAnchor then
		return COLORS.surface, "D"
	elseif cell.buildPolicy == "Blocked" then
		return COLORS.blocked, "×"
	elseif cell.terrainId == "void" then
		return COLORS.void, ""
	end
	return COLORS.ground, ""
end

local function paintCell(column: number, row: number)
	local current = stage()
	local radius = math.floor(paintBrushSize / 2)
	local brush = activeBrush()
	for targetRow = math.max(row - radius, 1), math.min(row + radius, current.grid.rows) do
		for targetColumn = math.max(column - radius, 1), math.min(column + radius, current.grid.columns) do
			local key = `{targetColumn}:{targetRow}`
			if not paintedKeys[key] then
				paintedKeys[key] = true
				local cell = current.grid.cells[key]
				if cell == nil then
					cell = {}
					current.grid.cells[key] = cell
				end
				brush.apply(cell)
				if next(cell) == nil then
					current.grid.cells[key] = nil
				end
			end
		end
	end
end

function renderCanvas()
	local current = stage()
	if current == nil then
		return
	end
	local grid = current.grid
	local width = grid.columns * paintCellPixels
	local height = grid.rows * paintCellPixels
	local offsetX = math.max(math.floor((gridScroll.AbsoluteWindowSize.X - width) / 2), 0)
	local offsetY = math.max(math.floor((gridScroll.AbsoluteWindowSize.Y - height) / 2), 0)
	gridCanvas.Position = UDim2.fromOffset(offsetX, offsetY)
	gridCanvas.Size = UDim2.fromOffset(width, height)
	gridScroll.CanvasSize = UDim2.fromOffset(
		math.max(width + offsetX * 2, gridScroll.AbsoluteWindowSize.X),
		math.max(height + offsetY * 2, gridScroll.AbsoluteWindowSize.Y)
	)
	local firstColumn =
		math.max(math.floor(math.max(gridScroll.CanvasPosition.X - offsetX, 0) / paintCellPixels) + 1, 1)
	local firstRow =
		math.max(math.floor(math.max(gridScroll.CanvasPosition.Y - offsetY, 0) / paintCellPixels) + 1, 1)
	local visibleColumns =
		math.min(math.ceil(gridScroll.AbsoluteWindowSize.X / paintCellPixels) + 2, grid.columns)
	local visibleRows = math.min(math.ceil(gridScroll.AbsoluteWindowSize.Y / paintCellPixels) + 2, grid.rows)
	local needed = visibleColumns * visibleRows
	while #cellPool < needed do
		local cellButton = create("TextButton", {
			AutoButtonColor = false,
			BorderColor3 = Color3.fromRGB(24, 27, 31),
			BorderSizePixel = 1,
			Font = Enum.Font.BuilderSansBold,
			TextColor3 = COLORS.text,
			TextSize = 11,
		}, gridCanvas) :: TextButton
		cellButton.MouseButton1Down:Connect(function(screenX: number, screenY: number)
			local column, row = cellAtScreenPoint(Vector2.new(screenX, screenY))
			if column == nil or row == nil then
				return
			end
			selectedCellKey = `{column}:{row}`
			showHoveredCell(column, row)
			if paintModifierDown() then
				painting = true
				paintedKeys = {}
				ProjectStore.begin("Paint Stagewright cells")
				paintCell(column, row)
			end
			renderCanvas()
		end)
		cellButton.MouseEnter:Connect(function()
			local pointer = UserInputService:GetMouseLocation()
			local column, row = cellAtScreenPoint(pointer)
			showHoveredCell(column, row)
			if painting and paintModifierDown() and column ~= nil and row ~= nil then
				paintCell(column, row)
				renderCanvas()
			end
		end)
		table.insert(cellPool, cellButton)
	end
	local index = 0
	for row = firstRow, math.min(firstRow + visibleRows - 1, grid.rows) do
		for column = firstColumn, math.min(firstColumn + visibleColumns - 1, grid.columns) do
			index += 1
			local cellButton = cellPool[index]
			local key = `{column}:{row}`
			local cell = grid.cells[key] or grid.defaultCell
			local color, glyph = cellVisual(cell)
			cellButton.Position =
				UDim2.fromOffset((column - 1) * paintCellPixels, (row - 1) * paintCellPixels)
			cellButton.Size = UDim2.fromOffset(paintCellPixels, paintCellPixels)
			cellButton.BackgroundColor3 = color
			cellButton.BorderColor3 = if key == selectedCellKey
				then COLORS.accent
				else Color3.fromRGB(24, 27, 31)
			cellButton.BorderSizePixel = if key == selectedCellKey then 2 else 1
			cellButton.Text = glyph
			cellButton:SetAttribute("Column", column)
			cellButton:SetAttribute("Row", row)
			cellButton.Visible = true
		end
	end
	for poolIndex = index + 1, #cellPool do
		cellPool[poolIndex].Visible = false
	end
end
local function refreshCanvasFromPointer()
	local column, row = cellAtScreenPoint(UserInputService:GetMouseLocation())
	showHoveredCell(column, row)
	if painting and paintModifierDown() and column ~= nil and row ~= nil then
		paintCell(column, row)
	end
	renderCanvas()
end
gridScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshCanvasFromPointer)
gridScroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(renderCanvas)
gridScroll.MouseLeave:Connect(function()
	showHoveredCell(nil, nil)
end)
UserInputService.InputChanged:Connect(function(input)
	if
		activeMode == "Paint"
		and input.UserInputType == Enum.UserInputType.MouseMovement
		and gridScroll.Visible
	then
		local column, row = cellAtScreenPoint(Vector2.new(input.Position.X, input.Position.Y))
		showHoveredCell(column, row)
		if painting and paintModifierDown() and column ~= nil and row ~= nil then
			paintCell(column, row)
			renderCanvas()
		end
	end
end)

-- Stage browser.
local stagePage = contentByMode.Stage
local stageInspector = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 218),
}, rightSidebar) :: Frame
local stageInspectorTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(12, 9),
	Size = UDim2.new(1, -150, 0, 22),
	Text = "Level settings",
	TextColor3 = COLORS.text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
}, stageInspector)
local stageLevelLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLORS.accentMuted,
	BorderSizePixel = 0,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.new(1, -12, 0, 8),
	Size = UDim2.fromOffset(122, 26),
	Text = "STAGE 1 · LEVEL 1",
	TextColor3 = Color3.fromRGB(151, 194, 255),
	TextSize = 10,
}, stageInspector) :: TextLabel
create("UICorner", { CornerRadius = UDim.new(0, 6) }, stageLevelLabel)
local stageForm = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 42),
	Size = UDim2.new(1, -20, 0, 126),
}, stageInspector) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(8, 4),
	CellSize = UDim2.new(0.5, -4, 0, 38),
	FillDirectionMaxCells = 2,
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
	local columns = tonumber(columnsField.Text)
	local rows = tonumber(rowsField.Text)
	local cellSize = tonumber(cellSizeField.Text)
	if
		columns == nil
		or rows == nil
		or cellSize == nil
		or columns < 1
		or columns > 512
		or rows < 1
		or rows > 512
		or cellSize <= 0
		or cellSize > 128
	then
		setStatus(
			"Grid width and height must be 1–512; cell size must be greater than 0 and at most 128.",
			true
		)
		return
	end
	columns = math.floor(columns)
	rows = math.floor(rows)
	local truncated = 0
	for key in current.grid.cells do
		local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
		local column, row = tonumber(columnText), tonumber(rowText)
		if column == nil or row == nil or column > columns or row > rows then
			truncated += 1
		end
	end
	if
		truncated > 0
		and not confirm(`resize_{current.id}`, `Resize would remove {truncated} cell override(s).`)
	then
		return
	end
	mutate("Update Stagewright level settings", function()
		current.name = if stageNameField.Text ~= "" then stageNameField.Text else current.name
		current.waveSetId = waveSetField.Text
		current.themeId = themeField.Text
		current.grid.columns = columns
		current.grid.rows = rows
		current.grid.cellSize = cellSize
		for key in current.grid.cells do
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			local column, row = tonumber(columnText), tonumber(rowText)
			if column == nil or row == nil or column > columns or row > rows then
				current.grid.cells[key] = nil
			end
		end
	end)
	renderAll()
end)
applyStageButton.AnchorPoint = Vector2.new(1, 0)
applyStageButton.Position = UDim2.new(1, -12, 0, 178)
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(12, 181),
	Size = UDim2.new(1, -154, 0, 24),
	Text = "Width × height defines the grid. Shrinking asks before trimming painted cells.",
	TextColor3 = COLORS.muted,
	TextSize = 10,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, stageInspector)
local stageList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 80),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -230),
}, leftSidebar) :: ScrollingFrame
local stageSearchField = create("TextBox", {
	BackgroundColor3 = COLORS.field,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.BuilderSans,
	PlaceholderColor3 = COLORS.muted,
	PlaceholderText = "Search levels…",
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
	Position = UDim2.new(0, 0, 1, -146),
	Size = UDim2.new(1, 0, 0, 146),
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
	Size = UDim2.new(1, -20, 0, 112),
}, stagePage) :: Frame
create("UICorner", { CornerRadius = UDim.new(0, 8) }, levelHero)
create("UIStroke", { Color = COLORS.border, Thickness = 1 }, levelHero)
local levelOverviewName = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 28),
	Text = "Level 1",
	TextColor3 = COLORS.text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
}, levelHero) :: TextLabel
local levelOverviewMeta = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(16, 43),
	Size = UDim2.new(1, -32, 0, 22),
	Text = "32 × 27 grid · 0 nodes · 0 edges",
	TextColor3 = COLORS.muted,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
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
}, levelHero)
local workflowGrid = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 132),
	Size = UDim2.new(1, -20, 0, 218),
}, stagePage) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(10, 10),
	CellSize = UDim2.new(0.5, -5, 0, 104),
	FillDirectionMaxCells = 2,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, workflowGrid)
local workflowSteps = {
	{
		title = "✎  Open Paint",
		body = "Define terrain, tower build rules, traversal restrictions, and object roles.",
		mode = "Paint" :: Mode,
	},
	{
		title = "⌁  Open Flow",
		body = "Add spawn, junction, and goal nodes. Connect branches and choose lane counts.",
		mode = "Graph" :: Mode,
	},
	{
		title = "⚙  Level settings",
		body = "Set the level name, theme, wave-set reference, grid size, and cell size in the inspector.",
		mode = "Stage" :: Mode,
	},
	{
		title = "✓  Check level",
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
		Position = UDim2.fromOffset(10, 360),
		Size = UDim2.new(1, -20, 0, 82),
	}, stagePage) :: Frame
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
		Size = UDim2.new(1, -160, 0, 32),
		Text = "Grid ready  ·  Route ready  ·  No issues",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, summary) :: TextLabel
	local open = button(summary, "Open level  ↗", 118, function()
		activeMode = "Paint"
		renderAll()
	end)
	open.AnchorPoint = Vector2.new(1, 0.5)
	open.Position = UDim2.new(1, -14, 0.5, 8)
end

function mutate(name: string, callback: () -> ())
	ProjectStore.mutate(name, callback)
	project = ProjectStore.get()
	stageIds = ProjectStore.stageIds()
	renderCanvas()
	rebuildPreview()
	setStatus(`Working changes · {ProjectStore.workingChecksum()}`)
end

local stageActionOrder = 0
local function stageAction(text: string, callback: () -> ()): TextButton
	stageActionOrder += 1
	local result = button(stageActions, text, 80, callback)
	result.LayoutOrder = stageActionOrder
	return result
end

stageAction("＋ Stage", function()
	mutate("Create Stagewright stage group", function()
		selectedStageId = ProjectStore.createStage(nil)
	end)
	renderAll()
end)
stageAction("＋ Level", function()
	mutate("Create Stagewright level", function()
		selectedStageId = ProjectStore.createLevel(selectedStageId)
	end)
	renderAll()
end)
stageAction("⌫ Delete", function()
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
for _, move in { { "↑ Up", -1 }, { "↓ Down", 1 } } do
	stageAction(move[1] :: string, function()
		mutate("Reorder Stagewright stages", function()
			ProjectStore.moveStage(selectedStageId, move[2] :: number)
		end)
		renderAll()
	end)
end
stageAction("↗ Open 3D", function()
	AuthoringArea.focus()
	setStatus("Focused the separate Stagewright admin authoring area.")
end)
local islandGuideButton: TextButton
islandGuideButton = stageAction("◫ Guides", function()
	islandOutlinesEnabled = not islandOutlinesEnabled
	islandGuideButton.Text = if islandOutlinesEnabled then "◫ Guides" else "□ Guides"
	renderIslandOutlines()
	setStatus(if islandOutlinesEnabled then "Six island footprint guides shown." else "Island guides hidden.")
end)

function renderStageList()
	for _, child in stageList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	stageIds = ProjectStore.stageIds()
	local previousGroupId: string? = nil
	local groupCount = 0
	local visibleCount = 0
	local query = string.lower(stageSearchField.Text)
	for order, stageId in stageIds do
		local definition = project.stages[stageId]
		local address = StageHierarchy.address(definition)
		local searchText = string.lower(
			`stage {address.stageNumber} level {address.levelNumber} {definition.name} {stageId}`
		)
		if query ~= "" and string.find(searchText, query, 1, true) == nil then
			continue
		end
		visibleCount += 1
		if address.groupId ~= previousGroupId then
			groupCount += 1
			previousGroupId = address.groupId
			local groupHeader = create("TextLabel", {
				BackgroundColor3 = COLORS.background,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansBold,
				LayoutOrder = order * 2 - 1,
				Size = UDim2.new(1, -16, 0, 28),
				Text = `STAGE {address.stageNumber}  ·  {address.groupId:sub(-8)}`,
				TextColor3 = COLORS.muted,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, stageList) :: TextLabel
			create("UIPadding", { PaddingLeft = UDim.new(0, 6) }, groupHeader)
		end
		local stageButton = button(
			stageList,
			`Level {address.levelNumber}  ·  {definition.name}  ·  {string.sub(stageId, -8)}`,
			300,
			function()
				selectedStageId = stageId
				selectedGraphId = nil
				selectedNodeId = nil
				selectedEdgeId = nil
				tracedEdgeIds = {}
				renderAll()
			end
		)
		stageButton.LayoutOrder = order * 2
		stageButton.Size = UDim2.new(1, -16, 0, 32)
		stageButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, stageButton)
		setButtonSelected(stageButton, stageId == selectedStageId)
	end
	stageList.CanvasSize = UDim2.fromOffset(0, visibleCount * 37 + groupCount * 33 + 16)
end

-- Graph page: stable node/edge IDs, directed connections, predicates, lanes, and priorities.
local graphPage = contentByMode.Graph
graphPage.ClipsDescendants = true
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
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 116),
	Size = UDim2.new(1, 0, 1, -116),
}, rightSidebar) :: Frame
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
local focusNodeButton = button(nodeProperties, "Select in 3D", 112, function()
	local currentGraph = graph()
	local node = if currentGraph ~= nil and selectedNodeId ~= nil
		then currentGraph.nodes[selectedNodeId]
		else nil
	local part = if node ~= nil and previewFolder ~= nil
		then previewFolder:FindFirstChild(`Node_{node.name}`)
		else nil
	if part ~= nil then
		Selection:Set({ part })
	end
	AuthoringArea.focus()
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
	Size = UDim2.new(1, 0, 1, -322),
}, rightSidebar) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, graphList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, graphList)
local routeOverviewHost = create("Frame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Size = UDim2.new(1, 0, 1, -250),
}, graphPage) :: Frame
routeOverview = RouteOverview.new(routeOverviewHost, COLORS, {
	selectNode = function(nodeId: string)
		selectedNodeId = nodeId
		selectedEdgeId = nil
		tracedEdgeIds = {}
		renderGraphList()
		rebuildPreview()
	end,
	selectEdge = function(edgeId: string)
		selectedEdgeId = edgeId
		selectedNodeId = nil
		tracedEdgeIds = {}
		renderGraphList()
		rebuildPreview()
	end,
})
local graphActions = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.surface,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(760, 154),
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
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.new(1, -20, 1, -52),
		Visible = mode == graphToolMode,
	}, graphActions) :: Frame
	graphActionPages[mode] = page
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Size = UDim2.new(1, 0, 0, 30),
		Text = graphPageHelp[mode],
		TextColor3 = COLORS.muted,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, page)
	local controls = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
	}, page) :: Frame
	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 6),
		CellSize = UDim2.new(1 / columns, -4, 0, 29),
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, controls)
	return controls
end
local buildControls = graphActionPage("Build", 4)
local rulesControls = graphActionPage("Rules", 2)
local testControls = graphActionPage("Test", 2)
local buildCreationButtons: { TextButton } = {}
local nodeBuildButtons: { TextButton } = {}
local edgeBuildButtons: { TextButton } = {}
for order, modeName in { "Build", "Rules", "Test" } :: { GraphToolMode } do
	local mode = modeName :: GraphToolMode
	local tab = button(
		graphToolTabs,
		if mode == "Build" then "＋ Build" elseif mode == "Rules" then "◆ Rules" else "▶ Test",
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
		action.Visible = selectedEdgeId == nil
	end
	for _, action in nodeBuildButtons do
		action.Visible = selectedNodeId ~= nil
	end
	for _, action in edgeBuildButtons do
		action.Visible = selectedEdgeId ~= nil
	end
	local height = if graphToolMode == "Build" then 142 elseif graphToolMode == "Rules" then 196 else 224
	graphActions.Size = UDim2.fromOffset(math.clamp(graphPage.AbsoluteSize.X - 28, 330, 820), height)
	graphActions.ZIndex = 20
	for _, descendant in graphActions:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 21
		end
	end
	routeOverviewHost.Size = UDim2.fromScale(1, 1)
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

local PREDICATE_KINDS = {
	"WaveRange",
	"StageFlagEquals",
	"EnemyTag",
	"VisitCountBelow",
	"StageUnlocked",
	"UpgradeLevelAtLeast",
	"CurrencyAtLeast",
}

local function newNode(kind: string)
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local id = `node_{string.lower(game:GetService("HttpService"):GenerateGUID(false))}`
	local count = 0
	for _ in currentGraph.nodes do
		count += 1
	end
	currentGraph.nodes[id] = {
		id = id,
		name = `{kind} {count + 1}`,
		kind = kind,
		position = { x = (count - 1) * 8, y = 2, z = 0 },
		tags = {},
	}
	selectedNodeId = id
	selectedEdgeId = nil
end
for _, kind in { "Spawn", "Junction", "Goal" } do
	local icon = if kind == "Spawn" then "●" elseif kind == "Goal" then "◆" else "◇"
	local addButton = button(buildControls, `{icon}  {kind}`, 112, function()
		mutate(`Add {kind} node`, function()
			newNode(kind)
		end)
		renderAll()
	end)
	table.insert(buildCreationButtons, addButton)
end
table.insert(
	nodeBuildButtons,
	button(buildControls, "↗  Connect", 112, function()
		connectFromNodeId = selectedNodeId
		setStatus(if connectFromNodeId ~= nil then "Select a destination node." else "Select a node first.")
	end)
)
table.insert(
	nodeBuildButtons,
	button(buildControls, "⌫  Node", 112, function()
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
	button(buildControls, "⌫  Edge", 112, function()
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
	button(buildControls, "Priority −", 112, function()
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
	local kind = PREDICATE_KINDS[predicateKindIndex]
	local key = conditionKeyField.Text
	local value = conditionValueField.Text
	local maximum = conditionMaximumField.Text
	if kind == "WaveRange" then
		local minimumNumber = tonumber(value)
		local maximumNumber = tonumber(maximum)
		if minimumNumber == nil or maximumNumber == nil then
			return nil, "WaveRange needs numeric minimum and maximum values"
		end
		return { kind = kind, minimum = minimumNumber, maximum = maximumNumber }, nil
	elseif kind == "StageFlagEquals" then
		if key == "" or (string.lower(value) ~= "true" and string.lower(value) ~= "false") then
			return nil, "StageFlagEquals needs a key and true/false value"
		end
		return { kind = kind, key = key, value = string.lower(value) == "true" }, nil
	elseif kind == "EnemyTag" then
		return if key ~= "" then { kind = kind, tag = key } else nil,
			if key == "" then "EnemyTag needs a tag" else nil
	elseif kind == "VisitCountBelow" then
		local maximumNumber = tonumber(value)
		if maximumNumber == nil then
			return nil, "VisitCountBelow needs a numeric maximum"
		end
		return {
			kind = kind,
			nodeId = if key ~= "" then key else edge.fromNodeId,
			maximum = maximumNumber,
		},
			nil
	elseif kind == "StageUnlocked" then
		return if key ~= "" then { kind = kind, stageId = key } else nil,
			if key == "" then "StageUnlocked needs a stage ID" else nil
	elseif kind == "UpgradeLevelAtLeast" then
		local level = tonumber(value)
		if key == "" or level == nil then
			return nil, "UpgradeLevelAtLeast needs an upgrade ID and numeric level"
		end
		return { kind = kind, upgradeId = key, level = level }, nil
	elseif kind == "CurrencyAtLeast" then
		local amount = tonumber(value)
		if key == "" or amount == nil then
			return nil, "CurrencyAtLeast needs a currency ID and numeric amount"
		end
		return { kind = kind, currencyId = key, amount = amount }, nil
	end
	return nil, "Unknown predicate kind"
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

local function commaSet(text: string): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for token in string.gmatch(text, "[^,%s]+") do
		result[token] = true
	end
	return result
end

local function assignmentMap(text: string, booleanValues: boolean): { [string]: any }
	local result: { [string]: any } = {}
	for token in string.gmatch(text, "[^,]+") do
		local key, value = string.match(token, "^%s*([^=]+)%s*=%s*([^=]+)%s*$")
		if key ~= nil and value ~= nil then
			if booleanValues then
				result[key] = string.lower(value) == "true"
			else
				local numberValue = tonumber(value)
				if numberValue ~= nil then
					result[key] = numberValue
				end
			end
		end
	end
	return result
end

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
		stageFlags = assignmentMap(traceFlagsField.Text, true),
		enemyTags = commaSet(traceTagsField.Text),
		nodeVisits = {},
		unlockedStages = commaSet(traceUnlockedField.Text),
		upgradeLevels = assignmentMap(traceUpgradesField.Text, false),
		currencies = assignmentMap(traceCurrenciesField.Text, false),
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
	setStatus(`Trace {table.concat(path, " > ")} · {trace.stoppedReason}`, not trace.reachedGoal)
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
			local edge = currentGraph.edges[selectedEdgeId :: string]
			local profile = currentGraph.laneProfiles[edge.laneProfileId]
			local offsets = StageLanes.offsets(laneCount)
			profile.offsets = offsets
			profile.clearanceRadius = StageLanes.clearanceRadius(offsets)
		end)
		setStatus(`Route profile uses {laneCount} {if laneCount == 1 then "lane" else "lanes"}.`)
		renderAll()
	end)
	table.insert(edgeBuildButtons, laneButton)
end

local function connectNodes(fromId: string, toId: string)
	local currentGraph = graph()
	if currentGraph == nil or fromId == toId then
		return
	end
	local from = currentGraph.nodes[fromId]
	local to = currentGraph.nodes[toId]
	if from == nil or to == nil then
		return
	end
	local id = `edge_{string.lower(game:GetService("HttpService"):GenerateGUID(false))}`
	local delta = {
		x = (to.position.x - from.position.x) / 3,
		y = (to.position.y - from.position.y) / 3,
		z = (to.position.z - from.position.z) / 3,
	}
	currentGraph.edges[id] = {
		id = id,
		fromNodeId = fromId,
		toNodeId = toId,
		outHandleOffset = delta,
		inHandleOffset = { x = -delta.x, y = -delta.y, z = -delta.z },
		laneProfileId = "lane_default",
		priority = 1,
		predicates = {},
	}
	selectedEdgeId = id
	selectedNodeId = nil
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
		graphSelectionTitle.Text = `{selectedNode.kind} · {selectedNode.name}`
		graphSelectionHint.Text =
			`Drag its 3D control to reposition it · ID {string.sub(selectedNode.id, -8)}`
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
			`{if from ~= nil then from.name else "Missing"}  →  {if to ~= nil then to.name else "Missing"}`
		graphSelectionHint.Text = `P{selectedEdge.priority} · {laneCount} lane{if laneCount == 1
			then ""
			else "s"} · {if #ruleNames == 0 then "unconditional fallback" else table.concat(ruleNames, " + ")}`
		edgePropertiesText.Text =
			`Priority: {selectedEdge.priority}\nLanes: {laneCount}\nRules: {if #ruleNames == 0
				then "Fallback (always available)"
				else table.concat(ruleNames, " + ")}`
	else
		graphSelectionTitle.Text = `{#nodeIds} nodes · {#edgeIds} edges`
		graphSelectionHint.Text = "Select an item below, or add a spawn, junction, or goal from Build tools."
	end

	order += 1
	sectionLabel(graphList, "Nodes", order)
	for _, nodeId in nodeIds do
		local node = currentGraph.nodes[nodeId]
		order += 1
		local nodeButton = button(
			graphList,
			`{string.upper(node.kind)}  ·  {node.name}  ·  {string.sub(nodeId, -8)}`,
			300,
			function()
				if connectFromNodeId ~= nil then
					local from = connectFromNodeId
					connectFromNodeId = nil
					mutate("Connect Stagewright graph nodes", function()
						connectNodes(from, nodeId)
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
			`{if from ~= nil then from.name else "Missing"}  →  {if to ~= nil then to.name else "Missing"}  ·  P{edge.priority}  ·  {if #edge.predicates
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
	routeOverview:render(currentGraph, selectedNodeId, selectedEdgeId, tracedEdgeIds)
end

-- Validate/export page.
local validatePage = contentByMode.Validate
local validateSummary = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 74),
}, validatePage) :: Frame
local validateTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -28, 0, 22),
	Text = "Checking project…",
	TextColor3 = COLORS.text,
	TextSize = 14,
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
}, validateSummary) :: TextLabel
local issueList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 78),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -131),
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
	local errorCount = 0
	local warningCount = 0
	for _, issue in validationIssues do
		if issue.severity == "Error" then
			errorCount += 1
		else
			warningCount += 1
		end
	end
	if #validationIssues == 0 then
		validateTitle.Text = "Ready to export"
		validateTitle.TextColor3 = COLORS.success
		validateHint.Text = "No errors or warnings. The deployable bundle can be exported safely."
	else
		validateTitle.Text =
			`{errorCount} error{if errorCount == 1 then "" else "s"} · {warningCount} warning{if warningCount
					== 1
				then ""
				else "s"}`
		validateTitle.TextColor3 = if errorCount > 0 then COLORS.danger else COLORS.warning
		validateHint.Text = "Select an issue to jump to its level or route object. Errors block export."
	end
	exportButton.Active = errorCount == 0
	exportButton.BackgroundColor3 = if errorCount == 0 then COLORS.accent else COLORS.field
	exportButton.TextColor3 = if errorCount == 0 then COLORS.text else COLORS.muted
	for order, issue in validationIssues do
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
		local location = issue.objectId or "Level"
		issueButton.Size = UDim2.new(1, -16, 0, 42)
		issueButton.Text =
			`{if issue.severity == "Error" then "●" else "▲"}  {issue.code}  ·  {issue.message}     {if address
					~= nil
				then `Level {address.levelNumber}`
				else "Project"}  ·  {location}     ›`
		issueButton.TextColor3 = if issue.severity == "Error" then COLORS.danger else COLORS.warning
		issueButton.TextSize = 11
		issueButton.TextTruncate = Enum.TextTruncate.AtEnd
		issueButton.TextWrapped = false
		issueButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}, issueButton)
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
			Text = "✓  Everything looks good\nYour stage hierarchy and route graphs passed validation.",
			TextColor3 = COLORS.success,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, issueList)
	end
	issueList.CanvasSize = UDim2.fromOffset(0, math.max(#validationIssues, 1) * 48 + 16)
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
		setStatus(`Export hash matched · {result.bundle.checksum}`)
	else
		setStatus("Export cancelled; project was not changed.")
	end
end

button(exportActions, "↻  Refresh", 92, function()
	renderIssues()
	setStatus("Validation refreshed.")
end)
exportButton = button(exportActions, "⇧  Export bundle", 128, exportBundle)
button(exportActions, "⇩  Import selected", 128, function()
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
		setButtonSelected(modeButtons[mode], mode == activeMode)
	end
	local browsingLevels = activeMode ~= "Paint"
	sidebarTitle.Text = if activeMode == "Paint" then "PAINT TOOLS" else `STAGES & LEVELS  ·  {#stageIds}`
	stageSearchField.Visible = browsingLevels
	stageList.Visible = browsingLevels
	stageList.Size = UDim2.new(1, 0, 1, if activeMode == "Stage" then -230 else -80)
	stageActions.Visible = activeMode == "Stage"
	brushRail.Visible = activeMode == "Paint"
	stageInspector.Visible = activeMode == "Stage"
	graphSummary.Visible = activeMode == "Graph"
	graphProperties.Visible = activeMode == "Graph"
	graphList.Visible = false
	inspectorTitle.Text = if activeMode == "Graph"
		then "ROUTE PROPERTIES"
		elseif activeMode == "Stage" then "LEVEL PROPERTIES"
		else ""
	renderGraphTools()
	renderPaintChrome()
	renderIssues()
	local current = stage()
	if current ~= nil then
		local address = StageHierarchy.address(current)
		title.Text = `Stagewright  ·  Stage {address.stageNumber} / Level {address.levelNumber}`
		footerStage.Text =
			`Stage {address.stageNumber} · Level {address.levelNumber}    Theme: {current.themeId}    Wave set: {current.waveSetId}`
		levelOverviewName.Text =
			`Stage {address.stageNumber} · Level {address.levelNumber} — {current.name}`
		stageInspectorTitle.Text = `Level settings  ·  {current.name}`
		stageLevelLabel.Text = `STAGE {address.stageNumber} · LEVEL {address.levelNumber}`
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
			`{current.grid.columns} × {current.grid.rows} grid · {nodeCount} nodes · {edgeCount} edges · {string.sub(
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
			`{current.grid.columns * current.grid.rows} cells  ·  {nodeCount} nodes / {edgeCount} edges  ·  {currentIssueCount} issue{if currentIssueCount
					== 1
				then ""
				else "s"}`
		levelHealthText.TextColor3 = if currentIssueCount > 0 then COLORS.warning else COLORS.success
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
		then "✓  Ready to export"
		else `{errorCount} errors  ·  {warningCount} warnings`
	headerValidation.TextColor3 = if errorCount > 0
		then COLORS.danger
		elseif warningCount > 0 then COLORS.warning
		else COLORS.success
	renderCanvas()
	renderStageList()
	renderGraphList()
	renderIslandOutlines()
	applyResponsiveShell()
	if activeMode == "Graph" then
		rebuildPreview()
	end
end
renderAll = rerenderAll
headerValidation.Activated:Connect(function()
	activeMode = "Validate"
	renderAll()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and painting then
		painting = false
		ProjectStore.finish(true)
		setStatus(`Working changes · {ProjectStore.workingChecksum()}`)
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
		islandGuideButton.Text = if islandOutlinesEnabled then "◫ Guides" else "□ Guides"
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
plugin.Unloading:Connect(function()
	ProjectStore.cleanup()
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

setStatus(`Working changes · {ProjectStore.save()}`)
rerenderAll()

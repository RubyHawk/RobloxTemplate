--!strict

local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AuthoringArea = require(script.AuthoringArea)
local ProjectStore = require(script.ProjectStore)
local StageTrace = require(script.Shared.StageTrace)

local PLUGIN_NAME = "Stagewright"
local PREVIEW_TAG = "StagewrightTransientPreview"
local CELL_PIXELS = 22
local COLORS = {
	background = Color3.fromRGB(17, 18, 20),
	panel = Color3.fromRGB(23, 25, 29),
	field = Color3.fromRGB(31, 34, 40),
	border = Color3.fromRGB(54, 59, 68),
	text = Color3.fromRGB(232, 235, 240),
	muted = Color3.fromRGB(152, 160, 172),
	accent = Color3.fromRGB(76, 132, 203),
	ground = Color3.fromRGB(75, 132, 91),
	void = Color3.fromRGB(28, 30, 35),
	blocked = Color3.fromRGB(157, 76, 76),
	spawn = Color3.fromRGB(116, 96, 181),
	goal = Color3.fromRGB(195, 123, 65),
	auto = Color3.fromRGB(60, 145, 166),
}

type Mode = "Paint" | "Graph" | "Stage" | "Validate"
type Brush = {
	id: string,
	label: string,
	apply: (cell: any) -> (),
}

local authoringPlatform = AuthoringArea.ensure()
local project = ProjectStore.load(authoringPlatform)
local stageIds = ProjectStore.stageIds()
local selectedStageId = project.startingStageId or stageIds[1]
local selectedGraphId: string? = nil
local selectedNodeId: string? = nil
local selectedEdgeId: string? = nil
local tracedEdgeIds: { [string]: boolean } = {}
local connectFromNodeId: string? = nil
local activeMode: Mode = "Paint"
local activeBrushId = "build_blocked"
local predicateKindIndex = 1
local painting = false
local paintedKeys: { [string]: boolean } = {}
local previewFolder: Folder? = nil
local previewMoveRevision = 0
local pendingConfirmation: { id: string, expires: number }? = nil

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local openButton = toolbar:CreateButton(
	"StagewrightEditor",
	"Open the Stagewright stage authoring workbench",
	"rbxasset://textures/StudioSharedUI/grid@2x.png",
	PLUGIN_NAME
)
openButton.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"StagewrightPanel",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, false, 520, 760, 360, 480)
)
widget.Title = "Stagewright · Versioned Stage Editor"

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
	Size = UDim2.new(1, 0, 0, 82),
}, root) :: Frame
local title = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSansBold,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 24),
	Text = "STAGEWRIGHT",
	TextColor3 = COLORS.text,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header) :: TextLabel
local status = create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.BuilderSans,
	Position = UDim2.fromOffset(14, 31),
	Size = UDim2.new(1, -28, 0, 18),
	Text = "Loading versioned project…",
	TextColor3 = COLORS.muted,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header) :: TextLabel
local modes = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 53),
	Size = UDim2.new(1, -20, 0, 25),
}, header) :: Frame
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, modes)
local body = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 82),
	Size = UDim2.new(1, 0, 1, -82),
}, root) :: Frame

local function button(parent: Instance, text: string, width: number?, callback: () -> ()): TextButton
	local result = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Size = UDim2.fromOffset(width or 110, 27),
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 12,
	}, parent) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, result)
	create("UIStroke", { Color = COLORS.border, Thickness = 1 }, result)
	result.Activated:Connect(callback)
	return result
end

local modeButtons: { [Mode]: TextButton } = {} :: any
local contentByMode: { [Mode]: Frame } = {} :: any
local rerenderAll: () -> ()
local renderAll: () -> ()
local mutate: (string, () -> ()) -> ()

local function stage(): any
	return project.stages[selectedStageId]
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
	status.TextColor3 = if errorState then Color3.fromRGB(239, 105, 105) else COLORS.muted
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
		id = "terrain_ground",
		label = "Terrain · Ground",
		apply = function(cell)
			cell.terrainId = "ground"
		end,
	},
	{
		id = "terrain_void",
		label = "Terrain · Void",
		apply = function(cell)
			cell.terrainId = "void"
		end,
	},
	{
		id = "build_allowed",
		label = "Build · Allowed",
		apply = function(cell)
			cell.buildPolicy = "Allowed"
		end,
	},
	{
		id = "build_blocked",
		label = "Build · Blocked",
		apply = function(cell)
			cell.buildPolicy = "Blocked"
		end,
	},
	{
		id = "build_auto",
		label = "Build · Auto only",
		apply = function(cell)
			cell.buildPolicy = "AutoOnly"
		end,
	},
	{
		id = "traversal_allowed",
		label = "Enemy · Allowed",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Allowed"
		end,
	},
	{
		id = "traversal_blocked",
		label = "Enemy · Blocked",
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
		label = `Role · {role}`,
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
		for index = 2, #edge.samples do
			local before = edge.samples[index - 1].position
			local after = edge.samples[index].position
			local a = origin:PointToWorldSpace(Vector3.new(before.x, before.y, before.z))
			local b = origin:PointToWorldSpace(Vector3.new(after.x, after.y, after.z))
			local segment = Instance.new("Part")
			segment.Name = `Edge_{edgeId}_{index}`
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

for order, modeName in { "Paint", "Graph", "Stage", "Validate" } :: { Mode } do
	local mode = modeName :: Mode
	modeButtons[mode] = button(modes, mode, 88, function()
		activeMode = mode
		rerenderAll()
	end)
	modeButtons[mode].LayoutOrder = order
	local page = create("Frame", {
		Name = `{mode}Page`,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, body) :: Frame
	contentByMode[mode] = page
end

-- Paint page: a layer-aware brush rail and a virtualized grid canvas.
local paintPage = contentByMode.Paint
local brushRail = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, #brushes * 31 + 10),
	ScrollBarThickness = 5,
	Size = UDim2.new(0, 150, 1, 0),
}, paintPage) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, brushRail)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 5),
	PaddingRight = UDim.new(0, 5),
	PaddingTop = UDim.new(0, 5),
}, brushRail)
local brushButtons: { [string]: TextButton } = {}
for order, brushDefinition in brushes do
	local brush = brushDefinition
	local brushButton = button(brushRail, brush.label, 138, function()
		activeBrushId = brush.id
		rerenderAll()
	end)
	brushButton.LayoutOrder = order
	brushButtons[brush.id] = brushButton
end
local gridScroll = create("ScrollingFrame", {
	BackgroundColor3 = Color3.fromRGB(12, 13, 15),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(154, 0),
	ScrollBarThickness = 8,
	ScrollingDirection = Enum.ScrollingDirection.XY,
	Size = UDim2.new(1, -154, 1, 0),
}, paintPage) :: ScrollingFrame
local gridCanvas = create("Frame", { BackgroundTransparency = 1 }, gridScroll) :: Frame
local cellPool: { TextButton } = {}

local function cellVisual(cell: any): (Color3, string)
	local roles = cell.roles or {}
	if roles.EnemySpawn then
		return COLORS.spawn, "S"
	elseif roles.EnemyGoal then
		return COLORS.goal, "G"
	elseif roles.AutoPlace then
		return COLORS.auto, "A"
	elseif cell.buildPolicy == "Blocked" then
		return COLORS.blocked, "×"
	elseif cell.terrainId == "void" then
		return COLORS.void, ""
	end
	return COLORS.ground, ""
end

local function paintCell(column: number, row: number)
	local key = `{column}:{row}`
	if paintedKeys[key] then
		return
	end
	paintedKeys[key] = true
	local current = stage()
	local cell = current.grid.cells[key]
	if cell == nil then
		cell = {}
		current.grid.cells[key] = cell
	end
	activeBrush().apply(cell)
end

local function renderCanvas()
	local current = stage()
	if current == nil then
		return
	end
	local grid = current.grid
	local width = grid.columns * CELL_PIXELS
	local height = grid.rows * CELL_PIXELS
	gridCanvas.Size = UDim2.fromOffset(width, height)
	gridScroll.CanvasSize = UDim2.fromOffset(width, height)
	local firstColumn = math.max(math.floor(gridScroll.CanvasPosition.X / CELL_PIXELS) + 1, 1)
	local firstRow = math.max(math.floor(gridScroll.CanvasPosition.Y / CELL_PIXELS) + 1, 1)
	local visibleColumns =
		math.min(math.ceil(gridScroll.AbsoluteWindowSize.X / CELL_PIXELS) + 2, grid.columns)
	local visibleRows = math.min(math.ceil(gridScroll.AbsoluteWindowSize.Y / CELL_PIXELS) + 2, grid.rows)
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
		cellButton.MouseButton1Down:Connect(function()
			painting = true
			paintedKeys = {}
			ProjectStore.begin("Paint Stagewright cells")
			paintCell(cellButton:GetAttribute("Column"), cellButton:GetAttribute("Row"))
			renderCanvas()
		end)
		cellButton.MouseEnter:Connect(function()
			if painting then
				paintCell(cellButton:GetAttribute("Column"), cellButton:GetAttribute("Row"))
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
			cellButton.Position = UDim2.fromOffset((column - 1) * CELL_PIXELS, (row - 1) * CELL_PIXELS)
			cellButton.Size = UDim2.fromOffset(CELL_PIXELS, CELL_PIXELS)
			cellButton.BackgroundColor3 = color
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
gridScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(renderCanvas)
gridScroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(renderCanvas)

-- Stage browser.
local stagePage = contentByMode.Stage
local stageInspector = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 138),
}, stagePage) :: Frame
local function textField(parent: Instance, label: string, x: number, y: number, width: number): TextBox
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 16),
		Text = label,
		TextColor3 = COLORS.muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		Position = UDim2.fromOffset(x, y + 17),
		Size = UDim2.fromOffset(width, 26),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, field)
	return field
end
local stageNameField = textField(stageInspector, "DISPLAY NAME", 8, 7, 180)
local columnsField = textField(stageInspector, "COLUMNS", 194, 7, 66)
local rowsField = textField(stageInspector, "ROWS", 266, 7, 66)
local cellSizeField = textField(stageInspector, "CELL SIZE", 338, 7, 72)
local waveSetField = textField(stageInspector, "WAVE SET ID", 8, 59, 180)
local themeField = textField(stageInspector, "THEME ID", 194, 59, 138)
button(stageInspector, "Apply Stage", 112, function()
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
		setStatus("Grid dimensions must be 1–512 and cell size must be 0–128.", true)
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
	mutate("Update Stagewright stage settings", function()
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
end).Position =
	UDim2.fromOffset(338, 77)
local stageList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(0, 142),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -214),
}, stagePage) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, stageList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, stageList)
local stageActions = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 1, -68),
	Size = UDim2.new(1, 0, 0, 68),
}, stagePage) :: Frame
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, stageActions)
create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, stageActions)

function mutate(name: string, callback: () -> ())
	ProjectStore.mutate(name, callback)
	project = ProjectStore.get()
	stageIds = ProjectStore.stageIds()
	renderCanvas()
	rebuildPreview()
	setStatus(`Working changes · {ProjectStore.workingChecksum()}`)
end

button(stageActions, "New", 62, function()
	mutate("Create Stagewright stage", function()
		selectedStageId = ProjectStore.createStage(nil)
	end)
	renderAll()
end)
button(stageActions, "Duplicate", 76, function()
	mutate("Duplicate Stagewright stage", function()
		selectedStageId = ProjectStore.createStage(selectedStageId)
	end)
	renderAll()
end)
button(stageActions, "Delete", 62, function()
	if not confirm(`delete_{selectedStageId}`, "Delete this stage and its graph data?") then
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
for _, move in { { "↑", -1 }, { "↓", 1 } } do
	button(stageActions, move[1] :: string, 36, function()
		mutate("Reorder Stagewright stages", function()
			ProjectStore.moveStage(selectedStageId, move[2] :: number)
		end)
		renderAll()
	end)
end
button(stageActions, "Focus Admin", 88, function()
	AuthoringArea.focus()
	setStatus("Focused the separate Stagewright admin authoring area.")
end)

local function renderStageList()
	for _, child in stageList:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	stageIds = ProjectStore.stageIds()
	for order, stageId in stageIds do
		local definition = project.stages[stageId]
		local stageButton = button(
			stageList,
			`{definition.name}  ·  {string.sub(stageId, -8)}`,
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
		stageButton.LayoutOrder = order
		stageButton.Size = UDim2.new(1, -16, 0, 34)
		stageButton.TextXAlignment = Enum.TextXAlignment.Left
		stageButton.BackgroundColor3 = if stageId == selectedStageId then COLORS.accent else COLORS.field
	end
	stageList.CanvasSize = UDim2.fromOffset(0, #stageIds * 39 + 16)
end

-- Graph page: stable node/edge IDs, directed connections, predicates, lanes, and priorities.
local graphPage = contentByMode.Graph
local graphList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -214),
}, graphPage) :: ScrollingFrame
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, graphList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
}, graphList)
local graphActions = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 1, -210),
	Size = UDim2.new(1, 0, 0, 210),
}, graphPage) :: Frame
create("UIGridLayout", {
	CellPadding = UDim2.fromOffset(5, 5),
	CellSize = UDim2.new(0.25, -9, 0, 27),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, graphActions)
create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8) }, graphActions)

local function actionField(placeholder: string): TextBox
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.BuilderSans,
		PlaceholderColor3 = COLORS.muted,
		PlaceholderText = placeholder,
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, graphActions) :: TextBox
	create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, field)
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, field)
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
end
for _, kind in { "Spawn", "Junction", "Goal" } do
	button(graphActions, `Add {kind}`, 112, function()
		mutate(`Add {kind} node`, function()
			newNode(kind)
		end)
		renderAll()
	end)
end
button(graphActions, "Connect From", 112, function()
	connectFromNodeId = selectedNodeId
	setStatus(if connectFromNodeId ~= nil then "Select a destination node." else "Select a node first.")
end)
button(graphActions, "Delete Node", 112, function()
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
button(graphActions, "Priority +", 112, function()
	local currentGraph = graph()
	if currentGraph == nil or selectedEdgeId == nil then
		return
	end
	mutate("Change edge priority", function()
		currentGraph.edges[selectedEdgeId :: string].priority += 1
	end)
	renderAll()
end)
button(graphActions, "Priority −", 112, function()
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
button(graphActions, "Set Fallback", 112, function()
	local currentGraph = graph()
	if currentGraph == nil or selectedEdgeId == nil then
		return
	end
	mutate("Set route fallback", function()
		currentGraph.edges[selectedEdgeId :: string].predicates = {}
	end)
	renderAll()
end)

local conditionKindButton: TextButton
conditionKindButton = button(graphActions, PREDICATE_KINDS[predicateKindIndex], 112, function()
	predicateKindIndex = (predicateKindIndex % #PREDICATE_KINDS) + 1
	conditionKindButton.Text = PREDICATE_KINDS[predicateKindIndex]
end)
local conditionKeyField = actionField("condition key / ID")
local conditionValueField = actionField("minimum / value")
local conditionMaximumField = actionField("maximum")

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

button(graphActions, "Add Condition", 112, function()
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
button(graphActions, "Remove Condition", 112, function()
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

local traceWaveField = actionField("trace wave (1)")
local traceTagsField = actionField("tags: Ground,Boss")
local traceFlagsField = actionField("flags: hard=true")
local traceCurrenciesField = actionField("currency: coins=500")
local traceUpgradesField = actionField("upgrades: range=4")
local traceUnlockedField = actionField("unlocked stage IDs")

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

button(graphActions, "Trace Route", 112, function()
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
	local trace = StageTrace.trace(currentGraph, spawnIds[1], {
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
button(graphActions, "Add Lane", 112, function()
	local currentGraph = graph()
	if currentGraph == nil or selectedEdgeId == nil then
		return
	end
	mutate("Add route lane", function()
		local profile = currentGraph.laneProfiles[currentGraph.edges[selectedEdgeId :: string].laneProfileId]
		table.insert(
			profile.offsets,
			(#profile.offsets % 2 == 1 and 1 or -1) * math.ceil(#profile.offsets / 2) * 3
		)
	end)
	renderAll()
end)

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
end

local function renderGraphList()
	for _, child in graphList:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local currentGraph = graph()
	if currentGraph == nil then
		return
	end
	local order = 0
	for nodeId, node in currentGraph.nodes do
		order += 1
		local nodeButton = button(
			graphList,
			`{node.kind} · {node.name} · {string.sub(nodeId, -8)}`,
			300,
			function()
				if connectFromNodeId ~= nil then
					local from = connectFromNodeId
					connectFromNodeId = nil
					mutate("Connect Stagewright graph nodes", function()
						connectNodes(from, nodeId)
					end)
				else
					selectedNodeId = nodeId
					local part = if previewFolder ~= nil
						then previewFolder:FindFirstChild(`Node_{node.name}`)
						else nil
					if part ~= nil then
						Selection:Set({ part })
					end
				end
				renderAll()
			end
		)
		nodeButton.LayoutOrder = order
		nodeButton.Size = UDim2.new(1, -16, 0, 30)
		nodeButton.BackgroundColor3 = if selectedNodeId == nodeId then COLORS.accent else COLORS.field
	end
	for edgeId, edge in currentGraph.edges do
		order += 1
		local edgeButton = button(
			graphList,
			`→ {string.sub(edge.fromNodeId, -6)} → {string.sub(edge.toNodeId, -6)} · P{edge.priority} · {#edge.predicates} condition(s)`,
			300,
			function()
				selectedEdgeId = edgeId
				tracedEdgeIds = {}
				renderAll()
			end
		)
		edgeButton.LayoutOrder = order
		edgeButton.Size = UDim2.new(1, -16, 0, 30)
		edgeButton.BackgroundColor3 = if selectedEdgeId == edgeId then COLORS.accent else COLORS.field
	end
	graphList.CanvasSize = UDim2.fromOffset(0, order * 34 + 16)
end

-- Validate/export page.
local validatePage = contentByMode.Validate
local issueList = create("ScrollingFrame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, 0, 1, -45),
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
	Position = UDim2.new(0, 0, 1, -41),
	Size = UDim2.new(1, 0, 0, 41),
}, validatePage) :: Frame
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, exportActions)
create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, exportActions)

local function renderIssues()
	for _, child in issueList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local issues = ProjectStore.validate()
	for order, issue in issues do
		local label = create("TextLabel", {
			BackgroundColor3 = COLORS.field,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSans,
			LayoutOrder = order,
			Size = UDim2.new(1, -16, 0, 42),
			Text = `[{issue.severity}] {issue.code} · {issue.message}`,
			TextColor3 = if issue.severity == "Error"
				then Color3.fromRGB(239, 105, 105)
				else Color3.fromRGB(245, 190, 78),
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, issueList) :: TextLabel
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, label)
	end
	if #issues == 0 then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Size = UDim2.new(1, -16, 0, 42),
			Text = "✓ No validation issues. Bundle is ready to export.",
			TextColor3 = Color3.fromRGB(102, 204, 132),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, issueList)
	end
	issueList.CanvasSize = UDim2.fromOffset(0, math.max(#issues, 1) * 46 + 16)
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
	local payload = Instance.new("StringValue")
	payload.Name = "StagewrightPayload"
	payload.Parent = model
	local runtime = Instance.new("StringValue")
	runtime.Name = "StagewrightRuntime"
	local schema = require(script.Shared.StageSchema)
	payload.Value = schema.encodeCanonical(ProjectStore.get())
	runtime.Value = schema.encodeCanonical(result.bundle)
	runtime.Parent = model
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

button(exportActions, "Validate", 80, function()
	renderIssues()
	setStatus("Validation refreshed.")
end)
button(exportActions, "Export Bundle", 110, exportBundle)
button(exportActions, "Import Selected", 110, function()
	local selected = Selection:Get()[1]
	local payload = if selected ~= nil then selected:FindFirstChild("StagewrightPayload", true) else nil
	if payload == nil or not payload:IsA("StringValue") then
		setStatus("Select a StagewrightBundle model first.", true)
		return
	end
	local ok, message = false, "Import failed"
	ProjectStore.mutate("Import Stagewright bundle", function()
		ok, message = ProjectStore.importPayload(payload.Value)
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
		modeButtons[mode].BackgroundColor3 = if mode == activeMode then COLORS.accent else COLORS.field
	end
	for brushId, brushButton in brushButtons do
		brushButton.BackgroundColor3 = if brushId == activeBrushId then COLORS.accent else COLORS.field
	end
	local current = stage()
	if current ~= nil then
		title.Text = `STAGEWRIGHT  ·  {current.name}  ·  {string.sub(current.id, -8)}`
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
	renderCanvas()
	renderStageList()
	renderGraphList()
	renderIssues()
	if activeMode == "Graph" then
		rebuildPreview()
	end
end
renderAll = rerenderAll

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and painting then
		painting = false
		ProjectStore.finish(true)
		setStatus(`Working changes · {ProjectStore.workingChecksum()}`)
	end
end)

local validateAction = plugin:CreatePluginAction(
	"StagewrightValidate",
	"Validate Stagewright",
	"Validate the current Stagewright project",
	"",
	true
)
validateAction.Triggered:Connect(function()
	activeMode = "Validate"
	widget.Enabled = true
	renderAll()
end)
local focusAction = plugin:CreatePluginAction(
	"StagewrightFocus",
	"Focus Stagewright",
	"Open the Stagewright editor",
	"",
	true
)
focusAction.Triggered:Connect(function()
	widget.Enabled = true
end)
local focusAdminAction = plugin:CreatePluginAction(
	"StagewrightFocusAdminArea",
	"Focus Stagewright Admin Area",
	"Focus the separate Stagewright authoring platform below the map",
	"",
	true
)
focusAdminAction.Triggered:Connect(function()
	AuthoringArea.focus()
end)
local duplicateAction = plugin:CreatePluginAction(
	"StagewrightDuplicateStage",
	"Duplicate Stage",
	"Duplicate the selected stage",
	"",
	true
)
duplicateAction.Triggered:Connect(function()
	mutate("Duplicate Stagewright stage", function()
		selectedStageId = ProjectStore.createStage(selectedStageId)
	end)
	renderAll()
end)

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

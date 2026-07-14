--!strict

local RouteOverview = {}
RouteOverview.__index = RouteOverview

type Theme = {
	background: Color3,
	panel: Color3,
	surface: Color3,
	field: Color3,
	hover: Color3,
	border: Color3,
	text: Color3,
	muted: Color3,
	accent: Color3,
	success: Color3,
	warning: Color3,
}

export type Callbacks = {
	selectNode: (string) -> (),
	selectEdge: (string) -> (),
}

export type Controller = typeof(setmetatable(
	{} :: {
		root: Frame,
		viewport: ScrollingFrame,
		canvas: Frame,
		zoomLabel: TextLabel,
		theme: Theme,
		callbacks: Callbacks,
		zoom: number,
		graph: any?,
		selectedNodeId: string?,
		selectedEdgeId: string?,
		tracedEdgeIds: { [string]: boolean },
		nodePositions: { [string]: Vector2 },
	},
	RouteOverview
))

local BASE_SIZE = Vector2.new(1_120, 720)
local NODE_SIZE = Vector2.new(128, 68)

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function controlButton(parent: Instance, text: string, theme: Theme, callback: () -> ()): TextButton
	local result = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.field,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Size = UDim2.fromOffset(34, 28),
		Text = text,
		TextColor3 = theme.text,
		TextSize = 12,
	}, parent) :: TextButton
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, result)
	create("UIStroke", { Color = theme.border, Thickness = 1 }, result)
	result.Activated:Connect(callback)
	return result
end

local function edgeLine(
	parent: Instance,
	from: Vector2,
	to: Vector2,
	color: Color3,
	thickness: number,
	zIndex: number,
	transparency: number?
): Frame
	local delta = to - from
	local center = (from + to) / 2
	return create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(center.X, center.Y),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		Size = UDim2.fromOffset(delta.Magnitude, thickness),
		ZIndex = zIndex,
	}, parent) :: Frame
end

local function nodeColor(kind: string): Color3
	if kind == "Spawn" then
		return Color3.fromRGB(41, 108, 69)
	elseif kind == "Goal" then
		return Color3.fromRGB(93, 55, 128)
	end
	return Color3.fromRGB(42, 78, 115)
end

local function topologyLayout(graph: any, nodeIds: { string }): { [string]: Vector2 }
	local outgoing: { [string]: { string } } = {}
	local depthByNode: { [string]: number } = {}
	local queue: { string } = {}
	for _, nodeId in nodeIds do
		outgoing[nodeId] = {}
		if graph.nodes[nodeId].kind == "Spawn" then
			depthByNode[nodeId] = 0
			table.insert(queue, nodeId)
		end
	end
	for _, edge in graph.edges do
		if outgoing[edge.fromNodeId] ~= nil and graph.nodes[edge.toNodeId] ~= nil then
			table.insert(outgoing[edge.fromNodeId], edge.toNodeId)
		end
	end
	for _, destinations in outgoing do
		table.sort(destinations)
	end
	local head = 1
	while queue[head] ~= nil do
		local nodeId = queue[head]
		head += 1
		local nextDepth = (depthByNode[nodeId] or 0) + 1
		for _, destinationId in outgoing[nodeId] do
			if depthByNode[destinationId] == nil then
				depthByNode[destinationId] = nextDepth
				table.insert(queue, destinationId)
			end
		end
	end
	local maximumDepth = 0
	for _, depth in depthByNode do
		maximumDepth = math.max(maximumDepth, depth)
	end
	for _, nodeId in nodeIds do
		if depthByNode[nodeId] == nil then
			maximumDepth += 1
			depthByNode[nodeId] = maximumDepth
		end
	end
	local columns: { [number]: { string } } = {}
	for _, nodeId in nodeIds do
		local depth = depthByNode[nodeId]
		columns[depth] = columns[depth] or {}
		table.insert(columns[depth], nodeId)
	end
	for _, column in columns do
		table.sort(column, function(leftId, rightId)
			local left = graph.nodes[leftId]
			local right = graph.nodes[rightId]
			if left.position.z ~= right.position.z then
				return left.position.z < right.position.z
			end
			if left.name ~= right.name then
				return left.name < right.name
			end
			return leftId < rightId
		end)
	end
	local result: { [string]: Vector2 } = {}
	local horizontalPadding = 92
	local verticalPadding = 76
	local usableWidth = BASE_SIZE.X - horizontalPadding * 2
	local usableHeight = BASE_SIZE.Y - verticalPadding * 2
	for depth, column in columns do
		local x = if maximumDepth == 0
			then BASE_SIZE.X / 2
			else horizontalPadding + usableWidth * (depth / maximumDepth)
		for index, nodeId in column do
			local y = verticalPadding + usableHeight * (index / (#column + 1))
			result[nodeId] = Vector2.new(x, y)
		end
	end
	return result
end

function RouteOverview.new(parent: Instance, theme: Theme, callbacks: Callbacks): Controller
	local root = create("Frame", {
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, parent) :: Frame
	local toolbar = create("Frame", {
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 42),
	}, root) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -220, 1, 0),
		Text = "ROUTE OVERVIEW",
		TextColor3 = theme.muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, toolbar)
	local controls = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(250, 30),
	}, toolbar) :: Frame
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, controls)
	local viewport = create("ScrollingFrame", {
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(BASE_SIZE.X, BASE_SIZE.Y),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 42),
		ScrollBarImageColor3 = theme.border,
		ScrollBarThickness = 7,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Size = UDim2.new(1, 0, 1, -42),
	}, root) :: ScrollingFrame
	local canvas = create("Frame", {
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(BASE_SIZE.X, BASE_SIZE.Y),
	}, viewport) :: Frame
	local controller: Controller = setmetatable({
		root = root,
		viewport = viewport,
		canvas = canvas,
		zoomLabel = nil :: any,
		theme = theme,
		callbacks = callbacks,
		zoom = 1,
		graph = nil,
		selectedNodeId = nil,
		selectedEdgeId = nil,
		tracedEdgeIds = {},
		nodePositions = {},
	}, RouteOverview)
	controlButton(controls, "−", theme, function()
		controller.zoom = math.max(0.65, controller.zoom - 0.15)
		controller:rerender()
	end)
	local zoomLabel = create("TextLabel", {
		BackgroundColor3 = theme.surface,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Size = UDim2.fromOffset(54, 28),
		Text = "100%",
		TextColor3 = theme.text,
		TextSize = 11,
	}, controls) :: TextLabel
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, zoomLabel)
	controller.zoomLabel = zoomLabel
	controlButton(controls, "+", theme, function()
		controller.zoom = math.min(1.6, controller.zoom + 0.15)
		controller:rerender()
	end)
	local centerButton = controlButton(controls, "Center", theme, function()
		controller:focusSelection()
	end)
	centerButton.Size = UDim2.fromOffset(54, 28)
	local fitButton = controlButton(controls, "Fit", theme, function()
		local available = viewport.AbsoluteWindowSize
		if available.X > 0 and available.Y > 0 then
			controller.zoom =
				math.clamp(math.min(available.X / BASE_SIZE.X, available.Y / BASE_SIZE.Y), 0.65, 1.3)
		end
		controller:rerender()
		controller.viewport.CanvasPosition = Vector2.zero
	end)
	fitButton.Size = UDim2.fromOffset(42, 28)
	return controller
end

function RouteOverview.render(
	self: Controller,
	graph: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean }
)
	self.graph = graph
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self:rerender()
end

function RouteOverview.rerender(self: Controller)
	for _, child in self.canvas:GetChildren() do
		child:Destroy()
	end
	local zoom = self.zoom
	local canvasSize = BASE_SIZE * zoom
	self.canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	self.viewport.CanvasSize = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	self.zoomLabel.Text = `{math.round(zoom * 100)}%`
	for x = 0, canvasSize.X, 40 * zoom do
		create("Frame", {
			BackgroundColor3 = self.theme.border,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(1, canvasSize.Y),
			ZIndex = 0,
		}, self.canvas)
	end
	for y = 0, canvasSize.Y, 40 * zoom do
		create("Frame", {
			BackgroundColor3 = self.theme.border,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(canvasSize.X, 1),
			ZIndex = 0,
		}, self.canvas)
	end
	local graph = self.graph
	if graph == nil then
		return
	end
	local nodeIds: { string } = {}
	for nodeId in graph.nodes do
		table.insert(nodeIds, nodeId)
	end
	table.sort(nodeIds)
	if #nodeIds == 0 then
		return
	end
	local layout = topologyLayout(graph, nodeIds)
	self.nodePositions = {}
	for _, nodeId in nodeIds do
		self.nodePositions[nodeId] = layout[nodeId] * zoom
	end
	local edgeIds: { string } = {}
	for edgeId in graph.edges do
		table.insert(edgeIds, edgeId)
	end
	table.sort(edgeIds)
	for _, edgeId in edgeIds do
		local edge = graph.edges[edgeId]
		local from = self.nodePositions[edge.fromNodeId]
		local to = self.nodePositions[edge.toNodeId]
		if from ~= nil and to ~= nil then
			local fullDelta = to - from
			local direction = if fullDelta.Magnitude > 0.001 then fullDelta.Unit else Vector2.new(1, 0)
			local start = from + direction * (NODE_SIZE.X * zoom * 0.43)
			local finish = to - direction * (NODE_SIZE.X * zoom * 0.43)
			local selected = self.selectedEdgeId == edgeId
			local traced = self.tracedEdgeIds[edgeId] == true
			local color = if selected
				then self.theme.accent
				elseif traced then self.theme.success
				elseif #edge.predicates > 0 then self.theme.warning
				else self.theme.muted
			edgeLine(self.canvas, start, finish, color, if selected then 5 else 3, 2)
			local delta = finish - start
			local hit = create("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset((start.X + finish.X) / 2, (start.Y + finish.Y) / 2),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				Size = UDim2.fromOffset(delta.Magnitude, 18),
				Text = "",
				ZIndex = 3,
			}, self.canvas) :: TextButton
			hit.Activated:Connect(function()
				self.callbacks.selectEdge(edgeId)
			end)
			local label = create("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset((start.X + finish.X) / 2, (start.Y + finish.Y) / 2 - 14),
				Size = UDim2.fromOffset(76, 21),
				Text = `P{edge.priority} · {if #edge.predicates == 0
					then "Fallback"
					else `{#edge.predicates} rule`}`,
				TextColor3 = color,
				TextSize = 9,
				ZIndex = 4,
			}, self.canvas) :: TextButton
			create("UICorner", { CornerRadius = UDim.new(0, 4) }, label)
			label.Activated:Connect(function()
				self.callbacks.selectEdge(edgeId)
			end)
		end
	end
	for _, nodeId in nodeIds do
		local node = graph.nodes[nodeId]
		local point = self.nodePositions[nodeId]
		local selected = self.selectedNodeId == nodeId
		local size = NODE_SIZE * zoom
		local nodeButton = create("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = nodeColor(node.kind),
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(point.X, point.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
			Text = `{node.kind}\n{node.name}\n{string.sub(nodeId, -8)}`,
			TextColor3 = self.theme.text,
			TextSize = math.clamp(11 * zoom, 9, 14),
			TextWrapped = true,
			ZIndex = 5,
		}, self.canvas) :: TextButton
		create("UICorner", { CornerRadius = UDim.new(0, 7) }, nodeButton)
		create("UIStroke", {
			Color = if selected then self.theme.accent else self.theme.border,
			Thickness = if selected then 2 else 1,
		}, nodeButton)
		nodeButton.Activated:Connect(function()
			self.callbacks.selectNode(nodeId)
		end)
	end
end

function RouteOverview.focusSelection(self: Controller)
	local nodeId = self.selectedNodeId
	if nodeId == nil and self.selectedEdgeId ~= nil and self.graph ~= nil then
		local edge = self.graph.edges[self.selectedEdgeId]
		nodeId = if edge ~= nil then edge.fromNodeId else nil
	end
	local point = if nodeId ~= nil then self.nodePositions[nodeId] else nil
	if point ~= nil then
		local window = self.viewport.AbsoluteWindowSize
		self.viewport.CanvasPosition =
			Vector2.new(math.max(point.X - window.X / 2, 0), math.max(point.Y - window.Y / 2, 0))
	end
end

return RouteOverview

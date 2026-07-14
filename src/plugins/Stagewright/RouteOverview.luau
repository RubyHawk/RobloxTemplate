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
		layoutSize: Vector2,
		minimapCanvas: Frame,
		lastWindowSize: Vector2,
	},
	RouteOverview
))

local BASE_SIZE = Vector2.new(920, 620)
local NODE_SIZE = Vector2.new(132, 72)

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
		ZIndex = 21,
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

local function topologyLayout(graph: any, nodeIds: { string }): ({ [string]: Vector2 }, Vector2)
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
	local horizontalPadding = 76
	local horizontalSpacing = 142
	local verticalPadding = 96
	local maximumRows = 1
	for _, column in columns do
		maximumRows = math.max(maximumRows, #column)
	end
	local layoutSize = Vector2.new(
		math.max(BASE_SIZE.X, horizontalPadding * 2 + maximumDepth * horizontalSpacing),
		math.max(BASE_SIZE.Y, verticalPadding * 2 + (maximumRows - 1) * 116)
	)
	local usableWidth = layoutSize.X - horizontalPadding * 2
	local usableHeight = layoutSize.Y - verticalPadding * 2
	local minimumZ = math.huge
	local maximumZ = -math.huge
	for _, nodeId in nodeIds do
		local z = graph.nodes[nodeId].position.z
		minimumZ = math.min(minimumZ, z)
		maximumZ = math.max(maximumZ, z)
	end
	local zRange = maximumZ - minimumZ
	for depth, column in columns do
		local x = if maximumDepth == 0
			then layoutSize.X / 2
			else horizontalPadding + usableWidth * (depth / maximumDepth)
		local previousY = -math.huge
		for index, nodeId in column do
			local node = graph.nodes[nodeId]
			local y = if zRange > 0.5
				then verticalPadding + usableHeight * (0.12 + 0.76 * ((node.position.z - minimumZ) / zRange))
				else verticalPadding + usableHeight * (index / (#column + 1))
			if previousY > -math.huge then
				y = math.max(y, previousY + NODE_SIZE.Y + 28)
			end
			y = math.min(y, layoutSize.Y - verticalPadding)
			previousY = y
			result[nodeId] = Vector2.new(x, y)
		end
	end
	return result, layoutSize
end

local function cubicPoint(
	start: Vector2,
	first: Vector2,
	second: Vector2,
	finish: Vector2,
	alpha: number
): Vector2
	local inverse = 1 - alpha
	return start * (inverse ^ 3)
		+ first * (3 * inverse ^ 2 * alpha)
		+ second * (3 * inverse * alpha ^ 2)
		+ finish * (alpha ^ 3)
end

local function drawEdge(
	parent: Instance,
	start: Vector2,
	finish: Vector2,
	color: Color3,
	thickness: number,
	selectEdge: () -> ()
): Vector2
	local horizontal = math.max(math.abs(finish.X - start.X) * 0.48, 42)
	local direction = if finish.X >= start.X then 1 else -1
	local first = start + Vector2.new(horizontal * direction, 0)
	local second = finish - Vector2.new(horizontal * direction, 0)
	local previous = start
	local midpoint = start
	for segment = 1, 14 do
		local alpha = segment / 14
		local point = cubicPoint(start, first, second, finish, alpha)
		edgeLine(parent, previous, point, color, thickness, 2)
		local delta = point - previous
		local hit = create("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((previous.X + point.X) / 2, (previous.Y + point.Y) / 2),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 16),
			Text = "",
			ZIndex = 3,
		}, parent) :: TextButton
		hit.Activated:Connect(selectEdge)
		if segment == 7 then
			midpoint = point
		end
		previous = point
	end
	create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(finish.X - 8 * direction, finish.Y),
		Size = UDim2.fromOffset(18, 18),
		Text = if direction > 0 then ">" else "<",
		TextColor3 = color,
		TextSize = 12,
		ZIndex = 4,
	}, parent).Activated:Connect(selectEdge)
	return midpoint
end

function RouteOverview.new(parent: Instance, theme: Theme, callbacks: Callbacks): Controller
	local root = create("Frame", {
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, parent) :: Frame
	local toolbar = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, root) :: Frame
	local controls = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(64, 158),
		ZIndex = 20,
	}, toolbar) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, controls)
	create("UIStroke", { Color = theme.border, Thickness = 1 }, controls)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, controls)
	create("UIPadding", { PaddingTop = UDim.new(0, 7) }, controls)
	local viewport = create("ScrollingFrame", {
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(BASE_SIZE.X, BASE_SIZE.Y),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 0),
		ScrollBarImageColor3 = theme.border,
		ScrollBarThickness = 7,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Size = UDim2.fromScale(1, 1),
	}, root) :: ScrollingFrame
	local canvas = create("Frame", {
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(BASE_SIZE.X, BASE_SIZE.Y),
	}, viewport) :: Frame
	local minimap = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(154, 92),
		ZIndex = 20,
	}, root) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, minimap)
	create("UIStroke", { Color = theme.border, Thickness = 1 }, minimap)
	local minimapCanvas = create("Frame", {
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 1, -14),
		ZIndex = 21,
	}, minimap) :: Frame
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
		layoutSize = BASE_SIZE,
		minimapCanvas = minimapCanvas,
		lastWindowSize = Vector2.zero,
	}, RouteOverview)
	controlButton(controls, "-", theme, function()
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
		ZIndex = 21,
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
	centerButton.Size = UDim2.fromOffset(50, 28)
	local fitButton = controlButton(controls, "Fit", theme, function()
		local available = viewport.AbsoluteWindowSize
		if available.X > 0 and available.Y > 0 then
			controller.zoom = math.clamp(
				math.min(available.X / controller.layoutSize.X, available.Y / controller.layoutSize.Y),
				0.55,
				1.35
			)
		end
		controller:rerender()
		controller.viewport.CanvasPosition = Vector2.zero
	end)
	fitButton.Size = UDim2.fromOffset(50, 28)
	viewport:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		local available = viewport.AbsoluteWindowSize
		if
			available.X < 200
			or available.Y < 160
			or (available - controller.lastWindowSize).Magnitude < 2
		then
			return
		end
		controller.lastWindowSize = available
		controller.zoom = math.clamp(
			math.min(available.X / controller.layoutSize.X, available.Y / controller.layoutSize.Y),
			0.65,
			1.35
		)
		controller:rerender()
		controller.viewport.CanvasPosition = Vector2.zero
	end)
	return controller
end

function RouteOverview.render(
	self: Controller,
	graph: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean }
)
	local graphChanged = self.graph ~= graph
	self.graph = graph
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self:rerender()
	if graphChanged then
		local available = self.viewport.AbsoluteWindowSize
		if available.X > 0 and available.Y > 0 then
			self.zoom = math.clamp(
				math.min(available.X / self.layoutSize.X, available.Y / self.layoutSize.Y),
				0.55,
				1.35
			)
			self:rerender()
			self.viewport.CanvasPosition = Vector2.zero
		end
	end
end

function RouteOverview.rerender(self: Controller)
	for _, child in self.canvas:GetChildren() do
		child:Destroy()
	end
	for _, child in self.minimapCanvas:GetChildren() do
		child:Destroy()
	end
	local graph = self.graph
	local nodeIds: { string } = {}
	if graph ~= nil then
		for nodeId in graph.nodes do
			table.insert(nodeIds, nodeId)
		end
		table.sort(nodeIds)
	end
	local layout = {} :: { [string]: Vector2 }
	if graph ~= nil and #nodeIds > 0 then
		layout, self.layoutSize = topologyLayout(graph, nodeIds)
	else
		self.layoutSize = BASE_SIZE
	end
	local zoom = self.zoom
	local canvasSize = self.layoutSize * zoom
	local window = self.viewport.AbsoluteWindowSize
	local canvasOffset = Vector2.new(
		math.max((window.X - canvasSize.X) * 0.5, 0),
		math.max((window.Y - canvasSize.Y) * 0.5, 0)
	)
	self.canvas.Position = UDim2.fromOffset(canvasOffset.X, canvasOffset.Y)
	self.canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	self.viewport.CanvasSize = UDim2.fromOffset(
		math.max(canvasSize.X + canvasOffset.X * 2, window.X),
		math.max(canvasSize.Y + canvasOffset.Y * 2, window.Y)
	)
	self.zoomLabel.Text = `{math.round(zoom * 100)}%`
	for x = 12, canvasSize.X, 32 * zoom do
		for y = 12, canvasSize.Y, 32 * zoom do
			create("Frame", {
				BackgroundColor3 = self.theme.border,
				BackgroundTransparency = 0.62,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(2, 2),
				ZIndex = 0,
			}, self.canvas)
		end
	end
	if graph == nil then
		return
	end
	if #nodeIds == 0 then
		return
	end
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
			local direction = if to.X >= from.X then 1 else -1
			local start = from + Vector2.new(NODE_SIZE.X * zoom * 0.5 * direction, 0)
			local finish = to - Vector2.new(NODE_SIZE.X * zoom * 0.5 * direction, 0)
			local selected = self.selectedEdgeId == edgeId
			local traced = self.tracedEdgeIds[edgeId] == true
			local color = if selected
				then self.theme.accent
				elseif traced then self.theme.success
				elseif #edge.predicates > 0 then self.theme.warning
				else self.theme.muted
			local midpoint = drawEdge(self.canvas, start, finish, color, if selected then 5 else 3, function()
				self.callbacks.selectEdge(edgeId)
			end)
			local profile = graph.laneProfiles[edge.laneProfileId]
			local lanes = if profile ~= nil and type(profile.offsets) == "table" then #profile.offsets else 1
			local showBadge = selected or #edge.predicates > 0 or edge.priority > 1 or lanes > 1
			local label = create("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(midpoint.X, midpoint.Y - 16),
				Size = UDim2.fromOffset(112, 22),
				Text = `P{edge.priority} / {lanes} lane{if lanes == 1 then "" else "s"}{if #edge.predicates
						> 0
					then " / Rule"
					else ""}`,
				TextColor3 = color,
				TextSize = 9,
				ZIndex = 4,
				Visible = showBadge,
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
			Text = "",
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
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(12 * zoom, 7 * zoom),
			Size = UDim2.new(1, -24 * zoom, 0, 16 * zoom),
			Text = string.upper(node.kind),
			TextColor3 = if node.kind == "Spawn"
				then self.theme.success
				elseif node.kind == "Goal" then Color3.fromRGB(215, 171, 255)
				else Color3.fromRGB(143, 194, 255),
			TextSize = math.clamp(9 * zoom, 8, 11),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(12 * zoom, 25 * zoom),
			Size = UDim2.new(1, -24 * zoom, 0, 19 * zoom),
			Text = node.name,
			TextColor3 = self.theme.text,
			TextSize = math.clamp(11 * zoom, 9, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(12 * zoom, 47 * zoom),
			Size = UDim2.new(1, -24 * zoom, 0, 15 * zoom),
			Text = `{string.sub(node.id, -8)} / {if node.kind == "Spawn"
				then "Entry"
				elseif node.kind == "Goal" then "Destination"
				else "Junction"}`,
			TextColor3 = self.theme.muted,
			TextSize = math.clamp(8 * zoom, 7, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		nodeButton.Activated:Connect(function()
			self.callbacks.selectNode(nodeId)
		end)
	end
	local minimapScale = math.min(132 / math.max(self.layoutSize.X, 1), 70 / math.max(self.layoutSize.Y, 1))
	for _, edgeId in edgeIds do
		local edge = graph.edges[edgeId]
		local from = layout[edge.fromNodeId]
		local to = layout[edge.toNodeId]
		if from ~= nil and to ~= nil then
			edgeLine(
				self.minimapCanvas,
				from * minimapScale + Vector2.new(4, 4),
				to * minimapScale + Vector2.new(4, 4),
				self.theme.muted,
				1,
				22
			)
		end
	end
	for _, nodeId in nodeIds do
		local node = graph.nodes[nodeId]
		local point = layout[nodeId] * minimapScale + Vector2.new(4, 4)
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = nodeColor(node.kind),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(point.X, point.Y),
			Size = UDim2.fromOffset(7, 5),
			ZIndex = 23,
		}, self.minimapCanvas)
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

--!strict

local UserInputService = game:GetService("UserInputService")

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
	connectNodes: (string, string) -> (),
}

export type Controller = typeof(setmetatable(
	{} :: {
		root: Frame,
		viewport: ScrollingFrame,
		canvas: Frame,
		theme: Theme,
		callbacks: Callbacks,
		zoom: number,
		showLanes: boolean,
		graph: any?,
		selectedNodeId: string?,
		selectedEdgeId: string?,
		tracedEdgeIds: { [string]: boolean },
		nodePositions: { [string]: Vector2 },
		layoutSize: Vector2,
		minimapCanvas: Frame,
		lastWindowSize: Vector2,
		connectionFromNodeId: string?,
		connectionPreview: Frame?,
		connections: { RBXScriptConnection },
	},
	RouteOverview
))

local BASE_SIZE = Vector2.new(1_120, 640)
local NODE_SIZE = Vector2.new(150, 88)

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
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

local function positionEdgeLine(segment: Frame, from: Vector2, to: Vector2)
	local delta = to - from
	segment.Position = UDim2.fromOffset((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5)
	segment.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	segment.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), segment.Size.Y.Offset)
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
	local horizontalSpacing = 168
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
				then verticalPadding + usableHeight * (0.24 + 0.52 * ((node.position.z - minimumZ) / zRange))
				else verticalPadding + usableHeight * (index / (#column + 1))
			if previousY > -math.huge then
				y = math.max(y, previousY + NODE_SIZE.Y + 34)
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
		Size = UDim2.fromOffset(210, 126),
		ZIndex = 20,
	}, root) :: Frame
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, minimap)
	create("UIStroke", { Color = theme.border, Thickness = 1 }, minimap)
	local minimapCanvas = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(35, 58, 39),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(9, 27),
		Size = UDim2.new(1, -18, 1, -36),
		ZIndex = 21,
	}, minimap) :: Frame
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(9, 5),
		Size = UDim2.new(1, -18, 0, 18),
		Text = "WORLD PREVIEW",
		TextColor3 = theme.muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, minimap)
	local controller: Controller = setmetatable({
		root = root,
		viewport = viewport,
		canvas = canvas,
		theme = theme,
		callbacks = callbacks,
		zoom = 1,
		showLanes = true,
		graph = nil,
		selectedNodeId = nil,
		selectedEdgeId = nil,
		tracedEdgeIds = {},
		nodePositions = {},
		layoutSize = BASE_SIZE,
		minimapCanvas = minimapCanvas,
		lastWindowSize = Vector2.zero,
		connectionFromNodeId = nil,
		connectionPreview = nil,
		connections = {},
	}, RouteOverview)
	table.insert(
		controller.connections,
		UserInputService.InputChanged:Connect(function(input)
			local fromNodeId = controller.connectionFromNodeId
			local from = if fromNodeId ~= nil then controller.nodePositions[fromNodeId] else nil
			if
				from == nil
				or input.UserInputType ~= Enum.UserInputType.MouseMovement
				or not controller.root.Visible
			then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
				- controller.canvas.AbsolutePosition
			local start = from + Vector2.new(NODE_SIZE.X * controller.zoom * 0.5, 0)
			if controller.connectionPreview == nil then
				controller.connectionPreview =
					edgeLine(controller.canvas, start, pointer, controller.theme.accent, 3, 4, 0.18)
			else
				positionEdgeLine(controller.connectionPreview, start, pointer)
			end
		end)
	)
	table.insert(
		controller.connections,
		UserInputService.InputEnded:Connect(function(input)
			local fromNodeId = controller.connectionFromNodeId
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or fromNodeId == nil then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
				- controller.canvas.AbsolutePosition
			local destinationId: string? = nil
			for nodeId, point in controller.nodePositions do
				if
					nodeId ~= fromNodeId
					and math.abs(pointer.X - point.X) <= NODE_SIZE.X * controller.zoom * 0.6
					and math.abs(pointer.Y - point.Y) <= NODE_SIZE.Y * controller.zoom * 0.72
				then
					destinationId = nodeId
					break
				end
			end
			controller:cancelInteraction()
			if destinationId ~= nil then
				controller.callbacks.connectNodes(fromNodeId, destinationId)
			else
				controller:rerender()
			end
		end)
	)
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
	self.connectionPreview = nil
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
			local profile = graph.laneProfiles[edge.laneProfileId]
			local lanes = if profile ~= nil and type(profile.offsets) == "table" then #profile.offsets else 1
			local color = if selected
				then self.theme.accent
				elseif traced then self.theme.success
				elseif #edge.predicates > 0 then self.theme.warning
				else self.theme.muted
			if selected and self.showLanes and lanes > 1 then
				local laneSpacing = math.clamp(6 * zoom, 4, 8)
				for laneIndex = 1, lanes do
					local offset = (laneIndex - (lanes + 1) * 0.5) * laneSpacing
					drawEdge(
						self.canvas,
						start + Vector2.new(0, offset),
						finish + Vector2.new(0, offset),
						Color3.fromRGB(172, 235, 246),
						1,
						function()
							self.callbacks.selectEdge(edgeId)
						end
					)
				end
			end
			local midpoint = drawEdge(self.canvas, start, finish, color, if selected then 5 else 3, function()
				self.callbacks.selectEdge(edgeId)
			end)
			if selected then
				local handleStart = midpoint + Vector2.new(-24 * zoom, 34 * zoom)
				local handleEnd = midpoint + Vector2.new(24 * zoom, -34 * zoom)
				edgeLine(self.canvas, handleStart, handleEnd, self.theme.accent, 1, 5, 0.18)
				for _, point in { handleStart, handleEnd } do
					local handle = create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = self.theme.accent,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(point.X, point.Y),
						Size = UDim2.fromOffset(10, 10),
						ZIndex = 6,
					}, self.canvas) :: Frame
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, handle)
				end
			end
			local showBadge = selected or #edge.predicates > 0 or edge.priority > 1 or lanes > 1
			local edgeLabel = if #edge.predicates > 0
				then `{lanes} lanes  •  P{edge.priority}`
				elseif edge.priority > 1 then "Fallback"
				else `{lanes} lane{if lanes == 1 then "" else "s"}  •  P{edge.priority}`
			local label = create("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(midpoint.X, midpoint.Y - 16),
				Size = UDim2.fromOffset(112, 22),
				Text = edgeLabel,
				TextColor3 = color,
				TextSize = 9,
				ZIndex = 4,
				Visible = showBadge,
			}, self.canvas) :: TextButton
			create("UICorner", { CornerRadius = UDim.new(0, 4) }, label)
			label.Activated:Connect(function()
				self.callbacks.selectEdge(edgeId)
			end)
			if #edge.predicates > 0 then
				local predicate = edge.predicates[1]
				local ruleText = if predicate.kind == "WaveRange"
					then `Wave ≥ {predicate.minimum or 1}`
					else predicate.kind
				local rule = create("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundColor3 = Color3.fromRGB(50, 34, 71),
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSansBold,
					Position = UDim2.fromOffset(finish.X, finish.Y - NODE_SIZE.Y * zoom * 0.52 - 8),
					Size = UDim2.fromOffset(92, 24),
					Text = ruleText,
					TextColor3 = Color3.fromRGB(218, 185, 255),
					TextSize = 10,
					ZIndex = 7,
				}, self.canvas) :: TextLabel
				create("UICorner", { CornerRadius = UDim.new(0, 6) }, rule)
				create("UIStroke", { Color = Color3.fromRGB(104, 66, 148), Thickness = 1 }, rule)
			end
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
			Size = UDim2.new(1, -24 * zoom, 0, 14 * zoom),
			Text = string.sub(node.id, -8),
			TextColor3 = self.theme.muted,
			TextSize = math.clamp(8 * zoom, 7, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		local nodePriority = 1
		local nodeLanes = 1
		for _, edge in graph.edges do
			if edge.fromNodeId == nodeId or edge.toNodeId == nodeId then
				nodePriority = edge.priority
				local profile = graph.laneProfiles[edge.laneProfileId]
				nodeLanes = if profile ~= nil then #profile.offsets else 1
				if edge.fromNodeId == nodeId then
					break
				end
			end
		end
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(12 * zoom, 65 * zoom),
			Size = UDim2.new(1, -24 * zoom, 0, 15 * zoom),
			Text = `P{nodePriority}                              {nodeLanes} lanes`,
			TextColor3 = self.theme.text,
			TextSize = math.clamp(8 * zoom, 7, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		local inputPort = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = self.theme.background,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(math.clamp(11 * zoom, 9, 14), math.clamp(11 * zoom, 9, 14)),
			ZIndex = 7,
		}, nodeButton) :: Frame
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, inputPort)
		create("UIStroke", { Color = self.theme.muted, Thickness = 2 }, inputPort)
		local outputPort = create("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = self.theme.background,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(math.clamp(13 * zoom, 10, 16), math.clamp(13 * zoom, 10, 16)),
			Text = "",
			ZIndex = 8,
		}, nodeButton) :: TextButton
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, outputPort)
		create("UIStroke", { Color = self.theme.accent, Thickness = 2 }, outputPort)
		outputPort.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.connectionFromNodeId = nodeId
				self.callbacks.selectNode(nodeId)
			end
		end)
		nodeButton.Activated:Connect(function()
			self.callbacks.selectNode(nodeId)
		end)
	end
	local minimumX = math.huge
	local maximumX = -math.huge
	local minimumZ = math.huge
	local maximumZ = -math.huge
	for _, nodeId in nodeIds do
		local position = graph.nodes[nodeId].position
		minimumX = math.min(minimumX, position.x)
		maximumX = math.max(maximumX, position.x)
		minimumZ = math.min(minimumZ, position.z)
		maximumZ = math.max(maximumZ, position.z)
	end
	local worldRangeX = math.max(maximumX - minimumX, 1)
	local worldRangeZ = math.max(maximumZ - minimumZ, 1)
	local function worldPreviewPoint(node: any): Vector2
		return Vector2.new(
			6 + ((node.position.x - minimumX) / worldRangeX) * 180,
			6 + ((node.position.z - minimumZ) / worldRangeZ) * 78
		)
	end
	for _, edgeId in edgeIds do
		local edge = graph.edges[edgeId]
		local fromNode = graph.nodes[edge.fromNodeId]
		local toNode = graph.nodes[edge.toNodeId]
		local from = if fromNode ~= nil then worldPreviewPoint(fromNode) else nil
		local to = if toNode ~= nil then worldPreviewPoint(toNode) else nil
		if from ~= nil and to ~= nil then
			edgeLine(self.minimapCanvas, from, to, Color3.fromRGB(163, 128, 83), 4, 22)
		end
	end
	for _, nodeId in nodeIds do
		local node = graph.nodes[nodeId]
		local point = worldPreviewPoint(node)
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

function RouteOverview.zoomBy(self: Controller, amount: number)
	self.zoom = math.clamp(self.zoom + amount, 0.55, 1.6)
	self:rerender()
end

function RouteOverview.fitToView(self: Controller)
	local available = self.viewport.AbsoluteWindowSize
	if available.X > 0 and available.Y > 0 then
		self.zoom =
			math.clamp(math.min(available.X / self.layoutSize.X, available.Y / self.layoutSize.Y), 0.55, 1.35)
	end
	self:rerender()
	self.viewport.CanvasPosition = Vector2.zero
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

function RouteOverview.cancelInteraction(self: Controller): boolean
	local canceled = self.connectionFromNodeId ~= nil or self.connectionPreview ~= nil
	self.connectionFromNodeId = nil
	if self.connectionPreview ~= nil then
		self.connectionPreview:Destroy()
		self.connectionPreview = nil
	end
	return canceled
end

function RouteOverview.destroy(self: Controller)
	self:cancelInteraction()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.root:Destroy()
end

return RouteOverview

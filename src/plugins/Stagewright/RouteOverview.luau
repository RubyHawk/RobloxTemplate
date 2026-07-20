--!strict

local UserInputService = game:GetService("UserInputService")

local RouteOverview = {}
RouteOverview.__index = RouteOverview

export type Tool = "Select" | "Pan" | "Connect" | "Split"

type HandleId = "Out" | "In"

type Vec3 = {
	x: number,
	y: number,
	z: number,
}

type CurveProjection = {
	worldForward: Vector2,
	worldSide: Vector2,
	screenForward: Vector2,
	screenSide: Vector2,
	scale: number,
}

type HandleDrag = {
	edgeId: string,
	handleId: HandleId,
	startPointer: Vector2,
	offset: Vec3,
	moved: boolean,
}

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
	beginSource: (string) -> boolean,
	connectNode: (string) -> boolean?,
	connectNodes: (string, string) -> boolean?,
	splitEdge: (string) -> boolean,
	moveHandle: (string, HandleId, Vec3) -> boolean,
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
		tool: Tool,
		graph: any?,
		selectedNodeId: string?,
		selectedEdgeId: string?,
		tracedEdgeIds: { [string]: boolean },
		nodePositions: { [string]: Vector2 },
		layoutSize: Vector2,
		minimapCanvas: Frame,
		lastWindowSize: Vector2,
		obstructionRight: number,
		obstructionBottom: number,
		topologySignature: string?,
		connectionFromNodeId: string?,
		connectionPreview: Frame?,
		suppressNodeActivationId: string?,
		suppressNodeActivationUntil: number,
		panInputStart: Vector2?,
		panCanvasStart: Vector2?,
		handleDrag: HandleDrag?,
		lastHandleRenderAt: number,
		connections: { RBXScriptConnection },
	},
	RouteOverview
))

local BASE_SIZE = Vector2.new(1_120, 640)
local NODE_SIZE = Vector2.new(142, 80)
local MINIMAP_SIZE = Vector2.new(204, 118)
local MIN_ZOOM = 0.35
local MAX_FIT_ZOOM = 1.35
local HORIZONTAL_PADDING = math.ceil(NODE_SIZE.X * 0.5) + 34
local HORIZONTAL_SPACING = 158
local VERTICAL_PADDING = math.ceil(NODE_SIZE.Y * 0.5) + 48
local ROW_SPACING = NODE_SIZE.Y + 30
local HANDLE_DRAG_THRESHOLD = 3
local HANDLE_RENDER_INTERVAL = 0.04

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function isVisible(gui: GuiObject): boolean
	local current: Instance? = gui
	while current ~= nil do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
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

local function topologySignature(graph: any?): string
	if graph == nil then
		return "none"
	end
	local nodeIds: { string } = {}
	for nodeId in graph.nodes do
		table.insert(nodeIds, nodeId)
	end
	table.sort(nodeIds)
	local edgeIds: { string } = {}
	for edgeId in graph.edges do
		table.insert(edgeIds, edgeId)
	end
	table.sort(edgeIds)
	local parts = { tostring(graph.id or "") }
	for _, nodeId in nodeIds do
		local node = graph.nodes[nodeId]
		table.insert(
			parts,
			`N:{nodeId}:{tostring(node.kind)}:{tostring(node.name)}:{tostring(node.position.z)}`
		)
	end
	for _, edgeId in edgeIds do
		local edge = graph.edges[edgeId]
		table.insert(parts, `E:{edgeId}:{tostring(edge.fromNodeId)}:{tostring(edge.toNodeId)}`)
	end
	return table.concat(parts, "|")
end

local function safeWindowSize(self: Controller): Vector2
	local window = self.viewport.AbsoluteWindowSize
	return Vector2.new(
		math.max(window.X - self.obstructionRight, 0),
		math.max(window.Y - self.obstructionBottom, 0)
	)
end

local function fitZoom(self: Controller): number?
	local available = safeWindowSize(self)
	if available.X < 1 or available.Y < 1 then
		return nil
	end
	return math.clamp(
		math.min(available.X / self.layoutSize.X, available.Y / self.layoutSize.Y),
		MIN_ZOOM,
		MAX_FIT_ZOOM
	)
end

local function edgeLess(left: any, right: any): boolean
	if left.priority == right.priority then
		return left.id < right.id
	end
	return left.priority < right.priority
end

local function summaryEdge(graph: any, nodeId: string): any?
	local outgoing = {}
	local incoming = {}
	for _, edge in graph.edges do
		if edge.fromNodeId == nodeId then
			table.insert(outgoing, edge)
		elseif edge.toNodeId == nodeId then
			table.insert(incoming, edge)
		end
	end
	table.sort(outgoing, edgeLess)
	table.sort(incoming, edgeLess)
	return outgoing[1] or incoming[1]
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
	local maximumRows = 1
	for _, column in columns do
		maximumRows = math.max(maximumRows, #column)
	end
	local layoutSize = Vector2.new(
		math.max(BASE_SIZE.X, HORIZONTAL_PADDING * 2 + maximumDepth * HORIZONTAL_SPACING),
		math.max(BASE_SIZE.Y, VERTICAL_PADDING * 2 + (maximumRows - 1) * ROW_SPACING)
	)
	local usableWidth = layoutSize.X - HORIZONTAL_PADDING * 2
	local usableHeight = layoutSize.Y - VERTICAL_PADDING * 2
	for depth, column in columns do
		local x = if maximumDepth == 0
			then layoutSize.X / 2
			else HORIZONTAL_PADDING + usableWidth * (depth / maximumDepth)
		for index, nodeId in column do
			local alpha = if #column == 1 then 0.5 else (index - 1) / (#column - 1)
			result[nodeId] = Vector2.new(x, VERTICAL_PADDING + usableHeight * alpha)
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

local function curveProjection(fromNode: any, toNode: any, start: Vector2, finish: Vector2): CurveProjection
	local worldDelta =
		Vector2.new(toNode.position.x - fromNode.position.x, toNode.position.z - fromNode.position.z)
	local screenDelta = finish - start
	local worldLength = worldDelta.Magnitude
	local screenLength = screenDelta.Magnitude
	local worldForward = if worldLength > 0.001 then worldDelta / worldLength else Vector2.new(1, 0)
	local screenForward = if screenLength > 0.001 then screenDelta / screenLength else Vector2.new(1, 0)
	return {
		worldForward = worldForward,
		worldSide = Vector2.new(-worldForward.Y, worldForward.X),
		screenForward = screenForward,
		screenSide = Vector2.new(-screenForward.Y, screenForward.X),
		scale = if worldLength > 0.001
			then math.max(screenLength / worldLength, 0.001)
			else math.max(screenLength / 64, 0.001),
	}
end

local function projectOffset(projection: CurveProjection, offset: any): Vector2
	local worldOffset = Vector2.new(offset.x, offset.z)
	local forward = worldOffset:Dot(projection.worldForward)
	local side = worldOffset:Dot(projection.worldSide)
	return projection.screenForward * (forward * projection.scale)
		+ projection.screenSide * (side * projection.scale)
end

local function unprojectOffset(projection: CurveProjection, screenOffset: Vector2, y: number): Vec3
	local forward = screenOffset:Dot(projection.screenForward) / projection.scale
	local side = screenOffset:Dot(projection.screenSide) / projection.scale
	local worldOffset = projection.worldForward * forward + projection.worldSide * side
	return {
		x = worldOffset.X,
		y = y,
		z = worldOffset.Y,
	}
end

local function edgeGeometry(
	fromNode: any,
	toNode: any,
	edge: any,
	start: Vector2,
	finish: Vector2,
	drag: HandleDrag?
): (Vector2, Vector2)
	local projection = curveProjection(fromNode, toNode, start, finish)
	local outOffset = edge.outHandleOffset
	local inOffset = edge.inHandleOffset
	if drag ~= nil and drag.edgeId == edge.id then
		if drag.handleId == "Out" then
			outOffset = drag.offset
		else
			inOffset = drag.offset
		end
	end
	return start + projectOffset(projection, outOffset), finish + projectOffset(projection, inOffset)
end

local function drawEdge(
	parent: Instance,
	start: Vector2,
	first: Vector2,
	second: Vector2,
	finish: Vector2,
	color: Color3,
	thickness: number,
	selectEdge: () -> ()
): Vector2
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
	local finishTangent = finish - second
	if finishTangent.Magnitude < 0.001 then
		finishTangent = finish - start
	end
	local tangentDirection = if finishTangent.Magnitude > 0.001 then finishTangent.Unit else Vector2.new(1, 0)
	create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(finish.X - tangentDirection.X * 8, finish.Y - tangentDirection.Y * 8),
		Rotation = math.deg(math.atan2(tangentDirection.Y, tangentDirection.X)),
		Size = UDim2.fromOffset(18, 18),
		Text = ">",
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
		ScrollingEnabled = false,
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
		Size = UDim2.fromOffset(MINIMAP_SIZE.X, MINIMAP_SIZE.Y),
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
		tool = "Select",
		graph = nil,
		selectedNodeId = nil,
		selectedEdgeId = nil,
		tracedEdgeIds = {},
		nodePositions = {},
		layoutSize = BASE_SIZE,
		minimapCanvas = minimapCanvas,
		lastWindowSize = Vector2.zero,
		obstructionRight = 0,
		obstructionBottom = 0,
		topologySignature = nil,
		connectionFromNodeId = nil,
		connectionPreview = nil,
		suppressNodeActivationId = nil,
		suppressNodeActivationUntil = 0,
		panInputStart = nil,
		panCanvasStart = nil,
		handleDrag = nil,
		lastHandleRenderAt = 0,
		connections = {},
	}, RouteOverview)
	table.insert(
		controller.connections,
		UserInputService.InputBegan:Connect(function(input)
			if
				controller.tool ~= "Pan"
				or input.UserInputType ~= Enum.UserInputType.MouseButton1
				or not isVisible(controller.root)
			then
				return
			end
			local point = Vector2.new(input.Position.X, input.Position.Y) - controller.root.AbsolutePosition
			local safeWindow = safeWindowSize(controller)
			if point.X < 0 or point.Y < 0 or point.X > safeWindow.X or point.Y > safeWindow.Y then
				return
			end
			controller.panInputStart = Vector2.new(input.Position.X, input.Position.Y)
			controller.panCanvasStart = controller.viewport.CanvasPosition
		end)
	)
	table.insert(
		controller.connections,
		UserInputService.InputChanged:Connect(function(input)
			local handleDrag = controller.handleDrag
			if handleDrag ~= nil and input.UserInputType == Enum.UserInputType.MouseMovement then
				local absolutePointer = Vector2.new(input.Position.X, input.Position.Y)
				if
					handleDrag.moved
					or (absolutePointer - handleDrag.startPointer).Magnitude >= HANDLE_DRAG_THRESHOLD
				then
					handleDrag.moved = true
					local offset = controller:handleOffsetAt(handleDrag, absolutePointer)
					if offset ~= nil then
						handleDrag.offset = offset
						local now = os.clock()
						if now - controller.lastHandleRenderAt >= HANDLE_RENDER_INTERVAL then
							controller.lastHandleRenderAt = now
							controller:rerender()
						end
					end
				end
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local panInputStart = controller.panInputStart
				local panCanvasStart = controller.panCanvasStart
				if panInputStart ~= nil and panCanvasStart ~= nil then
					local pointer = Vector2.new(input.Position.X, input.Position.Y)
					local delta = pointer - panInputStart
					controller.viewport.CanvasPosition = Vector2.new(
						math.max(panCanvasStart.X - delta.X, 0),
						math.max(panCanvasStart.Y - delta.Y, 0)
					)
					return
				end
			end
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
			local handleDrag = controller.handleDrag
			if input.UserInputType == Enum.UserInputType.MouseButton1 and handleDrag ~= nil then
				local absolutePointer = Vector2.new(input.Position.X, input.Position.Y)
				local moved = handleDrag.moved
					or (absolutePointer - handleDrag.startPointer).Magnitude >= HANDLE_DRAG_THRESHOLD
				local offset = if moved then controller:handleOffsetAt(handleDrag, absolutePointer) else nil
				controller.handleDrag = nil
				controller.lastHandleRenderAt = 0
				if offset ~= nil then
					controller.callbacks.moveHandle(handleDrag.edgeId, handleDrag.handleId, offset)
				end
				controller:rerender()
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 and controller.panInputStart ~= nil then
				controller.panInputStart = nil
				controller.panCanvasStart = nil
				return
			end
			local fromNodeId = controller.connectionFromNodeId
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				or fromNodeId == nil
				or not isVisible(controller.root)
			then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
				- controller.canvas.AbsolutePosition
			local destinationId: string? = nil
			local destinationDistance = math.huge
			for nodeId, point in controller.nodePositions do
				local destination = if controller.graph ~= nil then controller.graph.nodes[nodeId] else nil
				if
					nodeId ~= fromNodeId
					and destination ~= nil
					and destination.kind ~= "Spawn"
					and math.abs(pointer.X - point.X) <= NODE_SIZE.X * controller.zoom * 0.6
					and math.abs(pointer.Y - point.Y) <= NODE_SIZE.Y * controller.zoom * 0.72
				then
					local distance = (pointer - point).Magnitude
					if
						distance < destinationDistance
						or (
							distance == destinationDistance
							and (destinationId == nil or nodeId < destinationId)
						)
					then
						destinationId = nodeId
						destinationDistance = distance
					end
				end
			end
			controller:cancelInteraction()
			if destinationId ~= nil then
				controller.suppressNodeActivationId = destinationId
				controller.suppressNodeActivationUntil = os.clock() + 0.25
				controller.callbacks.connectNodes(fromNodeId, destinationId)
			else
				controller:rerender()
			end
		end)
	)
	viewport:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		local window = viewport.AbsoluteWindowSize
		local available = safeWindowSize(controller)
		if available.X < 200 or available.Y < 160 or (window - controller.lastWindowSize).Magnitude < 2 then
			return
		end
		controller.lastWindowSize = window
		controller.zoom = fitZoom(controller) or controller.zoom
		controller:rerender()
		controller.viewport.CanvasPosition = Vector2.zero
	end)
	return controller
end

function RouteOverview.handleOffsetAt(self: Controller, drag: HandleDrag, absolutePointer: Vector2): Vec3?
	local graph = self.graph
	local edge = if graph ~= nil then graph.edges[drag.edgeId] else nil
	if graph == nil or edge == nil then
		return nil
	end
	local fromNode = graph.nodes[edge.fromNodeId]
	local toNode = graph.nodes[edge.toNodeId]
	local from = self.nodePositions[edge.fromNodeId]
	local to = self.nodePositions[edge.toNodeId]
	if fromNode == nil or toNode == nil or from == nil or to == nil then
		return nil
	end
	local direction = if to.X >= from.X then 1 else -1
	local start = from + Vector2.new(NODE_SIZE.X * self.zoom * 0.5 * direction, 0)
	local finish = to - Vector2.new(NODE_SIZE.X * self.zoom * 0.5 * direction, 0)
	local projection = curveProjection(fromNode, toNode, start, finish)
	local anchor = if drag.handleId == "Out" then start else finish
	local currentOffset = if drag.handleId == "Out" then edge.outHandleOffset else edge.inHandleOffset
	local canvasPointer = absolutePointer - self.canvas.AbsolutePosition
	return unprojectOffset(projection, canvasPointer - anchor, currentOffset.y)
end

function RouteOverview.beginHandleDrag(
	self: Controller,
	edgeId: string,
	handleId: HandleId,
	input: InputObject
)
	if self.tool ~= "Select" or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local edge = if self.graph ~= nil then self.graph.edges[edgeId] else nil
	if edge == nil or self.selectedEdgeId ~= edgeId then
		return
	end
	if self.connectionPreview ~= nil then
		self.connectionPreview:Destroy()
		self.connectionPreview = nil
	end
	self.connectionFromNodeId = nil
	local sourceOffset = if handleId == "Out" then edge.outHandleOffset else edge.inHandleOffset
	local pointer = Vector2.new(input.Position.X, input.Position.Y)
	self.handleDrag = {
		edgeId = edgeId,
		handleId = handleId,
		startPointer = pointer,
		offset = {
			x = sourceOffset.x,
			y = sourceOffset.y,
			z = sourceOffset.z,
		},
		moved = false,
	}
	self.lastHandleRenderAt = 0
end

function RouteOverview.render(
	self: Controller,
	graph: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean }
)
	local nextTopologySignature = topologySignature(graph)
	local topologyChanged = self.topologySignature ~= nextTopologySignature
	self.graph = graph
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self.topologySignature = nextTopologySignature
	self:rerender()
	if topologyChanged then
		local zoom = fitZoom(self)
		if zoom ~= nil then
			self.zoom = zoom
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
	local safeWindow = safeWindowSize(self)
	local canvasOffset = Vector2.new(
		math.max((safeWindow.X - canvasSize.X) * 0.5, 0),
		math.max((safeWindow.Y - canvasSize.Y) * 0.5, 0)
	)
	self.canvas.Position = UDim2.fromOffset(canvasOffset.X, canvasOffset.Y)
	self.canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	local overflowFocusPadding = Vector2.new(
		if canvasSize.X > safeWindow.X then safeWindow.X * 0.5 else 0,
		if canvasSize.Y > safeWindow.Y then safeWindow.Y * 0.5 else 0
	)
	self.viewport.CanvasSize = UDim2.fromOffset(
		math.max(canvasSize.X + canvasOffset.X * 2 + self.obstructionRight + overflowFocusPadding.X, window.X),
		math.max(
			canvasSize.Y + canvasOffset.Y * 2 + self.obstructionBottom + overflowFocusPadding.Y,
			window.Y
		)
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
	self.nodePositions = {}
	if graph == nil then
		return
	end
	if #nodeIds == 0 then
		return
	end
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
		local fromNode = graph.nodes[edge.fromNodeId]
		local toNode = graph.nodes[edge.toNodeId]
		local from = self.nodePositions[edge.fromNodeId]
		local to = self.nodePositions[edge.toNodeId]
		if fromNode ~= nil and toNode ~= nil and from ~= nil and to ~= nil then
			local function selectThisEdge()
				if self.tool == "Split" then
					self.callbacks.splitEdge(edgeId)
				elseif self.tool == "Select" then
					self.callbacks.selectEdge(edgeId)
				end
			end
			local direction = if to.X >= from.X then 1 else -1
			local start = from + Vector2.new(NODE_SIZE.X * zoom * 0.5 * direction, 0)
			local finish = to - Vector2.new(NODE_SIZE.X * zoom * 0.5 * direction, 0)
			local first, second = edgeGeometry(fromNode, toNode, edge, start, finish, self.handleDrag)
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
					local laneOffset = Vector2.new(0, offset)
					drawEdge(
						self.canvas,
						start + laneOffset,
						first + laneOffset,
						second + laneOffset,
						finish + laneOffset,
						Color3.fromRGB(172, 235, 246),
						1,
						selectThisEdge
					)
				end
			end
			local midpoint = drawEdge(
				self.canvas,
				start,
				first,
				second,
				finish,
				color,
				if selected then 5 else 3,
				selectThisEdge
			)
			if selected then
				edgeLine(self.canvas, start, first, self.theme.accent, 1, 5, 0.18)
				edgeLine(self.canvas, second, finish, self.theme.accent, 1, 5, 0.18)
				local function createHandle(point: Vector2, handleId: HandleId)
					local handle = create("TextButton", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(point.X, point.Y),
						Size = UDim2.fromOffset(24, 24),
						Text = "",
						ZIndex = 9,
					}, self.canvas) :: TextButton
					local dot = create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = self.theme.accent,
						BorderSizePixel = 0,
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(12, 12),
						ZIndex = 10,
					}, handle) :: Frame
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
					create("UIStroke", { Color = self.theme.text, Thickness = 1 }, dot)
					handle.InputBegan:Connect(function(input)
						self:beginHandleDrag(edgeId, handleId, input)
					end)
				end
				createHandle(first, "Out")
				createHandle(second, "In")
			end
			local showBadge = selected or edge.priority > 1
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
				selectThisEdge()
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
		local primaryEdge = summaryEdge(graph, nodeId)
		local profile = if primaryEdge ~= nil then graph.laneProfiles[primaryEdge.laneProfileId] else nil
		local nodePriority = if primaryEdge ~= nil then primaryEdge.priority else nil
		local nodeLanes = if profile ~= nil then #profile.offsets else nil
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.fromOffset(12 * zoom, 64 * zoom),
			Size = UDim2.new(0.5, -12 * zoom, 0, math.max(12 * zoom, 8)),
			Text = if nodePriority ~= nil then `P{nodePriority}` else "P-",
			TextColor3 = self.theme.text,
			TextSize = math.clamp(8 * zoom, 7, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, nodeButton)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Position = UDim2.new(0.5, 0, 0, 64 * zoom),
			Size = UDim2.new(0.5, -12 * zoom, 0, math.max(12 * zoom, 8)),
			Text = if nodeLanes ~= nil then `{nodeLanes} lane{if nodeLanes == 1 then "" else "s"}` else "-",
			TextColor3 = self.theme.text,
			TextSize = math.clamp(8 * zoom, 7, 10),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 6,
		}, nodeButton)
		if node.kind ~= "Spawn" then
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
		end
		if node.kind ~= "Goal" then
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
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				if self.tool == "Connect" then
					if self.callbacks.beginSource(nodeId) then
						self.connectionFromNodeId = nodeId
					else
						self:cancelInteraction()
					end
				elseif self.tool == "Select" then
					self.connectionFromNodeId = nodeId
					self.callbacks.selectNode(nodeId)
				end
			end)
		end
		nodeButton.Activated:Connect(function()
			if self.suppressNodeActivationId == nodeId and os.clock() <= self.suppressNodeActivationUntil then
				self.suppressNodeActivationId = nil
				self.suppressNodeActivationUntil = 0
				return
			end
			if self.tool == "Connect" then
				if self.callbacks.connectNode(nodeId) == false then
					self.connectionFromNodeId = nodeId
				end
			elseif self.tool == "Select" then
				self.callbacks.selectNode(nodeId)
			end
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
	local minimapSize = self.minimapCanvas.AbsoluteSize
	if minimapSize.X < 1 or minimapSize.Y < 1 then
		minimapSize = Vector2.new(MINIMAP_SIZE.X - 18, MINIMAP_SIZE.Y - 36)
	end
	local minimapPadding = 6
	local function worldPreviewPoint(node: any): Vector2
		return Vector2.new(
			minimapPadding
				+ ((node.position.x - minimumX) / worldRangeX)
					* math.max(minimapSize.X - minimapPadding * 2, 1),
			minimapPadding
				+ ((node.position.z - minimumZ) / worldRangeZ)
					* math.max(minimapSize.Y - minimapPadding * 2, 1)
		)
	end
	for _, edgeId in edgeIds do
		local edge = graph.edges[edgeId]
		local fromNode = graph.nodes[edge.fromNodeId]
		local toNode = graph.nodes[edge.toNodeId]
		local from = if fromNode ~= nil then worldPreviewPoint(fromNode) else nil
		local to = if toNode ~= nil then worldPreviewPoint(toNode) else nil
		if from ~= nil and to ~= nil then
			local selected = self.selectedEdgeId == edgeId
			local traced = self.tracedEdgeIds[edgeId] == true
			edgeLine(
				self.minimapCanvas,
				from,
				to,
				if selected
					then self.theme.accent
					elseif traced then self.theme.success
					else Color3.fromRGB(163, 128, 83),
				if selected or traced then 3 else 2,
				22
			)
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
			Size = UDim2.fromOffset(if self.selectedNodeId == nodeId then 7 else 5, 5),
			ZIndex = 23,
		}, self.minimapCanvas)
	end
end

function RouteOverview.setTool(self: Controller, tool: Tool)
	if self.tool == tool then
		return
	end
	self:cancelInteraction()
	self.tool = tool
end

function RouteOverview.beginConnection(self: Controller, nodeId: string): boolean
	local node = if self.graph ~= nil then self.graph.nodes[nodeId] else nil
	if node == nil or node.kind == "Goal" then
		return false
	end
	self:cancelInteraction()
	self.tool = "Connect"
	self.connectionFromNodeId = nodeId
	return true
end

function RouteOverview.setObstructions(self: Controller, right: number, bottom: number)
	local resolvedRight = if right == right and right < math.huge then math.max(right, 0) else 0
	local resolvedBottom = if bottom == bottom and bottom < math.huge then math.max(bottom, 0) else 0
	if self.obstructionRight == resolvedRight and self.obstructionBottom == resolvedBottom then
		return
	end
	local canvasPosition = self.viewport.CanvasPosition
	self.obstructionRight = resolvedRight
	self.obstructionBottom = resolvedBottom
	self:rerender()
	self.viewport.CanvasPosition = canvasPosition
end

function RouteOverview.zoomBy(self: Controller, amount: number)
	local minimumZoom = fitZoom(self) or MIN_ZOOM
	self.zoom = math.clamp(self.zoom + amount, minimumZoom, 1.6)
	self:rerender()
end

function RouteOverview.fitToView(self: Controller)
	self.zoom = fitZoom(self) or self.zoom
	self:rerender()
	self.viewport.CanvasPosition = Vector2.zero
end

function RouteOverview.focusSelection(self: Controller)
	local point = if self.selectedNodeId ~= nil then self.nodePositions[self.selectedNodeId] else nil
	if point == nil and self.selectedEdgeId ~= nil and self.graph ~= nil then
		local edge = self.graph.edges[self.selectedEdgeId]
		local from = if edge ~= nil then self.nodePositions[edge.fromNodeId] else nil
		local to = if edge ~= nil then self.nodePositions[edge.toNodeId] else nil
		if from ~= nil and to ~= nil then
			point = (from + to) * 0.5
		else
			point = from or to
		end
	end
	if point ~= nil then
		local safeWindow = safeWindowSize(self)
		local canvasOffset = Vector2.new(self.canvas.Position.X.Offset, self.canvas.Position.Y.Offset)
		local target = canvasOffset + point
		self.viewport.CanvasPosition = Vector2.new(
			math.max(target.X - safeWindow.X * 0.5, 0),
			math.max(target.Y - safeWindow.Y * 0.5, 0)
		)
	end
end

function RouteOverview.cancelInteraction(self: Controller): boolean
	local hadHandleDrag = self.handleDrag ~= nil
	local canceled = self.connectionFromNodeId ~= nil
		or self.connectionPreview ~= nil
		or self.panInputStart ~= nil
		or hadHandleDrag
	self.connectionFromNodeId = nil
	self.panInputStart = nil
	self.panCanvasStart = nil
	self.handleDrag = nil
	self.lastHandleRenderAt = 0
	if self.connectionPreview ~= nil then
		self.connectionPreview:Destroy()
		self.connectionPreview = nil
	end
	if hadHandleDrag and self.root.Parent ~= nil then
		self:rerender()
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

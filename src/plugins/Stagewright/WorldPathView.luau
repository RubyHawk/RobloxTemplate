--!strict

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CanvasTransform = require(script.Parent.Interaction.CanvasTransform)
local HitTest = require(script.Parent.Interaction.HitTest)
local PointerDrag = require(script.Parent.Interaction.PointerDrag)

export type Theme = {
	background: Color3,
	panel: Color3,
	surface: Color3,
	field: Color3,
	hover: Color3,
	border: Color3,
	borderStrong: Color3,
	text: Color3,
	muted: Color3,
	accent: Color3,
	success: Color3,
	warning: Color3,
	danger: Color3,
	ground: Color3,
	void: Color3,
}

export type Callbacks = {
	cancelInteraction: () -> (),
	selectNode: (string) -> (),
	selectEdge: (string) -> (),
	moveNode: (string, any, boolean) -> (),
	moveHandle: (string, string, any, boolean) -> (),
	setLanes: (string, number) -> (),
	focusWorld: (string?) -> (),
	testSegment: (string) -> (),
}

export type Controller = {
	root: Frame,
	theme: Theme,
	callbacks: Callbacks,
	stage: any?,
	graph: any?,
	preview: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean },
	transform: CanvasTransform.Transform?,
	transformStageId: string?,
	canvas: Frame?,
	assetPreview: boolean,
	showLanes: boolean,
	showBuildMask: boolean,
	showConflicts: boolean,
	pointerState: PointerDrag.State,
	hitPrimitives: { HitTest.Primitive },
	hitBlockers: { GuiObject },
	touchPointerIds: { [InputObject]: string },
	nextTouchPointerId: number,
	lastDragRenderAt: number,
	lastDragValue: any?,
	panLastScreen: Vector2?,
	connections: { RBXScriptConnection },
	render: (Controller, any?, any?, any?, string?, string?, { [string]: boolean }) -> (),
	rerender: (Controller) -> (),
	fitToView: (Controller) -> (),
	cancelInteraction: (Controller) -> boolean,
	destroy: (Controller) -> (),
}

local WorldPathView = {}
WorldPathView.__index = WorldPathView

local GRAVEL = Color3.fromRGB(153, 121, 80)
local GRAVEL_DARK = Color3.fromRGB(90, 78, 65)
local GRAVEL_LIGHT = Color3.fromRGB(205, 181, 139)
local LANE = Color3.fromRGB(239, 236, 224)
local SELECTED = Color3.fromRGB(69, 207, 230)
local WATER = Color3.fromRGB(22, 68, 95)
local CANVAS_PADDING = 18
local INSPECTOR_HEIGHT = 216
local NODE_HIT_RADIUS = 16
local HANDLE_HIT_RADIUS = 14

local function backdropSource(): Instance?
	local firstIsland = Workspace:FindFirstChild("FirstPrivateIsland")
	if firstIsland ~= nil and (firstIsland:IsA("Model") or firstIsland:IsA("BasePart")) then
		return firstIsland
	end
	local grass = Workspace:FindFirstChild("island1_grass", true)
	if grass ~= nil then
		local candidate = grass
		while candidate.Parent ~= nil and candidate.Parent ~= Workspace do
			candidate = candidate.Parent
		end
		if candidate:IsA("Model") or candidate:IsA("BasePart") then
			return candidate
		end
	end
	local authoringArea = Workspace:FindFirstChild("StagewrightAdminArea")
	local platform = if authoringArea ~= nil then authoringArea:FindFirstChild("GamePlatform") else nil
	return if platform ~= nil and (platform:IsA("Model") or platform:IsA("BasePart")) then platform else nil
end

local function createWorldBackdrop(parent: Instance, worldWidth: number, worldHeight: number): boolean
	local source = backdropSource()
	if source == nil then
		return false
	end
	local cloned: Instance? = nil
	local clonedSuccessfully = pcall(function()
		cloned = source:Clone()
	end)
	if not clonedSuccessfully or cloned == nil then
		return false
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Ambient = Color3.fromRGB(118, 130, 116)
	viewport.BackgroundColor3 = WATER
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.ImageColor3 = Color3.fromRGB(225, 235, 225)
	viewport.LightColor = Color3.fromRGB(255, 244, 218)
	viewport.LightDirection = Vector3.new(-0.45, -1, -0.35)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 0
	viewport.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local scene = Instance.new("Model")
	scene.Name = "StagewrightWorldPreview"
	scene.Parent = world
	cloned.Parent = scene
	local platform = if cloned.Name == "GamePlatform"
		then cloned
		else cloned:FindFirstChild("GamePlatform", true)
	local platformFrame = if platform ~= nil and platform:IsA("Model")
		then platform:GetPivot()
		elseif platform ~= nil and platform:IsA("BasePart") then platform.CFrame
		else nil
	if platformFrame ~= nil then
		local alignment = platformFrame.Rotation:Inverse() * CFrame.new(-platformFrame.Position)
		for _, descendant in scene:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame = alignment * descendant.CFrame
			end
		end
	end
	for _, descendant in scene:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("LayerCollector") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local _, boundsSize = scene:GetBoundingBox()
	if boundsSize.X <= 0 or boundsSize.Z <= 0 then
		viewport:Destroy()
		return false
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 26
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local aspect = math.max(parent.AbsoluteSize.X / math.max(parent.AbsoluteSize.Y, 1), 0.25)
	local visibleDepth = math.max(worldHeight, worldWidth / aspect)
	local cameraHeight = visibleDepth * 0.5 / math.tan(math.rad(camera.FieldOfView * 0.5))
	local center = Vector3.zero
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, cameraHeight, 0), center, Vector3.new(0, 0, -1))
	return true
end

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function rounded(instance: GuiObject, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function stroke(instance: GuiObject, color: Color3, thickness: number, transparency: number?)
	create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
	}, instance)
end

local function button(
	parent: Instance,
	theme: Theme,
	text: string,
	position: UDim2,
	size: UDim2,
	callback: () -> (),
	selected: boolean?
): TextButton
	local result = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = if selected then theme.accent else theme.field,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Position = position,
		Size = size,
		Text = text,
		TextColor3 = theme.text,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
	}, parent) :: TextButton
	rounded(result, 6)
	stroke(result, if selected then Color3.fromRGB(123, 174, 245) else theme.border, 1)
	result.Activated:Connect(callback)
	return result
end

local function line(
	parent: Instance,
	from: Vector2,
	to: Vector2,
	color: Color3,
	thickness: number,
	zIndex: number,
	transparency: number?
): Frame
	local delta = to - from
	local result = create("Frame", {
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		Selectable = false,
		Size = UDim2.fromOffset(math.max(delta.Magnitude + 1, 1), math.max(thickness, 1)),
		ZIndex = zIndex,
	}, parent) :: Frame
	return result
end

local function resolvedCell(grid: any, key: string): any
	local override = grid.cells[key]
	if override == nil then
		return grid.defaultCell
	end
	return setmetatable({}, {
		__index = function(_, field)
			local value = override[field]
			return if value ~= nil then value else grid.defaultCell[field]
		end,
	})
end

local function nodeColor(kind: string): Color3
	if kind == "Spawn" then
		return Color3.fromRGB(49, 166, 91)
	elseif kind == "Goal" then
		return Color3.fromRGB(132, 80, 207)
	end
	return Color3.fromRGB(238, 158, 48)
end

local function displayName(node: any?): string
	return if node ~= nil and type(node.name) == "string" then node.name else "Missing node"
end

function WorldPathView.cancelInteraction(self: Controller): boolean
	local pointerResult = PointerDrag.cancel(self.pointerState, "Editor interaction cancelled")
	local canceled = #pointerResult.actions > 0 or self.panLastScreen ~= nil
	self.pointerState = pointerResult.state
	table.clear(self.touchPointerIds)
	self.lastDragRenderAt = 0
	self.lastDragValue = nil
	self.panLastScreen = nil
	return canceled
end

function WorldPathView.new(parent: Instance, theme: Theme, callbacks: Callbacks): Controller
	local root = create("Frame", {
		Active = true,
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, parent) :: Frame
	local self: Controller = setmetatable({
		root = root,
		theme = theme,
		callbacks = callbacks,
		stage = nil,
		graph = nil,
		preview = nil,
		selectedNodeId = nil,
		selectedEdgeId = nil,
		tracedEdgeIds = {},
		transform = nil,
		transformStageId = nil,
		canvas = nil,
		assetPreview = true,
		showLanes = true,
		showBuildMask = false,
		showConflicts = true,
		pointerState = PointerDrag.idle(),
		hitPrimitives = {},
		hitBlockers = {},
		touchPointerIds = {},
		nextTouchPointerId = 0,
		lastDragRenderAt = 0,
		lastDragValue = nil,
		panLastScreen = nil,
		connections = {},
	}, WorldPathView)

	local function pointToLocal(position: Vector2): any?
		local stage = self.stage
		local transform = self.transform
		if stage == nil or transform == nil then
			return nil
		end
		local point = position - self.root.AbsolutePosition
		if
			point.X < 0
			or point.Y < 0
			or point.X > transform.viewportSize.x
			or point.Y > transform.viewportSize.y
		then
			return nil
		end
		local grid = stage.grid
		local worldPoint = CanvasTransform.canvasToWorld(transform, { x = point.X, y = point.Y })
		local halfWidth = grid.columns * grid.cellSize * 0.5
		local halfHeight = grid.rows * grid.cellSize * 0.5
		if
			worldPoint.x < -halfWidth
			or worldPoint.x > halfWidth
			or worldPoint.y < -halfHeight
			or worldPoint.y > halfHeight
		then
			return nil
		end
		return {
			x = worldPoint.x,
			y = 0.48,
			z = worldPoint.y,
		}
	end

	local function updateDrag(target: PointerDrag.Target, pointer: Vector2, finished: boolean): boolean
		local localPosition = pointToLocal(pointer)
		local graph = self.graph
		if graph == nil then
			return false
		end
		if target.kind == "Node" then
			local node = graph.nodes[target.id]
			if node == nil then
				return false
			end
			local value = localPosition
			if value ~= nil then
				value.y = node.position.y
				self.lastDragValue = value
			elseif finished then
				value = self.lastDragValue
			end
			if value == nil then
				return false
			end
			self.callbacks.moveNode(target.id, value, finished)
			return true
		elseif target.kind == "Handle" and target.handleId ~= nil then
			local edge = graph.edges[target.id]
			if edge == nil then
				return false
			end
			local anchorId = if target.handleId == "Out" then edge.fromNodeId else edge.toNodeId
			local anchor = graph.nodes[anchorId]
			if anchor == nil then
				return false
			end
			local value = nil
			if localPosition ~= nil then
				value = {
					x = localPosition.x - anchor.position.x,
					y = if target.handleId == "Out" then edge.outHandleOffset.y else edge.inHandleOffset.y,
					z = localPosition.z - anchor.position.z,
				}
				self.lastDragValue = value
			elseif finished then
				value = self.lastDragValue
			end
			if value == nil then
				return false
			end
			self.callbacks.moveHandle(target.id, target.handleId, value, finished)
			return true
		end
		return false
	end

	local function seedDragValue(target: PointerDrag.Target): any?
		local graph = self.graph
		if graph == nil then
			return nil
		elseif target.kind == "Node" then
			local node = graph.nodes[target.id]
			if node == nil then
				return nil
			end
			return {
				x = node.position.x,
				y = node.position.y,
				z = node.position.z,
			}
		elseif target.kind == "Handle" then
			local edge = graph.edges[target.id]
			if edge == nil then
				return nil
			end
			local offset = if target.handleId == "Out" then edge.outHandleOffset else edge.inHandleOffset
			return {
				x = offset.x,
				y = offset.y,
				z = offset.z,
			}
		end
		return nil
	end

	local function dispatchPointerActions(actions: { PointerDrag.Action })
		for _, action in actions do
			if action.kind == "DragStarted" then
				self.lastDragRenderAt = os.clock()
				if updateDrag(action.target, Vector2.new(action.position.x, action.position.y), false) then
					self:rerender()
				end
			elseif action.kind == "DragMoved" then
				local now = os.clock()
				if now - self.lastDragRenderAt >= 0.05 then
					self.lastDragRenderAt = now
					if
						updateDrag(action.target, Vector2.new(action.position.x, action.position.y), false)
					then
						self:rerender()
					end
				end
			elseif action.kind == "Committed" then
				local committed =
					updateDrag(action.target, Vector2.new(action.position.x, action.position.y), true)
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				if not committed then
					self:rerender()
				end
			elseif action.kind == "Clicked" then
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				if action.target.kind == "Edge" then
					self.callbacks.selectEdge(action.target.id)
				end
			elseif action.kind == "Cancelled" then
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
			end
		end
	end

	local function isVisible(): boolean
		local current: Instance? = self.root
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

	local function viewportPoint(pointer: Vector2): (CanvasTransform.Point2?, CanvasTransform.Transform?)
		local transform = self.transform
		if transform == nil then
			return nil, nil
		end
		local point = pointer - self.root.AbsolutePosition
		if
			point.X < 0
			or point.Y < 0
			or point.X > transform.viewportSize.x
			or point.Y > transform.viewportSize.y
		then
			return nil, transform
		end
		return { x = point.X, y = point.Y }, transform
	end

	local function pointerId(input: InputObject, createTouchId: boolean): string?
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseMovement
		then
			return "mouse-primary"
		elseif input.UserInputType ~= Enum.UserInputType.Touch then
			return nil
		end
		local existing = self.touchPointerIds[input]
		if existing ~= nil or not createTouchId then
			return existing
		end
		self.nextTouchPointerId += 1
		local created = `touch-{self.nextTouchPointerId}`
		self.touchPointerIds[input] = created
		return created
	end

	local function beginPrimaryPointer(input: InputObject, pointer: Vector2)
		if self.panLastScreen ~= nil or PointerDrag.isActive(self.pointerState) then
			return
		end
		local canvas = self.canvas
		if viewportPoint(pointer) == nil or canvas == nil or canvas.Parent == nil then
			return
		end
		for _, blocker in self.hitBlockers do
			local blockerPosition = blocker.AbsolutePosition
			local blockerSize = blocker.AbsoluteSize
			if
				blocker.Visible
				and pointer.X >= blockerPosition.X
				and pointer.Y >= blockerPosition.Y
				and pointer.X <= blockerPosition.X + blockerSize.X
				and pointer.Y <= blockerPosition.Y + blockerSize.Y
			then
				return
			end
		end
		local canvasPosition = pointer - canvas.AbsolutePosition
		local canvasSize = canvas.AbsoluteSize
		if
			canvasPosition.X < 0
			or canvasPosition.Y < 0
			or canvasPosition.X > canvasSize.X
			or canvasPosition.Y > canvasSize.Y
		then
			return
		end
		local hit = HitTest.resolve({ x = canvasPosition.X, y = canvasPosition.Y }, self.hitPrimitives)
		if hit == nil then
			return
		end
		local resolvedPointerId = pointerId(input, true)
		if resolvedPointerId == nil then
			return
		end
		local target: PointerDrag.Target
		if hit.kind == "Handle" then
			local handleId = hit.handleId
			if handleId == nil then
				return
			end
			target = {
				kind = "Handle",
				id = hit.id,
				handleId = handleId,
			}
		elseif hit.kind == "Node" then
			target = {
				kind = "Node",
				id = hit.id,
			}
		else
			target = {
				kind = "Edge",
				id = hit.id,
			}
		end
		self.lastDragRenderAt = 0
		self.lastDragValue = seedDragValue(target)
		local result =
			PointerDrag.press(self.pointerState, resolvedPointerId, target, { x = pointer.X, y = pointer.Y })
		self.pointerState = result.state
		if hit.kind == "Node" then
			self.callbacks.selectNode(hit.id)
		end
	end

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input)
			if not isVisible() then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				if not PointerDrag.isActive(self.pointerState) and viewportPoint(pointer) ~= nil then
					self.panLastScreen = pointer
				end
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginPrimaryPointer(input, pointer)
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if not isVisible() then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				if PointerDrag.isActive(self.pointerState) or self.panLastScreen ~= nil then
					return
				end
				local point, transform = viewportPoint(pointer)
				if point ~= nil and transform ~= nil and input.Position.Z ~= 0 then
					self.transform = CanvasTransform.zoomAt(
						transform,
						if input.Position.Z > 0 then 1.12 else 1 / 1.12,
						point
					)
					self:rerender()
				end
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement and self.panLastScreen ~= nil then
				local transform = self.transform
				local delta = pointer - self.panLastScreen
				self.panLastScreen = pointer
				if transform ~= nil and delta.Magnitude > 0 then
					self.transform = CanvasTransform.pan(transform, { x = delta.X, y = delta.Y })
					local canvas = self.canvas
					if canvas ~= nil and canvas.Parent ~= nil then
						local position = canvas.Position
						canvas.Position = UDim2.new(
							position.X.Scale,
							position.X.Offset + delta.X,
							position.Y.Scale,
							position.Y.Offset + delta.Y
						)
					end
				end
				return
			end
			if not PointerDrag.isActive(self.pointerState) then
				return
			end
			local resolvedPointerId = pointerId(input, false)
			if resolvedPointerId ~= nil then
				local result =
					PointerDrag.move(self.pointerState, resolvedPointerId, { x = pointer.X, y = pointer.Y })
				self.pointerState = result.state
				dispatchPointerActions(result.actions)
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				self.panLastScreen = nil
				return
			end
			local resolvedPointerId = pointerId(input, false)
			if resolvedPointerId == nil then
				return
			end
			local result = PointerDrag.release(self.pointerState, resolvedPointerId, {
				x = input.Position.X,
				y = input.Position.Y,
			})
			self.pointerState = result.state
			dispatchPointerActions(result.actions)
			if input.UserInputType == Enum.UserInputType.Touch then
				self.touchPointerIds[input] = nil
			end
		end)
	)

	table.insert(
		self.connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if PointerDrag.isActive(self.pointerState) or self.panLastScreen ~= nil then
				self.callbacks.cancelInteraction()
				return
			end
			self:rerender()
		end)
	)
	return self
end

function WorldPathView.render(
	self: Controller,
	stage: any?,
	graph: any?,
	preview: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean }
)
	local nextStageId = if stage ~= nil and type(stage.id) == "string" then stage.id else nil
	if self.transformStageId ~= nextStageId then
		self.transform = nil
		self.transformStageId = nextStageId
	end
	self.stage = stage
	self.graph = graph
	self.preview = preview
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self:rerender()
end

function WorldPathView.fitToView(self: Controller)
	if self.transform ~= nil then
		self.transform = CanvasTransform.resetFit(self.transform)
	end
	self:rerender()
end

function WorldPathView.rerender(self: Controller)
	self.canvas = nil
	table.clear(self.hitPrimitives)
	table.clear(self.hitBlockers)
	for _, child in self.root:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local stage = self.stage
	local graph = self.graph
	local preview = self.preview
	if stage == nil or graph == nil or preview == nil then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Size = UDim2.fromScale(1, 1),
			Text = "This level has no route preview yet.",
			TextColor3 = self.theme.muted,
			TextSize = 14,
		}, self.root)
		return
	end

	local inspectorHeight = INSPECTOR_HEIGHT
	local mapHost = create("Frame", {
		BackgroundColor3 = WATER,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 1, -inspectorHeight - 4),
	}, self.root) :: Frame
	local grid = stage.grid
	local available = mapHost.AbsoluteSize
	if available.X <= CANVAS_PADDING * 2 or available.Y <= CANVAS_PADDING * 2 then
		return
	end
	local worldWidth = math.max(grid.columns * grid.cellSize, 1)
	local worldHeight = math.max(grid.rows * grid.cellSize, 1)
	local viewportSize = { x = available.X, y = available.Y }
	local worldSize = { x = worldWidth, y = worldHeight }
	local transform = self.transform
	if transform == nil or transform.worldSize.x ~= worldWidth or transform.worldSize.y ~= worldHeight then
		transform = CanvasTransform.fit(viewportSize, worldSize, CANVAS_PADDING)
	elseif transform.viewportSize.x ~= available.X or transform.viewportSize.y ~= available.Y then
		transform = CanvasTransform.resize(transform, viewportSize)
	end
	local resolvedTransform = assert(transform, "World Path canvas transform was not initialized")
	self.transform = resolvedTransform
	local scale = CanvasTransform.scale(resolvedTransform)
	local topLeftPoint = CanvasTransform.worldToCanvas(resolvedTransform, {
		x = -worldWidth * 0.5,
		y = -worldHeight * 0.5,
	})
	local bottomRightPoint = CanvasTransform.worldToCanvas(resolvedTransform, {
		x = worldWidth * 0.5,
		y = worldHeight * 0.5,
	})
	local topLeft = Vector2.new(topLeftPoint.x, topLeftPoint.y)
	local mapSize = Vector2.new(bottomRightPoint.x - topLeftPoint.x, bottomRightPoint.y - topLeftPoint.y)

	local canvas = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(50, 79, 54),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(topLeft.X, topLeft.Y),
		Size = UDim2.fromOffset(mapSize.X, mapSize.Y),
		ZIndex = 1,
	}, mapHost) :: Frame
	self.canvas = canvas
	local hasWorldBackdrop = createWorldBackdrop(canvas, worldWidth, worldHeight)
	canvas.BackgroundTransparency = if hasWorldBackdrop then 0.64 else 0
	local tint = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(23, 42, 32),
		BackgroundTransparency = if hasWorldBackdrop then 0.68 else 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, canvas) :: Frame
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(31, 55, 39), Color3.fromRGB(15, 31, 25)),
		Rotation = 90,
		Transparency = NumberSequence.new(0.15, 0.55),
	}, tint)
	stroke(canvas, Color3.fromRGB(65, 98, 71), 1)

	local cellPixel = Vector2.new(grid.cellSize * scale, grid.cellSize * scale)
	if grid.columns * grid.rows <= 2_500 and math.min(cellPixel.X, cellPixel.Y) >= 3 then
		for row = 1, grid.rows do
			for column = 1, grid.columns do
				local key = `{column}:{row}`
				local cell = resolvedCell(grid, key)
				local color = if cell.terrainId == "void" then self.theme.void else Color3.fromRGB(60, 91, 64)
				create("Frame", {
					BackgroundColor3 = color,
					BackgroundTransparency = if hasWorldBackdrop then 0.72 else 0,
					BorderColor3 = Color3.fromRGB(35, 54, 39),
					BorderSizePixel = 1,
					Position = UDim2.fromOffset((column - 1) * cellPixel.X, (row - 1) * cellPixel.Y),
					Size = UDim2.fromOffset(math.ceil(cellPixel.X), math.ceil(cellPixel.Y)),
					ZIndex = 2,
				}, canvas)
			end
		end
	end

	local function worldPoint(position: any): Vector2
		local canvasPoint = CanvasTransform.worldToCanvas(resolvedTransform, {
			x = position.x,
			y = position.z,
		})
		return Vector2.new(canvasPoint.x - topLeft.X, canvasPoint.y - topLeft.Y)
	end

	local bakedGraph = preview.pathGraphs[graph.id]
	if bakedGraph ~= nil then
		local edgeIds: { string } = {}
		for edgeId in bakedGraph.edges do
			table.insert(edgeIds, edgeId)
		end
		table.sort(edgeIds)
		for _, edgeId in edgeIds do
			local edge = bakedGraph.edges[edgeId]
			local profile = bakedGraph.laneProfiles[edge.laneProfileId]
			local radius = if profile ~= nil then profile.clearanceRadius else grid.cellSize * 0.5
			local routeScale = scale
			local walkwayWidth = math.max(radius * 2 * routeScale, 8)
			local samples = edge.samples or {}
			local edgeHitPoints: { HitTest.Point2 } = {}
			if #samples > 0 then
				local firstPoint = worldPoint(samples[1].position)
				table.insert(edgeHitPoints, { x = firstPoint.X, y = firstPoint.Y })
			end
			local step = math.max(math.floor(#samples / 72), 1)
			local previousIndex = 1
			local selected = self.selectedEdgeId == edgeId
			local traced = self.tracedEdgeIds[edgeId] == true
			for index = math.min(1 + step, #samples), #samples, step do
				local resolvedIndex = if index + step > #samples then #samples else index
				local first = worldPoint(samples[previousIndex].position)
				local second = worldPoint(samples[resolvedIndex].position)
				if selected then
					line(canvas, first, second, SELECTED, walkwayWidth + 6, 4, 0.02)
				elseif traced then
					line(canvas, first, second, self.theme.success, walkwayWidth + 5, 4, 0.4)
				end
				if self.assetPreview then
					line(canvas, first, second, Color3.fromRGB(105, 99, 82), walkwayWidth + 5, 5, 0)
					line(canvas, first, second, GRAVEL_DARK, walkwayWidth + 2, 6, 0)
					line(canvas, first, second, GRAVEL, walkwayWidth, 7, 0)
					line(canvas, first, second, GRAVEL_LIGHT, math.max(walkwayWidth * 0.08, 1), 8, 0.68)
					local delta = second - first
					if delta.Magnitude > 0.01 then
						local normal = Vector2.new(-delta.Y, delta.X).Unit
						local midpoint = (first + second) * 0.5
						local pebbleSize = math.clamp(walkwayWidth * 0.17, 3, 8)
						for side in { -1, 1 } do
							local pebble = create("Frame", {
								AnchorPoint = Vector2.new(0.5, 0.5),
								BackgroundColor3 = Color3.fromRGB(118, 104, 83),
								BorderSizePixel = 0,
								Position = UDim2.fromOffset(
									midpoint.X + normal.X * walkwayWidth * 0.5 * side,
									midpoint.Y + normal.Y * walkwayWidth * 0.5 * side
								),
								Size = UDim2.fromOffset(pebbleSize, pebbleSize * 0.72),
								ZIndex = 8,
							}, canvas) :: Frame
							rounded(pebble, math.ceil(pebbleSize * 0.5))
						end
					end
				else
					line(canvas, first, second, Color3.fromRGB(58, 77, 81), walkwayWidth, 5, 0.16)
					line(canvas, first, second, LANE, 2, 7, 0.16)
				end
				table.insert(edgeHitPoints, { x = second.X, y = second.Y })
				previousIndex = resolvedIndex
				if resolvedIndex == #samples then
					break
				end
			end
			if #edgeHitPoints > 0 then
				table.insert(self.hitPrimitives, {
					kind = "Edge",
					id = edgeId,
					points = edgeHitPoints,
					radius = math.max(walkwayWidth * 0.5 + 5, 8),
				})
			end

			if selected and profile ~= nil and self.showLanes then
				for laneIndex, laneOffset in profile.offsets do
					local lanePrevious = 1
					local dashIndex = 0
					for index = math.min(1 + step, #samples), #samples, step do
						local resolvedIndex = if index + step > #samples then #samples else index
						local firstSample = samples[lanePrevious]
						local secondSample = samples[resolvedIndex]
						local first = worldPoint({
							x = firstSample.position.x - firstSample.tangent.z * laneOffset,
							z = firstSample.position.z + firstSample.tangent.x * laneOffset,
						})
						local second = worldPoint({
							x = secondSample.position.x - secondSample.tangent.z * laneOffset,
							z = secondSample.position.z + secondSample.tangent.x * laneOffset,
						})
						dashIndex += 1
						if dashIndex % 3 ~= 0 then
							line(canvas, first, second, LANE, 2, 9, 0.06)
						end
						lanePrevious = resolvedIndex
						if resolvedIndex == #samples then
							break
						end
					end
					if #samples > 0 then
						local labelSample = samples[math.clamp(math.floor(#samples * 0.56), 1, #samples)]
						local labelPoint = worldPoint({
							x = labelSample.position.x - labelSample.tangent.z * laneOffset,
							z = labelSample.position.z + labelSample.tangent.x * laneOffset,
						})
						create("TextLabel", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundTransparency = 1,
							Font = Enum.Font.BuilderSansBold,
							Position = UDim2.fromOffset(labelPoint.X, labelPoint.Y),
							Rotation = math.deg(math.atan2(labelSample.tangent.z, labelSample.tangent.x)),
							Size = UDim2.fromOffset(72, 18),
							Text = `Lane {laneIndex}`,
							TextColor3 = LANE,
							TextSize = 11,
							TextStrokeColor3 = Color3.fromRGB(31, 25, 20),
							TextStrokeTransparency = 0.25,
							ZIndex = 12,
						}, canvas)
						local unitSample =
							samples[math.clamp(math.floor(#samples * (0.68 + laneIndex * 0.08)), 1, #samples)]
						local unitPoint = worldPoint({
							x = unitSample.position.x - unitSample.tangent.z * laneOffset,
							z = unitSample.position.z + unitSample.tangent.x * laneOffset,
						})
						local ghost = create("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundColor3 = if laneIndex % 2 == 0
								then Color3.fromRGB(137, 159, 236)
								else Color3.fromRGB(85, 195, 226),
							BackgroundTransparency = 0.38,
							BorderSizePixel = 0,
							Position = UDim2.fromOffset(unitPoint.X, unitPoint.Y),
							Rotation = math.deg(math.atan2(unitSample.tangent.z, unitSample.tangent.x)) + 90,
							Size = UDim2.fromOffset(13, 26),
							ZIndex = 12,
						}, canvas) :: Frame
						rounded(ghost, 7)
						stroke(ghost, LANE, 1, 0.5)
					end
				end
			end

			if #samples >= 2 then
				for _, fraction in { 0.28, 0.56, 0.82 } do
					local marker = samples[math.clamp(math.floor(#samples * fraction), 1, #samples)]
					create("TextLabel", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Font = Enum.Font.BuilderSansBold,
						Position = UDim2.fromOffset(
							worldPoint(marker.position).X,
							worldPoint(marker.position).Y
						),
						Rotation = math.deg(math.atan2(marker.tangent.z, marker.tangent.x)),
						Size = UDim2.fromOffset(28, 22),
						Text = ">>",
						TextColor3 = Color3.fromRGB(239, 218, 174),
						TextSize = 13,
						TextTransparency = 0.22,
						ZIndex = 10,
					}, canvas)
				end
			end
		end
	end

	local routeMask = preview.routeNoBuildMask or {}
	local conflictCount = 0
	local conflictCenter = Vector2.zero
	for key in routeMask do
		local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
		local column = if columnText ~= nil then tonumber(columnText) else nil
		local row = if rowText ~= nil then tonumber(rowText) else nil
		if column ~= nil and row ~= nil then
			local cell = resolvedCell(grid, key)
			local traversalConflict = cell.enemyTraversalPolicy == "Blocked"
			if (self.showConflicts and traversalConflict) or self.showBuildMask then
				local conflict = create("Frame", {
					BackgroundColor3 = if traversalConflict then self.theme.warning else SELECTED,
					BackgroundTransparency = if traversalConflict then 0.76 else 0.88,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Position = UDim2.fromOffset((column - 1) * cellPixel.X + 1, (row - 1) * cellPixel.Y + 1),
					Size = UDim2.fromOffset(math.max(cellPixel.X - 2, 2), math.max(cellPixel.Y - 2, 2)),
					ZIndex = 12,
				}, canvas) :: Frame
				if traversalConflict then
					stroke(conflict, self.theme.warning, 2)
					conflictCount += 1
					conflictCenter += Vector2.new((column - 0.5) * cellPixel.X, (row - 0.5) * cellPixel.Y)
					for stripeIndex = -2, 4 do
						create("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundColor3 = self.theme.warning,
							BackgroundTransparency = 0.16,
							BorderSizePixel = 0,
							Position = UDim2.new(0.5, stripeIndex * 6, 0.5, 0),
							Rotation = -45,
							Size = UDim2.fromOffset(2, math.max(cellPixel.X + cellPixel.Y, 12)),
							ZIndex = 13,
						}, conflict)
					end
				end
			end
		end
	end
	if conflictCount > 0 and self.showConflicts then
		conflictCenter /= conflictCount
		local conflictBadge = create("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(27, 24, 15),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(conflictCenter.X + 28, conflictCenter.Y + 18),
			Size = UDim2.fromOffset(154, 30),
			Text = `!  {conflictCount} blocked {if conflictCount == 1 then "cell" else "cells"}`,
			TextColor3 = self.theme.warning,
			TextSize = 11,
			ZIndex = 18,
		}, canvas) :: TextLabel
		rounded(conflictBadge, 6)
		stroke(conflictBadge, self.theme.warning, 1, 0.45)
	end

	for nodeId, node in graph.nodes do
		local point = worldPoint(node.position)
		table.insert(self.hitPrimitives, {
			kind = "Node",
			id = nodeId,
			center = { x = point.X, y = point.Y },
			radius = NODE_HIT_RADIUS,
		})
		if node.kind == "Spawn" or node.kind == "Goal" then
			local glow = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = nodeColor(node.kind),
				BackgroundTransparency = 0.78,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(point.X, point.Y),
				Size = UDim2.fromOffset(44, 44),
				ZIndex = 18,
			}, canvas) :: Frame
			rounded(glow, 24)
			stroke(glow, nodeColor(node.kind), 3, 0.36)
		end
		local nodeButton = create("TextLabel", {
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = nodeColor(node.kind),
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(point.X, point.Y),
			Size = UDim2.fromOffset(
				if self.selectedNodeId == nodeId then 24 elseif node.kind == "Junction" then 19 else 21,
				if self.selectedNodeId == nodeId then 24 elseif node.kind == "Junction" then 19 else 21
			),
			Text = if node.kind == "Spawn" then "●" elseif node.kind == "Goal" then "◆" else "▼",
			TextColor3 = self.theme.text,
			TextSize = 9,
			ZIndex = 20,
			Selectable = false,
		}, canvas) :: TextLabel
		if node.kind == "Junction" then
			local pinTail = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = nodeColor(node.kind),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(point.X, point.Y + 9),
				Rotation = 45,
				Size = UDim2.fromOffset(8, 8),
				ZIndex = 19,
			}, canvas) :: Frame
			stroke(pinTail, Color3.fromRGB(45, 31, 19), 1, 0.15)
		end
		rounded(nodeButton, 12)
		stroke(
			nodeButton,
			if self.selectedNodeId == nodeId then self.theme.warning else self.theme.text,
			if self.selectedNodeId == nodeId then 3 else 1,
			0.15
		)
		local label = create("TextLabel", {
			AnchorPoint = if node.kind == "Spawn" then Vector2.new(0.5, 1) else Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(17, 21, 24),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = if node.kind == "Spawn" then UDim2.new(0.5, 0, 0, -10) else UDim2.new(1, 9, 0.5, 0),
			Size = UDim2.fromOffset(math.clamp(#node.name * 7 + 22, 70, 138), 22),
			Text = `  {node.name}  `,
			TextColor3 = self.theme.text,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 19,
		}, nodeButton) :: TextLabel
		rounded(label, 5)
		label.Visible = true
	end

	local selectedEdge = if self.selectedEdgeId ~= nil then graph.edges[self.selectedEdgeId] else nil
	if selectedEdge ~= nil then
		local from = graph.nodes[selectedEdge.fromNodeId]
		local to = graph.nodes[selectedEdge.toNodeId]
		if from ~= nil and to ~= nil then
			for _, definition in
				{
					{ id = "Out", node = from, offset = selectedEdge.outHandleOffset },
					{ id = "In", node = to, offset = selectedEdge.inHandleOffset },
				}
			do
				local anchor = worldPoint(definition.node.position)
				local handlePosition = {
					x = definition.node.position.x + definition.offset.x,
					z = definition.node.position.z + definition.offset.z,
				}
				local point = worldPoint(handlePosition)
				line(canvas, anchor, point, SELECTED, 1, 21, 0.18)
				table.insert(self.hitPrimitives, {
					kind = "Handle",
					id = selectedEdge.id,
					handleId = definition.id,
					center = { x = point.X, y = point.Y },
					radius = HANDLE_HIT_RADIUS,
				})
				local handle = create("Frame", {
					Active = false,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = SELECTED,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(point.X, point.Y),
					Selectable = false,
					Size = UDim2.fromOffset(12, 12),
					ZIndex = 22,
				}, canvas) :: Frame
				rounded(handle, 8)
				stroke(handle, self.theme.text, 1)
			end
		end
	end

	local legend = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(18, 22, 27),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.fromOffset(156, 126),
		ZIndex = 25,
	}, mapHost) :: Frame
	table.insert(self.hitBlockers, legend)
	rounded(legend, 7)
	stroke(legend, self.theme.border, 1)
	local function legendLabel(text: string, row: number)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(48, 9 + (row - 1) * 28),
			Size = UDim2.fromOffset(98, 22),
			Text = text,
			TextColor3 = self.theme.text,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 26,
		}, legend)
	end
	local gravelSwatch = create("Frame", {
		BackgroundColor3 = GRAVEL,
		BorderColor3 = GRAVEL_DARK,
		BorderSizePixel = 2,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.fromOffset(24, 18),
		ZIndex = 26,
	}, legend) :: Frame
	create("UIGradient", {
		Color = ColorSequence.new(GRAVEL_DARK, GRAVEL_LIGHT),
		Rotation = 35,
	}, gravelSwatch)
	legendLabel("Gravel asset", 1)
	for dash = 0, 2 do
		create("Frame", {
			BackgroundColor3 = LANE,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(14 + dash * 10, 48),
			Size = UDim2.fromOffset(7, 2),
			ZIndex = 26,
		}, legend)
	end
	legendLabel("Lane centerline", 2)
	create("Frame", {
		BackgroundColor3 = SELECTED,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.fromOffset(24, 2),
		ZIndex = 26,
	}, legend)
	legendLabel("Selected spline", 3)
	local conflictSwatch = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(42, 34, 15),
		BorderColor3 = self.theme.warning,
		BorderSizePixel = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(14, 94),
		Size = UDim2.fromOffset(24, 18),
		ZIndex = 26,
	}, legend) :: Frame
	for stripe = -1, 3 do
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = self.theme.warning,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, stripe * 6, 0.5, 0),
			Rotation = -45,
			Size = UDim2.fromOffset(2, 34),
			ZIndex = 27,
		}, conflictSwatch)
	end
	legendLabel("Conflict", 4)

	local inspector = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = self.theme.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, inspectorHeight),
		ZIndex = 28,
	}, self.root) :: Frame
	stroke(inspector, self.theme.borderStrong, 1)
	local fromNode = if selectedEdge ~= nil then graph.nodes[selectedEdge.fromNodeId] else nil
	local toNode = if selectedEdge ~= nil then graph.nodes[selectedEdge.toNodeId] else nil
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(28, 7),
		Size = UDim2.new(1, -56, 0, 40),
		Text = if selectedEdge ~= nil
			then `⌃   Selected spline   •   {displayName(fromNode)}  →  {displayName(toNode)}`
			elseif self.selectedNodeId ~= nil then `⌃   Selected node   •   {displayName(
				graph.nodes[self.selectedNodeId]
			)}`
			else "Select a gravel spline or route marker to edit it",
		TextColor3 = self.theme.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 30,
	}, inspector)
	create("Frame", {
		BackgroundColor3 = self.theme.border,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 30,
	}, inspector)
	if selectedEdge ~= nil and self.selectedEdgeId ~= nil then
		local edgeId = self.selectedEdgeId
		local profile = graph.laneProfiles[selectedEdge.laneProfileId]
		local laneCount = if profile ~= nil then #profile.offsets else 1
		local layoutScale = math.clamp(self.root.AbsoluteSize.X / 1_600, 0.5, 1)
		local function scaled(value: number): number
			return math.floor(value * layoutScale + 0.5)
		end
		local function fieldLabel(text: string, x: number, width: number)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(scaled(x), 66),
				Size = UDim2.fromOffset(scaled(width), 18),
				Text = text,
				TextColor3 = self.theme.muted,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector)
		end
		local function field(text: string, x: number, width: number): TextLabel
			local result = create("TextLabel", {
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(scaled(x), 88),
				Size = UDim2.fromOffset(scaled(width), 42),
				Text = text,
				TextColor3 = self.theme.text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector) :: TextLabel
			rounded(result, 6)
			stroke(result, self.theme.border, 1)
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}, result)
			return result
		end

		fieldLabel("Path asset", 28, 220)
		field("▦  Gravel   ⌄", 28, 220)
		fieldLabel("Surface mode", 280, 166)
		field("Follow terrain   ⌄", 280, 166)
		fieldLabel("Lanes", 480, 190)
		local laneHost = create("Frame", {
			BackgroundColor3 = self.theme.surface,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(scaled(480), 88),
			Size = UDim2.fromOffset(scaled(190), 42),
			ZIndex = 30,
		}, inspector) :: Frame
		rounded(laneHost, 6)
		stroke(laneHost, self.theme.border, 1)
		for index = 1, 3 do
			local count = index
			button(
				laneHost,
				self.theme,
				tostring(count),
				UDim2.fromOffset(math.floor((count - 1) * scaled(190) / 3), 0),
				UDim2.fromOffset(math.ceil(scaled(190) / 3), 42),
				function()
					self.callbacks.setLanes(edgeId, count)
				end,
				laneCount == count
			)
		end
		fieldLabel("Lane width", 704, 152)
		field("4 studs   ⌄", 704, 152)
		fieldLabel("Curve mode", 888, 154)
		field("Smooth   ⌄", 888, 154)
		fieldLabel("Priority", 1074, 92)
		field(tostring(selectedEdge.priority or 1), 1074, 92)
		button(
			inspector,
			self.theme,
			"⌁  Edit handles",
			UDim2.new(1, -410, 0, 88),
			UDim2.fromOffset(176, 42),
			function()
				self.callbacks.focusWorld(edgeId)
			end
		)
		button(
			inspector,
			self.theme,
			"▶  Test segment",
			UDim2.new(1, -218, 0, 88),
			UDim2.fromOffset(190, 42),
			function()
				self.callbacks.testSegment(edgeId)
			end
		)
		create("Frame", {
			BackgroundColor3 = self.theme.border,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 150),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 30,
		}, inspector)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(28, 166),
			Size = UDim2.new(1, -52, 0, 34),
			Text = `Walkway width {if profile ~= nil
				then math.round(profile.clearanceRadius * 2)
				else grid.cellSize} studs   •   Build mask derived automatically   •   {conflictCount} conflicts`,
			TextColor3 = if conflictCount > 0 then self.theme.warning else self.theme.muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 30,
		}, inspector)
	end
end

function WorldPathView.destroy(self: Controller)
	self:cancelInteraction()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.root:Destroy()
end

return WorldPathView

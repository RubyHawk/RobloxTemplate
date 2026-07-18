--!strict

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
	selectNode: (string) -> (),
	selectEdge: (string) -> (),
	moveNode: (string, any, boolean) -> (),
	moveHandle: (string, string, any, boolean) -> (),
	setLanes: (string, number) -> (),
	smoothEdge: (string) -> (),
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
	mapTopLeft: Vector2,
	mapScale: Vector2,
	mapSize: Vector2,
	assetPreview: boolean,
	showLanes: boolean,
	showBuildMask: boolean,
	showConflicts: boolean,
	dragKind: string?,
	dragId: string?,
	dragHandle: string?,
	dragStartScreen: Vector2?,
	dragMoved: boolean,
	lastDragRenderAt: number,
	lastDragValue: any?,
	connections: { RBXScriptConnection },
	render: (Controller, any?, any?, any?, string?, string?, { [string]: boolean }) -> (),
	rerender: (Controller) -> (),
	cancelInteraction: (Controller) -> (),
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

local function createWorldBackdrop(parent: Instance): boolean
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

	local boundsFrame, boundsSize = scene:GetBoundingBox()
	if boundsSize.X <= 0 or boundsSize.Z <= 0 then
		viewport:Destroy()
		return false
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 26
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local aspect = math.max(parent.AbsoluteSize.X / math.max(parent.AbsoluteSize.Y, 1), 0.25)
	local visibleDepth = math.max(boundsSize.Z * 1.08, boundsSize.X * 1.08 / aspect)
	local cameraHeight = visibleDepth * 0.5 / math.tan(math.rad(camera.FieldOfView * 0.5)) + boundsSize.Y
	local center = boundsFrame.Position
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

local function lineButton(parent: Instance, from: Vector2, to: Vector2, thickness: number, callback: () -> ())
	local delta = to - from
	local hitTarget = create("TextButton", {
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		Size = UDim2.fromOffset(math.max(delta.Magnitude + 3, 3), math.max(thickness, 12)),
		Text = "",
		ZIndex = 15,
	}, parent) :: TextButton
	hitTarget.Activated:Connect(callback)
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

function WorldPathView.cancelInteraction(self: Controller)
	self.dragKind = nil
	self.dragId = nil
	self.dragHandle = nil
	self.dragStartScreen = nil
	self.dragMoved = false
	self.lastDragRenderAt = 0
	self.lastDragValue = nil
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
		mapTopLeft = Vector2.zero,
		mapScale = Vector2.one,
		mapSize = Vector2.zero,
		assetPreview = true,
		showLanes = true,
		showBuildMask = false,
		showConflicts = true,
		dragKind = nil,
		dragId = nil,
		dragHandle = nil,
		dragStartScreen = nil,
		dragMoved = false,
		lastDragRenderAt = 0,
		lastDragValue = nil,
		connections = {},
	}, WorldPathView)

	local function pointToLocal(position: Vector2): any?
		local stage = self.stage
		if stage == nil or self.mapScale.X <= 0 or self.mapScale.Y <= 0 then
			return nil
		end
		local point = position - self.root.AbsolutePosition - self.mapTopLeft
		if point.X < 0 or point.Y < 0 or point.X > self.mapSize.X or point.Y > self.mapSize.Y then
			return nil
		end
		local grid = stage.grid
		return {
			x = point.X / self.mapScale.X - grid.columns * grid.cellSize * 0.5,
			y = 0.48,
			z = point.Y / self.mapScale.Y - grid.rows * grid.cellSize * 0.5,
		}
	end

	local function resetDrag()
		self:cancelInteraction()
	end

	local function updateDrag(pointer: Vector2): boolean
		local localPosition = pointToLocal(pointer)
		if localPosition == nil or self.graph == nil or self.dragId == nil then
			return false
		end
		if self.dragKind == "Node" then
			local node = self.graph.nodes[self.dragId]
			if node == nil then
				return false
			end
			localPosition.y = node.position.y
			self.lastDragValue = localPosition
			self.callbacks.moveNode(self.dragId, localPosition, false)
			return true
		elseif self.dragKind == "Handle" and self.dragHandle ~= nil then
			local edge = self.graph.edges[self.dragId]
			if edge == nil then
				return false
			end
			local anchorId = if self.dragHandle == "Out" then edge.fromNodeId else edge.toNodeId
			local anchor = self.graph.nodes[anchorId]
			if anchor == nil then
				return false
			end
			local offset = {
				x = localPosition.x - anchor.position.x,
				y = if self.dragHandle == "Out" then edge.outHandleOffset.y else edge.inHandleOffset.y,
				z = localPosition.z - anchor.position.z,
			}
			self.lastDragValue = offset
			self.callbacks.moveHandle(self.dragId, self.dragHandle, offset, false)
			return true
		end
		return false
	end

	local function finishDrag(pointer: Vector2)
		local dragKind = self.dragKind
		local dragId = self.dragId
		local dragHandle = self.dragHandle
		local moved = self.dragMoved
		if moved then
			updateDrag(pointer)
		end
		local finalValue = self.lastDragValue
		resetDrag()
		if moved and dragKind == "Node" and dragId ~= nil and finalValue ~= nil then
			self.callbacks.moveNode(dragId, finalValue, true)
		elseif
			moved
			and dragKind == "Handle"
			and dragId ~= nil
			and dragHandle ~= nil
			and finalValue ~= nil
		then
			self.callbacks.moveHandle(dragId, dragHandle, finalValue, true)
		else
			self:rerender()
		end
	end

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				self.dragKind == nil
				or not self.root.Visible
				or input.UserInputType ~= Enum.UserInputType.MouseMovement
			then
				return
			end
			local pointer = Vector2.new(input.Position.X, input.Position.Y)
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				finishDrag(pointer)
				return
			end
			if self.dragStartScreen == nil or (pointer - self.dragStartScreen).Magnitude < 4 then
				return
			end
			local now = os.clock()
			if now - self.lastDragRenderAt < 0.05 then
				return
			end
			self.dragMoved = true
			self.lastDragRenderAt = now
			if updateDrag(pointer) then
				self:rerender()
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or self.dragKind == nil then
				return
			end
			finishDrag(Vector2.new(input.Position.X, input.Position.Y))
		end)
	)

	table.insert(
		self.connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
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
	self.stage = stage
	self.graph = graph
	self.preview = preview
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self:rerender()
end

function WorldPathView.rerender(self: Controller)
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

	local inspectorHeight = if self.selectedEdgeId ~= nil or self.selectedNodeId ~= nil then 216 else 54
	local mapHost = create("Frame", {
		BackgroundColor3 = WATER,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 1, -inspectorHeight - 4),
	}, self.root) :: Frame
	local hasWorldBackdrop = createWorldBackdrop(mapHost)
	local tint = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(23, 42, 32),
		BackgroundTransparency = if hasWorldBackdrop then 0.68 else 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, mapHost) :: Frame
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(31, 55, 39), Color3.fromRGB(15, 31, 25)),
		Rotation = 90,
		Transparency = NumberSequence.new(0.15, 0.55),
	}, tint)
	local grid = stage.grid
	local available = mapHost.AbsoluteSize
	if available.X <= 8 or available.Y <= 8 then
		return
	end
	local padding = 0
	local worldWidth = math.max(grid.columns * grid.cellSize, 1)
	local worldHeight = math.max(grid.rows * grid.cellSize, 1)
	local scale = Vector2.new(
		math.max((available.X - padding * 2) / worldWidth, 0.1),
		math.max((available.Y - padding * 2) / worldHeight, 0.1)
	)
	local mapSize = Vector2.new(worldWidth * scale.X, worldHeight * scale.Y)
	local topLeft = Vector2.new((available.X - mapSize.X) * 0.5, (available.Y - mapSize.Y) * 0.5)
	self.mapTopLeft = topLeft
	self.mapScale = scale
	self.mapSize = mapSize

	local canvas = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(50, 79, 54),
		BackgroundTransparency = if hasWorldBackdrop then 0.64 else 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(topLeft.X, topLeft.Y),
		Size = UDim2.fromOffset(mapSize.X, mapSize.Y),
	}, mapHost) :: Frame
	stroke(canvas, Color3.fromRGB(65, 98, 71), 1)

	local cellPixel = Vector2.new(grid.cellSize * scale.X, grid.cellSize * scale.Y)
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
					ZIndex = 1,
				}, canvas)
			end
		end
	end

	local function worldPoint(position: any): Vector2
		return Vector2.new(
			(position.x + worldWidth * 0.5) * scale.X,
			(position.z + worldHeight * 0.5) * scale.Y
		)
	end

	local bakedGraph = preview.pathGraphs[graph.id]
	if bakedGraph ~= nil then
		local edgeIds: { string } = {}
		for edgeId in bakedGraph.edges do
			table.insert(edgeIds, edgeId)
		end
		table.sort(edgeIds)
		for _, edgeId in edgeIds do
			local selectableEdgeId = edgeId
			local edge = bakedGraph.edges[edgeId]
			local profile = bakedGraph.laneProfiles[edge.laneProfileId]
			local radius = if profile ~= nil then profile.clearanceRadius else grid.cellSize * 0.5
			local routeScale = math.sqrt(scale.X * scale.Y)
			local walkwayWidth = math.max(radius * 2 * routeScale, 8)
			local samples = edge.samples or {}
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
				lineButton(canvas, first, second, walkwayWidth + 10, function()
					self.callbacks.selectEdge(selectableEdgeId)
				end)
				previousIndex = resolvedIndex
				if resolvedIndex == #samples then
					break
				end
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
		local nodeButton = create("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
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
		}, canvas) :: TextButton
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
		nodeButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.dragKind = "Node"
				self.dragId = nodeId
				self.dragHandle = nil
				self.dragStartScreen = Vector2.new(input.Position.X, input.Position.Y)
				self.dragMoved = false
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				self.callbacks.selectNode(nodeId)
			end
		end)
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
				local handle = create("TextButton", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					AutoButtonColor = false,
					BackgroundColor3 = SELECTED,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(point.X, point.Y),
					Size = UDim2.fromOffset(12, 12),
					Text = "",
					ZIndex = 22,
				}, canvas) :: TextButton
				rounded(handle, 8)
				stroke(handle, self.theme.text, 1)
				handle.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						self.dragKind = "Handle"
						self.dragId = selectedEdge.id
						self.dragHandle = definition.id
						self.dragStartScreen = Vector2.new(input.Position.X, input.Position.Y)
						self.dragMoved = false
						self.lastDragRenderAt = 0
						self.lastDragValue = nil
					end
				end)
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

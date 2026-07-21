--!strict

local RunService = game:GetService("RunService")

local CanvasTransform = require(script.Parent.Interaction.CanvasTransform)
local HitTest = require(script.Parent.Interaction.HitTest)
local PointerDrag = require(script.Parent.Interaction.PointerDrag)
local StageCell = require(script.Parent.Shared.StageCell)
local StagePathAssets = require(script.Parent.Shared.StagePathAssets)

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

export type WorldSize = CanvasTransform.Point2

export type Callbacks = {
	cancelInteraction: () -> (),
	backdropImage: () -> string?,
	mapWorldSize: () -> WorldSize?,
	worldSource: () -> Instance?,
	worldOrigin: () -> CFrame?,
	addNode: ("Spawn" | "Junction" | "Goal", any) -> (),
	selectNode: (string) -> (),
	selectEdge: (string) -> (),
	connectNode: (string) -> boolean?,
	splitEdge: (string) -> boolean,
	moveNode: (string, any, boolean) -> boolean,
	moveHandle: (string, string, any, boolean) -> boolean,
	setLanes: (string, number) -> (),
	setLaneWidth: (string, number) -> (),
	setPriority: (string, number) -> (),
	setCurveMode: (string, string) -> (),
	setPathAsset: (string, string) -> (),
	focusWorld: (string?) -> (),
	testSegment: (string) -> (),
}

export type Tool = "Select" | "Pan" | "AddSpawn" | "AddJunction" | "AddGoal" | "Connect" | "Split"

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
	transformMapId: string?,
	canvas: Frame?,
	interactionSurface: TextButton,
	backdropHost: Frame?,
	backdropImageLabel: ImageLabel?,
	backdropLoadStatus: TextLabel?,
	backdropImageContent: string?,
	backdropImageToken: number,
	backdropImageLoadConnection: RBXScriptConnection?,
	backdropCamera: Camera?,
	backdropSource: Instance?,
	backdropOrigin: CFrame?,
	backdropObservedSource: Instance?,
	backdropDirty: boolean,
	backdropDirtyAt: number,
	backdropRefreshScheduled: boolean,
	backdropRefreshToken: number,
	backdropSourceConnections: { RBXScriptConnection },
	backdropVisualConnections: { [Instance]: RBXScriptConnection },
	assetPreview: boolean,
	showLanes: boolean,
	showBuildMask: boolean,
	showConflicts: boolean,
	inspectorExpanded: boolean,
	tool: Tool,
	pointerState: PointerDrag.State,
	hitPrimitives: { HitTest.Primitive },
	hitBlockers: { GuiObject },
	touchPointerIds: { [InputObject]: string },
	nextTouchPointerId: number,
	lastDragRenderAt: number,
	lastDragValue: any?,
	dragGrabOffset: any?,
	panLastScreen: Vector2?,
	panPointerId: string?,
	pendingAddPointerId: string?,
	pendingAddStart: Vector2?,
	pendingAddKind: ("Spawn" | "Junction" | "Goal")?,
	activePointerInput: InputObject?,
	activePointerStateConnection: RBXScriptConnection?,
	lastPointerPosition: Vector2?,
	lastNodeClickAt: number,
	lastNodeClickPosition: Vector2?,
	lastNodeCandidateKey: string?,
	lastNodeClickId: string?,
	connections: { RBXScriptConnection },
	render: (Controller, any?, any?, any?, string?, string?, { [string]: boolean }) -> (),
	rerender: (Controller) -> (),
	fitToView: (Controller) -> (),
	setTool: (Controller, Tool) -> (),
	cancelInteraction: (Controller) -> boolean,
	destroy: (Controller) -> (),
}

local WorldPathView = {}
WorldPathView.__index = WorldPathView

local LANE = Color3.fromRGB(239, 236, 224)
local SELECTED = Color3.fromRGB(69, 207, 230)
local WATER = Color3.fromRGB(22, 68, 95)
local CANVAS_PADDING = 18
local MIN_WORLD_ZOOM = 1
local INSPECTOR_HEIGHT = 196
local COMPACT_INSPECTOR_HEIGHT = 210
local SHORT_INSPECTOR_HEIGHT = 104
local COLLAPSED_INSPECTOR_HEIGHT = 44
local NODE_HIT_RADIUS = 24
local HANDLE_HIT_RADIUS = 20
local CLICK_DRAG_THRESHOLD = 8
local NODE_CYCLE_SECONDS = 0.75
local NODE_CYCLE_RADIUS = 7
local DRAG_RENDER_INTERVAL = 0.04
local BACKDROP_REFRESH_DELAY = 0.18
local BACKDROP_LOAD_TIMEOUT = 8
local BACKDROP_ASPECT_RATIO = 16 / 9
local LEGACY_PATH_FOLDERS = {
	PathPoints = true,
	PathTiles = true,
}
local BACKDROP_VISUAL_PROPERTIES: { [string]: boolean } = {
	AlphaMode = true,
	Archivable = true,
	BackSurface = true,
	BottomSurface = true,
	BrickColor = true,
	CastShadow = true,
	CFrame = true,
	Color = true,
	Color3 = true,
	ColorMap = true,
	DoubleSided = true,
	Face = true,
	FrontSurface = true,
	LeftSurface = true,
	LocalTransparencyModifier = true,
	Material = true,
	MaterialVariant = true,
	MeshId = true,
	MeshType = true,
	MetalnessMap = true,
	Name = true,
	NormalMap = true,
	Offset = true,
	OffsetStudsU = true,
	OffsetStudsV = true,
	Orientation = true,
	PivotOffset = true,
	Position = true,
	Reflectance = true,
	RenderFidelity = true,
	RightSurface = true,
	RoughnessMap = true,
	Scale = true,
	Shape = true,
	Size = true,
	StudsPerTileU = true,
	StudsPerTileV = true,
	Texture = true,
	TextureID = true,
	TextureId = true,
	TopSurface = true,
	Transparency = true,
	UsePartColor = true,
	VertexColor = true,
	ZIndex = true,
}

local function backdropSource(self: Controller): Instance?
	local source = self.callbacks.worldSource()
	return if source ~= nil and (source:IsA("Model") or source:IsA("BasePart")) then source else nil
end

local function ensureBackdropHost(self: Controller, inspectorHeight: number): Frame
	local host = self.backdropHost
	if host == nil or host.Parent == nil then
		host = Instance.new("Frame")
		host.Active = false
		host.BackgroundColor3 = WATER
		host.BorderSizePixel = 0
		host.ClipsDescendants = true
		host.Name = "WorldBackdropHost"
		host.Position = UDim2.fromOffset(0, 0)
		host.ZIndex = 0
		host.Parent = self.root
		self.backdropHost = host
	end
	host.Size = UDim2.new(1, 0, 1, -inspectorHeight - 4)
	return host
end

local function clearWorldBackdrop(self: Controller)
	self.backdropImageToken += 1
	local imageLoadConnection = self.backdropImageLoadConnection
	self.backdropImageLoadConnection = nil
	if imageLoadConnection ~= nil then
		imageLoadConnection:Disconnect()
	end
	local host = self.backdropHost
	if host ~= nil then
		for _, child in host:GetChildren() do
			child:Destroy()
		end
	end
	self.backdropImageLabel = nil
	self.backdropLoadStatus = nil
	self.backdropImageContent = nil
	self.backdropCamera = nil
end

local function sanitizedClone(source: Instance): Instance?
	local cloned: Instance? = nil
	local clonedSuccessfully = pcall(function()
		cloned = source:Clone()
	end)
	if not clonedSuccessfully or cloned == nil then
		return nil
	end
	for _, descendant in cloned:GetDescendants() do
		if LEGACY_PATH_FOLDERS[descendant.Name] == true then
			descendant:Destroy()
		end
	end
	if cloned:IsA("BasePart") then
		cloned.Anchored = true
		cloned.CanCollide = false
		cloned.CanQuery = false
		cloned.CanTouch = false
	end
	for _, descendant in cloned:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("LayerCollector") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return cloned
end

local function disconnectBackdropSource(self: Controller)
	for _, connection in self.backdropSourceConnections do
		connection:Disconnect()
	end
	table.clear(self.backdropSourceConnections)
	for _, connection in self.backdropVisualConnections do
		connection:Disconnect()
	end
	table.clear(self.backdropVisualConnections)
	self.backdropObservedSource = nil
end

local function affectsBackdrop(instance: Instance): boolean
	return instance:IsA("BasePart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceAppearance")
		or instance:IsA("SpecialMesh")
end

local function isLegacyBackdropDescendant(instance: Instance, source: Instance): boolean
	local current: Instance? = instance
	while current ~= nil and current ~= source do
		if LEGACY_PATH_FOLDERS[current.Name] == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function shouldObserveBackdrop(instance: Instance, source: Instance): boolean
	return affectsBackdrop(instance) and not isLegacyBackdropDescendant(instance, source)
end

local function cancelBackdropRefresh(self: Controller)
	self.backdropRefreshToken += 1
	self.backdropRefreshScheduled = false
end

local function markBackdropDirty(self: Controller)
	self.backdropDirty = true
	self.backdropDirtyAt = os.clock()
	if self.backdropRefreshScheduled then
		return
	end
	self.backdropRefreshScheduled = true
	self.backdropRefreshToken += 1
	local token = self.backdropRefreshToken
	task.delay(BACKDROP_REFRESH_DELAY, function()
		while token == self.backdropRefreshToken do
			local remaining = BACKDROP_REFRESH_DELAY - (os.clock() - self.backdropDirtyAt)
			if remaining <= 0 then
				break
			end
			task.wait(remaining)
		end
		if token ~= self.backdropRefreshToken then
			return
		end
		self.backdropRefreshScheduled = false
		if self.backdropDirty and self.root.Parent ~= nil then
			self:rerender()
		end
	end)
end

local function observeBackdropSource(self: Controller, source: Instance)
	if self.backdropObservedSource == source then
		return
	end
	disconnectBackdropSource(self)
	self.backdropObservedSource = source
	markBackdropDirty(self)

	local function observeVisual(instance: Instance)
		if shouldObserveBackdrop(instance, source) and self.backdropVisualConnections[instance] == nil then
			self.backdropVisualConnections[instance] = instance.Changed:Connect(function(propertyName)
				if BACKDROP_VISUAL_PROPERTIES[propertyName] == true then
					markBackdropDirty(self)
				end
			end)
		end
	end

	observeVisual(source)
	for _, descendant in source:GetDescendants() do
		observeVisual(descendant)
	end
	table.insert(
		self.backdropSourceConnections,
		source.DescendantAdded:Connect(function(descendant)
			if shouldObserveBackdrop(descendant, source) then
				markBackdropDirty(self)
				observeVisual(descendant)
			end
		end)
	)
	table.insert(
		self.backdropSourceConnections,
		source.DescendantRemoving:Connect(function(descendant)
			local connection = self.backdropVisualConnections[descendant]
			if connection ~= nil then
				markBackdropDirty(self)
				connection:Disconnect()
				self.backdropVisualConnections[descendant] = nil
			end
		end)
	)
	table.insert(
		self.backdropSourceConnections,
		source.AncestryChanged:Connect(function()
			markBackdropDirty(self)
		end)
	)
end

local function updateBackdropCamera(self: Controller)
	local host = self.backdropHost
	local camera = self.backdropCamera
	local transform = self.transform
	if host == nil or camera == nil or transform == nil then
		return
	end
	local size = host.AbsoluteSize
	local scale = CanvasTransform.scale(transform)
	if size.X <= 0 or size.Y <= 0 or scale <= 0 then
		return
	end
	-- Matching the canvas' pixels-per-stud keeps the full-bleed ViewportFrame
	-- aligned with the fitted overlay while naturally revealing more world in
	-- the unused horizontal or vertical space.
	local aspect = math.max(size.X / size.Y, 0.25)
	local worldHeight = size.Y / scale
	local worldWidth = size.X / scale
	local visibleDepth = math.max(worldHeight, worldWidth / aspect)
	local cameraHeight = visibleDepth * 0.5 / math.tan(math.rad(camera.FieldOfView * 0.5))
	local center = Vector3.new(transform.center.x, 0, transform.center.y)
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, cameraHeight, 0), center, Vector3.new(0, 0, -1))
end

local function configuredBackdropImage(self: Controller): string?
	local configured = self.callbacks.backdropImage()
	if type(configured) ~= "string" then
		return nil
	end
	local trimmed = string.match(configured, "^%s*(.-)%s*$") or ""
	if string.match(trimmed, "^%d+$") ~= nil then
		return `rbxassetid://{trimmed}`
	end
	return if string.match(trimmed, "^rbxassetid://%d+$") ~= nil then trimmed else nil
end

local function imageCoverRect(
	transform: CanvasTransform.Transform,
	worldWidth: number,
	worldHeight: number
): (Vector2, Vector2)
	local coverWidth = worldWidth
	local coverHeight = worldHeight
	if coverWidth / coverHeight < BACKDROP_ASPECT_RATIO then
		coverWidth = coverHeight * BACKDROP_ASPECT_RATIO
	else
		coverHeight = coverWidth / BACKDROP_ASPECT_RATIO
	end
	local topLeftPoint = CanvasTransform.worldToCanvas(transform, {
		x = -coverWidth * 0.5,
		y = -coverHeight * 0.5,
	})
	local bottomRightPoint = CanvasTransform.worldToCanvas(transform, {
		x = coverWidth * 0.5,
		y = coverHeight * 0.5,
	})
	local topLeft = Vector2.new(topLeftPoint.x, topLeftPoint.y)
	return topLeft, Vector2.new(bottomRightPoint.x - topLeft.X, bottomRightPoint.y - topLeft.Y)
end

local function createImageBackdrop(
	self: Controller,
	host: Frame,
	transform: CanvasTransform.Transform,
	worldWidth: number,
	worldHeight: number,
	contentId: string
)
	disconnectBackdropSource(self)
	self.backdropDirty = false
	self.backdropSource = nil
	self.backdropOrigin = nil
	local image = self.backdropImageLabel
	local status = self.backdropLoadStatus
	if
		image == nil
		or image.Parent ~= host
		or status == nil
		or status.Parent ~= host
		or self.backdropImageContent ~= contentId
	then
		clearWorldBackdrop(self)
		image = Instance.new("ImageLabel")
		image.Name = "MapBackdropImage"
		image.BackgroundColor3 = Color3.fromRGB(13, 29, 36)
		image.BackgroundTransparency = 0
		image.BorderSizePixel = 0
		image.Image = contentId
		image.ImageColor3 = Color3.new(1, 1, 1)
		image.ImageTransparency = 0
		image.ResampleMode = Enum.ResamplerMode.Default
		image.ScaleType = Enum.ScaleType.Stretch
		image.ZIndex = 0
		image.Parent = host

		status = Instance.new("TextLabel")
		status.Name = "MapBackdropLoadStatus"
		status.AnchorPoint = Vector2.new(0.5, 0.5)
		status.BackgroundColor3 = Color3.fromRGB(10, 20, 26)
		status.BackgroundTransparency = 0.12
		status.BorderSizePixel = 0
		status.Font = Enum.Font.BuilderSansMedium
		status.Text = "Loading map artwork..."
		status.TextColor3 = Color3.fromRGB(221, 229, 235)
		status.TextSize = 12
		status.ZIndex = 2
		status.Parent = host
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = status

		self.backdropImageLabel = image
		self.backdropLoadStatus = status
		self.backdropImageContent = contentId
		self.backdropImageToken += 1
		local loadToken = self.backdropImageToken
		local observedImage = image :: ImageLabel
		local observedStatus = status :: TextLabel
		local function settleLoaded()
			if
				loadToken ~= self.backdropImageToken
				or observedImage.Parent == nil
				or observedStatus.Parent == nil
				or not observedImage.IsLoaded
			then
				return
			end
			observedStatus.Visible = false
			local connection = self.backdropImageLoadConnection
			if connection ~= nil then
				connection:Disconnect()
				self.backdropImageLoadConnection = nil
			end
		end
		self.backdropImageLoadConnection =
			observedImage:GetPropertyChangedSignal("IsLoaded"):Connect(settleLoaded)
		settleLoaded()
		task.delay(BACKDROP_LOAD_TIMEOUT, function()
			if
				loadToken ~= self.backdropImageToken
				or observedImage.Parent == nil
				or observedStatus.Parent == nil
			then
				return
			end
			if observedImage.IsLoaded then
				settleLoaded()
				return
			end
			observedStatus.Text = "Map image unavailable - check asset ownership or moderation"
			observedStatus.TextColor3 = Color3.fromRGB(255, 180, 105)
			observedStatus.Visible = true
		end)
	end

	local topLeft, imageSize = imageCoverRect(transform, worldWidth, worldHeight)
	image.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
	image.Size = UDim2.fromOffset(imageSize.X, imageSize.Y)
	status.Position = UDim2.fromOffset(topLeft.X + imageSize.X * 0.5, topLeft.Y + imageSize.Y * 0.5)
	status.Size = UDim2.fromOffset(math.clamp(imageSize.X - 32, 180, 420), 36)
	if image.IsLoaded then
		status.Visible = false
	end
end

local function createWorldBackdrop(self: Controller, host: Frame): boolean
	local source = backdropSource(self)
	if source == nil then
		disconnectBackdropSource(self)
		cancelBackdropRefresh(self)
		self.backdropDirty = false
		self.backdropSource = nil
		self.backdropOrigin = nil
		clearWorldBackdrop(self)
		return false
	end
	observeBackdropSource(self, source)
	local originFrame = self.callbacks.worldOrigin()
	if originFrame == nil then
		self.backdropSource = nil
		self.backdropOrigin = nil
		clearWorldBackdrop(self)
		return false
	end
	if self.backdropSource == source and self.backdropOrigin == originFrame and not self.backdropDirty then
		local ready = self.backdropCamera ~= nil and self.backdropCamera.Parent ~= nil
		if ready then
			updateBackdropCamera(self)
			return true
		end
	end

	self.backdropSource = nil
	self.backdropOrigin = nil
	clearWorldBackdrop(self)
	local cloned = sanitizedClone(source)
	if cloned == nil then
		return false
	end
	local alignment = originFrame:Inverse()
	if cloned:IsA("BasePart") then
		cloned.CFrame = alignment * cloned.CFrame
	end
	for _, descendant in cloned:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = alignment * descendant.CFrame
		end
	end

	local basePartCount = 0
	for _, descendant in cloned:GetDescendants() do
		if descendant:IsA("BasePart") then
			basePartCount += 1
		end
	end
	if cloned:IsA("BasePart") then
		basePartCount += 1
	end
	if basePartCount == 0 then
		cloned:Destroy()
		return false
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Active = false
	viewport.Ambient = Color3.fromRGB(118, 130, 116)
	viewport.BackgroundColor3 = WATER
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.ImageColor3 = Color3.fromRGB(235, 242, 232)
	viewport.LightColor = Color3.fromRGB(255, 244, 218)
	viewport.LightDirection = Vector3.new(-0.45, -1, -0.35)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 0
	viewport.Parent = host
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local scene = Instance.new("Model")
	scene.Name = "StagewrightWorldPreview"
	scene.Parent = world
	cloned.Parent = scene
	local camera = Instance.new("Camera")
	camera.FieldOfView = 26
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	self.backdropCamera = camera
	self.backdropSource = source
	self.backdropOrigin = originFrame
	self.backdropDirty = false
	updateBackdropCamera(self)
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

local function nodeColor(kind: string): Color3
	if kind == "Spawn" then
		return Color3.fromRGB(49, 166, 91)
	elseif kind == "Goal" then
		return Color3.fromRGB(132, 80, 207)
	end
	return Color3.fromRGB(238, 158, 48)
end

local function pathAssetColors(assetId: any): (Color3, Color3, Color3)
	local definition = StagePathAssets.find(assetId) or StagePathAssets.find(StagePathAssets.DEFAULT_ASSET_ID)
	local rgb = assert(definition, "Stagewright requires a default path asset").rgb
	local base = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	return base, base:Lerp(Color3.new(0, 0, 0), 0.42), base:Lerp(Color3.new(1, 1, 1), 0.34)
end

local function displayName(node: any?): string
	return if node ~= nil and type(node.name) == "string" then node.name else "Missing node"
end

local function liveEdgeSamples(graph: any, edge: any, segmentCount: number): { any }
	local from = graph.nodes[edge.fromNodeId]
	local to = graph.nodes[edge.toNodeId]
	if from == nil or to == nil then
		return {}
	end
	local p0 = from.position
	local p1 = {
		x = p0.x + edge.outHandleOffset.x,
		y = p0.y + edge.outHandleOffset.y,
		z = p0.z + edge.outHandleOffset.z,
	}
	local p3 = to.position
	local p2 = {
		x = p3.x + edge.inHandleOffset.x,
		y = p3.y + edge.inHandleOffset.y,
		z = p3.z + edge.inHandleOffset.z,
	}
	local samples: { any } = {}
	for index = 0, segmentCount do
		local t = index / segmentCount
		local inverse = 1 - t
		local inverseSquared = inverse * inverse
		local tSquared = t * t
		local x = inverseSquared * inverse * p0.x
			+ 3 * inverseSquared * t * p1.x
			+ 3 * inverse * tSquared * p2.x
			+ tSquared * t * p3.x
		local y = inverseSquared * inverse * p0.y
			+ 3 * inverseSquared * t * p1.y
			+ 3 * inverse * tSquared * p2.y
			+ tSquared * t * p3.y
		local z = inverseSquared * inverse * p0.z
			+ 3 * inverseSquared * t * p1.z
			+ 3 * inverse * tSquared * p2.z
			+ tSquared * t * p3.z
		local tangentX = 3 * inverseSquared * (p1.x - p0.x)
			+ 6 * inverse * t * (p2.x - p1.x)
			+ 3 * tSquared * (p3.x - p2.x)
		local tangentZ = 3 * inverseSquared * (p1.z - p0.z)
			+ 6 * inverse * t * (p2.z - p1.z)
			+ 3 * tSquared * (p3.z - p2.z)
		local magnitude = math.sqrt(tangentX * tangentX + tangentZ * tangentZ)
		if magnitude <= 1e-5 then
			tangentX = 1
			tangentZ = 0
			magnitude = 1
		end
		table.insert(samples, {
			position = { x = x, y = y, z = z },
			tangent = { x = tangentX / magnitude, y = 0, z = tangentZ / magnitude },
			up = { x = 0, y = 1, z = 0 },
		})
	end
	return samples
end

function WorldPathView.cancelInteraction(self: Controller): boolean
	local pointerResult = PointerDrag.cancel(self.pointerState, "Editor interaction cancelled")
	local canceled = #pointerResult.actions > 0
		or self.panLastScreen ~= nil
		or self.pendingAddPointerId ~= nil
	self.pointerState = pointerResult.state
	table.clear(self.touchPointerIds)
	self.lastDragRenderAt = 0
	self.lastDragValue = nil
	self.dragGrabOffset = nil
	self.panLastScreen = nil
	self.panPointerId = nil
	self.pendingAddPointerId = nil
	self.pendingAddStart = nil
	self.pendingAddKind = nil
	self.activePointerInput = nil
	self.lastPointerPosition = nil
	self.lastNodeClickAt = 0
	self.lastNodeClickPosition = nil
	self.lastNodeCandidateKey = nil
	self.lastNodeClickId = nil
	local stateConnection = self.activePointerStateConnection
	self.activePointerStateConnection = nil
	if stateConnection ~= nil then
		stateConnection:Disconnect()
	end
	return canceled
end

function WorldPathView.setTool(self: Controller, tool: Tool)
	if self.tool == tool then
		return
	end
	if
		PointerDrag.isActive(self.pointerState)
		or self.panLastScreen ~= nil
		or self.pendingAddPointerId ~= nil
	then
		self:cancelInteraction()
	end
	self.tool = tool
	self.lastNodeClickAt = 0
	self.lastNodeClickPosition = nil
	self.lastNodeCandidateKey = nil
	self.lastNodeClickId = nil
end

function WorldPathView.new(parent: Instance, theme: Theme, callbacks: Callbacks): Controller
	local root = create("Frame", {
		Active = true,
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, parent) :: Frame
	local interactionSurface = create("TextButton", {
		Active = true,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		Visible = false,
		ZIndex = 24,
	}, root) :: TextButton
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
		transformMapId = nil,
		canvas = nil,
		interactionSurface = interactionSurface,
		backdropHost = nil,
		backdropImageLabel = nil,
		backdropLoadStatus = nil,
		backdropImageContent = nil,
		backdropImageToken = 0,
		backdropImageLoadConnection = nil,
		backdropCamera = nil,
		backdropSource = nil,
		backdropOrigin = nil,
		backdropObservedSource = nil,
		backdropDirty = true,
		backdropDirtyAt = 0,
		backdropRefreshScheduled = false,
		backdropRefreshToken = 0,
		backdropSourceConnections = {},
		backdropVisualConnections = {},
		assetPreview = true,
		showLanes = true,
		showBuildMask = false,
		showConflicts = true,
		inspectorExpanded = false,
		tool = "Select",
		pointerState = PointerDrag.idle(),
		hitPrimitives = {},
		hitBlockers = {},
		touchPointerIds = {},
		nextTouchPointerId = 0,
		lastDragRenderAt = 0,
		lastDragValue = nil,
		dragGrabOffset = nil,
		panLastScreen = nil,
		panPointerId = nil,
		pendingAddPointerId = nil,
		pendingAddStart = nil,
		pendingAddKind = nil,
		activePointerInput = nil,
		activePointerStateConnection = nil,
		lastPointerPosition = nil,
		lastNodeClickAt = 0,
		lastNodeClickPosition = nil,
		lastNodeCandidateKey = nil,
		lastNodeClickId = nil,
		connections = {},
	}, WorldPathView)

	local function pointToLocal(position: Vector2, clampToGrid: boolean?): any?
		local stage = self.stage
		local transform = self.transform
		if stage == nil or transform == nil then
			return nil
		end
		local point = position - self.root.AbsolutePosition
		if
			not clampToGrid
			and (
				point.X < 0
				or point.Y < 0
				or point.X > transform.viewportSize.x
				or point.Y > transform.viewportSize.y
			)
		then
			return nil
		end
		local grid = stage.grid
		local worldPoint = CanvasTransform.canvasToWorld(transform, { x = point.X, y = point.Y })
		local halfWidth = grid.columns * grid.cellSize * 0.5
		local halfHeight = grid.rows * grid.cellSize * 0.5
		if
			not clampToGrid
			and (
				worldPoint.x < -halfWidth
				or worldPoint.x > halfWidth
				or worldPoint.y < -halfHeight
				or worldPoint.y > halfHeight
			)
		then
			return nil
		end
		return {
			x = math.clamp(worldPoint.x, -halfWidth, halfWidth),
			y = 0.48,
			z = math.clamp(worldPoint.y, -halfHeight, halfHeight),
		}
	end

	local function updateDrag(target: PointerDrag.Target, pointer: Vector2, finished: boolean): boolean
		local localPosition = pointToLocal(pointer, true)
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
				local grabOffset = self.dragGrabOffset
				if type(grabOffset) == "table" then
					local stage = self.stage
					local grid = if stage ~= nil then stage.grid else nil
					if grid ~= nil then
						local halfWidth = grid.columns * grid.cellSize * 0.5
						local halfHeight = grid.rows * grid.cellSize * 0.5
						value.x = math.clamp(value.x + grabOffset.x, -halfWidth, halfWidth)
						value.z = math.clamp(value.z + grabOffset.z, -halfHeight, halfHeight)
					end
				end
				value.y = node.position.y
				self.lastDragValue = value
			elseif finished then
				value = self.lastDragValue
			end
			if value == nil then
				return false
			end
			return self.callbacks.moveNode(target.id, value, finished)
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
				local grabOffset = self.dragGrabOffset
				value = {
					x = localPosition.x - anchor.position.x + if type(grabOffset) == "table"
						then grabOffset.x
						else 0,
					y = if target.handleId == "Out" then edge.outHandleOffset.y else edge.inHandleOffset.y,
					z = localPosition.z - anchor.position.z + if type(grabOffset) == "table"
						then grabOffset.z
						else 0,
				}
				self.lastDragValue = value
			elseif finished then
				value = self.lastDragValue
			end
			if value == nil then
				return false
			end
			return self.callbacks.moveHandle(target.id, target.handleId, value, finished)
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

	local function clearNodeClickCycle()
		self.lastNodeClickAt = 0
		self.lastNodeClickPosition = nil
		self.lastNodeCandidateKey = nil
		self.lastNodeClickId = nil
	end

	local function clickedNodeHit(position: PointerDrag.Point2): HitTest.Hit?
		local canvas = self.canvas
		if canvas == nil or canvas.Parent == nil then
			return nil
		end
		local canvasPosition = Vector2.new(position.x, position.y) - canvas.AbsolutePosition
		local hits = HitTest.resolveAll({ x = canvasPosition.X, y = canvasPosition.Y }, self.hitPrimitives)
		local candidateIds: { string } = {}
		for _, hit in hits do
			if hit.kind == "Node" then
				table.insert(candidateIds, hit.id)
			end
		end
		table.sort(candidateIds)
		local candidateKey = table.concat(candidateIds, "\0")
		local pointer = Vector2.new(position.x, position.y)
		local lastPosition = self.lastNodeClickPosition
		local now = os.clock()
		local repeated = candidateKey ~= ""
			and candidateKey == self.lastNodeCandidateKey
			and lastPosition ~= nil
			and (pointer - lastPosition).Magnitude <= NODE_CYCLE_RADIUS
			and now - self.lastNodeClickAt <= NODE_CYCLE_SECONDS
		local chosen = HitTest.cycleNode(hits, if repeated then self.lastNodeClickId else nil)
		self.lastNodeClickAt = now
		self.lastNodeClickPosition = pointer
		self.lastNodeCandidateKey = candidateKey
		self.lastNodeClickId = if chosen ~= nil then chosen.id else nil
		return chosen
	end

	local function dispatchPointerActions(actions: { PointerDrag.Action })
		for _, action in actions do
			if action.kind == "DragStarted" then
				clearNodeClickCycle()
				if self.tool == "Select" then
					if action.target.kind == "Node" then
						self.selectedNodeId = action.target.id
						self.selectedEdgeId = nil
						self.callbacks.selectNode(action.target.id)
						self.tracedEdgeIds = {}
					end
					self.lastDragRenderAt = os.clock()
					if
						updateDrag(action.target, Vector2.new(action.position.x, action.position.y), false)
					then
						self:rerender()
					end
				end
			elseif action.kind == "DragMoved" then
				if self.tool == "Select" then
					local now = os.clock()
					if now - self.lastDragRenderAt >= DRAG_RENDER_INTERVAL then
						self.lastDragRenderAt = now
						if
							updateDrag(
								action.target,
								Vector2.new(action.position.x, action.position.y),
								false
							)
						then
							self:rerender()
						end
					end
				end
			elseif action.kind == "Committed" then
				local committed = self.tool == "Select"
					and updateDrag(action.target, Vector2.new(action.position.x, action.position.y), true)
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				self.dragGrabOffset = nil
				if self.tool == "Select" and not committed then
					self:rerender()
				end
			elseif action.kind == "Clicked" then
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				self.dragGrabOffset = nil
				if action.target.kind == "Node" then
					local hit = clickedNodeHit(action.position)
					if hit ~= nil then
						if self.tool == "Connect" then
							self.callbacks.connectNode(hit.id)
						elseif self.tool == "Select" then
							self.selectedNodeId = hit.id
							self.selectedEdgeId = nil
							self.callbacks.selectNode(hit.id)
							self.tracedEdgeIds = {}
							self:rerender()
						end
					end
				elseif action.target.kind == "Edge" then
					clearNodeClickCycle()
					if self.tool == "Split" then
						self.callbacks.splitEdge(action.target.id)
					elseif self.tool == "Select" then
						self.selectedEdgeId = action.target.id
						self.selectedNodeId = nil
						self.callbacks.selectEdge(action.target.id)
						self.tracedEdgeIds = {}
						self:rerender()
					end
				else
					clearNodeClickCycle()
				end
			elseif action.kind == "Cancelled" then
				self.lastDragRenderAt = 0
				self.lastDragValue = nil
				self.dragGrabOffset = nil
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

	local pluginGui: PluginGui? = nil
	local ancestor: Instance? = root.Parent
	while ancestor ~= nil do
		if ancestor:IsA("PluginGui") then
			pluginGui = ancestor :: PluginGui
			break
		end
		ancestor = ancestor.Parent
	end

	local function pointerPosition(input: InputObject): Vector2
		if
			pluginGui ~= nil
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton3
				or input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.MouseWheel
			)
		then
			return pluginGui:GetRelativeMousePosition()
		end
		return Vector2.new(input.Position.X, input.Position.Y)
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

	table.insert(
		self.connections,
		interactionSurface.InputChanged:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseWheel
				or not input:IsModifierKeyDown(Enum.ModifierKey.Ctrl)
				or not isVisible()
				or PointerDrag.isActive(self.pointerState)
				or self.panLastScreen ~= nil
				or input.Position.Z == 0
			then
				return
			end
			local pointer = pointerPosition(input)
			local point, transform = viewportPoint(pointer)
			if point == nil or transform == nil then
				return
			end
			local factor = if input.Position.Z > 0 then 1.12 else 1 / 1.12
			local requestedZoom = transform.zoom * factor
			self.transform = if requestedZoom <= MIN_WORLD_ZOOM
				then CanvasTransform.resetFit(transform)
				else CanvasTransform.zoomAt(transform, factor, point)
			self:rerender()
		end)
	)

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

	local function emptyCanvasPosition(pointer: Vector2): any?
		local canvas = self.canvas
		if viewportPoint(pointer) == nil or canvas == nil or canvas.Parent == nil then
			return nil
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
				return nil
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
			return nil
		end
		if HitTest.resolve({ x = canvasPosition.X, y = canvasPosition.Y }, self.hitPrimitives) ~= nil then
			return nil
		end
		return pointToLocal(pointer)
	end

	local function beginPrimaryPointer(input: InputObject, pointer: Vector2)
		if
			self.panLastScreen ~= nil
			or self.pendingAddPointerId ~= nil
			or PointerDrag.isActive(self.pointerState)
		then
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
		local insideCanvas = not (
			canvasPosition.X < 0
			or canvasPosition.Y < 0
			or canvasPosition.X > canvasSize.X
			or canvasPosition.Y > canvasSize.Y
		)
		local hit: HitTest.Hit? = nil
		if insideCanvas then
			local hits =
				HitTest.resolveAll({ x = canvasPosition.X, y = canvasPosition.Y }, self.hitPrimitives)
			if self.tool == "Connect" then
				hit = HitTest.cycleNode(hits, nil)
			elseif self.tool == "Split" then
				for _, candidate in hits do
					if candidate.kind == "Edge" then
						hit = candidate
						break
					end
				end
			else
				hit = HitTest.preferSelectedNode(hits, self.selectedNodeId)
			end
		end
		local addKind = if self.tool == "AddSpawn"
			then "Spawn"
			elseif self.tool == "AddJunction" then "Junction"
			elseif self.tool == "AddGoal" then "Goal"
			else nil
		if addKind ~= nil then
			if insideCanvas and hit == nil and pointToLocal(pointer) ~= nil then
				local resolvedPointerId = pointerId(input, true)
				if resolvedPointerId ~= nil then
					self.pendingAddPointerId = resolvedPointerId
					self.pendingAddStart = pointer
					self.pendingAddKind = addKind
				end
			end
			return
		end
		if self.tool == "Pan" then
			local resolvedPointerId = pointerId(input, true)
			if resolvedPointerId ~= nil then
				self.panLastScreen = pointer
				self.panPointerId = resolvedPointerId
			end
			return
		end
		if not insideCanvas or hit == nil then
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
		self.lastDragValue = if self.tool == "Select" then seedDragValue(target) else nil
		self.dragGrabOffset = nil
		local pointerLocal = pointToLocal(pointer, true)
		if self.tool == "Select" and pointerLocal ~= nil and target.kind == "Node" then
			local node = if self.graph ~= nil then self.graph.nodes[target.id] else nil
			if node ~= nil then
				self.dragGrabOffset = {
					x = node.position.x - pointerLocal.x,
					z = node.position.z - pointerLocal.z,
				}
			end
		elseif
			self.tool == "Select"
			and pointerLocal ~= nil
			and target.kind == "Handle"
			and target.handleId ~= nil
		then
			local edge = if self.graph ~= nil then self.graph.edges[target.id] else nil
			if edge ~= nil then
				local anchorId = if target.handleId == "Out" then edge.fromNodeId else edge.toNodeId
				local anchor = self.graph.nodes[anchorId]
				local offset = if target.handleId == "Out" then edge.outHandleOffset else edge.inHandleOffset
				if anchor ~= nil then
					self.dragGrabOffset = {
						x = anchor.position.x + offset.x - pointerLocal.x,
						z = anchor.position.z + offset.z - pointerLocal.z,
					}
				end
			end
		end
		local result =
			PointerDrag.press(self.pointerState, resolvedPointerId, target, { x = pointer.X, y = pointer.Y })
		self.pointerState = result.state
	end

	local function moveCapturedPointer(pointer: Vector2)
		local input = self.activePointerInput
		if input == nil or not isVisible() then
			return
		end
		self.lastPointerPosition = pointer
		local resolvedPointerId = pointerId(input, false)
		local pendingPointerId = self.pendingAddPointerId
		if pendingPointerId ~= nil and resolvedPointerId == pendingPointerId then
			local start = self.pendingAddStart
			if start ~= nil and (pointer - start).Magnitude > CLICK_DRAG_THRESHOLD then
				self.pendingAddKind = nil
			end
			return
		end
		if self.panLastScreen ~= nil then
			local matchesPan = self.panPointerId == "mouse-middle" or resolvedPointerId == self.panPointerId
			if matchesPan then
				local transform = self.transform
				local panLastScreen = self.panLastScreen
				local delta = pointer - panLastScreen
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
					updateBackdropCamera(self)
				end
				return
			end
		end
		if not PointerDrag.isActive(self.pointerState) or resolvedPointerId == nil then
			return
		end
		local result = PointerDrag.move(
			self.pointerState,
			resolvedPointerId,
			{ x = pointer.X, y = pointer.Y },
			CLICK_DRAG_THRESHOLD
		)
		self.pointerState = result.state
		dispatchPointerActions(result.actions)
	end

	local function clearPointerCapture()
		local stateConnection = self.activePointerStateConnection
		self.activePointerStateConnection = nil
		if stateConnection ~= nil then
			stateConnection:Disconnect()
		end
		self.activePointerInput = nil
		self.lastPointerPosition = nil
	end

	local function finishCapturedPointer(input: InputObject, canceled: boolean)
		if self.activePointerInput ~= input then
			return
		end
		local isMousePointer = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton3
		local pointer = if isMousePointer and not canceled
			then pointerPosition(input)
			else self.lastPointerPosition or pointerPosition(input)
		local resolvedPointerId = pointerId(input, false)
		clearPointerCapture()
		if canceled then
			self.callbacks.cancelInteraction()
			return
		end
		if resolvedPointerId == nil and self.panPointerId ~= "mouse-middle" then
			return
		end
		if resolvedPointerId == self.pendingAddPointerId then
			local start = self.pendingAddStart
			local addKind = self.pendingAddKind
			self.pendingAddPointerId = nil
			self.pendingAddStart = nil
			self.pendingAddKind = nil
			if start ~= nil and addKind ~= nil and (pointer - start).Magnitude <= CLICK_DRAG_THRESHOLD then
				local localPosition = emptyCanvasPosition(pointer)
				if localPosition ~= nil then
					self.callbacks.addNode(addKind, localPosition)
				end
			end
		elseif self.panPointerId == "mouse-middle" or resolvedPointerId == self.panPointerId then
			self.panLastScreen = nil
			self.panPointerId = nil
		else
			local result = PointerDrag.release(self.pointerState, resolvedPointerId :: string, {
				x = pointer.X,
				y = pointer.Y,
			}, CLICK_DRAG_THRESHOLD)
			self.pointerState = result.state
			dispatchPointerActions(result.actions)
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			self.touchPointerIds[input] = nil
		end
	end

	local function capturePointer(input: InputObject, pointer: Vector2)
		clearPointerCapture()
		self.activePointerInput = input
		self.lastPointerPosition = pointer
		self.activePointerStateConnection = input
			:GetPropertyChangedSignal("UserInputState")
			:Connect(function()
				local inputState = input.UserInputState
				if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
					finishCapturedPointer(input, inputState == Enum.UserInputState.Cancel)
				end
			end)
	end

	table.insert(
		self.connections,
		interactionSurface.InputBegan:Connect(function(input)
			if not isVisible() or self.activePointerInput ~= nil then
				return
			end
			local pointer = pointerPosition(input)
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				if
					self.panLastScreen == nil
					and not PointerDrag.isActive(self.pointerState)
					and viewportPoint(pointer) ~= nil
				then
					self.panLastScreen = pointer
					self.panPointerId = "mouse-middle"
					capturePointer(input, pointer)
				end
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginPrimaryPointer(input, pointer)
				if
					PointerDrag.isActive(self.pointerState)
					or self.panLastScreen ~= nil
					or self.pendingAddPointerId ~= nil
				then
					capturePointer(input, pointer)
				end
			end
		end)
	)

	table.insert(
		self.connections,
		interactionSurface.InputChanged:Connect(function(input)
			local activeInput = self.activePointerInput
			if activeInput == nil then
				return
			end
			if input == activeInput or input.UserInputType == Enum.UserInputType.MouseMovement then
				moveCapturedPointer(pointerPosition(activeInput))
			end
		end)
	)

	table.insert(
		self.connections,
		interactionSurface.InputEnded:Connect(function(input)
			finishCapturedPointer(input, false)
		end)
	)

	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			local input = self.activePointerInput
			if
				input == nil
				or (
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.MouseButton3
				)
			then
				return
			end
			local pointer = pointerPosition(input)
			if self.lastPointerPosition == nil or (pointer - self.lastPointerPosition).Magnitude > 0.1 then
				moveCapturedPointer(pointer)
			end
		end)
	)

	table.insert(
		self.connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if
				PointerDrag.isActive(self.pointerState)
				or self.panLastScreen ~= nil
				or self.pendingAddPointerId ~= nil
			then
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
	local nextMapId = if stage ~= nil
			and type(stage.mapId) == "string"
			and stage.mapId ~= ""
		then stage.mapId
		elseif stage ~= nil and type(stage.id) == "string" then stage.id
		else nil
	if self.transformMapId ~= nextMapId then
		self.transform = nil
	end
	self.transformMapId = nextMapId
	self.stage = stage
	self.graph = graph
	self.preview = preview
	self.selectedNodeId = selectedNodeId
	self.selectedEdgeId = selectedEdgeId
	self.tracedEdgeIds = tracedEdgeIds
	self:rerender()
end

function WorldPathView.fitToView(self: Controller)
	self.transform = nil
	self:rerender()
end

function WorldPathView.rerender(self: Controller)
	self.canvas = nil
	self.interactionSurface.Visible = false
	table.clear(self.hitPrimitives)
	table.clear(self.hitBlockers)
	for _, child in self.root:GetChildren() do
		if child:IsA("GuiObject") and child ~= self.backdropHost and child ~= self.interactionSurface then
			child:Destroy()
		end
	end
	local stage = self.stage
	local graph = self.graph
	local preview = self.preview
	if stage == nil or graph == nil or preview == nil then
		if self.backdropHost ~= nil then
			self.backdropHost.Visible = false
		end
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

	local shortViewport = self.root.AbsoluteSize.Y < 460
	local expandedInspectorHeight = if shortViewport then SHORT_INSPECTOR_HEIGHT else INSPECTOR_HEIGHT
	if not shortViewport and self.root.AbsoluteSize.X < 1_560 then
		expandedInspectorHeight = COMPACT_INSPECTOR_HEIGHT
	end
	local inspectorHeight = if self.inspectorExpanded
		then expandedInspectorHeight
		else COLLAPSED_INSPECTOR_HEIGHT
	local backdropHost = ensureBackdropHost(self, inspectorHeight)
	local mapHost = create("Frame", {
		-- A neutral full-bleed ground fallback keeps wide widgets useful even
		-- before an authored island model exists. The stage grid remains the
		-- truthful coordinate boundary without reading as a tiny map in water.
		BackgroundColor3 = Color3.fromRGB(24, 52, 45),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 1, -inspectorHeight - 4),
		ZIndex = 1,
	}, self.root) :: Frame
	self.interactionSurface.Size = mapHost.Size
	self.interactionSurface.Visible = true
	local grid = stage.grid
	local available = mapHost.AbsoluteSize
	if available.X <= CANVAS_PADDING * 2 or available.Y <= CANVAS_PADDING * 2 then
		return
	end
	local liveWorldWidth = math.max(grid.columns * grid.cellSize, 1)
	local liveWorldHeight = math.max(grid.rows * grid.cellSize, 1)
	local mapWorldWidth = liveWorldWidth
	local mapWorldHeight = liveWorldHeight
	local configuredMapWorldSize = self.callbacks.mapWorldSize()
	if
		configuredMapWorldSize ~= nil
		and configuredMapWorldSize.x == configuredMapWorldSize.x
		and configuredMapWorldSize.y == configuredMapWorldSize.y
		and configuredMapWorldSize.x > 0
		and configuredMapWorldSize.y > 0
		and configuredMapWorldSize.x < math.huge
		and configuredMapWorldSize.y < math.huge
	then
		mapWorldWidth = math.max(mapWorldWidth, configuredMapWorldSize.x)
		mapWorldHeight = math.max(mapWorldHeight, configuredMapWorldSize.y)
	end
	local viewportSize = { x = available.X, y = available.Y }
	local transform = self.transform
	if
		transform == nil
		or transform.worldSize.x ~= mapWorldWidth
		or transform.worldSize.y ~= mapWorldHeight
	then
		transform = CanvasTransform.fit(
			viewportSize,
			{ x = mapWorldWidth, y = mapWorldHeight },
			CANVAS_PADDING,
			{ x = 0, y = 0 }
		)
	elseif transform.viewportSize.x ~= available.X or transform.viewportSize.y ~= available.Y then
		transform = CanvasTransform.resize(transform, viewportSize)
	end
	local resolvedTransform = assert(transform, "World Path canvas transform was not initialized")
	self.transform = resolvedTransform
	local scale = CanvasTransform.scale(resolvedTransform)
	local configuredImage = configuredBackdropImage(self)
	local hasImageBackdrop = configuredImage ~= nil
	local hasWorldBackdrop = false
	if configuredImage ~= nil then
		createImageBackdrop(
			self,
			backdropHost,
			resolvedTransform,
			mapWorldWidth,
			mapWorldHeight,
			configuredImage
		)
	else
		hasWorldBackdrop = createWorldBackdrop(self, backdropHost)
		updateBackdropCamera(self)
	end
	local hasBackdrop = hasImageBackdrop or hasWorldBackdrop
	backdropHost.Visible = hasBackdrop
	mapHost.BackgroundTransparency = if hasBackdrop then 1 else 0
	local topLeftPoint = CanvasTransform.worldToCanvas(resolvedTransform, {
		x = -liveWorldWidth * 0.5,
		y = -liveWorldHeight * 0.5,
	})
	local bottomRightPoint = CanvasTransform.worldToCanvas(resolvedTransform, {
		x = liveWorldWidth * 0.5,
		y = liveWorldHeight * 0.5,
	})
	local topLeft = Vector2.new(topLeftPoint.x, topLeftPoint.y)
	local mapSize = Vector2.new(bottomRightPoint.x - topLeftPoint.x, bottomRightPoint.y - topLeftPoint.y)

	local defaultTerrainId = grid.defaultCell.terrainId
	local defaultTerrainColor = if defaultTerrainId == "void"
		then self.theme.void
		else Color3.fromRGB(50, 79, 54)
	local canvas = create("Frame", {
		BackgroundColor3 = defaultTerrainColor,
		BackgroundTransparency = if hasImageBackdrop then 1 elseif hasWorldBackdrop then 0.82 else 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(topLeft.X, topLeft.Y),
		Size = UDim2.fromOffset(mapSize.X, mapSize.Y),
		ZIndex = 1,
	}, mapHost) :: Frame
	self.canvas = canvas
	local tint = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(23, 42, 32),
		BackgroundTransparency = if hasImageBackdrop then 1 elseif hasWorldBackdrop then 0.88 else 1,
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
		-- The old renderer allocated one bordered Frame per cell. Drawing only
		-- terrain overrides plus shared grid lines keeps the same coordinate truth
		-- with a much smaller instance budget during node drags.
		for key in grid.cells do
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			local column = if columnText ~= nil then tonumber(columnText) else nil
			local row = if rowText ~= nil then tonumber(rowText) else nil
			if
				column ~= nil
				and row ~= nil
				and column >= 1
				and column <= grid.columns
				and row >= 1
				and row <= grid.rows
			then
				local cell = StageCell.resolve(grid.defaultCell, grid.cells[key])
				if cell.terrainId ~= defaultTerrainId then
					create("Frame", {
						BackgroundColor3 = if cell.terrainId == "void"
							then self.theme.void
							else Color3.fromRGB(60, 91, 64),
						BackgroundTransparency = if hasBackdrop then 0.56 else 0,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset((column - 1) * cellPixel.X, (row - 1) * cellPixel.Y),
						Size = UDim2.fromOffset(math.ceil(cellPixel.X), math.ceil(cellPixel.Y)),
						ZIndex = 2,
					}, canvas)
				end
			end
		end
		local gridTransparency = if hasBackdrop then 0.72 else 0.42
		for column = 0, grid.columns do
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(40, 68, 45),
				BackgroundTransparency = gridTransparency,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(math.round(column * cellPixel.X), 0),
				Size = UDim2.fromOffset(1, math.ceil(mapSize.Y)),
				ZIndex = 3,
			}, canvas)
		end
		for row = 0, grid.rows do
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(40, 68, 45),
				BackgroundTransparency = gridTransparency,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, math.round(row * cellPixel.Y)),
				Size = UDim2.fromOffset(math.ceil(mapSize.X), 1),
				ZIndex = 3,
			}, canvas)
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
		local dragging = PointerDrag.isActive(self.pointerState)
		local renderGraph = if dragging then graph else bakedGraph
		local edgeIds: { string } = {}
		for edgeId in renderGraph.edges do
			table.insert(edgeIds, edgeId)
		end
		table.sort(edgeIds)
		local segmentBudget = if dragging then 96 else 240
		local maximumSegmentsPerEdge = math.clamp(math.floor(segmentBudget / math.max(#edgeIds, 1)), 8, 36)
		for _, edgeId in edgeIds do
			local edge = renderGraph.edges[edgeId]
			local profile = renderGraph.laneProfiles[edge.laneProfileId]
			local metadata = if type(edge.metadata) == "table" then edge.metadata else {}
			local assetBase, assetDark, assetLight = pathAssetColors(metadata.pathAssetId)
			local radius = if profile ~= nil then profile.clearanceRadius else grid.cellSize * 0.5
			local routeScale = scale
			local walkwayWidth = math.max(radius * 2 * routeScale, 8)
			local samples = if dragging
				then liveEdgeSamples(graph, edge, maximumSegmentsPerEdge)
				else edge.samples or {}
			local edgeHitPoints: { HitTest.Point2 } = {}
			if #samples > 0 then
				local firstPoint = worldPoint(samples[1].position)
				table.insert(edgeHitPoints, { x = firstPoint.X, y = firstPoint.Y })
			end
			local step = math.max(math.ceil(math.max(#samples - 1, 1) / maximumSegmentsPerEdge), 1)
			local previousIndex = 1
			local selected = self.selectedEdgeId == edgeId
			local traced = self.tracedEdgeIds[edgeId] == true
			if #samples >= 2 then
				for index = math.min(1 + step, #samples), #samples, step do
					local resolvedIndex = if index + step > #samples then #samples else index
					local first = worldPoint(samples[previousIndex].position)
					local second = worldPoint(samples[resolvedIndex].position)
					if traced then
						line(canvas, first, second, self.theme.success, walkwayWidth + 10, 3, 0.24)
					end
					if selected then
						line(canvas, first, second, SELECTED, walkwayWidth + 6, 4, 0.02)
					end
					if self.assetPreview then
						line(canvas, first, second, assetDark, walkwayWidth + 4, 5, 0)
						line(canvas, first, second, assetBase, walkwayWidth, 7, 0)
						line(canvas, first, second, assetLight, math.max(walkwayWidth * 0.08, 1), 8, 0.68)
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
					if #samples >= 2 then
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
			local cell = StageCell.resolve(grid.defaultCell, grid.cells[key])
			local traversalConflict = cell.enemyTraversalPolicy == "Blocked"
			if traversalConflict then
				conflictCount += 1
				conflictCenter += Vector2.new((column - 0.5) * cellPixel.X, (row - 0.5) * cellPixel.Y)
			end
			local showConflictCell = self.showConflicts and traversalConflict
			if not PointerDrag.isActive(self.pointerState) and (showConflictCell or self.showBuildMask) then
				local conflict = create("Frame", {
					BackgroundColor3 = if showConflictCell then self.theme.warning else SELECTED,
					BackgroundTransparency = if showConflictCell then 0.76 else 0.88,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Position = UDim2.fromOffset((column - 1) * cellPixel.X + 1, (row - 1) * cellPixel.Y + 1),
					Size = UDim2.fromOffset(math.max(cellPixel.X - 2, 2), math.max(cellPixel.Y - 2, 2)),
					ZIndex = 12,
				}, canvas) :: Frame
				if showConflictCell then
					stroke(conflict, self.theme.warning, 2)
					for stripeIndex = -1, 1 do
						create("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundColor3 = self.theme.warning,
							BackgroundTransparency = 0.16,
							BorderSizePixel = 0,
							Position = UDim2.new(0.5, stripeIndex * 8, 0.5, 0),
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
			area = "Marker",
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
		local nodeSize = if self.selectedNodeId == nodeId
			then 24
			elseif node.kind == "Junction" then 19
			else 21
		local nodeButton = create("TextLabel", {
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = nodeColor(node.kind),
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(point.X, point.Y),
			Size = UDim2.fromOffset(nodeSize, nodeSize),
			Text = if node.kind == "Spawn" then "S" elseif node.kind == "Goal" then "G" else "+",
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
		local labelWidth = math.clamp(#node.name * 7 + 22, 70, 138)
		local labelHeight = 22
		local labelGap = 9
		local labelCenter: Vector2
		if node.kind == "Spawn" then
			local above = point.Y - nodeSize * 0.5 - labelGap - labelHeight * 0.5
			local resolvedY = if above - labelHeight * 0.5 >= 4
				then above
				else point.Y + nodeSize * 0.5 + labelGap + labelHeight * 0.5
			labelCenter = Vector2.new(point.X, resolvedY)
		else
			local right = point.X + nodeSize * 0.5 + labelGap + labelWidth * 0.5
			local resolvedX = if right + labelWidth * 0.5 <= mapSize.X - 4
				then right
				else point.X - nodeSize * 0.5 - labelGap - labelWidth * 0.5
			labelCenter = Vector2.new(resolvedX, point.Y)
		end
		local halfLabelWidth = labelWidth * 0.5
		local halfLabelHeight = labelHeight * 0.5
		labelCenter = Vector2.new(
			if mapSize.X >= labelWidth + 8
				then math.clamp(labelCenter.X, halfLabelWidth + 4, mapSize.X - halfLabelWidth - 4)
				else mapSize.X * 0.5,
			if mapSize.Y >= labelHeight + 8
				then math.clamp(labelCenter.Y, halfLabelHeight + 4, mapSize.Y - halfLabelHeight - 4)
				else mapSize.Y * 0.5
		)
		local label = create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(17, 21, 24),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Position = UDim2.fromOffset(labelCenter.X, labelCenter.Y),
			Size = UDim2.fromOffset(labelWidth, labelHeight),
			Text = `  {node.name}  `,
			TextColor3 = self.theme.text,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 19,
		}, canvas) :: TextLabel
		rounded(label, 5)
		local labelHitRadius = 13
		local hitSpan = math.max(labelWidth - labelHitRadius * 2, 0)
		local hitCount = math.max(math.ceil(hitSpan / (labelHitRadius * 1.5)) + 1, 1)
		for hitIndex = 1, hitCount do
			local alpha = if hitCount == 1 then 0.5 else (hitIndex - 1) / (hitCount - 1)
			table.insert(self.hitPrimitives, {
				kind = "Node",
				id = nodeId,
				center = {
					x = labelCenter.X - hitSpan * 0.5 + hitSpan * alpha,
					y = labelCenter.Y,
				},
				radius = labelHitRadius,
				area = "Label",
			})
		end
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

	local legendWidth = 156
	local legendHeight = 126
	local legendInset = 20
	local legendLeft = legendInset
	local legendTop = available.Y - legendInset - legendHeight
	local legendRight = legendLeft + legendWidth
	local legendBottom = legendTop + legendHeight
	local legendHasClearSpace = true
	for _, primitive in self.hitPrimitives do
		if primitive.kind == "Node" or primitive.kind == "Handle" then
			local centerX = topLeft.X + primitive.center.x
			local centerY = topLeft.Y + primitive.center.y
			local radius = primitive.radius
			if
				centerX + radius >= legendLeft
				and centerX - radius <= legendRight
				and centerY + radius >= legendTop
				and centerY - radius <= legendBottom
			then
				legendHasClearSpace = false
				break
			end
		end
	end
	local legend = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(18, 22, 27),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = UDim2.new(0, legendInset, 1, -legendInset),
		Size = UDim2.fromOffset(legendWidth, legendHeight),
		ZIndex = 25,
	}, mapHost) :: Frame
	legend.Visible = available.X >= 1_000 and available.Y >= 300 and legendHasClearSpace
	if legend.Visible then
		table.insert(self.hitBlockers, legend)
	end
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
	local selectedAssetId = if selectedEdge ~= nil and type(selectedEdge.metadata) == "table"
		then selectedEdge.metadata.pathAssetId
		else StagePathAssets.DEFAULT_ASSET_ID
	local selectedAssetBase, selectedAssetDark, selectedAssetLight = pathAssetColors(selectedAssetId)
	local gravelSwatch = create("Frame", {
		BackgroundColor3 = selectedAssetBase,
		BorderColor3 = selectedAssetDark,
		BorderSizePixel = 2,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.fromOffset(24, 18),
		ZIndex = 26,
	}, legend) :: Frame
	create("UIGradient", {
		Color = ColorSequence.new(selectedAssetDark, selectedAssetLight),
		Rotation = 35,
	}, gravelSwatch)
	legendLabel(`{StagePathAssets.label(selectedAssetId)} asset`, 1)
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
	for stripe = -1, 1 do
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
	local compactInspector = shortViewport or self.root.AbsoluteSize.X < 1_560
	local headerDividerY = if not self.inspectorExpanded
		then COLLAPSED_INSPECTOR_HEIGHT - 1
		elseif compactInspector then 42
		else 44
	local selectedSummary = if selectedEdge ~= nil
		then `Selected spline  |  {displayName(fromNode)} -> {displayName(toNode)}`
		elseif self.selectedNodeId ~= nil then `Selected node  |  {displayName(
			graph.nodes[self.selectedNodeId]
		)}`
		else "Select a path spline or route marker to edit it"
	local inspectorToggle = create("TextButton", {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 36),
		Text = `{if self.inspectorExpanded then "v" else "^"}   {selectedSummary}`,
		TextColor3 = self.theme.text,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 30,
	}, inspector) :: TextButton
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, inspectorToggle)
	inspectorToggle.Activated:Connect(function()
		self.inspectorExpanded = not self.inspectorExpanded
		self:rerender()
	end)
	create("Frame", {
		BackgroundColor3 = self.theme.border,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, headerDividerY),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 30,
	}, inspector)
	if not self.inspectorExpanded then
		return
	end
	if selectedEdge ~= nil and self.selectedEdgeId ~= nil then
		local edgeId = self.selectedEdgeId
		local profile = graph.laneProfiles[selectedEdge.laneProfileId]
		local laneCount = if profile ~= nil then #profile.offsets else 1
		local metadata = if type(selectedEdge.metadata) == "table" then selectedEdge.metadata else {}
		local pathAssetId = if type(metadata.pathAssetId) == "string"
			then metadata.pathAssetId
			else StagePathAssets.DEFAULT_ASSET_ID
		local pathAssetLabel = StagePathAssets.label(pathAssetId)
		local laneWidth = if type(metadata.laneWidth) == "number" then metadata.laneWidth else 4
		local curveMode = if type(metadata.curveMode) == "string" then metadata.curveMode else "Free"
		local fieldHeight = if compactInspector then 32 else 36
		local function fieldLabel(text: string, x: number, width: number, labelY: number)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(x, labelY),
				Size = UDim2.fromOffset(width, 14),
				Text = text,
				TextColor3 = self.theme.muted,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector)
		end
		local function field(text: string, x: number, width: number, fieldY: number): TextLabel
			local result = create("TextLabel", {
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(x, fieldY),
				Size = UDim2.fromOffset(width, fieldHeight),
				Text = text,
				TextColor3 = self.theme.text,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector) :: TextLabel
			rounded(result, 6)
			stroke(result, self.theme.border, 1)
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}, result)
			return result
		end
		local function cycleField(
			label: string,
			value: string,
			x: number,
			width: number,
			labelY: number,
			fieldY: number,
			callback: () -> ()
		)
			fieldLabel(label, x, width, labelY)
			local control = button(
				inspector,
				self.theme,
				`{value}  · Next`,
				UDim2.fromOffset(x, fieldY),
				UDim2.fromOffset(width, fieldHeight),
				callback
			)
			control.TextXAlignment = Enum.TextXAlignment.Left
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}, control)
		end
		local function lanesField(x: number, width: number, labelY: number, fieldY: number)
			fieldLabel("Lanes", x, width, labelY)
			local laneHost = create("Frame", {
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, fieldY),
				Size = UDim2.fromOffset(width, fieldHeight),
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
					UDim2.fromOffset(math.floor((count - 1) * width / 3), 0),
					UDim2.fromOffset(math.ceil(width / 3), fieldHeight),
					function()
						self.callbacks.setLanes(edgeId, count)
					end,
					laneCount == count
				)
			end
		end
		local function segmentedCurve(x: number, width: number, labelY: number, fieldY: number)
			fieldLabel("Curve", x, width, labelY)
			local host = create("Frame", {
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, fieldY),
				Size = UDim2.fromOffset(width, fieldHeight),
				ZIndex = 30,
			}, inspector) :: Frame
			rounded(host, 6)
			stroke(host, self.theme.border, 1)
			for index, mode in { "Smooth", "Mirrored", "Free" } do
				local selectedMode = mode
				button(
					host,
					self.theme,
					mode,
					UDim2.fromOffset(math.floor((index - 1) * width / 3), 0),
					UDim2.fromOffset(math.ceil(width / 3), fieldHeight),
					function()
						self.callbacks.setCurveMode(edgeId, selectedMode)
					end,
					curveMode == mode
				)
			end
		end
		local function stepper(
			label: string,
			value: string,
			x: number,
			width: number,
			labelY: number,
			fieldY: number,
			decrease: () -> (),
			increase: () -> ()
		)
			fieldLabel(label, x, width, labelY)
			local stepWidth = math.clamp(math.floor(width * 0.24), 26, 34)
			button(
				inspector,
				self.theme,
				"-",
				UDim2.fromOffset(x, fieldY),
				UDim2.fromOffset(stepWidth, fieldHeight),
				decrease
			)
			local valueField = field(value, x + stepWidth + 3, width - stepWidth * 2 - 6, fieldY)
			valueField.TextXAlignment = Enum.TextXAlignment.Center
			button(
				inspector,
				self.theme,
				"+",
				UDim2.fromOffset(x + width - stepWidth, fieldY),
				UDim2.fromOffset(stepWidth, fieldHeight),
				increase
			)
		end

		if shortViewport then
			local gap = 8
			local usableWidth = math.max(self.root.AbsoluteSize.X - 36, 520)
			local pathWidth = math.floor(usableWidth * 0.3)
			local lanesWidth = math.floor(usableWidth * 0.26)
			local actionWidth = math.floor((usableWidth - pathWidth - lanesWidth - gap * 3) * 0.5)
			local pathX = 18
			local lanesX = pathX + pathWidth + gap
			local editX = lanesX + lanesWidth + gap
			local testX = editX + actionWidth + gap
			local testWidth = pathX + usableWidth - testX
			local pathControl = button(
				inspector,
				self.theme,
				`Asset: {pathAssetLabel}  · Next`,
				UDim2.fromOffset(pathX, 52),
				UDim2.fromOffset(pathWidth, fieldHeight),
				function()
					self.callbacks.setPathAsset(edgeId, StagePathAssets.next(pathAssetId))
				end
			)
			pathControl.TextXAlignment = Enum.TextXAlignment.Left
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}, pathControl)
			local shortLaneHost = create("Frame", {
				BackgroundColor3 = self.theme.surface,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(lanesX, 52),
				Size = UDim2.fromOffset(lanesWidth, fieldHeight),
				ZIndex = 30,
			}, inspector) :: Frame
			rounded(shortLaneHost, 6)
			stroke(shortLaneHost, self.theme.border, 1)
			for count = 1, 3 do
				local laneChoice = count
				button(
					shortLaneHost,
					self.theme,
					`{laneChoice} {if laneChoice == 1 then "lane" else "lanes"}`,
					UDim2.fromOffset(math.floor((laneChoice - 1) * lanesWidth / 3), 0),
					UDim2.fromOffset(math.ceil(lanesWidth / 3), fieldHeight),
					function()
						self.callbacks.setLanes(edgeId, laneChoice)
					end,
					laneCount == laneChoice
				)
			end
			button(
				inspector,
				self.theme,
				"Edit handles",
				UDim2.fromOffset(editX, 52),
				UDim2.fromOffset(actionWidth, fieldHeight),
				function()
					self.callbacks.focusWorld(edgeId)
				end
			)
			button(
				inspector,
				self.theme,
				"Test segment",
				UDim2.fromOffset(testX, 52),
				UDim2.fromOffset(testWidth, fieldHeight),
				function()
					self.callbacks.testSegment(edgeId)
				end
			)
			return
		elseif compactInspector then
			local gap = 8
			local usableWidth = math.max(self.root.AbsoluteSize.X - 36, 520)
			local rowWidth = usableWidth - gap * 2
			local pathWidth = math.floor(rowWidth * 0.34)
			local surfaceWidth = math.floor(rowWidth * 0.28)
			local lanesWidth = rowWidth - pathWidth - surfaceWidth
			local pathX = 18
			local surfaceX = pathX + pathWidth + gap
			local lanesX = surfaceX + surfaceWidth + gap
			cycleField("Path asset", pathAssetLabel, pathX, pathWidth, 48, 63, function()
				self.callbacks.setPathAsset(edgeId, StagePathAssets.next(pathAssetId))
			end)
			fieldLabel("Surface", surfaceX, surfaceWidth, 48)
			field("Route plane", surfaceX, surfaceWidth, 63)
			lanesField(lanesX, lanesWidth, 48, 63)

			local secondRowWidth = usableWidth - gap * 4
			local laneWidthWidth = math.floor(secondRowWidth * 0.2)
			local curveWidth = math.floor(secondRowWidth * 0.28)
			local priorityWidth = math.floor(secondRowWidth * 0.16)
			local actionWidth =
				math.floor((secondRowWidth - laneWidthWidth - curveWidth - priorityWidth) * 0.5)
			local laneWidthX = 18
			local curveX = laneWidthX + laneWidthWidth + gap
			local priorityX = curveX + curveWidth + gap
			local editX = priorityX + priorityWidth + gap
			local testX = editX + actionWidth + gap
			stepper(
				"Lane width",
				`{math.round(laneWidth)} studs`,
				laneWidthX,
				laneWidthWidth,
				103,
				118,
				function()
					self.callbacks.setLaneWidth(edgeId, laneWidth - 1)
				end,
				function()
					self.callbacks.setLaneWidth(edgeId, laneWidth + 1)
				end
			)
			segmentedCurve(curveX, curveWidth, 103, 118)
			stepper(
				"Priority",
				tostring(selectedEdge.priority or 1),
				priorityX,
				priorityWidth,
				103,
				118,
				function()
					self.callbacks.setPriority(edgeId, (selectedEdge.priority or 1) - 1)
				end,
				function()
					self.callbacks.setPriority(edgeId, (selectedEdge.priority or 1) + 1)
				end
			)
			fieldLabel("Handles", editX, actionWidth, 103)
			button(
				inspector,
				self.theme,
				"Edit handles",
				UDim2.fromOffset(editX, 118),
				UDim2.fromOffset(actionWidth, fieldHeight),
				function()
					self.callbacks.focusWorld(edgeId)
				end
			)
			fieldLabel("Preview", testX, actionWidth, 103)
			button(
				inspector,
				self.theme,
				"Test segment",
				UDim2.fromOffset(testX, 118),
				UDim2.fromOffset(actionWidth, fieldHeight),
				function()
					self.callbacks.testSegment(edgeId)
				end
			)
		else
			cycleField("Path asset", pathAssetLabel, 28, 220, 52, 69, function()
				self.callbacks.setPathAsset(edgeId, StagePathAssets.next(pathAssetId))
			end)
			fieldLabel("Surface", 280, 166, 52)
			field("Route plane", 280, 166, 69)
			lanesField(480, 190, 52, 69)
			stepper("Lane width", `{math.round(laneWidth)} studs`, 704, 152, 52, 69, function()
				self.callbacks.setLaneWidth(edgeId, laneWidth - 1)
			end, function()
				self.callbacks.setLaneWidth(edgeId, laneWidth + 1)
			end)
			segmentedCurve(888, 154, 52, 69)
			stepper("Priority", tostring(selectedEdge.priority or 1), 1074, 92, 52, 69, function()
				self.callbacks.setPriority(edgeId, (selectedEdge.priority or 1) - 1)
			end, function()
				self.callbacks.setPriority(edgeId, (selectedEdge.priority or 1) + 1)
			end)
			button(
				inspector,
				self.theme,
				"Edit handles",
				UDim2.new(1, -352, 0, 69),
				UDim2.fromOffset(150, fieldHeight),
				function()
					self.callbacks.focusWorld(edgeId)
				end
			)
			button(
				inspector,
				self.theme,
				"Test segment",
				UDim2.new(1, -184, 0, 69),
				UDim2.fromOffset(164, fieldHeight),
				function()
					self.callbacks.testSegment(edgeId)
				end
			)
		end
		create("Frame", {
			BackgroundColor3 = self.theme.border,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, if compactInspector then 158 else 123),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 30,
		}, inspector)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSans,
			Position = UDim2.fromOffset(20, if compactInspector then 166 else 132),
			Size = UDim2.new(1, -40, 0, if compactInspector then 24 else 30),
			Text = `Walkway width {if profile ~= nil
				then math.round(profile.clearanceRadius * 2)
				else grid.cellSize} studs  |  {conflictCount} conflicts  |  Drag markers to move  |  Drag cyan handles to shape  |  Esc cancels`,
			TextColor3 = if conflictCount > 0 then self.theme.warning else self.theme.muted,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 30,
		}, inspector)
	elseif self.selectedNodeId ~= nil and graph.nodes[self.selectedNodeId] ~= nil then
		local node = graph.nodes[self.selectedNodeId]
		local nudge = math.max(grid.cellSize * 0.25, 1)
		local labelY = if shortViewport then 46 else 52
		local fieldY = if shortViewport then 62 else 69
		local fieldHeight = if shortViewport then 32 else 36
		local halfWidth = grid.columns * grid.cellSize * 0.5
		local halfHeight = grid.rows * grid.cellSize * 0.5
		local function nodeControl(label: string, text: string, x: number, deltaX: number, deltaZ: number)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSansMedium,
				Position = UDim2.fromOffset(x, labelY),
				Size = UDim2.fromOffset(190, 14),
				Text = label,
				TextColor3 = self.theme.muted,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector)
			button(
				inspector,
				self.theme,
				text,
				UDim2.fromOffset(x, fieldY),
				UDim2.fromOffset(190, fieldHeight),
				function()
					self.callbacks.moveNode(node.id, {
						x = math.clamp(node.position.x + deltaX, -halfWidth, halfWidth),
						y = node.position.y,
						z = math.clamp(node.position.z + deltaZ, -halfHeight, halfHeight),
					}, true)
				end
			)
		end
		nodeControl("Horizontal", `<  X {math.round(node.position.x * 10) / 10}  (-{nudge})`, 28, -nudge, 0)
		nodeControl("Horizontal", `X {math.round(node.position.x * 10) / 10}  (+{nudge})  >`, 230, nudge, 0)
		nodeControl("Vertical", `<  Z {math.round(node.position.z * 10) / 10}  (-{nudge})`, 448, 0, -nudge)
		nodeControl("Vertical", `Z {math.round(node.position.z * 10) / 10}  (+{nudge})  >`, 650, 0, nudge)
		if not shortViewport then
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.BuilderSans,
				Position = UDim2.fromOffset(28, 122),
				Size = UDim2.new(1, -56, 0, 30),
				Text = "Drag the marker directly for free movement, or use these one-stud nudges for precision.",
				TextColor3 = self.theme.muted,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 30,
			}, inspector)
		end
	end
end

function WorldPathView.destroy(self: Controller)
	self:cancelInteraction()
	cancelBackdropRefresh(self)
	disconnectBackdropSource(self)
	clearWorldBackdrop(self)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.root:Destroy()
end

return WorldPathView

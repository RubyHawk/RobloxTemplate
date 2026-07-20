--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local StagePathAssets = require(script.Parent.Shared.StagePathAssets)

local PREVIEW_NAME = "StagewrightPreview"
local PREVIEW_TAG = "StagewrightTransientPreview"

export type RenderState = {
	parent: Instance?,
	origin: CFrame,
	graph: any?,
	bakedStage: any?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean },
}

export type MoveTransaction = number

export type Config = {
	canEdit: () -> boolean,
	beginMove: () -> MoveTransaction?,
	moveNode: (string, Vector3) -> (),
	moveHandle: (string, string, Vector3) -> (),
	finishMove: (MoveTransaction, boolean) -> boolean,
	onMoveCommitted: () -> (),
	onMoveFailed: () -> (),
}

type ControllerState = {
	enabled: boolean,
	folder: Folder?,
	legacyRoot: Instance?,
	legacyHiddenParts: { [BasePart]: number },
	lastState: RenderState?,
	moveRevision: number,
	moveTransaction: MoveTransaction?,
	config: Config,
}

export type Controller = ControllerState & {
	isEnabled: (Controller) -> boolean,
	setEnabled: (Controller, boolean) -> boolean,
	render: (Controller, RenderState) -> (),
	clear: (Controller) -> (),
	cancelInteraction: (Controller) -> boolean,
	nodePart: (Controller, string) -> BasePart?,
	edgePart: (Controller, string) -> BasePart?,
	destroy: (Controller) -> (),
}

local Controller = {}
Controller.__index = Controller

local LEGACY_PATH_FOLDERS = {
	PathPoints = true,
	PathTiles = true,
}

local function part(parent: Folder, name: string, canQuery: boolean): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Anchored = true
	result.CanCollide = false
	result.CanQuery = canQuery
	result.CanTouch = false
	result.CastShadow = false
	result.Parent = parent
	return result
end

local function previewPoint(origin: CFrame, sample: any, laneOffset: number): Vector3
	local position =
		origin:PointToWorldSpace(Vector3.new(sample.position.x, sample.position.y, sample.position.z))
	local tangent =
		origin:VectorToWorldSpace(Vector3.new(sample.tangent.x, sample.tangent.y, sample.tangent.z))
	local up = origin:VectorToWorldSpace(Vector3.new(sample.up.x, sample.up.y, sample.up.z))
	local frame = CFrame.lookAt(position, position + tangent, up)
	return frame.Position + frame.RightVector * laneOffset
end

local function materialFromName(materialName: any): Enum.Material
	if type(materialName) == "string" then
		local candidate = (Enum.Material :: any)[materialName]
		if typeof(candidate) == "EnumItem" then
			return candidate :: Enum.Material
		end
	end
	return Enum.Material.Pebble
end

function Controller.isEnabled(self: Controller): boolean
	return self.enabled
end

local function clearPreview(self: Controller)
	local folder = self.folder
	self.folder = nil
	if folder ~= nil then
		folder:Destroy()
	end
end

local function restoreLegacyPathArtifacts(self: Controller)
	for partToRestore, transparency in self.legacyHiddenParts do
		if partToRestore.Parent ~= nil then
			partToRestore.LocalTransparencyModifier = transparency
		end
	end
	table.clear(self.legacyHiddenParts)
	self.legacyRoot = nil
end

local function isLegacyPathArtifact(instance: Instance, root: Instance): boolean
	local current = instance.Parent
	while current ~= nil and current ~= root do
		if LEGACY_PATH_FOLDERS[current.Name] == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function hideLegacyPathArtifacts(self: Controller, root: Instance?)
	if self.legacyRoot ~= root then
		restoreLegacyPathArtifacts(self)
	end
	if root == nil then
		return
	end
	self.legacyRoot = root
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and isLegacyPathArtifact(descendant, root) then
			if self.legacyHiddenParts[descendant] == nil then
				self.legacyHiddenParts[descendant] = descendant.LocalTransparencyModifier
			end
			descendant.LocalTransparencyModifier = 1
		end
	end
end

function Controller.clear(self: Controller)
	clearPreview(self)
	restoreLegacyPathArtifacts(self)
end

local function finishMove(self: Controller, revision: number)
	local transaction = self.moveTransaction
	if revision ~= self.moveRevision or transaction == nil then
		return
	end
	self.moveTransaction = nil
	if not self.enabled or not self.config.canEdit() then
		self.config.finishMove(transaction, false)
		self:clear()
		return
	end
	if self.config.finishMove(transaction, true) then
		self.config.onMoveCommitted()
	else
		self:clear()
		self.config.onMoveFailed()
	end
end

local function bindPosition(
	self: Controller,
	partToBind: BasePart,
	origin: CFrame,
	applyPosition: (Vector3) -> ()
)
	partToBind:GetPropertyChangedSignal("CFrame"):Connect(function()
		if partToBind.Parent == nil or not self.enabled or not self.config.canEdit() then
			return
		end
		if self.moveTransaction == nil then
			local transaction = self.config.beginMove()
			if transaction == nil then
				return
			end
			self.moveTransaction = transaction
		end
		self.moveRevision += 1
		local revision = self.moveRevision
		applyPosition(origin:PointToObjectSpace(partToBind.Position))
		task.delay(0.2, function()
			finishMove(self, revision)
		end)
	end)
end

local function renderRouteConflicts(folder: Folder, origin: CFrame, bakedStage: any)
	for key in bakedStage.routeNoBuildMask or {} do
		local authoredCell = bakedStage.grid.cells[key]
		local traversalPolicy = if authoredCell ~= nil and authoredCell.enemyTraversalPolicy ~= nil
			then authoredCell.enemyTraversalPolicy
			else bakedStage.grid.defaultCell.enemyTraversalPolicy
		if traversalPolicy ~= "Blocked" then
			continue
		end
		local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
		local column = if columnText ~= nil then tonumber(columnText) else nil
		local row = if rowText ~= nil then tonumber(rowText) else nil
		if column == nil or row == nil then
			continue
		end
		local grid = bakedStage.grid
		local x = -(grid.columns * grid.cellSize) * 0.5 + (column - 0.5) * grid.cellSize
		local z = -(grid.rows * grid.cellSize) * 0.5 + (row - 0.5) * grid.cellSize
		local cell = part(folder, `RouteConflict_{column}_{row}`, false)
		cell.Color = Color3.fromRGB(255, 154, 64)
		cell.Material = Enum.Material.Neon
		cell.Transparency = 0.38
		local footprint = math.max(grid.cellSize - 0.2, 0.05)
		cell.Size = Vector3.new(footprint, 0.12, footprint)
		cell.CFrame = origin * CFrame.new(x, 0.42, z)
		cell:SetAttribute("StagewrightRouteConflict", true)
	end
end

local function renderNodes(self: Controller, folder: Folder, origin: CFrame, graph: any, state: RenderState)
	for nodeId, node in graph.nodes do
		local nodePart = part(folder, `Node_{node.name}`, true)
		nodePart.Shape = Enum.PartType.Ball
		local selected = state.selectedNodeId == nodeId
		nodePart.Size = if selected then Vector3.new(2.15, 2.15, 2.15) else Vector3.new(1.45, 1.45, 1.45)
		nodePart.Color = if node.kind == "Spawn"
			then Color3.fromRGB(57, 185, 104)
			elseif node.kind == "Goal" then Color3.fromRGB(195, 123, 65)
			else Color3.fromRGB(60, 139, 214)
		nodePart.Material = if selected then Enum.Material.Neon else Enum.Material.SmoothPlastic
		nodePart.CFrame = origin * CFrame.new(node.position.x, node.position.y, node.position.z)
		nodePart:SetAttribute("StagewrightNodeId", nodeId)
		bindPosition(self, nodePart, origin, function(localPosition)
			self.config.moveNode(nodeId, localPosition)
		end)
	end
end

local function renderEdges(
	folder: Folder,
	origin: CFrame,
	bakedStage: any,
	bakedGraph: any,
	state: RenderState
)
	for edgeId, edge in bakedGraph.edges do
		local pathAsset, requestedAssetId = StagePathAssets.forEdge(edge)
		local pathMaterial = materialFromName(pathAsset.materialName)
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
			local a = previewPoint(origin, samples[index - 1], 0)
			local b = previewPoint(origin, samples[index], 0)
			local distance = (b - a).Magnitude
			if distance <= 0.001 then
				continue
			end
			local pathFrame = CFrame.lookAt((a + b) * 0.5, b)
			if state.selectedEdgeId == edgeId then
				local outline = part(folder, `Edge_{edgeId}_SelectedOutline_{index}`, false)
				outline.Color = Color3.fromRGB(62, 214, 235)
				outline.Material = Enum.Material.Neon
				outline.Transparency = 0.25
				outline.Size = Vector3.new(corridorWidth + 0.55, 0.12, distance + 0.16)
				outline.CFrame = pathFrame * CFrame.new(0, -0.07, 0)
			end
			local corridor = part(folder, `Edge_{edgeId}_Path_{index}`, true)
			corridor.Color = Color3.fromRGB(pathAsset.rgb[1], pathAsset.rgb[2], pathAsset.rgb[3])
			corridor.Material = pathMaterial
			corridor.Transparency = 0.08
			corridor.Size = Vector3.new(corridorWidth, 0.16, distance + 0.14)
			corridor.CFrame = pathFrame
			corridor:SetAttribute("StagewrightEdgeId", edgeId)
			corridor:SetAttribute("StagewrightPathAsset", pathAsset.id)
			corridor:SetAttribute("StagewrightRequestedPathAsset", requestedAssetId)
		end
		if state.selectedEdgeId == edgeId or state.tracedEdgeIds[edgeId] then
			for laneIndex, laneOffset in laneOffsets do
				for index = 2, #samples do
					local a = previewPoint(origin, samples[index - 1], laneOffset) + Vector3.new(0, 0.14, 0)
					local b = previewPoint(origin, samples[index], laneOffset) + Vector3.new(0, 0.14, 0)
					local distance = (b - a).Magnitude
					if distance <= 0.001 then
						continue
					end
					local segment = part(folder, `Edge_{edgeId}_Lane_{laneIndex}_{index}`, false)
					segment.Color = if state.tracedEdgeIds[edgeId]
						then Color3.fromRGB(96, 220, 132)
						else Color3.fromRGB(237, 244, 247)
					segment.Material = Enum.Material.Neon
					segment.Transparency = 0.12
					segment.Size = Vector3.new(0.14, 0.08, distance)
					segment.CFrame = CFrame.lookAt((a + b) * 0.5, b)
				end
			end
		end
	end
end

local function renderHandles(self: Controller, folder: Folder, origin: CFrame, graph: any, state: RenderState)
	local selectedEdge = if state.selectedEdgeId ~= nil then graph.edges[state.selectedEdgeId] else nil
	if selectedEdge == nil then
		return
	end
	local from = graph.nodes[selectedEdge.fromNodeId]
	local to = graph.nodes[selectedEdge.toNodeId]
	if from == nil or to == nil then
		return
	end
	for handleName, handleData in
		{
			Out = { node = from, offset = selectedEdge.outHandleOffset },
			In = { node = to, offset = selectedEdge.inHandleOffset },
		}
	do
		local handle = part(folder, `{handleName}Handle_{selectedEdge.id}`, true)
		handle.Shape = Enum.PartType.Ball
		handle.Size = Vector3.new(1.2, 1.2, 1.2)
		handle.Material = Enum.Material.Neon
		handle.Color = Color3.fromRGB(62, 214, 235)
		local position = {
			x = handleData.node.position.x + handleData.offset.x,
			y = handleData.node.position.y + handleData.offset.y,
			z = handleData.node.position.z + handleData.offset.z,
		}
		handle.CFrame = origin * CFrame.new(position.x, position.y, position.z)
		local connector = part(folder, `{handleName}HandleGuide_{selectedEdge.id}`, false)
		connector.Color = Color3.fromRGB(62, 214, 235)
		connector.Material = Enum.Material.Neon
		connector.Transparency = 0.18
		local anchor = origin:PointToWorldSpace(
			Vector3.new(handleData.node.position.x, handleData.node.position.y, handleData.node.position.z)
		)
		local function updateConnector()
			local distance = (handle.Position - anchor).Magnitude
			connector.Size = Vector3.new(0.08, 0.08, math.max(distance, 0.08))
			connector.CFrame = CFrame.lookAt((handle.Position + anchor) * 0.5, handle.Position)
		end
		updateConnector()
		handle:GetPropertyChangedSignal("CFrame"):Connect(updateConnector)
		bindPosition(self, handle, origin, function(localPosition)
			self.config.moveHandle(selectedEdge.id, handleName, localPosition)
		end)
	end
end

function Controller.render(self: Controller, state: RenderState)
	self.lastState = state
	clearPreview(self)
	if not self.config.canEdit() then
		restoreLegacyPathArtifacts(self)
		return
	end
	hideLegacyPathArtifacts(self, state.parent)
	if not self.enabled then
		return
	end
	local graph = state.graph
	local bakedStage = state.bakedStage
	local bakedGraph = if graph ~= nil and bakedStage ~= nil then bakedStage.pathGraphs[graph.id] else nil
	if graph == nil or bakedStage == nil or bakedGraph == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_NAME
	folder.Archivable = false
	folder:SetAttribute("StagewrightEditorOnly", true)
	folder.Parent = state.parent or Workspace
	CollectionService:AddTag(folder, PREVIEW_TAG)
	self.folder = folder
	local origin = state.origin
	renderRouteConflicts(folder, origin, bakedStage)
	renderNodes(self, folder, origin, graph, state)
	renderEdges(folder, origin, bakedStage, bakedGraph, state)
	renderHandles(self, folder, origin, graph, state)
end

function Controller.setEnabled(self: Controller, enabled: boolean): boolean
	if enabled and not self.config.canEdit() then
		enabled = false
	end
	if self.enabled == enabled then
		return enabled
	end
	self.enabled = enabled
	if not enabled then
		self:cancelInteraction()
		self:clear()
	else
		local state = self.lastState
		if state ~= nil then
			self:render(state)
		end
	end
	return enabled
end

function Controller.cancelInteraction(self: Controller): boolean
	self.moveRevision += 1
	local transaction = self.moveTransaction
	if transaction ~= nil then
		self.moveTransaction = nil
		self.config.finishMove(transaction, false)
		return true
	end
	return false
end

local function attributedPart(self: Controller, attribute: string, value: string): BasePart?
	local folder = self.folder
	if folder == nil then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(attribute) == value then
			return child
		end
	end
	return nil
end

function Controller.nodePart(self: Controller, nodeId: string): BasePart?
	return attributedPart(self, "StagewrightNodeId", nodeId)
end

function Controller.edgePart(self: Controller, edgeId: string): BasePart?
	return attributedPart(self, "StagewrightEdgeId", edgeId)
end

function Controller.destroy(self: Controller)
	self.enabled = false
	self:cancelInteraction()
	self:clear()
	self.lastState = nil
end

local WorkspacePreview = {}

function WorkspacePreview.new(config: Config): Controller
	for _, tagged in CollectionService:GetTagged(PREVIEW_TAG) do
		if tagged:IsDescendantOf(Workspace) then
			tagged:Destroy()
		end
	end
	return setmetatable({
		enabled = false,
		folder = nil,
		legacyRoot = nil,
		legacyHiddenParts = {},
		lastState = nil,
		moveRevision = 0,
		moveTransaction = nil,
		config = config,
	}, Controller) :: any
end

return WorkspacePreview

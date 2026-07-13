--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local StageCatalog = require(Shared.StageCatalog)
local StagePath = require(Shared.StagePath)

local StageGridRenderer = {}

local localPlayer = Players.LocalPlayer
local initialized = false

local LEGACY_EDITOR_NAMES: { [string]: boolean } = {
	grideditor = true,
	gridforgeeditor = true,
	gridplatformeditor = true,
	gridplatformeditorclient = true,
}

local function color(value: { number }): Color3
	return Color3.fromRGB(value[1], value[2], value[3])
end

local function faded(transparency: number, fade: number): number
	return 1 - (1 - transparency) * (1 - math.clamp(fade, 0, 1))
end

local function hideEditorRoot(root: Instance)
	local descendants = root:GetDescendants()
	table.insert(descendants, root)
	for _, descendant in descendants do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif
			descendant:IsA("SurfaceGui")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("ScreenGui")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Highlight")
			or descendant:IsA("Light")
		then
			local enabledInstance = descendant :: any
			enabledInstance.Enabled = false
		end
	end
end

local function hideEditorOnlyWorldContent()
	for _, child in Workspace:GetChildren() do
		if child:GetAttribute("StagewrightEditorOnly") == true then
			hideEditorRoot(child)
		end
	end
	Workspace.ChildAdded:Connect(function(child)
		if child:GetAttribute("StagewrightEditorOnly") == true then
			hideEditorRoot(child)
		end
	end)
end

local function hideLegacyEditGridControl(instance: Instance)
	local normalizedName = string.lower(instance.Name)
	local matches = LEGACY_EDITOR_NAMES[normalizedName] == true
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		matches = matches or string.find(string.lower(instance.Text), "edit grid", 1, true) ~= nil
	end
	if not matches then
		return
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local current: Instance? = instance
	while current ~= nil and current ~= playerGui do
		if current:IsA("ScreenGui") then
			current.Enabled = false
			return
		elseif current:IsA("GuiButton") then
			current.Visible = false
			return
		elseif current:IsA("GuiObject") then
			current.Visible = false
		end
		current = current.Parent
	end
end

local function hideLegacyEditGridUi()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	for _, descendant in playerGui:GetDescendants() do
		hideLegacyEditGridControl(descendant)
	end
	playerGui.DescendantAdded:Connect(hideLegacyEditGridControl)
end

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	partColor: Color3,
	transparency: number,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = material
	part.Color = partColor
	part.Transparency = transparency
	part.Size = size
	part.CFrame = frame
	part.Parent = parent
	return part
end

local function hideLegacyPreview()
	local island = Workspace:FindFirstChild(Config.towerDefense.firstPlatformIslandName)
	local platform = if island ~= nil
		then island:FindFirstChild(Config.towerDefense.platformModelName)
		else nil
	if platform == nil then
		return
	end
	for _, descendant in platform:GetDescendants() do
		if descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		end
	end
	for _, folderName in { "PathPoints", "PathTiles" } do
		local previewFolder = platform:FindFirstChild(folderName)
		if previewFolder ~= nil then
			for _, descendant in previewFolder:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

local function createRenderFolder(): Folder
	local visuals = Config.towerDefense.gridVisuals
	local existing = Workspace:FindFirstChild(visuals.folderName)
	if
		existing ~= nil
		and existing:IsA("Folder")
		and existing:GetAttribute("StagewrightClientOwned") == true
	then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = if Workspace:FindFirstChild(visuals.folderName) == nil
		then visuals.folderName
		else `{visuals.folderName}_Local`
	folder:SetAttribute("StagewrightClientOwned", true)
	folder:SetAttribute("StageChecksum", StageCatalog.bundleChecksum)
	folder.Parent = Workspace
	return folder
end

local function renderGridLines(model: Model, stage: any, origin: CFrame, fade: number)
	local visuals = Config.towerDefense.gridVisuals
	local grid = stage.grid
	local width = grid.columns * grid.cellSize
	local depth = grid.rows * grid.cellSize
	createPart(
		model,
		"Surface",
		Vector3.new(width, visuals.surfaceHeight, depth),
		origin * CFrame.new(0, visuals.heightOffset - visuals.surfaceHeight * 0.5, 0),
		color(visuals.surfaceColor),
		faded(visuals.surfaceTransparency, fade),
		Enum.Material.SmoothPlastic
	)
	local lineColor = color(visuals.lineColor)
	for column = 0, grid.columns do
		local x = -width * 0.5 + column * grid.cellSize
		createPart(
			model,
			`Column_{string.format("%02d", column)}`,
			Vector3.new(visuals.lineThickness, visuals.lineHeight, depth + visuals.lineThickness),
			origin * CFrame.new(x, visuals.heightOffset + visuals.lineHeight * 0.5, 0),
			lineColor,
			faded(visuals.lineTransparency, fade),
			Enum.Material.Neon
		)
	end
	for row = 0, grid.rows do
		local z = -depth * 0.5 + row * grid.cellSize
		createPart(
			model,
			`Row_{string.format("%02d", row)}`,
			Vector3.new(width + visuals.lineThickness, visuals.lineHeight, visuals.lineThickness),
			origin * CFrame.new(0, visuals.heightOffset + visuals.lineHeight * 0.5, z),
			lineColor,
			faded(visuals.lineTransparency, fade),
			Enum.Material.Neon
		)
	end
end

local function renderRouteSegment(
	model: Model,
	index: number,
	fromPosition: Vector3,
	toPosition: Vector3,
	up: Vector3,
	fade: number
)
	local visuals = Config.towerDefense.gridVisuals
	local difference = toPosition - fromPosition
	local length = difference.Magnitude
	if length < 0.01 then
		return
	end
	local middle = fromPosition:Lerp(toPosition, 0.5)
	createPart(
		model,
		`Route_{string.format("%03d", index)}`,
		Vector3.new(visuals.routeWidth, visuals.routeHeight, length + 0.08),
		CFrame.lookAt(middle, toPosition, up),
		color(visuals.routeColor),
		faded(visuals.routeTransparency, fade),
		Enum.Material.SmoothPlastic
	)
end

local function renderRoutes(model: Model, stage: any, origin: CFrame, fade: number)
	local visuals = Config.towerDefense.gridVisuals
	local segmentIndex = 0
	local graphIds: { string } = {}
	for graphId in stage.pathGraphs do
		table.insert(graphIds, graphId)
	end
	table.sort(graphIds)
	for _, graphId in graphIds do
		local graph = stage.pathGraphs[graphId]
		local edgeIds: { string } = {}
		for edgeId in graph.edges do
			table.insert(edgeIds, edgeId)
		end
		table.sort(edgeIds)
		for _, edgeId in edgeIds do
			local edge = graph.edges[edgeId]
			local previous: Vector3? = nil
			local distance = 0
			while distance < edge.length do
				local sample = StagePath.sample(edge.samples, edge.length, distance)
				if sample ~= nil then
					local current = origin:PointToWorldSpace(
						Vector3.new(
							sample.position.x,
							sample.position.y + visuals.routeVerticalOffset,
							sample.position.z
						)
					)
					if previous ~= nil then
						segmentIndex += 1
						renderRouteSegment(model, segmentIndex, previous, current, origin.UpVector, fade)
					end
					previous = current
				end
				distance += visuals.routeSampleSpacing
			end
			local finalSample = StagePath.sample(edge.samples, edge.length, edge.length)
			if finalSample ~= nil and previous ~= nil then
				local finalPosition = origin:PointToWorldSpace(
					Vector3.new(
						finalSample.position.x,
						finalSample.position.y + visuals.routeVerticalOffset,
						finalSample.position.z
					)
				)
				segmentIndex += 1
				renderRouteSegment(model, segmentIndex, previous, finalPosition, origin.UpVector, fade)
			end
		end
	end
end

local function markerColor(cell: any): Color3?
	local visuals = Config.towerDefense.gridVisuals
	local roles = cell.roles or {}
	if roles.EnemySpawn then
		return color(visuals.spawnColor)
	elseif roles.EnemyGoal then
		return color(visuals.goalColor)
	elseif roles.AutoPlace then
		return color(visuals.autoPlaceColor)
	elseif cell.buildPolicy == "Blocked" then
		return color(visuals.blockedColor)
	end
	return nil
end

local function renderMarkers(model: Model, stage: any, origin: CFrame, fade: number)
	local visuals = Config.towerDefense.gridVisuals
	local grid = stage.grid
	local width = grid.columns * grid.cellSize
	local depth = grid.rows * grid.cellSize
	for key, cell in grid.cells do
		local partColor = markerColor(cell)
		if partColor == nil then
			continue
		end
		local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
		local column = tonumber(columnText)
		local row = tonumber(rowText)
		if column == nil or row == nil then
			continue
		end
		local x = -width * 0.5 + (column - 0.5) * grid.cellSize
		local z = -depth * 0.5 + (row - 0.5) * grid.cellSize
		createPart(
			model,
			`Cell_{column}_{row}`,
			Vector3.new(grid.cellSize * 0.78, visuals.markerHeight, grid.cellSize * 0.78),
			origin * CFrame.new(x, visuals.heightOffset + visuals.lineHeight + visuals.markerHeight * 0.5, z),
			partColor,
			faded(visuals.markerTransparency, fade),
			Enum.Material.Neon
		)
	end
end

local function renderStage(
	parent: Folder,
	slot: number,
	stage: any,
	origin: CFrame,
	isLocalOwner: boolean,
	ownerUserId: number
): Model
	local fade = if isLocalOwner then 0 else Config.towerDefense.gridVisuals.otherPlatformFade
	local model = Instance.new("Model")
	model.Name = `Platform_{string.format("%02d", slot)}`
	model:SetAttribute("PlatformSlot", slot)
	model:SetAttribute("StageId", stage.id)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("LocalOwner", isLocalOwner)
	model:SetAttribute("VisualFade", fade)
	model.Parent = parent
	renderGridLines(model, stage, origin, fade)
	renderRoutes(model, stage, origin, fade)
	renderMarkers(model, stage, origin, fade)
	return model
end

local function localPlatformSlot(origins: Folder): number?
	local attribute = localPlayer:GetAttribute("TowerDefensePlatformSlot")
	if type(attribute) == "number" then
		return attribute
	end
	for slot = 1, Config.towerDefense.platformSlotCount do
		local value = origins:FindFirstChild(`Slot_{string.format("%02d", slot)}`)
		if
			value ~= nil
			and value:IsA("CFrameValue")
			and value:GetAttribute("OwnerUserId") == localPlayer.UserId
		then
			return slot
		end
	end
	return nil
end

local function waitForLocalPlatformSlot(origins: Folder): number?
	for _ = 1, 100 do
		local slot = localPlatformSlot(origins)
		if slot ~= nil then
			return slot
		end
		task.wait(0.05)
	end
	return nil
end

function StageGridRenderer.initialize()
	if initialized or not Config.towerDefense.gridVisuals.enabled then
		return
	end
	initialized = true
	task.spawn(function()
		hideEditorOnlyWorldContent()
		hideLegacyEditGridUi()
		hideLegacyPreview()
		local origins = Template:WaitForChild(Config.towerDefense.platformOriginsFolderName, 20)
		if origins == nil or not origins:IsA("Folder") then
			warn("Stage grid renderer could not find the authoritative platform origins")
			return
		end
		if origins:GetAttribute("LayoutAvailable") ~= true then
			warn("Stage grid renderer received an unavailable platform layout")
			return
		end
		local stage = StageCatalog.get(StageCatalog.defaultStageId())
		if stage == nil then
			warn("Stage grid renderer could not find the default stage")
			return
		end
		local renderFolder = createRenderFolder()
		local ownedSlot = waitForLocalPlatformSlot(origins)
		if ownedSlot == nil then
			warn("Stage grid renderer could not resolve the local player's platform slot")
		end
		for slot = 1, Config.towerDefense.platformSlotCount do
			local value = origins:FindFirstChild(`Slot_{string.format("%02d", slot)}`)
			if value ~= nil and value:IsA("CFrameValue") then
				local rawOwnerUserId = value:GetAttribute("OwnerUserId")
				local ownerUserId = if type(rawOwnerUserId) == "number" then rawOwnerUserId else 0
				local model =
					renderStage(renderFolder, slot, stage, value.Value, slot == ownedSlot, ownerUserId)
				value:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
					local updated = value:GetAttribute("OwnerUserId")
					model:SetAttribute("OwnerUserId", if type(updated) == "number" then updated else 0)
				end)
			else
				warn(`Stage grid renderer is missing platform origin {slot}`)
			end
		end
	end)
end

return StageGridRenderer

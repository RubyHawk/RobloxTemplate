--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AuthoringArea = {}
local StagePlatformLayout = require(script.Parent.Shared.StagePlatformLayout)

local LAYOUT_VERSION = 3
local AUTHORING_ATTRIBUTE = "StagewrightAuthoringPlatform"
local MANAGED_ATTRIBUTE = "StagewrightManaged"
local OUTLINE_TAG = "StagewrightIslandOutlinePreview"

type AuthoringConfig = {
	enabled: boolean,
	areaName: string,
	offsetFromCenter: { number },
	roomSize: { number },
	wallThickness: number,
}

local warnedMissingConfig = false
local warnedMissingCenter = false
local warnedAmbiguousCenter = false
local sessionOutlineFolder: Folder? = nil
local cachedDesignerModule: ModuleScript? = nil
local cachedDesignerSource: string? = nil
local cachedDesignerCenter: { number }? = nil
local cachedDesignerLoaded = false

local function finiteVec3(value: any): { number }?
	if type(value) ~= "table" then
		return nil
	end
	local x = value[1]
	local y = value[2]
	local z = value[3]
	if
		type(x) ~= "number"
		or type(y) ~= "number"
		or type(z) ~= "number"
		or x ~= x
		or y ~= y
		or z ~= z
		or math.abs(x) == math.huge
		or math.abs(y) == math.huge
		or math.abs(z) == math.huge
	then
		return nil
	end
	return { x, y, z }
end

-- Rojo can replace DesignerConfig.Source after this plugin has already required
-- TemplateConfig. Roblox caches ModuleScript results per Luau environment, so a
-- unique clone lets edit-mode navigation see the current recipe without a Studio
-- restart. DesignerConfig recipes are dependency-free data modules.
local function freshDesignerPlatformCenter(shared: Instance): ({ number }?, boolean)
	local candidate = shared:FindFirstChild("DesignerConfig")
	if candidate == nil or not candidate:IsA("ModuleScript") then
		return nil, false
	end
	local source = candidate.Source
	if cachedDesignerLoaded and cachedDesignerModule == candidate and cachedDesignerSource == source then
		return cachedDesignerCenter, true
	end
	local snapshot = candidate:Clone()
	local success, result = pcall(require, snapshot)
	snapshot:Destroy()
	if not success or type(result) ~= "table" then
		return nil, false
	end
	local towerDefense = result.towerDefense
	local center = if type(towerDefense) == "table"
		then finiteVec3(towerDefense.platformCenterPosition)
		else nil
	cachedDesignerModule = candidate
	cachedDesignerSource = source
	cachedDesignerCenter = center
	cachedDesignerLoaded = true
	return center, true
end

local function config(): (any?, AuthoringConfig?)
	local template = ReplicatedStorage:FindFirstChild("Template")
	local shared = if template ~= nil then template:FindFirstChild("Shared") else nil
	local module = if shared ~= nil then shared:FindFirstChild("TemplateConfig") else nil
	if module == nil or not module:IsA("ModuleScript") then
		if not warnedMissingConfig then
			warn("Stagewright admin area is waiting for ReplicatedStorage.Template.Shared.TemplateConfig")
			warnedMissingConfig = true
		end
		return nil, nil
	end
	local success, result = pcall(require, module)
	if not success or type(result) ~= "table" or type(result.towerDefense) ~= "table" then
		if not warnedMissingConfig then
			warn("Stagewright admin area could not read TemplateConfig")
			warnedMissingConfig = true
		end
		return nil, nil
	end
	local freshCenter, freshLoaded = freshDesignerPlatformCenter(shared)
	if freshLoaded then
		local resolved = table.clone(result)
		local towerDefense = table.clone(result.towerDefense)
		towerDefense.platformCenterPosition = freshCenter
		resolved.towerDefense = towerDefense
		result = resolved
	end
	local authoring = result.towerDefense.authoringArea
	if type(authoring) ~= "table" then
		return result, nil
	end
	return result, authoring :: AuthoringConfig
end

local function centerPart(templateConfig: any): BasePart?
	local allowed: { [string]: boolean } = {}
	for _, name in templateConfig.towerDefense.centerPartNames do
		allowed[name] = true
	end
	local found: BasePart? = nil
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and allowed[descendant.Name] then
			if found ~= nil then
				if not warnedAmbiguousCenter then
					warn(
						`Stagewright playable map is ambiguous: both {found:GetFullName()} and {descendant:GetFullName()} match the configured center anchors`
					)
					warnedAmbiguousCenter = true
				end
				return nil
			end
			found = descendant
		end
	end
	if found ~= nil then
		warnedAmbiguousCenter = false
	end
	return found
end

local function layoutCenter(templateConfig: any): (CFrame?, string?)
	local configured = templateConfig.towerDefense.platformCenterPosition
	if type(configured) == "table" then
		local x = configured[1]
		local y = configured[2]
		local z = configured[3]
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return CFrame.new(x, y, z), "ConfiguredCenter"
		end
	end
	local center = centerPart(templateConfig)
	return if center ~= nil then center.CFrame else nil, if center ~= nil then center.Name else nil
end

local function legacyPlatform(templateConfig: any): Model?
	local island = Workspace:FindFirstChild(templateConfig.towerDefense.firstPlatformIslandName)
	local platform = if island ~= nil
		then island:FindFirstChild(templateConfig.towerDefense.platformModelName)
		else nil
	return if platform ~= nil and platform:IsA("Model") then platform else nil
end

local function platformInArea(area: Instance?, templateConfig: any): Model?
	if area == nil then
		return nil
	end
	local platform = area:FindFirstChild(templateConfig.towerDefense.platformModelName)
	return if platform ~= nil and platform:IsA("Model") then platform else nil
end

local function targetOrigin(centerFrame: CFrame, authoring: AuthoringConfig): CFrame
	local offset = authoring.offsetFromCenter
	return centerFrame * CFrame.new(offset[1], offset[2], offset[3])
end

local function playableSlotOrigin(templateConfig: any, centerFrame: CFrame, slot: number): CFrame
	local first = templateConfig.towerDefense.firstPlatformOffsetFromCenter
	local offset, yaw = StagePlatformLayout.slotOffset({
		x = first[1],
		y = first[2],
		z = first[3],
	}, slot, templateConfig.towerDefense.platformSlotCount)
	return centerFrame
		* CFrame.new(offset.x, offset.y, offset.z)
		* CFrame.Angles(0, yaw + math.rad(templateConfig.towerDefense.firstPlatformYawDegrees), 0)
end

local function setPartProperties(part: Part, size: Vector3, frame: CFrame)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(245, 247, 250)
	part.Transparency = 0.04
	part.Size = size
	part.CFrame = frame
	part:SetAttribute(MANAGED_ATTRIBUTE, true)
end

local function managedPart(parent: Model, name: string, size: Vector3, frame: CFrame): Part
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Part") and existing:GetAttribute(MANAGED_ATTRIBUTE) == true then
		setPartProperties(existing, size, frame)
		return existing
	end
	local part = Instance.new("Part")
	part.Name = name
	setPartProperties(part, size, frame)
	part.Parent = parent
	return part
end

local function ensureRoom(area: Model, origin: CFrame, authoring: AuthoringConfig)
	local room = area:FindFirstChild("WhiteRoom")
	if room == nil or not room:IsA("Model") then
		if room ~= nil then
			room:Destroy()
		end
		room = Instance.new("Model")
		room.Name = "WhiteRoom"
		room.Parent = area
	end
	local width = authoring.roomSize[1]
	local height = authoring.roomSize[2]
	local depth = authoring.roomSize[3]
	local thickness = authoring.wallThickness
	local wallY = height * 0.5 - thickness
	managedPart(room, "Floor", Vector3.new(width, thickness, depth), origin * CFrame.new(0, -thickness, 0))
	managedPart(
		room,
		"BackWall",
		Vector3.new(width, height, thickness),
		origin * CFrame.new(0, wallY, depth * 0.5)
	)
	managedPart(
		room,
		"LeftWall",
		Vector3.new(thickness, height, depth),
		origin * CFrame.new(-width * 0.5, wallY, 0)
	)
	managedPart(
		room,
		"RightWall",
		Vector3.new(thickness, height, depth),
		origin * CFrame.new(width * 0.5, wallY, 0)
	)
	managedPart(
		room,
		"FrontHeader",
		Vector3.new(width, 5, thickness),
		origin * CFrame.new(0, height - 4.5, -depth * 0.5)
	)
	managedPart(
		room,
		"FrontLeftPillar",
		Vector3.new(5, height, thickness),
		origin * CFrame.new(-width * 0.5 + 2.5, wallY, -depth * 0.5)
	)
	managedPart(
		room,
		"FrontRightPillar",
		Vector3.new(5, height, thickness),
		origin * CFrame.new(width * 0.5 - 2.5, wallY, -depth * 0.5)
	)
end

local function value(parent: Model, className: string, name: string, configuredValue: any): Instance
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing.ClassName == className then
		local existingValue = existing :: any
		existingValue.Value = configuredValue
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	local createdValue = created :: any
	createdValue.Value = configuredValue
	created.Parent = parent
	return created
end

local function createPlatformShell(origin: CFrame, templateConfig: any): Model
	local platform = Instance.new("Model")
	platform.Name = templateConfig.towerDefense.platformModelName
	platform:SetAttribute(AUTHORING_ATTRIBUTE, true)
	local base = Instance.new("Part")
	base.Name = "PlatformBase"
	base.Anchored = true
	base.CanCollide = true
	base.CanQuery = true
	base.CanTouch = false
	base.Color = Color3.fromRGB(20, 26, 36)
	base.Material = Enum.Material.SmoothPlastic
	base.Size = Vector3.new(128, 0.24, 108)
	base.Transparency = 0.12
	base.CFrame = origin * CFrame.new(0, -0.77, 0)
	base.Parent = platform
	local platformOrigin = Instance.new("Part")
	platformOrigin.Name = templateConfig.towerDefense.platformOriginName
	platformOrigin.Anchored = true
	platformOrigin.CanCollide = false
	platformOrigin.CanQuery = false
	platformOrigin.CanTouch = false
	platformOrigin.Color = Color3.fromRGB(112, 211, 255)
	platformOrigin.Material = Enum.Material.Neon
	platformOrigin.Size = Vector3.new(2, 0.35, 2)
	platformOrigin.Transparency = 0.2
	platformOrigin.CFrame = origin
	platformOrigin.Parent = platform
	value(platform, "IntValue", "Columns", 32)
	value(platform, "IntValue", "Rows", 27)
	value(platform, "IntValue", "CellSize", 4)
	value(platform, "BoolValue", "PlatformEnabled", true)
	value(platform, "BoolValue", "GridVisible", true)
	local cellMap = Instance.new("Folder")
	cellMap.Name = "CellMap"
	cellMap.Parent = platform
	for row = 1, 27 do
		local rowValue = Instance.new("StringValue")
		rowValue.Name = `Row_{string.format("%02d", row)}`
		rowValue.Value = string.rep(".", 32)
		rowValue.Parent = cellMap
	end
	return platform
end

local function alignPlatform(platform: Model, desiredOrigin: CFrame, originName: string)
	local origin = platform:FindFirstChild(originName)
	if origin ~= nil and origin:IsA("BasePart") then
		local transform = desiredOrigin * origin.CFrame:Inverse()
		platform:PivotTo(transform * platform:GetPivot())
	else
		platform:PivotTo(desiredOrigin)
	end
end

local function disableXrayAuthoringGuis(platform: Model)
	for _, descendant in platform:GetDescendants() do
		if descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.AlwaysOnTop = false
		end
	end
end

function AuthoringArea.findPlatform(): Model?
	local templateConfig, authoring = config()
	if templateConfig == nil then
		return nil
	end
	local area = if authoring ~= nil then Workspace:FindFirstChild(authoring.areaName) else nil
	return platformInArea(area, templateConfig) or legacyPlatform(templateConfig)
end

function AuthoringArea.container(): Model?
	local _, authoring = config()
	if authoring == nil then
		return nil
	end
	local area = Workspace:FindFirstChild(authoring.areaName)
	return if area ~= nil and area:IsA("Model") then area else nil
end

function AuthoringArea.platformOriginFrame(): CFrame?
	local platform = AuthoringArea.findPlatform()
	local templateConfig = config()
	local origin = if platform ~= nil and templateConfig ~= nil
		then platform:FindFirstChild(templateConfig.towerDefense.platformOriginName)
		else nil
	return if origin ~= nil and origin:IsA("BasePart") then origin.CFrame else nil
end

function AuthoringArea.origin(): CFrame
	local platformOriginFrame = AuthoringArea.platformOriginFrame()
	if platformOriginFrame ~= nil then
		return platformOriginFrame
	end
	local platform = AuthoringArea.findPlatform()
	local base = if platform ~= nil then platform:FindFirstChild("PlatformBase") else nil
	return if base ~= nil and base:IsA("BasePart") then base.CFrame else CFrame.new()
end

local function outlinePart(
	parent: Model,
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
	part.Color = partColor
	part.Material = material
	part.Size = size
	part.CFrame = frame
	part.Transparency = transparency
	part:SetAttribute("StagewrightDevelopmentGuide", true)
	part.Parent = parent
	return part
end

function AuthoringArea.clearIslandOutlines()
	local folder = sessionOutlineFolder
	sessionOutlineFolder = nil
	if folder ~= nil then
		folder:Destroy()
	end
	for _, tagged in CollectionService:GetTagged(OUTLINE_TAG) do
		if tagged:IsDescendantOf(Workspace) then
			tagged:Destroy()
		end
	end
end

function AuthoringArea.showIslandOutlines(columns: number, rows: number, cellSize: number): boolean
	AuthoringArea.clearIslandOutlines()
	if RunService:IsRunning() then
		return false
	end
	local templateConfig = config()
	if templateConfig == nil then
		return false
	end
	local centerFrame = layoutCenter(templateConfig)
	local outlines = templateConfig.towerDefense.developmentOutlines
	if centerFrame == nil or type(outlines) ~= "table" then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = outlines.folderName
	folder.Archivable = false
	folder:SetAttribute("StagewrightEditorOnly", true)
	folder:SetAttribute("PlatformCount", templateConfig.towerDefense.platformSlotCount)
	folder:SetAttribute("GridColumns", columns)
	folder:SetAttribute("GridRows", rows)
	folder:SetAttribute("CellSize", cellSize)
	folder.Parent = Workspace
	sessionOutlineFolder = folder
	CollectionService:AddTag(folder, OUTLINE_TAG)
	local width = columns * cellSize
	local depth = rows * cellSize
	local slotCount = templateConfig.towerDefense.platformSlotCount
	local lineColor = Color3.fromRGB(outlines.lineColor[1], outlines.lineColor[2], outlines.lineColor[3])
	local fillColor = Color3.fromRGB(outlines.fillColor[1], outlines.fillColor[2], outlines.fillColor[3])
	for slot = 1, slotCount do
		local origin = playableSlotOrigin(templateConfig, centerFrame, slot)
		local model = Instance.new("Model")
		model.Name = `Island_{string.format("%02d", slot)}`
		model:SetAttribute("PlatformSlot", slot)
		model:SetAttribute("StagewrightDevelopmentGuide", true)
		model.Parent = folder
		local height = outlines.heightOffset
		local lineHeight = outlines.lineHeight
		local thickness = outlines.lineThickness
		outlinePart(
			model,
			"Footprint",
			Vector3.new(width, 0.03, depth),
			origin * CFrame.new(0, height - 0.03, 0),
			fillColor,
			outlines.fillTransparency,
			Enum.Material.SmoothPlastic
		)
		for _, edge in
			{
				{
					"LeftEdge",
					Vector3.new(thickness, lineHeight, depth + thickness),
					CFrame.new(-width * 0.5, height, 0),
				},
				{
					"RightEdge",
					Vector3.new(thickness, lineHeight, depth + thickness),
					CFrame.new(width * 0.5, height, 0),
				},
				{
					"FrontEdge",
					Vector3.new(width + thickness, lineHeight, thickness),
					CFrame.new(0, height, -depth * 0.5),
				},
				{
					"BackEdge",
					Vector3.new(width + thickness, lineHeight, thickness),
					CFrame.new(0, height, depth * 0.5),
				},
			}
		do
			outlinePart(
				model,
				edge[1] :: string,
				edge[2] :: Vector3,
				origin * (edge[3] :: CFrame),
				lineColor,
				outlines.lineTransparency,
				Enum.Material.Neon
			)
		end
		local gridThickness = if type(outlines.gridLineThickness) == "number"
			then outlines.gridLineThickness
			else thickness * 0.375
		local gridTransparency = if type(outlines.gridLineTransparency) == "number"
			then outlines.gridLineTransparency
			else 0.32
		for column = 1, columns - 1 do
			local x = -width * 0.5 + column * cellSize
			outlinePart(
				model,
				`GridColumn_{string.format("%02d", column)}`,
				Vector3.new(gridThickness, lineHeight, depth),
				origin * CFrame.new(x, height, 0),
				lineColor,
				gridTransparency,
				Enum.Material.Neon
			)
		end
		for row = 1, rows - 1 do
			local z = -depth * 0.5 + row * cellSize
			outlinePart(
				model,
				`GridRow_{string.format("%02d", row)}`,
				Vector3.new(width, lineHeight, gridThickness),
				origin * CFrame.new(0, height, z),
				lineColor,
				gridTransparency,
				Enum.Material.Neon
			)
		end
	end
	return true
end

local function focusFrame(frame: CFrame, size: Vector3)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local span = math.max(size.X, size.Z, 24)
	local targetPosition = frame.Position
	local offset = frame:VectorToWorldSpace(
		Vector3.new(0, math.max(size.Y + span * 0.65, 35), -math.max(span * 1.1, 45))
	)
	camera.CFrame = CFrame.lookAt(targetPosition + offset, targetPosition)
	camera.Focus = CFrame.new(targetPosition)
	return true
end

local function focusTarget(target: Instance?): boolean
	if target == nil then
		return false
	end
	local frame: CFrame
	local size: Vector3
	if target:IsA("Model") then
		frame, size = target:GetBoundingBox()
	elseif target:IsA("BasePart") then
		frame, size = target.CFrame, target.Size
	else
		local part = target:FindFirstChildWhichIsA("BasePart", true)
		if part == nil then
			return false
		end
		frame, size = part.CFrame, part.Size
	end
	Selection:Set({ target })
	return focusFrame(frame, size)
end

function AuthoringArea.focus(): boolean
	local platform = AuthoringArea.ensure() or AuthoringArea.findPlatform()
	if platform == nil then
		return false
	end
	return focusTarget(platform)
end

function AuthoringArea.focusPlayable(columns: number, rows: number, cellSize: number): boolean
	local templateConfig = config()
	if
		templateConfig == nil
		or columns < 1
		or rows < 1
		or cellSize <= 0
		or columns % 1 ~= 0
		or rows % 1 ~= 0
	then
		return false
	end
	local centerFrame = layoutCenter(templateConfig)
	if centerFrame == nil then
		return false
	end
	local origin = playableSlotOrigin(templateConfig, centerFrame, 1)
	Selection:Set({})
	return focusFrame(origin, Vector3.new(columns * cellSize, 4, rows * cellSize))
end

local function legacyGridNpc(candidate: Instance?): Model?
	if candidate == nil or not candidate:IsA("Model") or candidate.Name ~= "GridNpc" then
		return nil
	end
	local requiredParts = { "Root", "Body", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
	if #candidate:GetChildren() ~= #requiredParts then
		return nil
	end
	for _, name in requiredParts do
		local part = candidate:FindFirstChild(name)
		if part == nil or not part:IsA("BasePart") or not part.Anchored or part.CanCollide then
			return nil
		end
	end
	local root = candidate:FindFirstChild("Root") :: BasePart
	return if root.Transparency == 1 and not root.CanQuery and not root.CanTouch then candidate else nil
end

local function legacyGridNpcScript(): Instance?
	local candidate = ServerScriptService:FindFirstChild("GridNpcDemo")
	if candidate == nil or (not candidate:IsA("Script") and not candidate:IsA("LocalScript")) then
		return nil
	end
	local success, source = pcall(function()
		return candidate.Source
	end)
	if
		not success
		or not string.find(source, "WALK_SPEED_STUDS_PER_SECOND", 1, true)
		or not string.find(source, "StagePath.sample", 1, true)
		or not string.find(source, 'Workspace:FindFirstChild("FirstPrivateIsland")', 1, true)
	then
		return nil
	end
	return candidate
end

function AuthoringArea.removeLegacyArtifacts(existingRecording: boolean?): number
	local templateConfig, authoring = config()
	if templateConfig == nil then
		return 0
	end
	local candidates: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(candidate: Instance?)
		if candidate ~= nil and candidate.Parent ~= nil and not seen[candidate] then
			seen[candidate] = true
			table.insert(candidates, candidate)
		end
	end
	local island = Workspace:FindFirstChild(templateConfig.towerDefense.firstPlatformIslandName)
	local area = if authoring ~= nil then Workspace:FindFirstChild(authoring.areaName) else nil
	for _, root in { island, area } do
		local platform = if root ~= nil
			then root:FindFirstChild(templateConfig.towerDefense.platformModelName)
			else nil
		if platform == nil or not platform:IsA("Model") then
			continue
		end
		for _, name in { "PathPoints", "PathTiles" } do
			local folder = platform:FindFirstChild(name)
			if folder ~= nil and folder:IsA("Folder") then
				add(folder)
			end
		end
		local base = platform:FindFirstChild("PlatformBase")
		local overlay = if base ~= nil then base:FindFirstChild("GridOverlay") else nil
		if overlay ~= nil and overlay:IsA("SurfaceGui") then
			add(overlay)
		end
	end
	add(legacyGridNpc(if island ~= nil then island:FindFirstChild("GridNpc") else nil))
	add(legacyGridNpcScript())
	if #candidates == 0 then
		return 0
	end
	local recording: any = nil
	if existingRecording ~= true then
		recording = ChangeHistoryService:TryBeginRecording(
			"Remove legacy Stagewright artifacts",
			"Remove retired path helpers and NPC demo"
		)
		if recording == nil then
			return 0
		end
	end
	for _, candidate in candidates do
		if candidate.Parent ~= nil then
			candidate:Destroy()
		end
	end
	if recording ~= nil then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return #candidates
end

function AuthoringArea.ensure(): Model?
	local templateConfig, authoring = config()
	if templateConfig == nil or authoring == nil or authoring.enabled ~= true then
		return AuthoringArea.findPlatform()
	end
	if RunService:IsRunning() then
		return AuthoringArea.findPlatform()
	end
	local centerFrame, centerSource = layoutCenter(templateConfig)
	if centerFrame == nil then
		if not warnedMissingCenter then
			warn("Stagewright admin area needs a configured or authored platform center")
			warnedMissingCenter = true
		end
		return legacyPlatform(templateConfig)
	end
	local existingArea = Workspace:FindFirstChild(authoring.areaName)
	local existingPlatform = platformInArea(existingArea, templateConfig)
	local legacy = legacyPlatform(templateConfig)
	local needsSetup = existingArea == nil
		or not existingArea:IsA("Model")
		or existingArea:GetAttribute("StagewrightLayoutVersion") ~= LAYOUT_VERSION
		or existingPlatform == nil
		or legacy ~= nil
	if not needsSetup and existingPlatform ~= nil then
		return existingPlatform
	end

	local recording = ChangeHistoryService:TryBeginRecording(
		"Stagewright admin area",
		"Create the separate Stagewright authoring room"
	)
	local success, result = pcall(function(): Model
		local area = existingArea
		if area == nil or not area:IsA("Model") then
			if area ~= nil then
				area:Destroy()
			end
			area = Instance.new("Model")
			area.Name = authoring.areaName
			area.Parent = Workspace
		end
		local desiredOrigin = targetOrigin(centerFrame, authoring)
		ensureRoom(area, desiredOrigin, authoring)
		local platform = platformInArea(area, templateConfig) or legacy
		if platform == nil then
			platform = createPlatformShell(desiredOrigin, templateConfig)
		end
		platform.Parent = area
		platform:SetAttribute(AUTHORING_ATTRIBUTE, true)
		alignPlatform(platform, desiredOrigin, templateConfig.towerDefense.platformOriginName)
		disableXrayAuthoringGuis(platform)
		area:SetAttribute("StagewrightLayoutVersion", LAYOUT_VERSION)
		area:SetAttribute("EditorOnly", true)
		area:SetAttribute("StagewrightEditorOnly", true)
		area:SetAttribute("RuntimeIslandCount", templateConfig.towerDefense.platformSlotCount)
		area:SetAttribute("WorldCenterName", centerSource or "")
		return platform
	end)
	if recording ~= nil then
		ChangeHistoryService:FinishRecording(
			recording,
			if success then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not success then
		warn(`Stagewright could not create the admin area: {result}`)
		return legacyPlatform(templateConfig)
	end
	return result :: Model
end

return table.freeze(AuthoringArea)

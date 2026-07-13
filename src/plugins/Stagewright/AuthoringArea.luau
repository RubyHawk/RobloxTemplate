--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local AuthoringArea = {}
local StagePlatformLayout = require(script.Parent.Shared.StagePlatformLayout)

local LAYOUT_VERSION = 2
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
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and allowed[descendant.Name] then
			return descendant
		end
	end
	return nil
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

local function targetOrigin(center: BasePart, authoring: AuthoringConfig): CFrame
	local offset = authoring.offsetFromCenter
	return center.CFrame * CFrame.new(offset[1], offset[2], offset[3])
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
	for _, name in { "PathPoints", "PathTiles" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = platform
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

function AuthoringArea.origin(): CFrame
	local platform = AuthoringArea.findPlatform()
	local templateConfig = config()
	local origin = if platform ~= nil and templateConfig ~= nil
		then platform:FindFirstChild(templateConfig.towerDefense.platformOriginName)
		else nil
	if origin ~= nil and origin:IsA("BasePart") then
		return origin.CFrame
	end
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
	local center = centerPart(templateConfig)
	local outlines = templateConfig.towerDefense.developmentOutlines
	if center == nil or type(outlines) ~= "table" then
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
	CollectionService:AddTag(folder, OUTLINE_TAG)
	local width = columns * cellSize
	local depth = rows * cellSize
	local first = templateConfig.towerDefense.firstPlatformOffsetFromCenter
	local firstOffset = { x = first[1], y = first[2], z = first[3] }
	local slotCount = templateConfig.towerDefense.platformSlotCount
	local lineColor = Color3.fromRGB(outlines.lineColor[1], outlines.lineColor[2], outlines.lineColor[3])
	local fillColor = Color3.fromRGB(outlines.fillColor[1], outlines.fillColor[2], outlines.fillColor[3])
	local facingColor =
		Color3.fromRGB(outlines.facingColor[1], outlines.facingColor[2], outlines.facingColor[3])
	for slot = 1, slotCount do
		local offset, yaw = StagePlatformLayout.slotOffset(firstOffset, slot, slotCount)
		local origin = center.CFrame
			* CFrame.new(offset.x, offset.y, offset.z)
			* CFrame.Angles(0, yaw + math.rad(templateConfig.towerDefense.firstPlatformYawDegrees), 0)
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
		outlinePart(
			model,
			"FacingGuide",
			Vector3.new(thickness * 1.8, lineHeight * 1.5, depth * 0.22),
			origin * CFrame.new(0, height + lineHeight * 0.5, -depth * 0.36),
			facingColor,
			0.02,
			Enum.Material.Neon
		)
	end
	return true
end

function AuthoringArea.focus()
	local platform = AuthoringArea.ensure() or AuthoringArea.findPlatform()
	if platform == nil then
		return
	end
	Selection:Set({ platform })
	local origin = AuthoringArea.origin()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local target = origin.Position
		camera.CFrame = CFrame.lookAt(target + origin:VectorToWorldSpace(Vector3.new(0, 105, -125)), target)
		camera.Focus = CFrame.new(target)
	end
end

function AuthoringArea.ensure(): Model?
	local templateConfig, authoring = config()
	if templateConfig == nil or authoring == nil or authoring.enabled ~= true then
		return AuthoringArea.findPlatform()
	end
	if RunService:IsRunning() then
		return AuthoringArea.findPlatform()
	end
	local center = centerPart(templateConfig)
	if center == nil then
		if not warnedMissingCenter then
			warn(
				"Stagewright admin area needs center_grass (or its configured alias) before it can move GamePlatform"
			)
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
		local desiredOrigin = targetOrigin(center, authoring)
		ensureRoom(area, desiredOrigin, authoring)
		local platform = platformInArea(area, templateConfig) or legacy
		if platform == nil then
			platform = createPlatformShell(desiredOrigin, templateConfig)
		end
		platform.Parent = area
		platform:SetAttribute(AUTHORING_ATTRIBUTE, true)
		alignPlatform(platform, desiredOrigin, templateConfig.towerDefense.platformOriginName)
		area:SetAttribute("StagewrightLayoutVersion", LAYOUT_VERSION)
		area:SetAttribute("EditorOnly", true)
		area:SetAttribute("StagewrightEditorOnly", true)
		area:SetAttribute("RuntimeIslandCount", templateConfig.towerDefense.platformSlotCount)
		area:SetAttribute("WorldCenterName", center.Name)
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

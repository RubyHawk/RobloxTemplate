--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local StageTowerRenderer = {}
local enabled = Config.features.towerDefense == true

type TowerRecord = {
	ownerUserId: number,
	slot: number,
	id: string,
	unitId: string,
	cell: {
		column: number,
		row: number,
	},
	frame: CFrame,
}

local FALLBACK_FOLDER_NAME = "StagewrightClientTowers"
local FALLBACK_COLOR = Color3.fromRGB(78, 151, 73)
local FALLBACK_SIZE = Vector3.new(1.4, 2.6, 2.6)
local MAX_GRID_INDEX = 512
local MAX_ID_LENGTH = 128
local MAX_SAFE_INTEGER = 9_007_199_254_740_991

local partsByKey: { [string]: Part } = {}
local partPool: { Part } = {}
local folder: Folder? = nil

local towerDefenseConfig: any = Config.towerDefense
local configuredVisuals: any = if type(towerDefenseConfig.towerVisuals) == "table"
	then towerDefenseConfig.towerVisuals
	else {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: any, minimum: number, maximum: number): boolean
	return isFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function configuredFolderName(): string
	local value = configuredVisuals.folderName
	return if type(value) == "string" and #value >= 1 and #value <= 100 then value else FALLBACK_FOLDER_NAME
end

local function configuredColor(): Color3
	local value = configuredVisuals.color
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "table" and isFinite(value[1]) and isFinite(value[2]) and isFinite(value[3]) then
		return Color3.fromRGB(
			math.clamp(value[1], 0, 255),
			math.clamp(value[2], 0, 255),
			math.clamp(value[3], 0, 255)
		)
	end
	return FALLBACK_COLOR
end

local function validSize(value: Vector3): boolean
	return isFinite(value.X)
		and isFinite(value.Y)
		and isFinite(value.Z)
		and value.X >= 0.05
		and value.Y >= 0.05
		and value.Z >= 0.05
		and value.X <= 512
		and value.Y <= 512
		and value.Z <= 512
end

local function configuredSize(): Vector3
	local value = configuredVisuals.size
	if typeof(value) == "Vector3" and validSize(value) then
		return value
	end
	if type(value) == "table" and isFinite(value[1]) and isFinite(value[2]) and isFinite(value[3]) then
		local size = Vector3.new(value[1], value[2], value[3])
		if validSize(size) then
			return size
		end
	end
	return FALLBACK_SIZE
end

local function configuredSlotCount(): number
	local value = towerDefenseConfig.platformSlotCount
	return if isInteger(value, 1, 100) then value else 6
end

local function validFrame(frame: CFrame): boolean
	local components = { frame:GetComponents() }
	for _, component in components do
		if not isFinite(component) then
			return false
		end
	end
	return true
end

local function parseRecord(value: any): TowerRecord?
	if type(value) ~= "table" then
		return nil
	end
	local ownerUserId = value.ownerUserId
	local slot = value.slot
	local id = value.id
	local unitId = value.unitId
	local cell = value.cell
	local frame = value.frame
	if
		not isInteger(ownerUserId, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER)
		or ownerUserId == 0
		or not isInteger(slot, 1, configuredSlotCount())
		or type(id) ~= "string"
		or #id < 1
		or #id > MAX_ID_LENGTH
		or type(unitId) ~= "string"
		or #unitId < 1
		or #unitId > MAX_ID_LENGTH
		or type(cell) ~= "table"
		or not isInteger(cell.column, 1, MAX_GRID_INDEX)
		or not isInteger(cell.row, 1, MAX_GRID_INDEX)
		or typeof(frame) ~= "CFrame"
		or not validFrame(frame)
	then
		return nil
	end
	return {
		ownerUserId = ownerUserId,
		slot = slot,
		id = id,
		unitId = unitId,
		cell = {
			column = cell.column,
			row = cell.row,
		},
		frame = frame,
	}
end

local function resetDestroyedFolderState()
	partsByKey = {}
	partPool = {}
end

local function renderFolder(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	if folder ~= nil then
		resetDestroyedFolderState()
	end
	local folderName = configuredFolderName()
	local existing = Workspace:FindFirstChild(folderName)
	if
		existing ~= nil
		and existing:IsA("Folder")
		and existing:GetAttribute("StagewrightClientOwned") == true
	then
		existing:Destroy()
		existing = nil
	end
	local nextFolder = Instance.new("Folder")
	nextFolder.Name = if existing == nil then folderName else `{folderName}_Local`
	nextFolder:SetAttribute("StagewrightClientOwned", true)
	nextFolder.Parent = Workspace
	folder = nextFolder
	return nextFolder
end

local function applyAppearance(part: Part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = configuredSize()
	part.Color = configuredColor()
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0
end

local function acquirePart(key: string): Part
	local part = table.remove(partPool)
	if part == nil then
		part = Instance.new("Part")
	end
	part.Name = key
	applyAppearance(part)
	part.Parent = renderFolder()
	return part
end

local function releasePart(part: Part)
	part.Name = "PooledTower"
	part.Transparency = 1
	part:SetAttribute("OwnerUserId", nil)
	part:SetAttribute("PlatformSlot", nil)
	part:SetAttribute("PlacementId", nil)
	part:SetAttribute("UnitId", nil)
	part:SetAttribute("CellColumn", nil)
	part:SetAttribute("CellRow", nil)
	table.insert(partPool, part)
end

local function recordKey(ownerUserId: number, id: string): string
	return `{ownerUserId}:{id}`
end

local function applyRecord(part: Part, key: string, record: TowerRecord)
	part.Name = key
	part.CFrame = record.frame
	part.Transparency = 0
	part:SetAttribute("OwnerUserId", record.ownerUserId)
	part:SetAttribute("PlatformSlot", record.slot)
	part:SetAttribute("PlacementId", record.id)
	part:SetAttribute("UnitId", record.unitId)
	part:SetAttribute("CellColumn", record.cell.column)
	part:SetAttribute("CellRow", record.cell.row)
end

function StageTowerRenderer.initialize()
	if not enabled then
		return
	end
	renderFolder()
end

function StageTowerRenderer.apply(records: any?)
	if not enabled then
		return
	end
	renderFolder()
	local seen: { [string]: boolean } = {}
	if type(records) == "table" then
		for _, value in ipairs(records) do
			local record = parseRecord(value)
			if record == nil then
				continue
			end
			local key = recordKey(record.ownerUserId, record.id)
			seen[key] = true
			local part = partsByKey[key]
			if part == nil then
				part = acquirePart(key)
				partsByKey[key] = part
			end
			applyRecord(part, key, record)
		end
	end
	for key, part in partsByKey do
		if not seen[key] then
			releasePart(part)
			partsByKey[key] = nil
		end
	end
end

return StageTowerRenderer

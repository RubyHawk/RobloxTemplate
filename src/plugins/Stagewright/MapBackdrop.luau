--!strict

local StageHierarchy = require(script.Parent.Shared.StageHierarchy)

local MapBackdrop = {}

local MAP_IMAGE_FIELD = "backdropImageId"
local LEGACY_METADATA_KEY = "stagewright.mapBackdrops"
local LEGACY_CONFLICT_KEY = "stagewright.legacyBackdropConflict"

local function stageMapId(stage: any): string?
	if type(stage) ~= "table" or type(stage.mapId) ~= "string" or stage.mapId == "" then
		return nil
	end
	return stage.mapId
end

local function mapRecord(project: any, stage: any): any?
	local mapId = stageMapId(stage)
	local maps = if type(project) == "table" then project.maps else nil
	if mapId == nil or type(maps) ~= "table" then
		return nil
	end
	local direct = maps[mapId]
	return if type(direct) == "table" then direct else nil
end

local function legacyBackdrops(project: any): any?
	local metadata = if type(project) == "table" then project.metadata else nil
	local backdrops = if type(metadata) == "table" then metadata[LEGACY_METADATA_KEY] else nil
	return if type(backdrops) == "table" then backdrops else nil
end

local function legacyGroupId(stage: any): string
	return StageHierarchy.address(stage).groupId
end

local function setLegacyImageId(project: any, stage: any, imageId: string): (boolean, string?)
	if type(project) ~= "table" then
		return false, "Stage project is missing"
	end
	local changed = false
	if type(project.metadata) ~= "table" then
		if imageId == "" and project.metadata == nil then
			return false, nil
		end
		project.metadata = {}
		changed = true
	end
	local metadata = project.metadata
	local backdrops = metadata[LEGACY_METADATA_KEY]
	local groupId = legacyGroupId(stage)
	if imageId == "" then
		if type(backdrops) == "table" and backdrops[groupId] ~= nil then
			backdrops[groupId] = nil
			changed = true
			if next(backdrops) == nil then
				metadata[LEGACY_METADATA_KEY] = nil
			end
		elseif backdrops ~= nil and type(backdrops) ~= "table" then
			metadata[LEGACY_METADATA_KEY] = nil
			changed = true
		end
		return changed, nil
	end
	if type(backdrops) ~= "table" then
		backdrops = {}
		metadata[LEGACY_METADATA_KEY] = backdrops
		changed = true
	end
	if backdrops[groupId] ~= imageId then
		backdrops[groupId] = imageId
		changed = true
	end
	return changed, nil
end

function MapBackdrop.normalizeImageId(value: any): string?
	-- Asset IDs remain strings throughout. Roblox IDs can outgrow exact Lua
	-- number precision, so accepting numbers here would silently corrupt them.
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return ""
	end
	if string.match(trimmed, "^%d+$") ~= nil then
		return trimmed
	end
	return string.match(trimmed, "^rbxassetid://(%d+)$")
end

function MapBackdrop.readImageId(project: any, stage: any): string
	local map = mapRecord(project, stage)
	if map ~= nil then
		local configured = MapBackdrop.normalizeImageId(map[MAP_IMAGE_FIELD])
		-- A first-class Map is authoritative, including an intentionally blank
		-- image. Legacy Stage-group artwork must not leak between Stages in the
		-- same Map after schema migration.
		return configured or ""
	end
	if type(project) == "table" and type(project.maps) == "table" then
		return ""
	end
	local backdrops = legacyBackdrops(project)
	local stored = if backdrops ~= nil then backdrops[legacyGroupId(stage)] else nil
	return MapBackdrop.normalizeImageId(stored) or ""
end

function MapBackdrop.contentId(project: any, stage: any): string?
	local imageId = MapBackdrop.readImageId(project, stage)
	return if imageId == "" then nil else `rbxassetid://{imageId}`
end

function MapBackdrop.apply(project: any, stage: any, imageIdValue: any): (boolean, string?)
	local imageId = MapBackdrop.normalizeImageId(imageIdValue)
	if imageId == nil then
		return false, "Backdrop image ID must be blank, digits, or rbxassetid://digits"
	end
	if type(project) ~= "table" then
		return false, "Stage project is missing"
	end
	if type(stage) ~= "table" then
		return false, "Stage is missing"
	end

	local map = mapRecord(project, stage)
	if map == nil then
		if type(project.maps) == "table" then
			return false, "The selected Level does not reference an existing Map"
		end
		return setLegacyImageId(project, stage, imageId)
	end
	local changed = false
	if map[MAP_IMAGE_FIELD] ~= imageId then
		map[MAP_IMAGE_FIELD] = imageId
		changed = true
	end
	if type(map.metadata) == "table" and map.metadata[LEGACY_CONFLICT_KEY] ~= nil then
		map.metadata[LEGACY_CONFLICT_KEY] = nil
		changed = true
	end
	return changed, nil
end

function MapBackdrop.clear(project: any, stage: any): (boolean, string?)
	return MapBackdrop.apply(project, stage, "")
end

return table.freeze(MapBackdrop)

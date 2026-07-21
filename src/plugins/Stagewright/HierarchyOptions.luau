--!strict

local StageHierarchy = require(script.Parent.Shared.StageHierarchy)

local HierarchyOptions = {}

export type SelectorOption = {
	value: string,
	label: string,
	selected: boolean,
}

export type LevelItem = {
	id: string,
	name: string,
	number: number,
}

export type StageItem = {
	id: string,
	number: number,
	representativeLevelId: string,
	levels: { LevelItem },
}

export type MapItem = {
	id: string,
	name: string,
	number: number,
	representativeLevelId: string,
	stages: { StageItem },
}

export type Result = {
	mapOptions: { SelectorOption },
	stageOptions: { SelectorOption },
	levelOptions: { SelectorOption },
	maps: { MapItem },
	selectedMapId: string?,
	selectedStageGroupId: string?,
}

export type WorldSize = {
	x: number,
	y: number,
}

local function positiveFinite(value: any): number?
	if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
		return nil
	end
	return value
end

local function mapName(definition: any, number: number): string
	local name = if type(definition) == "table" and type(definition.name) == "string"
		then definition.name
		else ""
	return if name == "" or name == `Map {number}` then `Map {number}` else `Map {number}: {name}`
end

local function buildTree(project: any): { MapItem }
	local stages = if type(project) == "table" and type(project.stages) == "table" then project.stages else {}
	local maps = if type(project) == "table" and type(project.maps) == "table" then project.maps else {}
	local sortedLevelIds = StageHierarchy.sortedIds(stages, maps)
	local mapItems: { MapItem } = {}
	local mapById: { [string]: MapItem } = {}

	for mapNumber, mapId in StageHierarchy.mapIds(maps) do
		local definition = maps[mapId]
		local item: MapItem = {
			id = mapId,
			name = mapName(definition, mapNumber),
			number = mapNumber,
			representativeLevelId = "",
			stages = {},
		}
		mapById[mapId] = item
		table.insert(mapItems, item)
	end

	local stageByMapAndGroup: { [string]: StageItem } = {}
	for _, levelId in sortedLevelIds do
		local definition = stages[levelId]
		if type(definition) ~= "table" then
			continue
		end
		local address = StageHierarchy.address(definition)
		local mapItem = mapById[address.mapId]
		if mapItem == nil then
			continue
		end
		if mapItem.representativeLevelId == "" then
			mapItem.representativeLevelId = levelId
		end
		local stageKey = `{address.mapId}\0{address.groupId}`
		local stageItem = stageByMapAndGroup[stageKey]
		if stageItem == nil then
			stageItem = {
				id = address.groupId,
				number = address.stageNumber,
				representativeLevelId = levelId,
				levels = {},
			}
			stageByMapAndGroup[stageKey] = stageItem
			table.insert(mapItem.stages, stageItem)
		end
		table.insert(stageItem.levels, {
			id = levelId,
			name = if type(definition.name) == "string" then definition.name else "",
			number = address.levelNumber,
		})
	end

	for _, mapItem in mapItems do
		table.sort(mapItem.stages, function(left, right)
			return if left.number == right.number then left.id < right.id else left.number < right.number
		end)
		for _, stageItem in mapItem.stages do
			table.sort(stageItem.levels, function(left, right)
				return if left.number == right.number then left.id < right.id else left.number < right.number
			end)
		end
	end
	return mapItems
end

function HierarchyOptions.build(project: any, selectedLevelId: string?): Result
	local stages = if type(project) == "table" and type(project.stages) == "table" then project.stages else {}
	local selectedLevel = if selectedLevelId ~= nil then stages[selectedLevelId] else nil
	local selectedAddress = if type(selectedLevel) == "table"
		then StageHierarchy.address(selectedLevel)
		else nil
	local tree = buildTree(project)
	local mapOptions: { SelectorOption } = {}
	local stageOptions: { SelectorOption } = {}
	local levelOptions: { SelectorOption } = {}

	for _, mapItem in tree do
		if selectedAddress ~= nil and selectedLevelId ~= nil and selectedAddress.mapId == mapItem.id then
			mapItem.representativeLevelId = selectedLevelId
			for _, stageItem in mapItem.stages do
				if selectedAddress.groupId == stageItem.id then
					stageItem.representativeLevelId = selectedLevelId
					break
				end
			end
		end
		if mapItem.representativeLevelId == "" then
			continue
		end
		local selected = selectedAddress ~= nil and selectedAddress.mapId == mapItem.id
		table.insert(mapOptions, {
			value = if selected and selectedLevelId ~= nil
				then selectedLevelId
				else mapItem.representativeLevelId,
			label = mapItem.name,
			selected = selected,
		})
		if not selected then
			continue
		end
		for _, stageItem in mapItem.stages do
			local stageSelected = selectedAddress ~= nil and selectedAddress.groupId == stageItem.id
			table.insert(stageOptions, {
				value = if stageSelected and selectedLevelId ~= nil
					then selectedLevelId
					else stageItem.representativeLevelId,
				label = `Stage {stageItem.number}`,
				selected = stageSelected,
			})
			if stageSelected then
				for _, levelItem in stageItem.levels do
					table.insert(levelOptions, {
						value = levelItem.id,
						label = `Level {levelItem.number}`,
						selected = levelItem.id == selectedLevelId,
					})
				end
			end
		end
	end

	return {
		mapOptions = mapOptions,
		stageOptions = stageOptions,
		levelOptions = levelOptions,
		maps = tree,
		selectedMapId = if selectedAddress ~= nil then selectedAddress.mapId else nil,
		selectedStageGroupId = if selectedAddress ~= nil then selectedAddress.groupId else nil,
	}
end

-- A Map owns one backdrop, so every Level in that Map must share one stable
-- coordinate frame. Derive it without changing any authored grid: the largest
-- width and depth across the Map define the frame, while each live grid remains
-- centered on the same world origin.
function HierarchyOptions.mapWorldSize(project: any, selectedLevel: any?): WorldSize?
	if type(project) ~= "table" or type(project.stages) ~= "table" or type(selectedLevel) ~= "table" then
		return nil
	end
	local selectedMapId = StageHierarchy.address(selectedLevel).mapId
	local maximumWidth = 0
	local maximumDepth = 0
	for _, level in project.stages do
		if type(level) == "table" and StageHierarchy.address(level).mapId == selectedMapId then
			local grid = level.grid
			if type(grid) == "table" then
				local columns = positiveFinite(grid.columns)
				local rows = positiveFinite(grid.rows)
				local cellSize = positiveFinite(grid.cellSize)
				if columns ~= nil and rows ~= nil and cellSize ~= nil then
					maximumWidth = math.max(maximumWidth, columns * cellSize)
					maximumDepth = math.max(maximumDepth, rows * cellSize)
				end
			end
		end
	end
	return if maximumWidth > 0 and maximumDepth > 0 then { x = maximumWidth, y = maximumDepth } else nil
end

return table.freeze(HierarchyOptions)

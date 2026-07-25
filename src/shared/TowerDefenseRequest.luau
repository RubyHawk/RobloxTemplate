--!strict

local TowerDefenseRequest = {}

TowerDefenseRequest.MAX_GRID_INDEX = 512
TowerDefenseRequest.MAX_UNIT_ID_LENGTH = 64
TowerDefenseRequest.MAX_STAGE_ID_LENGTH = 80

export type Placement = {
	unitId: string,
	column: number,
	row: number,
}

export type StageActivation = {
	stageId: string,
}

export type WavePlaytest = {
	stageId: string,
	waveNumber: number,
}

export type Loadout = {
	unitIds: { string },
}

local PLACEMENT_FIELDS: { [string]: boolean } = {
	unitId = true,
	column = true,
	row = true,
}

local STAGE_ACTIVATION_FIELDS: { [string]: boolean } = {
	stageId = true,
}

local WAVE_PLAYTEST_FIELDS: { [string]: boolean } = {
	stageId = true,
	waveNumber = true,
}

local LOADOUT_FIELDS: { [string]: boolean } = {
	unitIds = true,
}

local function hasOnlyFields(value: { [any]: any }, allowed: { [string]: boolean }): boolean
	for key in value do
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
	end
	return true
end

local function isGridIndex(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value >= 1
		and value <= TowerDefenseRequest.MAX_GRID_INDEX
end

function TowerDefenseRequest.parsePlacement(payload: any): Placement?
	if type(payload) ~= "table" or not hasOnlyFields(payload, PLACEMENT_FIELDS) then
		return nil
	end
	local unitId = payload.unitId
	local column = payload.column
	local row = payload.row
	if
		type(unitId) ~= "string"
		or #unitId < 1
		or #unitId > TowerDefenseRequest.MAX_UNIT_ID_LENGTH
		or not isGridIndex(column)
		or not isGridIndex(row)
	then
		return nil
	end
	return {
		unitId = unitId,
		column = column,
		row = row,
	}
end

function TowerDefenseRequest.parseStageActivation(payload: any): StageActivation?
	if type(payload) ~= "table" or not hasOnlyFields(payload, STAGE_ACTIVATION_FIELDS) then
		return nil
	end
	local stageId = payload.stageId
	if type(stageId) ~= "string" or #stageId < 1 or #stageId > TowerDefenseRequest.MAX_STAGE_ID_LENGTH then
		return nil
	end
	return { stageId = stageId }
end

function TowerDefenseRequest.parseWavePlaytest(payload: any): WavePlaytest?
	if type(payload) ~= "table" or not hasOnlyFields(payload, WAVE_PLAYTEST_FIELDS) then
		return nil
	end
	local stageId = payload.stageId
	local waveNumber = payload.waveNumber
	if
		type(stageId) ~= "string"
		or #stageId < 1
		or #stageId > TowerDefenseRequest.MAX_STAGE_ID_LENGTH
		or type(waveNumber) ~= "number"
		or waveNumber ~= waveNumber
		or waveNumber == math.huge
		or waveNumber == -math.huge
		or waveNumber % 1 ~= 0
		or waveNumber < 1
		or waveNumber > 100
	then
		return nil
	end
	return {
		stageId = stageId,
		waveNumber = waveNumber,
	}
end

function TowerDefenseRequest.parseUnitIds(unitIds: any, maxSlots: number): { string }?
	if
		type(unitIds) ~= "table"
		or maxSlots ~= maxSlots
		or maxSlots == math.huge
		or maxSlots == -math.huge
		or maxSlots % 1 ~= 0
		or maxSlots < 1
	then
		return nil
	end

	local count = 0
	for index, unitId in unitIds do
		if
			type(index) ~= "number"
			or index % 1 ~= 0
			or index < 1
			or index > maxSlots
			or type(unitId) ~= "string"
			or #unitId < 1
			or #unitId > TowerDefenseRequest.MAX_UNIT_ID_LENGTH
		then
			return nil
		end
		count += 1
	end

	local parsed: { string } = {}
	for index = 1, count do
		local unitId = unitIds[index]
		if type(unitId) ~= "string" then
			return nil
		end
		parsed[index] = unitId
	end
	return parsed
end

function TowerDefenseRequest.parseLoadout(payload: any, maxSlots: number): Loadout?
	if type(payload) ~= "table" or not hasOnlyFields(payload, LOADOUT_FIELDS) then
		return nil
	end
	local unitIds = TowerDefenseRequest.parseUnitIds(payload.unitIds, maxSlots)
	if unitIds == nil then
		return nil
	end
	return { unitIds = unitIds }
end

function TowerDefenseRequest.acceptsNoPayload(payload: any): boolean
	return payload == nil or (type(payload) == "table" and next(payload) == nil)
end

return table.freeze(TowerDefenseRequest)

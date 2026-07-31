--!strict

local TowerDefenseLogic = {}

export type OwnedUnitEntry = {
	count: number,
}

export type UnitLike = {
	id: string,
	damage: number,
	range: number,
	fireRate: number,
	deployCost: number,
	rollWeight: number,
}

export type GridCellCode = "." | "#" | "P" | "G" | "A"

local BUILDABLE_CODES = {
	["."] = true,
	A = true,
}

local BLOCKING_CODES = {
	["#"] = true,
	P = true,
	G = true,
}

function TowerDefenseLogic.normalizeCellCode(code: string?): GridCellCode
	if code == "." or code == "#" or code == "P" or code == "G" or code == "A" then
		return code
	end
	return "."
end

function TowerDefenseLogic.isBuildableCell(code: string?): boolean
	return BUILDABLE_CODES[TowerDefenseLogic.normalizeCellCode(code)] == true
end

function TowerDefenseLogic.isBlockedCell(code: string?): boolean
	return BLOCKING_CODES[TowerDefenseLogic.normalizeCellCode(code)] == true
end

function TowerDefenseLogic.isAutoPlaceCell(code: string?): boolean
	return TowerDefenseLogic.normalizeCellCode(code) == "A"
end

function TowerDefenseLogic.isPortalCell(code: string?): boolean
	return TowerDefenseLogic.normalizeCellCode(code) == "P"
end

function TowerDefenseLogic.isGoalCell(code: string?): boolean
	return TowerDefenseLogic.normalizeCellCode(code) == "G"
end

function TowerDefenseLogic.unitScore(unit: UnitLike): number
	local fireRate = math.max(unit.fireRate, 0.05)
	return (unit.damage / fireRate) * (1 + unit.range / 40)
end

function TowerDefenseLogic.bestLoadout(
	owned: { [string]: OwnedUnitEntry },
	units: { UnitLike },
	maxSlots: number
): { string }
	local candidates: { UnitLike } = {}
	for _, unit in units do
		local entry = owned[unit.id]
		if entry ~= nil and type(entry.count) == "number" and entry.count > 0 then
			table.insert(candidates, unit)
		end
	end
	table.sort(candidates, function(left, right)
		local leftScore = TowerDefenseLogic.unitScore(left)
		local rightScore = TowerDefenseLogic.unitScore(right)
		if leftScore == rightScore then
			return left.id < right.id
		end
		return leftScore > rightScore
	end)

	local loadout: { string } = {}
	for _, unit in candidates do
		local entry = owned[unit.id]
		local copies = if entry ~= nil and type(entry.count) == "number"
			then math.max(math.floor(entry.count), 0)
			else 0
		for _ = 1, copies do
			if #loadout >= maxSlots then
				break
			end
			table.insert(loadout, unit.id)
		end
		if #loadout >= maxSlots then
			return loadout
		end
	end
	return loadout
end

function TowerDefenseLogic.weightTotal(units: { UnitLike }): number
	local total = 0
	for _, unit in units do
		if unit.rollWeight > 0 then
			total += unit.rollWeight
		end
	end
	return total
end

function TowerDefenseLogic.pickWeightedUnitIndex(units: { UnitLike }, roll01: number): number
	local total = TowerDefenseLogic.weightTotal(units)
	if total <= 0 then
		return 0
	end
	local target = math.clamp(roll01, 0, 0.999999) * total
	local cursor = 0
	for index, unit in units do
		if unit.rollWeight > 0 then
			cursor += unit.rollWeight
			if target < cursor then
				return index
			end
		end
	end
	return #units
end

-- Wave difficulty growth moved to TowerDefenseWaves.scalingFor, which resolves
-- every axis from the wave set's authored loop curve instead of one hardcoded
-- health-and-reward ramp.

return table.freeze(TowerDefenseLogic)

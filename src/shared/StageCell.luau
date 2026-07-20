--!strict

local StageTypes = if script ~= nil then require(script.Parent.StageTypes) else require("./StageTypes")

type CellOverride = StageTypes.CellOverride

local StageCell = {}

function StageCell.resolve(defaultCell: CellOverride, override: CellOverride?): CellOverride
	if override == nil then
		return defaultCell
	end
	local resolved: any = table.clone(defaultCell :: any)
	for key, value in override :: any do
		resolved[key] = value
	end
	return resolved :: CellOverride
end

return table.freeze(StageCell)

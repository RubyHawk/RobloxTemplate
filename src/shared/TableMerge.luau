--!strict

-- Dependency-free deep merge used to apply per-pack theme overrides over the base
-- tokens without mutating the frozen base. Only plain tables are merged
-- recursively; any non-table value (numbers, strings, Color3/UDim/Font, etc.) is
-- treated as a leaf and the override wins. Returns a fresh table.

local TableMerge = {}

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = clone(child)
	end
	return result
end

function TableMerge.deep(base: any, override: any?): any
	local result = clone(base)
	if type(override) ~= "table" then
		return result
	end
	for key, value in override do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = TableMerge.deep(result[key], value)
		else
			result[key] = clone(value)
		end
	end
	return result
end

return TableMerge

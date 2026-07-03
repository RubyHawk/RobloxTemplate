--!strict

local DataStoreNames = {}

function DataStoreNames.validateNamespace(value: any): string
	assert(type(value) == "string", "DataStore namespace must be a string")
	assert(#value >= 1 and #value <= 15, "DataStore namespace must be 1-15 characters")
	assert(
		string.match(value, "^[a-z][a-z0-9_]*$") ~= nil,
		"DataStore namespace must be a lowercase identifier"
	)
	return value
end

function DataStoreNames.scoped(baseName: string, namespace: string): string
	local safeNamespace = DataStoreNames.validateNamespace(namespace)
	local result = `{baseName}_{safeNamespace}`
	assert(#result <= 50, `DataStore name is too long: {result}`)
	return result
end

return table.freeze(DataStoreNames)

--!strict

local MigrationCore = {}

function MigrationCore.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[MigrationCore.deepCopy(key)] = MigrationCore.deepCopy(child)
	end
	return result
end

function MigrationCore.reconcile(target: any, defaults: any)
	for key, value in defaults do
		if target[key] == nil or type(target[key]) ~= type(value) then
			target[key] = MigrationCore.deepCopy(value)
		elseif type(value) == "table" then
			MigrationCore.reconcile(target[key], value)
		elseif type(value) == "number" then
			local numberValue = target[key]
			if numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
				target[key] = value
			end
		end
	end
end

function MigrationCore.migrate(raw: any, defaults: any, currentVersion: number): any
	if
		type(raw) == "table"
		and type(raw.schemaVersion) == "number"
		and raw.schemaVersion > currentVersion
	then
		error(`profile schema {raw.schemaVersion} is newer than supported schema {currentVersion}`)
	end
	local profile = if type(raw) == "table"
		then MigrationCore.deepCopy(raw)
		else MigrationCore.deepCopy(defaults)
	MigrationCore.reconcile(profile, defaults)
	profile.schemaVersion = currentVersion
	return profile
end

return MigrationCore

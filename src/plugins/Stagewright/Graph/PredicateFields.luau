--!strict

local PredicateFields = {}

PredicateFields.KINDS = table.freeze({
	"WaveRange",
	"StageFlagEquals",
	"EnemyTag",
	"VisitCountBelow",
	"StageUnlocked",
	"UpgradeLevelAtLeast",
	"CurrencyAtLeast",
})

function PredicateFields.fromText(
	kind: string,
	key: string,
	value: string,
	maximum: string,
	edge: any
): (any?, string?)
	if kind == "WaveRange" then
		local minimumNumber = tonumber(value)
		local maximumNumber = tonumber(maximum)
		if minimumNumber == nil or maximumNumber == nil then
			return nil, "WaveRange needs numeric minimum and maximum values"
		end
		return { kind = kind, minimum = minimumNumber, maximum = maximumNumber }, nil
	elseif kind == "StageFlagEquals" then
		if key == "" or (string.lower(value) ~= "true" and string.lower(value) ~= "false") then
			return nil, "StageFlagEquals needs a key and true/false value"
		end
		return { kind = kind, key = key, value = string.lower(value) == "true" }, nil
	elseif kind == "EnemyTag" then
		return if key ~= "" then { kind = kind, tag = key } else nil,
			if key == "" then "EnemyTag needs a tag" else nil
	elseif kind == "VisitCountBelow" then
		local maximumNumber = tonumber(value)
		if maximumNumber == nil then
			return nil, "VisitCountBelow needs a numeric maximum"
		end
		return {
			kind = kind,
			nodeId = if key ~= "" then key else edge.fromNodeId,
			maximum = maximumNumber,
		},
			nil
	elseif kind == "StageUnlocked" then
		return if key ~= "" then { kind = kind, stageId = key } else nil,
			if key == "" then "StageUnlocked needs a stage ID" else nil
	elseif kind == "UpgradeLevelAtLeast" then
		local level = tonumber(value)
		if key == "" or level == nil then
			return nil, "UpgradeLevelAtLeast needs an upgrade ID and numeric level"
		end
		return { kind = kind, upgradeId = key, level = level }, nil
	elseif kind == "CurrencyAtLeast" then
		local amount = tonumber(value)
		if key == "" or amount == nil then
			return nil, "CurrencyAtLeast needs a currency ID and numeric amount"
		end
		return { kind = kind, currencyId = key, amount = amount }, nil
	end
	return nil, "Unknown predicate kind"
end

function PredicateFields.commaSet(text: string): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for token in string.gmatch(text, "[^,%s]+") do
		result[token] = true
	end
	return result
end

function PredicateFields.assignmentMap(text: string, booleanValues: boolean): { [string]: any }
	local result: { [string]: any } = {}
	for token in string.gmatch(text, "[^,]+") do
		local key, value = string.match(token, "^%s*([^=]+)%s*=%s*([^=]+)%s*$")
		if key ~= nil and value ~= nil then
			if booleanValues then
				result[key] = string.lower(value) == "true"
			else
				local numberValue = tonumber(value)
				if numberValue ~= nil then
					result[key] = numberValue
				end
			end
		end
	end
	return result
end

return table.freeze(PredicateFields)

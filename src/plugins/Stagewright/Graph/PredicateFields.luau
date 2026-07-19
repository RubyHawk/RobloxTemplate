--!strict

local PredicateFields = {}
local MAXIMUM_MAGNITUDE = 1_000_000_000_000

local function boundedNumber(value: number?): boolean
	return value ~= nil
		and value == value
		and value > -math.huge
		and value < math.huge
		and math.abs(value) <= MAXIMUM_MAGNITUDE
end

local function wholeAtLeast(value: number?, minimum: number): boolean
	return boundedNumber(value) and value >= minimum and value % 1 == 0
end

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
		local maximumNumber = if maximum == "" then nil else tonumber(maximum)
		if not wholeAtLeast(minimumNumber, 1) or (maximum ~= "" and not wholeAtLeast(maximumNumber, 1)) then
			return nil, "WaveRange needs a positive whole-number minimum and optional maximum"
		end
		if maximumNumber ~= nil and maximumNumber < minimumNumber then
			return nil, "WaveRange maximum must be greater than or equal to its minimum"
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
		if not wholeAtLeast(maximumNumber, 0) then
			return nil, "VisitCountBelow needs a nonnegative whole-number maximum"
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
		if key == "" or not wholeAtLeast(level, 0) then
			return nil, "UpgradeLevelAtLeast needs an upgrade ID and nonnegative whole-number level"
		end
		return { kind = kind, upgradeId = key, level = level }, nil
	elseif kind == "CurrencyAtLeast" then
		local amount = tonumber(value)
		if key == "" or not boundedNumber(amount) or amount < 0 then
			return nil, "CurrencyAtLeast needs a currency ID and nonnegative finite amount"
		end
		return { kind = kind, currencyId = key, amount = amount }, nil
	end
	return nil, "Unknown predicate kind"
end

function PredicateFields.describe(predicate: any): string
	if type(predicate) ~= "table" then
		return "Unknown condition"
	end
	if predicate.kind == "WaveRange" then
		if predicate.maximum ~= nil then
			return `Wave {tostring(predicate.minimum or 1)}-{tostring(predicate.maximum)}`
		end
		return `Wave >= {tostring(predicate.minimum or 1)}`
	elseif predicate.kind == "StageFlagEquals" then
		return `{tostring(predicate.key)} = {tostring(predicate.value)}`
	elseif predicate.kind == "EnemyTag" then
		return `Enemy tag: {tostring(predicate.tag)}`
	elseif predicate.kind == "VisitCountBelow" then
		return `Visits to {tostring(predicate.nodeId)} < {tostring(predicate.maximum)}`
	elseif predicate.kind == "StageUnlocked" then
		return `Unlocked: {tostring(predicate.stageId)}`
	elseif predicate.kind == "UpgradeLevelAtLeast" then
		return `{tostring(predicate.upgradeId)} >= {tostring(predicate.level)}`
	elseif predicate.kind == "CurrencyAtLeast" then
		return `{tostring(predicate.currencyId)} >= {tostring(predicate.amount)}`
	end
	return tostring(predicate.kind or "Unknown condition")
end

return table.freeze(PredicateFields)

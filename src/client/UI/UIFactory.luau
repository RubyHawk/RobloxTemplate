--!strict

-- Visual UI is authored as real StarterGui instances in TemplateUI.model.json.
-- This module intentionally contains only presentation-safe formatting helpers.
local UIFactory = {}

function UIFactory.formatNumber(value: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local absolute = math.abs(value)
	local index = 1
	while absolute >= 1000 and index < #suffixes do
		absolute /= 1000
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	return `{string.format("%.1f", value)}{suffixes[index]}`
end

return table.freeze(UIFactory)

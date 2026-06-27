--!strict

local Config = require(script.Parent.TemplateConfig)

local FeatureRegistry = {}

function FeatureRegistry.isEnabled(name: string): boolean
	return Config.features[name] == true
end

function FeatureRegistry.requireEnabled(name: string): (boolean, string?)
	if FeatureRegistry.isEnabled(name) then
		return true, nil
	end
	return false, `Feature "{name}" is disabled in TemplateConfig`
end

function FeatureRegistry.snapshot(): { [string]: boolean }
	return table.clone(Config.features)
end

return FeatureRegistry

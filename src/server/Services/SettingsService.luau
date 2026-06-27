--!strict

local ProfileService = require(script.Parent.ProfileService)

local SettingsService = {}

function SettingsService.update(player: Player, key: any, value: any): (boolean, string)
	local profile = ProfileService.get(player)
	if profile == nil or type(key) ~= "string" then
		return false, "Profile is not loaded"
	end
	if key == "musicVolume" or key == "sfxVolume" then
		if type(value) ~= "number" or value ~= value then
			return false, "Volume must be a number"
		end
		profile.settings[key] = math.clamp(value, 0, 1)
	elseif key == "uiScale" then
		if type(value) ~= "number" or value ~= value then
			return false, "UI scale must be a number"
		end
		profile.settings.uiScale = math.clamp(value, 0.8, 1.2)
	elseif
		key == "reducedMotion"
		or key == "announcements"
		or key == "afKRollOver"
		or key == "notifications"
	then
		if type(value) ~= "boolean" then
			return false, "Setting must be on or off"
		end
		profile.settings[key] = value
	else
		return false, "Setting is not supported"
	end
	ProfileService.markDirty(player, `settings:{key}`)
	return true, "Setting updated"
end

return SettingsService

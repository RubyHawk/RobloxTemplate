--!strict

local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local AfkService = {}

function AfkService.rollOver(player: Player): (boolean, string)
	if RunService:IsStudio() then
		return true, "AFK rollover simulated in Studio"
	end
	local success, message = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	return success, if success then "Joining a fresh server" else tostring(message)
end

return AfkService

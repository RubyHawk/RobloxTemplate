--!strict

local Config = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").TemplateConfig
)

local Provider = {}

function Provider.verify(player: Player): { status: string, value: boolean?, reason: string? }
	if not Config.features.communityVerification or Config.identity.communityId <= 0 then
		return { status = "disabled", value = false, reason = "Community ID is not configured" }
	end
	local success, verified = pcall(function()
		return player:IsInGroupAsync(Config.identity.communityId)
	end)
	if not success then
		return { status = "error", value = false, reason = "Roblox community lookup failed" }
	end
	return { status = "available", value = verified }
end

return Provider

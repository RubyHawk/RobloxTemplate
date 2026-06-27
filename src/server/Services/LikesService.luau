--!strict

local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local LikesService = {}
local lastKnown = Config.rewards.manualLikes
local updatedAt = 0

function LikesService.getLikes(): { status: string, value: number?, reason: string? }
	if os.time() - updatedAt < Config.rewards.likesRefreshSeconds then
		return { status = "available", value = lastKnown }
	end
	updatedAt = os.time()
	if Config.identity.universeId <= 0 or not HttpService.HttpEnabled then
		return { status = "disabled", value = lastKnown, reason = "Using the configured preview count" }
	end

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `https://games.roblox.com/v1/games/votes?universeIds={Config.identity.universeId}`,
			Method = "GET",
		})
	end)
	if success and response.Success then
		local decoded = HttpService:JSONDecode(response.Body)
		local first = decoded.data and decoded.data[1]
		if first and type(first.upVotes) == "number" then
			lastKnown = first.upVotes
			return { status = "available", value = lastKnown }
		end
	end
	return { status = "error", value = lastKnown, reason = "Showing the last known likes count" }
end

return LikesService

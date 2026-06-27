--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local FeedbackService = {}
local store = DataStoreService:GetDataStore(Config.feedbackStoreName)
local lastSubmittedAt: { [Player]: number } = {}
local allowedCategories = { Bug = true, Feedback = true, Accessibility = true, Other = true }

function FeedbackService.submit(player: Player, category: any, message: any): (boolean, string)
	if type(category) ~= "string" or not allowedCategories[category] then
		return false, "Choose a valid category"
	end
	if type(message) ~= "string" or #message < 3 or #message > Config.feedback.maxLength then
		return false, `Feedback must be 3-{Config.feedback.maxLength} characters`
	end
	local now = os.time()
	if now - (lastSubmittedAt[player] or 0) < Config.feedback.cooldownSeconds then
		return false, "Please wait before submitting again"
	end

	local filtered = ""
	local isMock = RunService:IsStudio() and not Config.studio.useLiveDataStore
	local filterSuccess = true
	if isMock then
		filtered = string.sub(message, 1, Config.feedback.maxLength)
	else
		filterSuccess = pcall(function()
			local result =
				TextService:FilterStringAsync(message, player.UserId, Enum.TextFilterContext.PrivateChat)
			filtered = result:GetNonChatStringForBroadcastAsync()
		end)
	end
	if not filterSuccess or filtered == "" then
		return false, "Feedback could not be filtered"
	end

	local record = {
		category = category,
		message = filtered,
		userId = player.UserId,
		placeId = game.PlaceId,
		jobId = game.JobId,
		templateVersion = Config.version,
		createdAt = now,
	}
	local success = true
	if isMock then
		print("[Template feedback mock]", record)
	else
		success = pcall(function()
			store:SetAsync(`report:{now}:{HttpService:GenerateGUID(false)}`, record)
		end)
	end
	if not success then
		return false, "Feedback storage is temporarily unavailable"
	end
	lastSubmittedAt[player] = now
	return true, "Thanks—your report was stored"
end

function FeedbackService.forget(player: Player)
	lastSubmittedAt[player] = nil
end

return FeedbackService

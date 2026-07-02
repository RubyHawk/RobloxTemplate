--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DataStoreKeys = require(Shared.DataStoreKeys)
local DataStoreRuntime = require(script.Parent.Parent.Util.DataStoreRuntime)
local ProfileService = require(script.Parent.ProfileService)

local FeedbackService = {}
local store: GlobalDataStore? = nil
local lastSubmittedAt: { [Player]: number } = {}
local allowedCategories = { Bug = true, Feedback = true, Accessibility = true, Other = true }

local function getStore(): GlobalDataStore
	local current = store
	if current == nil then
		current = DataStoreService:GetDataStore(Config.feedbackStoreName)
		store = current
	end
	return current
end

function FeedbackService.submit(player: Player, category: any, message: any): (boolean, string)
	if type(category) ~= "string" or not allowedCategories[category] then
		return false, "Choose a valid category"
	end
	if
		type(message) ~= "string"
		or #message < 3
		or #message > Config.feedback.maxLength
		or string.find(message, "%S") == nil
	then
		return false, `Feedback must be 3-{Config.feedback.maxLength} characters`
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Your data is not ready yet"
	end
	local now = os.time()
	local mostRecent = math.max(lastSubmittedAt[player] or 0, profile.feedback.lastSubmittedAt)
	if now - mostRecent < Config.feedback.cooldownSeconds then
		return false, "Please wait before submitting again"
	end

	local filtered = ""
	local isMock = DataStoreRuntime.isMock()
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
	local failure: any = nil
	if isMock then
		print("[Template feedback mock]", record)
	else
		success, failure = pcall(function()
			getStore():SetAsync(
				DataStoreKeys.feedback(player.UserId, now, HttpService:GenerateGUID(false)),
				record
			)
		end)
	end
	if not success then
		DataStoreRuntime.failure("Feedback", "store report", failure)
		return false, "Feedback storage is temporarily unavailable"
	end
	lastSubmittedAt[player] = now
	profile.feedback.lastSubmittedAt = now
	ProfileService.markDirty(player, "feedback:cooldown")
	if not isMock then
		ProfileService.save(player)
	end
	return true, "Thanks—your report was stored"
end

function FeedbackService.forget(player: Player)
	lastSubmittedAt[player] = nil
end

return FeedbackService

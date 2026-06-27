--!strict

local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local ProfileService = require(script.Parent.ProfileService)

local NotificationService = {}

local function request(path: string, body: any): boolean
	if Config.notifications.workerUrl == "" or not HttpService.HttpEnabled then
		return false
	end
	local success = pcall(function()
		local secret = HttpService:GetSecret("NotificationWorkerSecret")
		local headers: any = { Authorization = secret:AddPrefix("Bearer ") }
		local response = HttpService:RequestAsync({
			Url = Config.notifications.workerUrl .. path,
			Method = "POST",
			Headers = headers,
			Body = HttpService:JSONEncode(body),
		})
		if not response.Success then
			error(`Worker returned {response.StatusCode}`)
		end
	end)
	return success
end

function NotificationService.scheduleOnLeave(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil or not profile.settings.notifications then
		return
	end
	local now = os.time()
	local nextDay = (math.floor(now / 86400) + 1) * 86400 + 9 * 3600
	if Config.notifications.dailyMessageId ~= "" then
		request("/v1/jobs", {
			userId = player.UserId,
			kind = "daily",
			dueAt = nextDay,
			messageId = Config.notifications.dailyMessageId,
			launchData = "daily",
		})
	end
	if Config.notifications.offlineMessageId ~= "" then
		request("/v1/jobs", {
			userId = player.UserId,
			kind = "offline",
			dueAt = now + Config.economy.freeOfflineCapHours * 3600,
			messageId = Config.notifications.offlineMessageId,
			launchData = "offline",
		})
	end
end

function NotificationService.cancel(player: Player)
	request("/v1/cancel", { userId = player.UserId })
end

return NotificationService

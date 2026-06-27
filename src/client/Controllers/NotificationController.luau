--!strict

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local NotificationController = {}

function NotificationController.prompt(): (boolean, string)
	local success, canPrompt = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if not success then
		return false, "Notification eligibility could not be checked"
	end
	if not canPrompt then
		return false, "Roblox notifications are already configured or unavailable for this account"
	end
	local promptSuccess = pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
	return promptSuccess,
		if promptSuccess then "Roblox opened the notification prompt" else "Notification prompt failed"
end

return NotificationController

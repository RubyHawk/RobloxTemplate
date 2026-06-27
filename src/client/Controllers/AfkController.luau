--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Config = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").TemplateConfig
)

local AfkController = {}
local enabled = true
local countdownToken = 0

function AfkController.setEnabled(value: boolean)
	enabled = value
	if not enabled then
		countdownToken += 1
	end
end

function AfkController.initialize(requestRollOver: () -> (), notify: (string) -> ())
	UserInputService.InputBegan:Connect(function()
		countdownToken += 1
	end)

	Players.LocalPlayer.Idled:Connect(function(idleSeconds)
		if not enabled or idleSeconds < Config.afK.warnAfterIdleSeconds then
			return
		end
		countdownToken += 1
		local token = countdownToken
		notify(`AFK: moving to a fresh server in {Config.afK.countdownSeconds}s. Press any input to cancel.`)
		task.delay(Config.afK.countdownSeconds, function()
			if enabled and token == countdownToken then
				requestRollOver()
			end
		end)
	end)
end

return AfkController

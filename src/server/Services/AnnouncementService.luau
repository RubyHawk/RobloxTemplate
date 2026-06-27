--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local AnnouncementService = {}

function AnnouncementService.start(broadcast: (string) -> ())
	task.spawn(function()
		local index = 0
		while true do
			task.wait(Config.announcements.intervalSeconds)
			index = (index % #Config.announcements.messages) + 1
			broadcast(Config.announcements.messages[index])
		end
	end)
end

return AnnouncementService

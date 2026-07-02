--!strict

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local DataStoreRuntime = {}

export type Mode = "mock" | "live"

local announced = false

function DataStoreRuntime.mode(): Mode
	if RunService:IsStudio() and Config.studio.dataStoreMode == "mock" then
		return "mock"
	end
	return "live"
end

function DataStoreRuntime.isMock(): boolean
	return DataStoreRuntime.mode() == "mock"
end

function DataStoreRuntime.failure(area: string, operation: string, detail: any)
	local message = tostring(detail)
	local hint = ""
	if RunService:IsStudio() and DataStoreRuntime.mode() == "live" then
		if game.GameId == 0 then
			hint = " Publish this place before testing persistent data."
		elseif
			string.find(message, "StudioAccessToApisNotAllowed", 1, true)
			or string.find(message, "403", 1, true)
		then
			hint = " Enable File > Experience Settings > Security > Studio Access to API Services."
		end
	end
	warn(`[Template Data][{area}] {operation} failed: {message}.{hint}`)
end

function DataStoreRuntime.announce(container: Instance?)
	if announced then
		return
	end
	announced = true
	local mode = DataStoreRuntime.mode()
	if container then
		container:SetAttribute("DataStoreMode", mode)
		container:SetAttribute("DataStoreUniverseId", game.GameId)
		container:SetAttribute("ProfileStoreName", Config.profileStoreName)
		container:SetAttribute("ProfileKeyFormat", "player:<UserId>")
	end
	if mode == "mock" then
		warn(
			"[Template Data] MOCK mode: this Studio showroom keeps data in memory only. "
				.. "DataDelve will not show play-test changes."
		)
	elseif RunService:IsStudio() then
		if game.GameId == 0 then
			warn(
				"[Template Data] LIVE mode selected, but this file is unpublished. "
					.. "Publish it, enable Studio Access to API Services, then reopen it."
			)
		else
			print(
				`[Template Data] LIVE Studio mode for universe {game.GameId}; profile store "{Config.profileStoreName}".`
			)
		end
	else
		print(
			`[Template Data] LIVE server mode for universe {game.GameId}; profile store "{Config.profileStoreName}".`
		)
	end
end

return DataStoreRuntime

--!strict

local Config = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").TemplateConfig
)

local Provider = {}

function Provider.getRate(_player: Player): number
	return Config.economy.baseOfflineRatePerSecond
end

return Provider

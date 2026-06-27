--!strict

local Theme =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").Theme)

local UIStyles = {}

function UIStyles.install(screenGui: ScreenGui)
	local sheet = Instance.new("StyleSheet")
	sheet.Name = "TemplateTokens"
	for name, value in Theme.colors do
		sheet:SetAttribute(name, value)
	end
	sheet:SetAttribute("TouchTarget", Theme.touchTarget)
	sheet.Parent = screenGui

	local link = Instance.new("StyleLink")
	link.StyleSheet = sheet
	link.Parent = screenGui
end

return UIStyles

--!strict

local Theme = {
	colors = {
		background = Color3.fromRGB(241, 248, 255),
		surface = Color3.fromRGB(255, 255, 255),
		surfaceRaised = Color3.fromRGB(225, 239, 255),
		primary = Color3.fromRGB(59, 130, 246),
		secondary = Color3.fromRGB(137, 80, 237),
		accent = Color3.fromRGB(255, 203, 58),
		success = Color3.fromRGB(32, 193, 114),
		danger = Color3.fromRGB(255, 76, 91),
		text = Color3.fromRGB(20, 37, 69),
		textMuted = Color3.fromRGB(89, 110, 145),
		stroke = Color3.fromRGB(105, 160, 255),
	},
	radius = {
		small = UDim.new(0, 8),
		medium = UDim.new(0, 16),
		large = UDim.new(0, 22),
	},
	spacing = {
		xs = 4,
		sm = 8,
		md = 12,
		lg = 20,
		xl = 28,
	},
	touchTarget = 44,
	font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	fontBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}

return table.freeze(Theme)

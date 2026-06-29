--!strict

local Theme = {
	colors = {
		background = Color3.fromRGB(245, 249, 255),
		surface = Color3.fromRGB(255, 255, 255),
		surfaceRaised = Color3.fromRGB(232, 241, 255),
		primary = Color3.fromRGB(52, 120, 246),
		primaryHover = Color3.fromRGB(35, 95, 218),
		secondary = Color3.fromRGB(91, 77, 222),
		accent = Color3.fromRGB(255, 196, 46),
		success = Color3.fromRGB(38, 190, 112),
		danger = Color3.fromRGB(246, 73, 86),
		text = Color3.fromRGB(22, 39, 73),
		textMuted = Color3.fromRGB(91, 111, 145),
		stroke = Color3.fromRGB(31, 61, 112),
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

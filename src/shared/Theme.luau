--!strict

local Theme = {
	colors = {
		background = Color3.fromRGB(22, 25, 42),
		surface = Color3.fromRGB(41, 45, 73),
		surfaceRaised = Color3.fromRGB(55, 61, 96),
		primary = Color3.fromRGB(80, 135, 255),
		secondary = Color3.fromRGB(181, 91, 255),
		accent = Color3.fromRGB(255, 201, 64),
		success = Color3.fromRGB(63, 220, 142),
		danger = Color3.fromRGB(255, 91, 112),
		text = Color3.fromRGB(248, 249, 255),
		textMuted = Color3.fromRGB(180, 187, 218),
		stroke = Color3.fromRGB(112, 126, 184),
	},
	radius = {
		small = UDim.new(0, 8),
		medium = UDim.new(0, 14),
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

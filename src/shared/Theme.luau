--!strict

local Theme = {
	colors = {
		background = Color3.fromRGB(250, 246, 255),
		surface = Color3.fromRGB(255, 255, 255),
		surfaceRaised = Color3.fromRGB(243, 232, 255),
		primary = Color3.fromRGB(124, 58, 237),
		primaryHover = Color3.fromRGB(101, 40, 196),
		secondary = Color3.fromRGB(63, 185, 255),
		accent = Color3.fromRGB(255, 196, 46),
		success = Color3.fromRGB(20, 206, 151),
		danger = Color3.fromRGB(255, 65, 121),
		text = Color3.fromRGB(28, 17, 51),
		textMuted = Color3.fromRGB(104, 86, 135),
		stroke = Color3.fromRGB(55, 31, 92),
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
	font = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold),
	fontBold = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular),
}

return table.freeze(Theme)

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
	font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	fontBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),

	-- Per-pack partial overrides, deep-merged over the base tokens above by
	-- ThemeProvider.resolve(themeId). Only list the tokens that differ; anything
	-- omitted inherits the base. Keys here match PackDescriptor.themeId.
	packs = {
		incremental = {
			colors = {
				primary = Color3.fromRGB(124, 58, 237),
				accent = Color3.fromRGB(255, 196, 46),
			},
		},
		combat = {
			colors = {
				background = Color3.fromRGB(18, 20, 28),
				surface = Color3.fromRGB(30, 33, 44),
				surfaceRaised = Color3.fromRGB(44, 48, 63),
				primary = Color3.fromRGB(255, 65, 121),
				primaryHover = Color3.fromRGB(214, 44, 94),
				secondary = Color3.fromRGB(63, 185, 255),
				accent = Color3.fromRGB(255, 196, 46),
				success = Color3.fromRGB(20, 206, 151),
				danger = Color3.fromRGB(255, 71, 87),
				text = Color3.fromRGB(238, 240, 247),
				textMuted = Color3.fromRGB(150, 156, 173),
				stroke = Color3.fromRGB(12, 13, 18),
			},
		},
	},
}

return table.freeze(Theme)

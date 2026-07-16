--!strict

export type Palette = {
	background: Color3,
	panel: Color3,
	surface: Color3,
	field: Color3,
	hover: Color3,
	border: Color3,
	borderStrong: Color3,
	text: Color3,
	muted: Color3,
	accent: Color3,
	accentMuted: Color3,
	allowed: Color3,
	traversal: Color3,
	success: Color3,
	warning: Color3,
	danger: Color3,
	ground: Color3,
	void: Color3,
	blocked: Color3,
	spawn: Color3,
	goal: Color3,
	auto: Color3,
	route: Color3,
}

export type Metrics = {
	headerHeight: number,
	flowViewBarHeight: number,
	flowActionBarHeight: number,
	controlHeight: number,
	cornerRadius: number,
	panelGap: number,
}

local Theme = {
	colors = table.freeze({
		background = Color3.fromRGB(8, 12, 18),
		panel = Color3.fromRGB(13, 18, 25),
		surface = Color3.fromRGB(16, 22, 30),
		field = Color3.fromRGB(20, 27, 36),
		hover = Color3.fromRGB(27, 37, 49),
		border = Color3.fromRGB(35, 45, 59),
		borderStrong = Color3.fromRGB(52, 67, 87),
		text = Color3.fromRGB(229, 234, 242),
		muted = Color3.fromRGB(137, 149, 168),
		accent = Color3.fromRGB(0, 157, 255),
		accentMuted = Color3.fromRGB(3, 52, 83),
		allowed = Color3.fromRGB(91, 76, 157),
		traversal = Color3.fromRGB(47, 105, 84),
		success = Color3.fromRGB(87, 196, 128),
		warning = Color3.fromRGB(238, 181, 72),
		danger = Color3.fromRGB(239, 103, 112),
		ground = Color3.fromRGB(75, 132, 91),
		void = Color3.fromRGB(28, 30, 35),
		blocked = Color3.fromRGB(157, 76, 76),
		spawn = Color3.fromRGB(116, 96, 181),
		goal = Color3.fromRGB(195, 123, 65),
		auto = Color3.fromRGB(60, 145, 166),
		route = Color3.fromRGB(73, 207, 230),
	} :: Palette),
	metrics = table.freeze({
		headerHeight = 52,
		flowViewBarHeight = 52,
		flowActionBarHeight = 56,
		controlHeight = 34,
		cornerRadius = 6,
		panelGap = 8,
	} :: Metrics),
}

return table.freeze(Theme)

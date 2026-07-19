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
	headerControlHeight: number,
	headerControlGap: number,
	headerOuterPadding: number,
	iconInset: number,
	iconButtonTextPaddingLeft: number,
	iconButtonTextPaddingRight: number,
	flowViewBarHeight: number,
	flowActionBarHeight: number,
	controlHeight: number,
	cornerRadius: number,
	panelGap: number,
}

export type HeaderDensity = "compact" | "medium" | "wide"

export type HeaderLayout = {
	density: HeaderDensity,
	modeTextSize: number,
	navWidth: number,
	stageX: number,
	stageWidth: number,
	historyWidth: number,
	menuWidth: number,
	validationWidth: number,
	showTitle: boolean,
	showHistoryLabels: boolean,
	showMenuLabel: boolean,
	showValidationLabel: boolean,
}

local COMPACT_HEADER: HeaderLayout = table.freeze({
	density = "compact",
	modeTextSize = 12,
	navWidth = 340,
	stageX = 42,
	stageWidth = 150,
	historyWidth = 30,
	menuWidth = 32,
	validationWidth = 34,
	showTitle = false,
	showHistoryLabels = false,
	showMenuLabel = false,
	showValidationLabel = false,
})

local MEDIUM_HEADER: HeaderLayout = table.freeze({
	density = "medium",
	modeTextSize = 13,
	navWidth = 400,
	stageX = 44,
	stageWidth = 180,
	historyWidth = 36,
	menuWidth = 76,
	validationWidth = 188,
	showTitle = false,
	showHistoryLabels = false,
	showMenuLabel = true,
	showValidationLabel = true,
})

local WIDE_HEADER: HeaderLayout = table.freeze({
	density = "wide",
	modeTextSize = 14,
	navWidth = 436,
	stageX = 158,
	stageWidth = 208,
	historyWidth = 74,
	menuWidth = 76,
	validationWidth = 188,
	showTitle = true,
	showHistoryLabels = true,
	showMenuLabel = true,
	showValidationLabel = true,
})

local function resolveHeaderLayout(width: number): HeaderLayout
	if width >= 1_500 then
		return WIDE_HEADER
	elseif width >= 1_050 then
		return MEDIUM_HEADER
	end
	return COMPACT_HEADER
end

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
		headerHeight = 44,
		headerControlHeight = 34,
		headerControlGap = 6,
		headerOuterPadding = 8,
		iconInset = 10,
		iconButtonTextPaddingLeft = 33,
		iconButtonTextPaddingRight = 7,
		flowViewBarHeight = 44,
		flowActionBarHeight = 44,
		controlHeight = 34,
		cornerRadius = 6,
		panelGap = 8,
	} :: Metrics),
	resolveHeaderLayout = resolveHeaderLayout,
}

return table.freeze(Theme)

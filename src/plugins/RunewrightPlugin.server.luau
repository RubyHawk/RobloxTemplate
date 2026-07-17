--!strict

-- Runewright: private Studio workbench for the rune altar. Every adjustable
-- rune field lives here — altar pacing, pity, channel modes with momentum
-- tiers and unlock gates, copy milestones, rarity weights and colors, and the
-- rune cards themselves (names, glyphs, bonuses, flavor).
--
-- The panel is five tabs (Altar / Modes / Rarity / Runes / Review) over a
-- persistent action footer, drawn as flat form rows and tables rather than
-- nested boxes:
-- - Sections are hairline-ruled headers, labels sit beside compact inputs
--   instead of inside chunky cells, and repeating data (momentum tiers, copy
--   milestones, rarities) renders as real tables with column headers.
-- - Validation reruns after every edit. The footer says whether Apply is
--   ready, each tab badges its own issue count, and the Review tab lists
--   every problem with the tab it lives on.
-- - Fixed choices (mode kind, unlock gates, rarity pickers) are visible pill
--   pickers; rune cards use a rarity-tinted picker row and a colored edge.
-- - Scalar fields show their accepted range and refuse out-of-range input at
--   entry with the range in the message.
-- - Disabled mode cards collapse to their header row; unlock thresholds only
--   appear for gates that use one.
-- - Destructive actions (Remove Card, footer Reload) need a second confirming
--   click, and Reload from Place re-reads the open place at any time, so the
--   panel no longer goes stale when the plugin loads before the place does.
--
-- Apply writes the open place's DesignerConfig and RuneCatalog ModuleScripts
-- (undo-safe) so a playtest picks the values up immediately; Print emits the
-- same sources to the Output window for pasting back into the repo. Nothing
-- publishes.
--
-- Compliance note: rarity weights are integer parts-per-ten-thousand and must
-- sum to exactly 10000 so disclosed odds always total 100%
-- (docs/internal/2026-07-12-rune-channel-modes.md). Apply refuses invalid
-- data instead of writing it.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PLUGIN_NAME = "Runewright"
local PLUGIN_SUBTITLE = "Rune altar workbench"
local PLUGIN_BUTTON_ID = "RunewrightEditor"
local PLUGIN_WIDGET_ID = "RunewrightPanel"
local PLUGIN_ICON = "rbxasset://textures/StudioSharedUI/grid@2x.png"

-- Palette mirrors the studio's shared Stagewright theme (src/plugins/Stagewright/
-- UI/Theme.luau) so both Studio tools read as one product. The old palette packed
-- every surface into a flat 13-unit near-black band with the input field the
-- DARKEST layer of all, so fields read as holes punched in the panel. This is a
-- real elevation ramp — ground < chrome < button < field < hover, each rung a
-- touch bluer and lighter — and the field now sits ABOVE the body, so inputs read
-- as raised, editable controls. The accent is Stagewright's confident blue, not a
-- muted steel; filled-accent surfaces carry dark ink for contrast.
local PANEL_BG = Color3.fromRGB(12, 16, 23) -- root body (ground)
local SURFACE = Color3.fromRGB(16, 22, 30) -- raised cards / chrome (surface)
local PANEL_HEADER = Color3.fromRGB(16, 22, 30) -- tab bar / header chrome
local PANEL_STATUS = Color3.fromRGB(10, 14, 20) -- footer, seated below the body
local PANEL_FIELD = Color3.fromRGB(22, 29, 39) -- inputs, lifted above the body
local FIELD_HOVER = Color3.fromRGB(28, 38, 50) -- input/hover lift
local BUTTON_BG = Color3.fromRGB(18, 24, 33)
local BUTTON_ACTIVE = Color3.fromRGB(0, 157, 255) -- vivid accent (was muted steel)
local BUTTON_ACTIVE_HOVER = Color3.fromRGB(70, 182, 255)
local BUTTON_HOVER = Color3.fromRGB(28, 38, 50)
local ON_ACCENT = Color3.fromRGB(6, 20, 33) -- dark ink for text on a filled accent
local TRACK_ON = Color3.fromRGB(3, 82, 132) -- toggle "on" track, accent-tinted
local KNOB_OFF = Color3.fromRGB(120, 132, 150)
local KNOB_ON = Color3.fromRGB(235, 242, 250)
local BORDER = Color3.fromRGB(35, 45, 59)
local BORDER_STRONG = Color3.fromRGB(52, 67, 87)
local TEXT = Color3.fromRGB(229, 234, 242)
local TEXT_ACTIVE = Color3.fromRGB(245, 248, 252)
local MUTED = Color3.fromRGB(143, 155, 173)
local SUBTLE = Color3.fromRGB(110, 122, 140) -- brighter so 10px hints stay legible
local HEADING = Color3.fromRGB(150, 162, 180)
local AMBER = Color3.fromRGB(238, 181, 72) -- warning
local GOOD = Color3.fromRGB(87, 196, 128) -- success
local BAD = Color3.fromRGB(239, 103, 112) -- danger

local MODE_KINDS = { "luck", "surge" }
local UNLOCK_KINDS = { "always", "totalRolls", "runesOwned", "provider" }
local MAX_MODES = 4
-- Row counts match RuneModeConfig.MAX_TIERS / MAX_MILESTONES so the workbench
-- can hold everything the runtime accepts and never truncates authored
-- entries on load (the old 4/5-row panel silently dropped extras on Apply).
local TIER_ROWS = 8
local MILESTONE_ROWS = 8

-- Tab names double as the section tag on validation issues, so every problem
-- can point at the tab it is fixed on.
local TAB_ALTAR = "Altar"
local TAB_MODES = "Modes"
local TAB_RARITY = "Rarity"
local TAB_RUNES = "Runes"
local TAB_REVIEW = "Review"
local TAB_DEFS = { TAB_ALTAR, TAB_MODES, TAB_RARITY, TAB_RUNES, TAB_REVIEW }

type TierRow = { atSeconds: number?, value: number? }
type ModeRow = {
	enabled: boolean,
	id: string,
	name: string,
	kind: string,
	unlockKind: string,
	unlockValue: number,
	tiers: { TierRow },
}
type MilestoneRow = { copies: number?, multiplier: number? }
type RarityRow = { id: string, name: string, weight: number, color: { number } }
type RuneRow = {
	id: string,
	name: string,
	rarityId: string,
	glyph: string,
	bonusPercent: number,
	flavor: string,
}
type Issue = { tab: string, message: string }
type PillOption = { value: string, text: string, dotColor: Color3? }

-- Numeric altar tunables. Ranges mirror TemplateConfig's runeNumber clamps so
-- whatever Runewright writes is exactly what the runtime accepts.
type ScalarSpec = { key: string, label: string, min: number, max: number, integer: boolean }
local PACING_SPECS: { ScalarSpec } = {
	{ key = "baseCost", label = "Base Cost", min = 1, max = 1e9, integer = true },
	{ key = "costGrowth", label = "Cost Growth", min = 1, max = 10, integer = false },
	{ key = "maxCost", label = "Max Cost", min = 1, max = 1e12, integer = true },
	{ key = "autoRollSeconds", label = "Roll Every (s)", min = 0.5, max = 60, integer = false },
	{ key = "firstRollChargeSeconds", label = "First Charge (s)", min = 0, max = 30, integer = false },
	{ key = "tickSeconds", label = "Server Tick (s)", min = 0.05, max = 2, integer = false },
}
local LIMIT_SPECS: { ScalarSpec } = {
	{ key = "circlePadding", label = "Circle Padding", min = 0, max = 50, integer = false },
	{ key = "circleHeightTolerance", label = "Height Tolerance", min = 1, max = 50, integer = false },
	{ key = "maxTotalBonusPercent", label = "Max Total Bonus %", min = 100, max = 1e9, integer = true },
	{ key = "maxOwnedPerRune", label = "Max Owned / Rune", min = 1000, max = 1e12, integer = true },
	{ key = "maxTotalRolls", label = "Max Total Rolls", min = 1000, max = 1e12, integer = true },
	{ key = "revealSeconds", label = "Reveal Card (s)", min = 0.5, max = 30, integer = false },
}
local PITY_SPECS: { ScalarSpec } = {
	{ key = "pityThreshold", label = "Pity Threshold", min = 0, max = 1000, integer = true },
	{ key = "minCommonWeight", label = "Luck Common Floor", min = 0, max = 9999, integer = true },
}

local State = {
	loaded = false,
	problem = nil :: string?,
	scalars = {} :: { [string]: number },
	pityMinimumRarity = "epic",
	rareAudioMinimumRarity = "epic",
	defaultChannelMode = "luck",
	modes = {} :: { ModeRow },
	milestones = {} :: { MilestoneRow },
	rarities = {} :: { RarityRow },
	runes = {} :: { RuneRow },
}

-- UI refresh hooks registered while the panel builds, so data edits can
-- repaint the derived readouts (issue list and badges, odds preview, default
-- mode pills, rune list, status line).
local Refresh = {
	validation = nil :: (() -> ())?,
	odds = nil :: (() -> ())?,
	runesList = nil :: (() -> ())?,
	defaultMode = nil :: (() -> ())?,
	status = nil :: ((message: string, color: Color3?) -> ())?,
}

local function setStatus(message: string, color: Color3?)
	local apply = Refresh.status
	if apply ~= nil then
		apply(message, color)
	end
end

-- Recheck everything and repaint the footer readiness line, the tab badges,
-- and the Review issue list. Called after every state edit.
local function touch()
	local repaint = Refresh.validation
	if repaint ~= nil then
		repaint()
	end
end

local function sharedFolder(): Instance?
	local template = ReplicatedStorage:FindFirstChild("Template")
	if template == nil then
		return nil
	end
	return template:FindFirstChild("Shared")
end

local function sharedModule(name: string): ModuleScript?
	local shared = sharedFolder()
	local child = if shared ~= nil then shared:FindFirstChild(name) else nil
	if child ~= nil and child:IsA("ModuleScript") then
		return child
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Loading the current values out of the open place
-- ---------------------------------------------------------------------------

local Load = {}

function Load.tiers(rawTiers: any): { TierRow }
	local tiers: { TierRow } = {}
	for index = 1, TIER_ROWS do
		local raw = if type(rawTiers) == "table" then rawTiers[index] else nil
		if type(raw) == "table" and type(raw.atSeconds) == "number" and type(raw.value) == "number" then
			tiers[index] = { atSeconds = raw.atSeconds, value = raw.value }
		else
			tiers[index] = { atSeconds = nil, value = nil }
		end
	end
	return tiers
end

function Load.modes(rawModes: any)
	State.modes = {}
	for index = 1, MAX_MODES do
		local raw = if type(rawModes) == "table" then rawModes[index] else nil
		if type(raw) == "table" then
			local unlock = if type(raw.unlock) == "table" then raw.unlock else {}
			State.modes[index] = {
				enabled = true,
				id = tostring(raw.id),
				name = tostring(raw.name),
				kind = tostring(raw.kind),
				unlockKind = if type(unlock.kind) == "string" then unlock.kind else "always",
				unlockValue = if type(unlock.value) == "number" then unlock.value else 0,
				tiers = Load.tiers(raw.tiers),
			}
		else
			State.modes[index] = {
				enabled = false,
				id = "",
				name = "",
				kind = "luck",
				unlockKind = "always",
				unlockValue = 0,
				tiers = Load.tiers(nil),
			}
		end
	end
end

function Load.milestones(rawMilestones: any)
	State.milestones = {}
	for index = 1, MILESTONE_ROWS do
		local raw = if type(rawMilestones) == "table" then rawMilestones[index] else nil
		if type(raw) == "table" and type(raw.copies) == "number" and type(raw.multiplier) == "number" then
			State.milestones[index] = { copies = raw.copies, multiplier = raw.multiplier }
		else
			State.milestones[index] = { copies = nil, multiplier = nil }
		end
	end
end

function Load.fromPlace(): (boolean, string?)
	State.loaded = false
	local configModule = sharedModule("TemplateConfig")
	local catalogModule = sharedModule("RuneCatalog")
	if configModule == nil or catalogModule == nil then
		State.problem = "Open a place built from bootstrap.project.json, then click Reload from Place."
		return false, State.problem
	end
	local okConfig, config = pcall(require, configModule)
	local okCatalog, catalog = pcall(require, catalogModule)
	if not okConfig or type(config) ~= "table" or type(config.runes) ~= "table" then
		State.problem = "TemplateConfig could not be read; rebuild the place, then Reload from Place."
		return false, State.problem
	end
	if not okCatalog or type(catalog) ~= "table" or type(catalog.rarities) ~= "table" then
		State.problem = "RuneCatalog could not be read; rebuild the place, then Reload from Place."
		return false, State.problem
	end

	local runes = config.runes
	for _, group in { PACING_SPECS, LIMIT_SPECS, PITY_SPECS } do
		for _, spec in group do
			local value = runes[spec.key]
			State.scalars[spec.key] = if type(value) == "number" then value else spec.min
		end
	end
	State.pityMinimumRarity = tostring(runes.pityMinimumRarity)
	State.rareAudioMinimumRarity = tostring(runes.rareAudioMinimumRarity)
	State.defaultChannelMode = tostring(runes.defaultChannelMode)
	Load.modes(runes.channelModes)
	Load.milestones(runes.copyMilestones)

	State.rarities = {}
	for _, rarity in catalog.rarities do
		table.insert(State.rarities, {
			id = rarity.id,
			name = rarity.name,
			weight = rarity.weight,
			color = { rarity.color[1] or 255, rarity.color[2] or 255, rarity.color[3] or 255 },
		})
	end
	State.runes = {}
	for _, rune in catalog.runes do
		table.insert(State.runes, {
			id = rune.id,
			name = rune.name,
			rarityId = rune.rarityId,
			glyph = rune.glyph,
			bonusPercent = rune.bonusPercent,
			flavor = rune.flavor,
		})
	end
	State.loaded = true
	State.problem = nil
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Validation (mirrors RuneModeConfig + the Lune spec invariants). Every issue
-- carries the tab it is fixed on so the panel can badge tabs and build the
-- Review list.
-- ---------------------------------------------------------------------------

local Val = {}

function Val.isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Val.validId(value: string): boolean
	return #value >= 1 and #value <= 24 and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
end

function Val.rarityExists(rarityId: string): boolean
	for _, rarity in State.rarities do
		if rarity.id == rarityId then
			return true
		end
	end
	return false
end

function Val.weightTotal(): number
	local total = 0
	for _, rarity in State.rarities do
		total += rarity.weight
	end
	return total
end

function Val.filledTiers(mode: ModeRow): { { atSeconds: number, value: number } }
	local tiers = {}
	for _, tier in mode.tiers do
		if tier.atSeconds ~= nil and tier.value ~= nil then
			table.insert(tiers, { atSeconds = tier.atSeconds :: number, value = tier.value :: number })
		end
	end
	return tiers
end

function Val.filledMilestones(): { { copies: number, multiplier: number } }
	local milestones = {}
	for _, row in State.milestones do
		if row.copies ~= nil and row.multiplier ~= nil then
			table.insert(milestones, { copies = row.copies :: number, multiplier = row.multiplier :: number })
		end
	end
	return milestones
end

function Val.enabledModes(): { ModeRow }
	local modes = {}
	for _, mode in State.modes do
		if mode.enabled then
			table.insert(modes, mode)
		end
	end
	return modes
end

function Val.all(): { Issue }
	local problems: { Issue } = {}
	local function fail(tab: string, message: string)
		table.insert(problems, { tab = tab, message = message })
	end

	for _, group in { PACING_SPECS, LIMIT_SPECS, PITY_SPECS } do
		for _, spec in group do
			local value = State.scalars[spec.key]
			if not Val.isFinite(value) or value < spec.min or value > spec.max then
				fail(TAB_ALTAR, `{spec.label} must be between {spec.min} and {spec.max}`)
			elseif spec.integer and math.floor(value) ~= value then
				fail(TAB_ALTAR, `{spec.label} must be a whole number`)
			end
		end
	end
	if not Val.rarityExists(State.pityMinimumRarity) then
		fail(TAB_ALTAR, "Pity minimum rarity must be one of the configured rarities")
	end
	if not Val.rarityExists(State.rareAudioMinimumRarity) then
		fail(TAB_ALTAR, "Rare-audio rarity must be one of the configured rarities")
	end

	local modes = Val.enabledModes()
	if #modes == 0 then
		fail(TAB_MODES, "Enable at least one channel mode")
	end
	local usedModeIds: { [string]: boolean } = {}
	local defaultFound = false
	for _, mode in modes do
		local label = if #mode.id > 0 then mode.id else "(unnamed mode)"
		if not Val.validId(mode.id) then
			fail(TAB_MODES, `Mode id "{mode.id}" must be lowercase letters/digits/underscores`)
		elseif usedModeIds[mode.id] then
			fail(TAB_MODES, `Mode id "{mode.id}" is duplicated`)
		end
		usedModeIds[mode.id] = true
		if #mode.name < 1 or #mode.name > 32 then
			fail(TAB_MODES, `Mode {label} needs a name (1-32 characters)`)
		end
		if not table.find(MODE_KINDS, mode.kind) then
			fail(TAB_MODES, `Mode {label} has an unknown kind`)
		end
		if not table.find(UNLOCK_KINDS, mode.unlockKind) then
			fail(TAB_MODES, `Mode {label} has an unknown unlock kind`)
		end
		if
			(mode.unlockKind == "totalRolls" or mode.unlockKind == "runesOwned")
			and (not Val.isFinite(mode.unlockValue) or mode.unlockValue < 0)
		then
			fail(TAB_MODES, `Mode {label} unlock threshold must be 0 or more`)
		end
		local tiers = Val.filledTiers(mode)
		if #tiers == 0 then
			fail(TAB_MODES, `Mode {label} needs at least one momentum tier`)
		end
		local previousAt = 0
		for _, tier in tiers do
			if tier.atSeconds <= previousAt then
				fail(TAB_MODES, `Mode {label} tier times must strictly rise`)
				break
			end
			if tier.value < 1 or tier.value > 1000 then
				fail(TAB_MODES, `Mode {label} tier values must be between 1 and 1000`)
				break
			end
			previousAt = tier.atSeconds
		end
		if mode.id == State.defaultChannelMode then
			defaultFound = true
		end
	end
	if not defaultFound then
		fail(TAB_MODES, `Default mode "{State.defaultChannelMode}" must match an enabled mode id`)
	end

	local previousCopies = 1
	local previousMultiplier = 1
	for _, milestone in Val.filledMilestones() do
		if math.floor(milestone.copies) ~= milestone.copies or milestone.copies <= previousCopies then
			fail(TAB_RUNES, "Milestone copies must be whole numbers that strictly rise (2+)")
			break
		end
		if milestone.multiplier < previousMultiplier or milestone.multiplier > 1000 then
			fail(TAB_RUNES, "Milestone multipliers must never weaken (1+)")
			break
		end
		previousCopies = milestone.copies
		previousMultiplier = milestone.multiplier
	end

	local total = Val.weightTotal()
	if total ~= 10000 then
		fail(TAB_RARITY, `Rarity weights sum to {total}; they must equal exactly 10000`)
	end
	for _, rarity in State.rarities do
		if #rarity.name < 1 or #rarity.name > 24 then
			fail(TAB_RARITY, `Rarity {rarity.id} needs a name (1-24 characters)`)
		end
		if
			not Val.isFinite(rarity.weight)
			or rarity.weight < 1
			or math.floor(rarity.weight) ~= rarity.weight
		then
			fail(TAB_RARITY, `Rarity {rarity.id} weight must be a positive whole number`)
		end
		for _, channel in rarity.color do
			if
				not Val.isFinite(channel)
				or channel < 0
				or channel > 255
				or math.floor(channel) ~= channel
			then
				fail(TAB_RARITY, `Rarity {rarity.id} color channels must be whole numbers 0-255`)
				break
			end
		end
	end

	if #State.runes == 0 then
		fail(TAB_RUNES, "Add at least one rune")
	end
	local usedRuneIds: { [string]: boolean } = {}
	local runesPerRarity: { [string]: number } = {}
	for _, rune in State.runes do
		local label = if #rune.id > 0 then rune.id else "(unnamed rune)"
		if not Val.validId(rune.id) then
			fail(TAB_RUNES, `Rune id "{rune.id}" must be lowercase letters/digits/underscores`)
		elseif usedRuneIds[rune.id] then
			fail(TAB_RUNES, `Rune id "{rune.id}" is duplicated`)
		end
		usedRuneIds[rune.id] = true
		if #rune.name < 1 or #rune.name > 40 then
			fail(TAB_RUNES, `Rune {label} needs a name (1-40 characters)`)
		end
		if #rune.glyph < 1 or #rune.glyph > 16 then
			fail(TAB_RUNES, `Rune {label} needs a glyph (an emoji or a Roblox image asset id)`)
		end
		if not Val.isFinite(rune.bonusPercent) or rune.bonusPercent <= 0 then
			fail(TAB_RUNES, `Rune {label} bonus must be a positive percent`)
		end
		if #rune.flavor > 120 then
			fail(TAB_RUNES, `Rune {label} flavor text is limited to 120 characters`)
		end
		if not Val.rarityExists(rune.rarityId) then
			fail(TAB_RUNES, `Rune {label} points at an unknown rarity`)
		else
			runesPerRarity[rune.rarityId] = (runesPerRarity[rune.rarityId] or 0) + 1
		end
	end
	for _, rarity in State.rarities do
		if (runesPerRarity[rarity.id] or 0) == 0 then
			fail(TAB_RUNES, `Rarity {rarity.id} needs at least one rune`)
		end
	end

	return problems
end

-- ---------------------------------------------------------------------------
-- Source generation (Apply writes these; Print copies them to Output)
-- ---------------------------------------------------------------------------

local Gen = {}

function Gen.escape(value: string): string
	local escaped = string.gsub(value, "\\", "\\\\")
	escaped = string.gsub(escaped, '"', '\\"')
	escaped = string.gsub(escaped, "\n", "\\n")
	escaped = string.gsub(escaped, "\r", "\\r")
	escaped = string.gsub(escaped, "\t", "\\t")
	return `"{escaped}"`
end

function Gen.number(value: number): string
	if math.floor(value) == value and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return tostring(value)
end

-- Generic pretty emitter for the DesignerConfig table. Arrays keep order;
-- string keys emit in a stable known-first order so diffs stay readable.
local KNOWN_KEY_ORDER = {
	"experienceMode",
	"preset",
	"dataNamespace",
	"identity",
	"universeId",
	"placeId",
	"currencies",
	"features",
	"runes",
}

function Gen.sortedKeys(value: { [string]: any }): { string }
	local keys: { string } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		local orderA = table.find(KNOWN_KEY_ORDER, a) or 1000
		local orderB = table.find(KNOWN_KEY_ORDER, b) or 1000
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a < b
	end)
	return keys
end

function Gen.value(value: any, indent: string): string
	if type(value) == "string" then
		return Gen.escape(value)
	elseif type(value) == "number" then
		return Gen.number(value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) ~= "table" then
		return "nil"
	end
	local inner = indent .. "\t"
	local lines: { string } = { "{" }
	if #value > 0 then
		for _, item in value :: { any } do
			table.insert(lines, `{inner}{Gen.value(item, inner)},`)
		end
	else
		for _, key in Gen.sortedKeys(value) do
			local keyText = if string.match(key, "^[%a_][%w_]*$") ~= nil then key else `[{Gen.escape(key)}]`
			table.insert(lines, `{inner}{keyText} = {Gen.value(value[key], inner)},`)
		end
	end
	table.insert(lines, indent .. "}")
	return table.concat(lines, "\n")
end

function Gen.runesOverride(): { [string]: any }
	local override: { [string]: any } = {}
	for _, group in { PACING_SPECS, LIMIT_SPECS, PITY_SPECS } do
		for _, spec in group do
			override[spec.key] = State.scalars[spec.key]
		end
	end
	override.pityMinimumRarity = State.pityMinimumRarity
	override.rareAudioMinimumRarity = State.rareAudioMinimumRarity
	override.defaultChannelMode = State.defaultChannelMode
	override.copyMilestones = Val.filledMilestones()
	local modes = {}
	for _, mode in Val.enabledModes() do
		table.insert(modes, {
			id = mode.id,
			name = mode.name,
			kind = mode.kind,
			unlock = { kind = mode.unlockKind, value = mode.unlockValue },
			tiers = Val.filledTiers(mode),
		})
	end
	override.channelModes = modes
	return override
end

function Gen.designerSource(): string?
	local designerModule = sharedModule("DesignerConfig")
	if designerModule == nil then
		return nil
	end
	local ok, existing = pcall(require, designerModule)
	if not ok or type(existing) ~= "table" then
		return nil
	end
	local merged: { [string]: any } = table.clone(existing)
	merged.runes = Gen.runesOverride()
	return "--!strict\n\n"
		.. "-- Written by Runewright. The runes table overrides TemplateConfig's rune\n"
		.. "-- tunables for this place; delete it to fall back to the template defaults.\n"
		.. `return {Gen.value(merged, "")}\n`
end

function Gen.catalogSource(): string
	local lines: { string } = {
		"--!strict",
		"",
		"-- Rune altar catalog: rarity tiers and the finite rune card set.",
		"-- Written by Runewright. Pure data so Lune tests and the client can require",
		"-- it directly. Colors are {r, g, b} 0-255 tables because Color3 is",
		"-- unavailable outside Roblox. Rarity weights are integer parts-per-ten-",
		"-- thousand and MUST sum to exactly 10000 so the disclosed odds always total",
		"-- 100% (see docs/internal/2026-07-12-rune-channel-modes.md).",
		"-- Glyphs are display text unless the string is 5-16 digits, which names a",
		"-- Roblox image asset id (RuneLogic.glyphImage decides).",
		"",
		"export type RuneRarity = {",
		"\tid: string,",
		"\tname: string,",
		"\tweight: number,",
		"\tcolor: { number },",
		"}",
		"",
		"export type RuneDefinition = {",
		"\tid: string,",
		"\tname: string,",
		"\trarityId: string,",
		"\tglyph: string,",
		"\t-- Permanent additive bonus to currency generation, in percent.",
		"\tbonusPercent: number,",
		"\tflavor: string,",
		"}",
		"",
		"-- Ordered from most to least common; pity promotion uses this order.",
		"local Rarities: { RuneRarity } = {",
	}
	for _, rarity in State.rarities do
		table.insert(
			lines,
			`\t\{ id = {Gen.escape(rarity.id)}, name = {Gen.escape(rarity.name)}, weight = {Gen.number(
				rarity.weight
			)}, color = \{ {Gen.number(rarity.color[1])}, {Gen.number(rarity.color[2])}, {Gen.number(
				rarity.color[3]
			)} } },`
		)
	end
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, "local Runes: { RuneDefinition } = {")
	for _, rune in State.runes do
		table.insert(lines, "\t{")
		table.insert(lines, `\t\tid = {Gen.escape(rune.id)},`)
		table.insert(lines, `\t\tname = {Gen.escape(rune.name)},`)
		table.insert(lines, `\t\trarityId = {Gen.escape(rune.rarityId)},`)
		table.insert(lines, `\t\tglyph = {Gen.escape(rune.glyph)},`)
		table.insert(lines, `\t\tbonusPercent = {Gen.number(rune.bonusPercent)},`)
		table.insert(lines, `\t\tflavor = {Gen.escape(rune.flavor)},`)
		table.insert(lines, "\t},")
	end
	for _, tail in
		{
			"}",
			"",
			"local runesById: { [string]: RuneDefinition } = {}",
			"local runesByRarity: { [string]: { RuneDefinition } } = {}",
			"local raritiesById: { [string]: RuneRarity } = {}",
			"local rarityIndexById: { [string]: number } = {}",
			"",
			"for index, rarity in Rarities do",
			"\traritiesById[rarity.id] = rarity",
			"\trarityIndexById[rarity.id] = index",
			"\trunesByRarity[rarity.id] = {}",
			"end",
			"",
			"for _, rune in Runes do",
			"\trunesById[rune.id] = rune",
			"\tlocal bucket = runesByRarity[rune.rarityId]",
			"\tassert(bucket ~= nil, `rune {rune.id} references unknown rarity {rune.rarityId}`)",
			"\ttable.insert(bucket, rune)",
			"end",
			"",
			"local RuneCatalog = {",
			"\trarities = Rarities,",
			"\trunes = Runes,",
			"}",
			"",
			"function RuneCatalog.rune(runeId: string): RuneDefinition?",
			"\treturn runesById[runeId]",
			"end",
			"",
			"function RuneCatalog.rarity(rarityId: string): RuneRarity?",
			"\treturn raritiesById[rarityId]",
			"end",
			"",
			"function RuneCatalog.rarityIndex(rarityId: string): number?",
			"\treturn rarityIndexById[rarityId]",
			"end",
			"",
			"function RuneCatalog.runesForRarity(rarityId: string): { RuneDefinition }",
			"\treturn runesByRarity[rarityId] or {}",
			"end",
			"",
			"return table.freeze(RuneCatalog)",
			"",
		}
	do
		table.insert(lines, tail)
	end
	return table.concat(lines, "\n")
end

local NOT_CONNECTED_STATUS =
	"Not connected. Open a place built from bootstrap.project.json, then click Reload."

local function applyToPlace()
	if not State.loaded then
		setStatus(NOT_CONNECTED_STATUS, AMBER)
		return
	end
	local problems = Val.all()
	if #problems > 0 then
		local more = if #problems > 1 then ` (+{#problems - 1} more in Review)` else ""
		setStatus(`Fix first: {problems[1].message}{more}`, AMBER)
		return
	end
	local catalogModule = sharedModule("RuneCatalog")
	local designerSource = Gen.designerSource()
	local designerModule = sharedModule("DesignerConfig")
	if catalogModule == nil or designerModule == nil or designerSource == nil then
		setStatus("Place modules missing; rebuild from bootstrap.project.json.", BAD)
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("Runewright apply")
	catalogModule.Source = Gen.catalogSource()
	designerModule.Source = designerSource
	if recording ~= nil then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	setStatus(
		`Applied {os.date("%H:%M:%S")}. Playtest to feel it; with Rojo serve, Print Sources and paste`
			.. " into the repo so sync keeps it.",
		GOOD
	)
end

local function printSources()
	if not State.loaded then
		setStatus(NOT_CONNECTED_STATUS, AMBER)
		return
	end
	local problems = Val.all()
	if #problems > 0 then
		local more = if #problems > 1 then ` (+{#problems - 1} more in Review)` else ""
		setStatus(`Fix first: {problems[1].message}{more}`, AMBER)
		return
	end
	local designerSource = Gen.designerSource()
	print("---------- Runewright: DesignerConfig.luau ----------")
	print(designerSource or "-- DesignerConfig module not found in this place")
	print("---------- Runewright: RuneCatalog.luau ----------")
	print(Gen.catalogSource())
	setStatus("Both sources printed to Output.", GOOD)
end

-- ---------------------------------------------------------------------------
-- Display formatting helpers
-- ---------------------------------------------------------------------------

local COMPACT_STEPS: { { limit: number, suffix: string } } = {
	{ limit = 1e12, suffix = "T" },
	{ limit = 1e9, suffix = "B" },
	{ limit = 1e6, suffix = "M" },
	{ limit = 1e4, suffix = "k" },
}

-- "1000000000" reads terribly in a range hint; "1B" does not. Only whole
-- multiples compact, so oddballs like 9999 stay literal.
local function compactNumber(value: number): string
	for _, step in COMPACT_STEPS do
		if value >= step.limit and value % (if step.suffix == "k" then 1e3 else step.limit) == 0 then
			local divisor = if step.suffix == "k" then 1e3 else step.limit
			return `{Gen.number(value / divisor)}{step.suffix}`
		end
	end
	return Gen.number(value)
end

local function rangeText(spec: ScalarSpec): string
	local text = `{compactNumber(spec.min)} – {compactNumber(spec.max)}`
	if spec.integer then
		text ..= " · whole"
	end
	return text
end

local function colorHex(color: Color3): string
	return string.format(
		"%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

-- Accepts "#60A5FA" or "60a5fa"; returns the three 0-255 channels.
local function parseHexColor(text: string): (number?, number?, number?)
	local cleaned = string.gsub(string.gsub(text, "%s", ""), "^#", "")
	local r, g, b = string.match(cleaned, "^(%x%x)(%x%x)(%x%x)$")
	if r == nil or g == nil or b == nil then
		return nil, nil, nil
	end
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

-- Mirrors RuneLogic.glyphImage: a 5-16 digit glyph names a Roblox image
-- asset; anything else renders as display text. The plugin build is
-- standalone, so the rule is duplicated here — keep both in sync.
local function glyphImageId(glyph: string): string?
	if #glyph >= 5 and #glyph <= 16 and string.match(glyph, "^%d+$") ~= nil then
		return `rbxassetid://{glyph}`
	end
	return nil
end

local KIND_EXPLAINERS: { [string]: string } = {
	luck = "LUCK: momentum multiplies every rarity above common by the tier value; the increase is paid"
		.. " out of the common weight, so disclosed odds keep totalling 100%.",
	surge = "SURGE: momentum grants a temporary earnings multiplier equal to the tier value while"
		.. " channeling. The strongest boost wins; surge never stacks with potions.",
}

local UNLOCK_VALUE_LABELS: { [string]: string } = {
	totalRolls = "Unlocks after this many total rolls",
	runesOwned = "Unlocks at this many runes owned",
}

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local openButton = toolbar:CreateButton(PLUGIN_BUTTON_ID, `Open {PLUGIN_NAME}`, PLUGIN_ICON, PLUGIN_NAME)
openButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, false, 420, 760, 360, 520)
local widget = plugin:CreateDockWidgetPluginGuiAsync(PLUGIN_WIDGET_ID, widgetInfo)
widget.Title = `{PLUGIN_NAME} — {PLUGIN_SUBTITLE}`
widget.Name = PLUGIN_WIDGET_ID

-- The selected tab survives Reload rebuilds so fixing a value does not throw
-- you back to the first page.
local activeTabName = TAB_ALTAR

local rebuildPanel: () -> ()

local function performReload()
	Load.fromPlace()
	rebuildPanel()
	if State.loaded then
		setStatus("Reloaded live values from the open place.", GOOD)
	else
		setStatus(State.problem or "Rune configuration unavailable in this place.", AMBER)
	end
end

local TAB_BAR_HEIGHT = 34
local FOOTER_HEIGHT = 92
local INPUT_HEIGHT = 28
local ROW_HEIGHT = 32

local function buildPanel()
	Refresh.validation = nil
	Refresh.odds = nil
	Refresh.runesList = nil
	Refresh.defaultMode = nil
	Refresh.status = nil

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = PANEL_BG
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = widget

	local function createLabel(
		parent: Instance,
		name: string,
		text: string,
		height: number,
		color: Color3
	): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.Text = text
		label.TextColor3 = color
		label.TextSize = 11
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Size = UDim2.new(1, 0, 0, height)
		label.Parent = parent
		return label
	end

	local function round(parent: Instance, radius: number)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius)
		corner.Parent = parent
	end

	local function outline(parent: Instance, transparency: number): UIStroke
		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER
		stroke.Transparency = transparency
		stroke.Thickness = 1
		stroke.Parent = parent
		return stroke
	end

	local function createButton(
		parent: Instance,
		name: string,
		text: string,
		height: number,
		hover: boolean?
	): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.BackgroundColor3 = BUTTON_BG
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = text
		button.TextColor3 = TEXT
		button.TextSize = 11
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Size = UDim2.new(1, 0, 0, height)
		button.Parent = parent
		round(button, 5)
		outline(button, 0.55)
		if hover ~= false then
			button.MouseEnter:Connect(function()
				button.BackgroundColor3 = BUTTON_HOVER
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundColor3 = BUTTON_BG
			end)
		end
		return button
	end

	-- Destructive actions arm on the first click and only fire on a second
	-- click within a short window, so a stray click never removes work.
	local function armButton(button: TextButton, armedText: string, onConfirm: () -> ())
		local restingText = button.Text
		local restingColor = button.TextColor3
		local stroke = button:FindFirstChildOfClass("UIStroke")
		local restingStroke = if stroke ~= nil then stroke.Color else BORDER
		local armed = false
		local generation = 0
		local function rest()
			armed = false
			generation += 1
			button.Text = restingText
			button.TextColor3 = restingColor
			if stroke ~= nil then
				stroke.Color = restingStroke
			end
		end
		button.MouseButton1Click:Connect(function()
			if armed then
				rest()
				onConfirm()
				return
			end
			armed = true
			generation += 1
			local myGeneration = generation
			button.Text = armedText
			button.TextColor3 = BAD
			if stroke ~= nil then
				stroke.Color = BAD
			end
			task.delay(2.5, function()
				if armed and generation == myGeneration then
					rest()
				end
			end)
		end)
	end

	-- Flat section: uppercase title row (with an optional right-side meta
	-- slot), a hairline rule, then content stacked directly below — no box.
	type Section = { frame: Frame, head: Frame, title: TextLabel, meta: TextLabel }
	local function createSection(parent: Instance, name: string, titleText: string): Section
		local section = Instance.new("Frame")
		section.Name = name
		section.BackgroundTransparency = 1
		section.Size = UDim2.fromScale(1, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = section

		-- Head and rule keep LayoutOrder 0 like plain content, so insertion
		-- order puts them first and later explicitly-ordered children (cards,
		-- lists) always land below them.
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.BackgroundTransparency = 1
		head.Size = UDim2.new(1, 0, 0, 18)
		head.Parent = section

		local title = createLabel(head, "Title", string.upper(titleText), 18, HEADING)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 11
		title.Size = UDim2.new(0.5, 0, 0, 18)

		local meta = createLabel(head, "Meta", "", 18, MUTED)
		meta.Font = Enum.Font.GothamBold
		meta.TextSize = 11
		meta.Position = UDim2.fromScale(0.5, 0)
		meta.Size = UDim2.new(0.5, 0, 0, 18)
		meta.TextXAlignment = Enum.TextXAlignment.Right
		meta.TextTruncate = Enum.TextTruncate.AtEnd

		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.BackgroundColor3 = BORDER
		rule.BackgroundTransparency = 0.45
		rule.BorderSizePixel = 0
		rule.Size = UDim2.new(1, 0, 0, 1)
		rule.Parent = section

		return { frame = section, head = head, title = title, meta = meta }
	end

	local function createHint(parent: Instance, name: string, text: string): TextLabel
		local hint = createLabel(parent, name, text, 14, SUBTLE)
		hint.TextSize = 11
		hint.TextWrapped = true
		hint.AutomaticSize = Enum.AutomaticSize.Y
		hint.Size = UDim2.fromScale(1, 0)
		return hint
	end

	-- Compact editable value: a slim shell exactly as tall as its text, no
	-- label inside. Labels live beside or above as plain text. The shell
	-- brightens on hover and shows a steel focus ring while editing.
	local function inputBox(
		parent: Instance,
		name: string,
		initial: string,
		commit: (text: string) -> string
	): (TextBox, Frame)
		local shell = Instance.new("Frame")
		shell.Name = name
		shell.BackgroundColor3 = PANEL_FIELD
		shell.BorderSizePixel = 0
		shell.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		shell.Parent = parent
		round(shell, 4)
		local stroke = outline(shell, 0.7)

		local box = Instance.new("TextBox")
		box.Name = "Value"
		box.BackgroundTransparency = 1
		box.ClearTextOnFocus = false
		box.Font = Enum.Font.GothamBold
		box.Text = initial
		box.TextColor3 = TEXT_ACTIVE
		box.TextSize = 12
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextTruncate = Enum.TextTruncate.AtEnd
		box.Position = UDim2.fromOffset(7, 0)
		box.Size = UDim2.new(1, -14, 1, 0)
		box.Parent = shell

		local focused = false
		local hovered = false
		local function repaintStroke()
			if focused then
				stroke.Color = BUTTON_ACTIVE
				stroke.Transparency = 0.1
				shell.BackgroundColor3 = PANEL_FIELD
			else
				stroke.Color = if hovered then BORDER_STRONG else BORDER
				stroke.Transparency = if hovered then 0.35 else 0.55
				shell.BackgroundColor3 = if hovered then FIELD_HOVER else PANEL_FIELD
			end
		end
		box.Focused:Connect(function()
			focused = true
			repaintStroke()
		end)
		box.FocusLost:Connect(function()
			focused = false
			repaintStroke()
			box.Text = commit(box.Text)
		end)
		shell.MouseEnter:Connect(function()
			hovered = true
			repaintStroke()
		end)
		shell.MouseLeave:Connect(function()
			hovered = false
			repaintStroke()
		end)
		return box, shell
	end

	local function numberInput(
		parent: Instance,
		name: string,
		label: string,
		read: () -> number?,
		write: (value: number?) -> (),
		allowBlank: boolean
	): (TextBox, Frame)
		local function display(): string
			local value = read()
			return if value ~= nil then Gen.number(value) else ""
		end
		local box, shell = inputBox(parent, name, display(), function(text)
			local trimmed = string.gsub(text, "%s", "")
			if trimmed == "" and allowBlank then
				write(nil)
				touch()
				return ""
			end
			local value = tonumber(trimmed)
			if value == nil or not Val.isFinite(value) then
				setStatus(`{label}: "{text}" is not a number`, AMBER)
				return display()
			end
			write(value)
			touch()
			return display()
		end)
		if allowBlank then
			box.PlaceholderText = "—"
			box.PlaceholderColor3 = SUBTLE
		end
		return box, shell
	end

	local function textInput(
		parent: Instance,
		name: string,
		read: () -> string,
		write: (value: string) -> ()
	): (TextBox, Frame)
		return inputBox(parent, name, read(), function(text)
			write(text)
			touch()
			return read()
		end)
	end

	-- Full-width form line for an altar scalar: name left, accepted range in
	-- the middle, 96px value box right. Out-of-range or non-integer input is
	-- refused right here with the range in the message, instead of surfacing
	-- later as an Apply failure.
	local function scalarRow(parent: Instance, spec: ScalarSpec)
		local row = Instance.new("Frame")
		row.Name = spec.key
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.Parent = parent

		local nameLabel = createLabel(row, "Name", spec.label, ROW_HEIGHT, TEXT)
		nameLabel.Size = UDim2.new(1, -220, 0, ROW_HEIGHT)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local hintLabel = createLabel(row, "Range", rangeText(spec), ROW_HEIGHT, SUBTLE)
		hintLabel.AnchorPoint = Vector2.new(1, 0)
		hintLabel.Position = UDim2.new(1, -104, 0, 0)
		hintLabel.Size = UDim2.fromOffset(110, ROW_HEIGHT)
		hintLabel.TextSize = 10
		hintLabel.TextXAlignment = Enum.TextXAlignment.Right
		hintLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local _, shell = inputBox(row, "Value", Gen.number(State.scalars[spec.key]), function(text)
			local current = Gen.number(State.scalars[spec.key])
			local parsed = tonumber((string.gsub(text, "%s", "")))
			if parsed == nil or not Val.isFinite(parsed) then
				setStatus(`{spec.label}: "{text}" is not a number`, AMBER)
				return current
			end
			if parsed < spec.min or parsed > spec.max then
				setStatus(
					`{spec.label} must be between {compactNumber(spec.min)} and {compactNumber(spec.max)}`,
					AMBER
				)
				return current
			end
			if spec.integer and math.floor(parsed) ~= parsed then
				setStatus(`{spec.label} must be a whole number`, AMBER)
				return current
			end
			State.scalars[spec.key] = parsed
			touch()
			return Gen.number(parsed)
		end)
		shell.AnchorPoint = Vector2.new(1, 0.5)
		shell.Position = UDim2.fromScale(1, 0.5)
		shell.Size = UDim2.fromOffset(96, INPUT_HEIGHT)
	end

	-- Every fixed choice is a row of visible pills — one click selects any
	-- option directly, and the whole option set is always on screen (the old
	-- cycle buttons hid everything behind repeated clicks). Non-tinted pills
	-- fill steel blue when selected and may carry a colored dot; tinted pills
	-- (rune rarity) color the text when idle and fill with the rarity color
	-- when selected.
	local function optionPills(
		parent: Instance,
		name: string,
		columns: number,
		options: () -> { PillOption },
		read: () -> string,
		write: (value: string) -> (),
		tint: boolean?
	): (() -> (), Frame)
		local pillHost = Instance.new("Frame")
		pillHost.Name = name
		pillHost.BackgroundTransparency = 1
		pillHost.Size = UDim2.fromScale(1, 0)
		pillHost.AutomaticSize = Enum.AutomaticSize.Y
		pillHost.Parent = parent
		local pillLayout = Instance.new("UIGridLayout")
		pillLayout.CellPadding = UDim2.fromOffset(4, 4)
		pillLayout.CellSize = UDim2.new(1 / columns, -4, 0, 20)
		pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
		pillLayout.Parent = pillHost

		local repaint: () -> ()
		repaint = function()
			for _, child in pillHost:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			local current = read()
			for order, option in options() do
				local pill = Instance.new("TextButton")
				pill.Name = `Pill{option.value}`
				pill.AutoButtonColor = false
				pill.BorderSizePixel = 0
				pill.Font = Enum.Font.GothamBold
				pill.TextSize = if tint == true then 9 else 10
				pill.TextTruncate = Enum.TextTruncate.AtEnd
				pill.LayoutOrder = order
				local selected = option.value == current
				local idleText: Color3
				if tint == true and option.dotColor ~= nil then
					-- Selected: a translucent wash of the rarity color with a solid
					-- colored stroke and lightened text — a picked state, not a tag.
					local dotColor = option.dotColor
					idleText = dotColor
					pill.BackgroundColor3 = dotColor
					pill.BackgroundTransparency = if selected then 0.84 else 1
					pill.TextColor3 = if selected then dotColor:Lerp(Color3.new(1, 1, 1), 0.4) else dotColor
					pill.Text = option.text
				else
					idleText = MUTED
					pill.BackgroundColor3 = if selected then BUTTON_ACTIVE else PANEL_FIELD
					pill.BackgroundTransparency = if selected then 0 else 1
					pill.TextColor3 = if selected then ON_ACCENT else MUTED
					if option.dotColor ~= nil then
						pill.RichText = true
						pill.Text = `<font color="#{colorHex(option.dotColor)}">●</font> {option.text}`
					else
						pill.Text = option.text
					end
				end
				pill.Parent = pillHost
				round(pill, 4)
				local pillStroke = outline(pill, if selected then 0.35 else 0.6)
				if tint == true and selected and option.dotColor ~= nil then
					pillStroke.Color = option.dotColor
					pillStroke.Transparency = 0.25
				end
				if not selected then
					pill.MouseEnter:Connect(function()
						pill.TextColor3 = if tint == true
							then idleText:Lerp(Color3.new(1, 1, 1), 0.35)
							else TEXT
					end)
					pill.MouseLeave:Connect(function()
						pill.TextColor3 = idleText
					end)
				end
				pill.MouseButton1Click:Connect(function()
					write(option.value)
					repaint()
					touch()
				end)
			end
		end
		repaint()
		return repaint, pillHost
	end

	-- 11px caption used above a pill group.
	local function pillCaption(parent: Instance, name: string, text: string)
		local caption = createLabel(parent, name, text, 18, TEXT)
		caption.TextSize = 11
	end

	-- Exclusive choice as one connected track of equal segments — the selected
	-- segment fills steel blue. Distinct from pills: segments mean "exactly one
	-- of these few", pills stay color-keyed pickers.
	local function segmentedControl(
		parent: Instance,
		name: string,
		options: () -> { PillOption },
		read: () -> string,
		write: (value: string) -> ()
	): (() -> (), Frame)
		local track = Instance.new("Frame")
		track.Name = name
		track.BackgroundColor3 = PANEL_FIELD
		track.BorderSizePixel = 0
		track.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		track.Parent = parent
		round(track, 5)
		outline(track, 0.6)
		local trackPadding = Instance.new("UIPadding")
		trackPadding.PaddingTop = UDim.new(0, 2)
		trackPadding.PaddingBottom = UDim.new(0, 2)
		trackPadding.PaddingLeft = UDim.new(0, 2)
		trackPadding.PaddingRight = UDim.new(0, 2)
		trackPadding.Parent = track
		local trackLayout = Instance.new("UIListLayout")
		trackLayout.FillDirection = Enum.FillDirection.Horizontal
		trackLayout.Padding = UDim.new(0, 2)
		trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
		trackLayout.Parent = track

		local repaint: () -> ()
		repaint = function()
			for _, child in track:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			local list = options()
			local current = read()
			local count = math.max(#list, 1)
			for order, option in list do
				local segment = Instance.new("TextButton")
				segment.Name = `Segment{option.value}`
				segment.AutoButtonColor = false
				segment.BorderSizePixel = 0
				segment.Font = Enum.Font.GothamBold
				segment.TextSize = 11
				segment.TextTruncate = Enum.TextTruncate.AtEnd
				segment.LayoutOrder = order
				local selected = option.value == current
				segment.BackgroundColor3 = BUTTON_ACTIVE
				segment.BackgroundTransparency = if selected then 0 else 1
				segment.TextColor3 = if selected then ON_ACCENT else MUTED
				segment.Text = option.text
				segment.Size = UDim2.new(1 / count, if order < count then -2 else 0, 1, 0)
				segment.Parent = track
				round(segment, 3)
				if not selected then
					segment.MouseEnter:Connect(function()
						segment.TextColor3 = TEXT
					end)
					segment.MouseLeave:Connect(function()
						segment.TextColor3 = MUTED
					end)
				end
				segment.MouseButton1Click:Connect(function()
					write(option.value)
					repaint()
					touch()
				end)
			end
		end
		repaint()
		return repaint, track
	end

	-- On/off as a real switch: caption plus a 30×14 track whose knob slides
	-- across when toggled.
	local function toggleSwitch(
		parent: Instance,
		name: string,
		read: () -> boolean,
		write: (value: boolean) -> ()
	): (() -> (), TextButton)
		local hit = Instance.new("TextButton")
		hit.Name = name
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.BorderSizePixel = 0
		hit.Text = ""
		hit.Size = UDim2.fromOffset(96, 20)
		hit.Parent = parent

		local caption = createLabel(hit, "Caption", "", 20, MUTED)
		caption.Font = Enum.Font.GothamBold
		caption.TextSize = 11
		caption.Size = UDim2.new(1, -37, 0, 20)
		caption.TextXAlignment = Enum.TextXAlignment.Right

		local trackFrame = Instance.new("Frame")
		trackFrame.Name = "Track"
		trackFrame.BackgroundColor3 = PANEL_FIELD
		trackFrame.BorderSizePixel = 0
		trackFrame.AnchorPoint = Vector2.new(1, 0.5)
		trackFrame.Position = UDim2.fromScale(1, 0.5)
		trackFrame.Size = UDim2.fromOffset(30, 14)
		trackFrame.Parent = hit
		round(trackFrame, 7)
		local trackStroke = outline(trackFrame, 0.35)

		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.BorderSizePixel = 0
		knob.Size = UDim2.fromOffset(10, 10)
		knob.Position = UDim2.fromOffset(2, 2)
		knob.Parent = trackFrame
		round(knob, 5)

		local knobTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local function repaint(animate: boolean)
			local on = read()
			caption.Text = if on then "Enabled" else "Off"
			caption.TextColor3 = if on then TEXT else SUBTLE
			trackFrame.BackgroundColor3 = if on then TRACK_ON else PANEL_FIELD
			trackStroke.Color = if on then BUTTON_ACTIVE else BORDER
			local target = UDim2.fromOffset(if on then 18 else 2, 2)
			knob.BackgroundColor3 = if on then KNOB_ON else KNOB_OFF
			if animate then
				TweenService:Create(knob, knobTween, { Position = target }):Play()
			else
				knob.Position = target
			end
		end
		hit.MouseButton1Click:Connect(function()
			write(not read())
			repaint(true)
		end)
		repaint(false)
		return function()
			repaint(false)
		end, hit
	end

	-- Label-left / control-right line for small option sets (mode kind, unlock).
	-- Returns the right-side host (parent the segmented control there) and the
	-- row itself.
	local function inlineChoiceRow(parent: Instance, name: string, labelText: string): (Frame, Frame)
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		row.Parent = parent
		local label = createLabel(row, "Label", labelText, INPUT_HEIGHT, TEXT)
		label.Size = UDim2.fromOffset(48, INPUT_HEIGHT)
		local host = Instance.new("Frame")
		host.Name = "Host"
		host.BackgroundTransparency = 1
		host.Position = UDim2.fromOffset(56, 0)
		host.Size = UDim2.new(1, -56, 0, INPUT_HEIGHT)
		host.Parent = row
		return host, row
	end

	-- Three-column value table (index | wide input | fixed input) with one
	-- header row — used by momentum tiers and copy milestones so labels are
	-- written once instead of inside every cell. Returns the table plus an
	-- addRow builder; status messages borrow the column headers ("#3 boost ×").
	type TableRowBuilder = (
		index: number,
		readWide: () -> number?,
		writeWide: (value: number?) -> (),
		readFixed: () -> number?,
		writeFixed: (value: number?) -> ()
	) -> ()
	local function valueTable(
		parent: Instance,
		name: string,
		headWide: string,
		headFixed: string,
		fixedWidth: number
	): (Frame, TableRowBuilder)
		local host = Instance.new("Frame")
		host.Name = name
		host.BackgroundTransparency = 1
		host.Size = UDim2.fromScale(1, 0)
		host.AutomaticSize = Enum.AutomaticSize.Y
		host.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = host

		local head = Instance.new("Frame")
		head.Name = "Head"
		head.BackgroundTransparency = 1
		head.Size = UDim2.new(1, 0, 0, 12)
		head.LayoutOrder = 0
		head.Parent = host
		local headIndex = createLabel(head, "Index", "#", 12, SUBTLE)
		headIndex.Font = Enum.Font.GothamBold
		headIndex.TextSize = 10
		headIndex.Size = UDim2.fromOffset(22, 12)
		local headA = createLabel(head, "Wide", string.upper(headWide), 12, SUBTLE)
		headA.Font = Enum.Font.GothamBold
		headA.TextSize = 10
		headA.Position = UDim2.fromOffset(28, 0)
		headA.Size = UDim2.new(1, -(28 + fixedWidth + 6), 0, 12)
		local headB = createLabel(head, "Fixed", string.upper(headFixed), 12, SUBTLE)
		headB.Font = Enum.Font.GothamBold
		headB.TextSize = 10
		headB.AnchorPoint = Vector2.new(1, 0)
		headB.Position = UDim2.fromScale(1, 0)
		headB.Size = UDim2.fromOffset(fixedWidth, 12)

		-- Only the filled rows plus one blank "next" row show; typing in the
		-- blank row reveals the next, up to the runtime cap. No wall of dashes.
		local rowEntries: { { frame: Frame, readWide: () -> number?, readFixed: () -> number? } } = {}
		local function refreshTableRows()
			local lastFilled = 0
			for index, entry in rowEntries do
				if entry.readWide() ~= nil or entry.readFixed() ~= nil then
					lastFilled = index
				end
			end
			for index, entry in rowEntries do
				entry.frame.Visible = index <= math.min(lastFilled + 1, #rowEntries)
			end
		end

		local function addRow(
			index: number,
			readWide: () -> number?,
			writeWide: (value: number?) -> (),
			readFixed: () -> number?,
			writeFixed: (value: number?) -> ()
		)
			local row = Instance.new("Frame")
			row.Name = `Row{index}`
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
			row.LayoutOrder = index
			row.Parent = host

			local ix = createLabel(row, "Index", `{index}`, INPUT_HEIGHT, SUBTLE)
			ix.TextSize = 11
			ix.Size = UDim2.fromOffset(22, INPUT_HEIGHT)

			local _, wideShell = numberInput(row, "Wide", `#{index} {headWide}`, readWide, function(value)
				writeWide(value)
				refreshTableRows()
			end, true)
			wideShell.Position = UDim2.fromOffset(28, 0)
			wideShell.Size = UDim2.new(1, -(28 + fixedWidth + 6), 0, INPUT_HEIGHT)

			local _, fixedShell = numberInput(row, "Fixed", `#{index} {headFixed}`, readFixed, function(value)
				writeFixed(value)
				refreshTableRows()
			end, true)
			fixedShell.AnchorPoint = Vector2.new(1, 0)
			fixedShell.Position = UDim2.fromScale(1, 0)
			fixedShell.Size = UDim2.fromOffset(fixedWidth, INPUT_HEIGHT)

			table.insert(rowEntries, { frame = row, readWide = readWide, readFixed = readFixed })
			refreshTableRows()
		end
		return host, addRow
	end

	local function rarityColor(rarityId: string): Color3
		for _, rarity in State.rarities do
			if rarity.id == rarityId then
				return Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
			end
		end
		return BORDER
	end

	local function rarityOptions(): { PillOption }
		local options: { PillOption } = {}
		for _, rarity in State.rarities do
			table.insert(options, {
				value = rarity.id,
				text = rarity.id,
				dotColor = rarityColor(rarity.id),
			})
		end
		return options
	end

	-- Footer ----------------------------------------------------------------
	local footer = Instance.new("Frame")
	footer.Name = "ActionDock"
	footer.BackgroundColor3 = PANEL_STATUS
	footer.BorderSizePixel = 0
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT)
	footer.Parent = root

	local footerRule = Instance.new("Frame")
	footerRule.Name = "Rule"
	footerRule.BackgroundColor3 = BORDER
	footerRule.BackgroundTransparency = 0.5
	footerRule.BorderSizePixel = 0
	footerRule.Size = UDim2.new(1, 0, 0, 1)
	footerRule.Parent = footer

	local validationLabel = createLabel(footer, "Readiness", "", 12, MUTED)
	validationLabel.Font = Enum.Font.GothamBold
	validationLabel.Position = UDim2.fromOffset(12, 5)
	validationLabel.Size = UDim2.new(1, -24, 0, 12)
	validationLabel.TextSize = 11
	validationLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local statusLabel = createLabel(footer, "Status", "", 26, MUTED)
	statusLabel.Position = UDim2.fromOffset(12, 19)
	statusLabel.Size = UDim2.new(1, -24, 0, 26)
	statusLabel.TextSize = 11
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	Refresh.status = function(message: string, color: Color3?)
		statusLabel.Text = message
		statusLabel.TextColor3 = color or MUTED
	end

	local actionRow = Instance.new("Frame")
	actionRow.Name = "Actions"
	actionRow.BackgroundTransparency = 1
	actionRow.Position = UDim2.fromOffset(12, 50)
	actionRow.Size = UDim2.new(1, -24, 0, 30)
	actionRow.Parent = footer
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actionRow

	-- Disconnected: no tabs, no forms — one clear recovery path -------------
	if not State.loaded then
		validationLabel.Text = "Not connected to a template place."
		validationLabel.TextColor3 = AMBER

		local reloadButton = createButton(actionRow, "Reload", "Reload from Place", 30)
		reloadButton.Size = UDim2.fromScale(1, 1)
		reloadButton.MouseButton1Click:Connect(performReload)

		local notice = Instance.new("Frame")
		notice.Name = "NotConnected"
		notice.BackgroundTransparency = 1
		notice.Size = UDim2.new(1, 0, 1, -FOOTER_HEIGHT)
		notice.Parent = root
		local noticePadding = Instance.new("UIPadding")
		noticePadding.PaddingTop = UDim.new(0, 16)
		noticePadding.PaddingLeft = UDim.new(0, 14)
		noticePadding.PaddingRight = UDim.new(0, 14)
		noticePadding.Parent = notice
		local noticeLayout = Instance.new("UIListLayout")
		noticeLayout.Padding = UDim.new(0, 10)
		noticeLayout.SortOrder = Enum.SortOrder.LayoutOrder
		noticeLayout.Parent = notice

		local noticeTitle = createLabel(notice, "Title", "Not connected to a place", 18, TEXT)
		noticeTitle.Font = Enum.Font.GothamBold
		noticeTitle.TextSize = 13

		local problemLabel = createLabel(
			notice,
			"Problem",
			State.problem or "Rune configuration unavailable in this place.",
			18,
			AMBER
		)
		problemLabel.TextWrapped = true
		problemLabel.AutomaticSize = Enum.AutomaticSize.Y
		problemLabel.Size = UDim2.fromScale(1, 0)

		local steps = createLabel(
			notice,
			"Steps",
			"1. Open a place built from bootstrap.project.json (2_START.cmd serves it live)."
				.. "\n2. Click Reload from Place — the workbench reads the live rune values.",
			18,
			MUTED
		)
		steps.TextWrapped = true
		steps.AutomaticSize = Enum.AutomaticSize.Y
		steps.Size = UDim2.fromScale(1, 0)
		return
	end

	-- Loaded: actions -------------------------------------------------------
	local applyButton = createButton(actionRow, "Apply", "Apply to Place", 30, false)
	applyButton.Size = UDim2.new(0.4, -6, 1, 0)
	applyButton.LayoutOrder = 1
	applyButton.BackgroundColor3 = BUTTON_ACTIVE
	applyButton.TextColor3 = ON_ACCENT
	applyButton.MouseButton1Click:Connect(applyToPlace)
	applyButton.MouseEnter:Connect(function()
		if applyButton.BackgroundColor3 == BUTTON_ACTIVE then
			applyButton.BackgroundColor3 = BUTTON_ACTIVE_HOVER
		end
	end)
	applyButton.MouseLeave:Connect(function()
		if applyButton.BackgroundColor3 == BUTTON_ACTIVE_HOVER then
			applyButton.BackgroundColor3 = BUTTON_ACTIVE
		end
	end)

	local printButton = createButton(actionRow, "Print", "Print Sources", 30)
	printButton.Size = UDim2.new(0.33, -6, 1, 0)
	printButton.LayoutOrder = 2
	printButton.MouseButton1Click:Connect(printSources)

	-- Reload discards unapplied edits, so it arms like Remove does.
	local reloadButton = createButton(actionRow, "Reload", "Reload", 30, false)
	reloadButton.Size = UDim2.new(0.27, -6, 1, 0)
	reloadButton.LayoutOrder = 3
	armButton(reloadButton, "Discard edits?", performReload)

	-- Tab bar: flat labels over a hairline, active tab carries a 2px steel
	-- underline and issue counts render as amber superscripts.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundColor3 = PANEL_HEADER
	tabBar.BorderSizePixel = 0
	tabBar.Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT)
	tabBar.Parent = root
	local tabPadding = Instance.new("UIPadding")
	tabPadding.PaddingLeft = UDim.new(0, 4)
	tabPadding.PaddingRight = UDim.new(0, 4)
	tabPadding.Parent = tabBar
	local tabLayout = Instance.new("UIGridLayout")
	tabLayout.CellPadding = UDim2.fromOffset(0, 0)
	tabLayout.CellSize = UDim2.fromScale(0.2, 1)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local tabBarRule = Instance.new("Frame")
	tabBarRule.Name = "TabBarRule"
	tabBarRule.BackgroundColor3 = BORDER
	tabBarRule.BackgroundTransparency = 0.5
	tabBarRule.BorderSizePixel = 0
	tabBarRule.Position = UDim2.fromOffset(0, TAB_BAR_HEIGHT - 1)
	tabBarRule.Size = UDim2.new(1, 0, 0, 1)
	tabBarRule.ZIndex = 2
	tabBarRule.Parent = root

	local pageHost = Instance.new("Frame")
	pageHost.Name = "Pages"
	pageHost.BackgroundTransparency = 1
	pageHost.Position = UDim2.fromOffset(0, TAB_BAR_HEIGHT)
	pageHost.Size = UDim2.new(1, 0, 1, -(TAB_BAR_HEIGHT + FOOTER_HEIGHT))
	pageHost.Parent = root

	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local issueCountByTab: { [string]: number } = {}

	for order, tabName in TAB_DEFS do
		local page = Instance.new("ScrollingFrame")
		page.Name = tabName
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Size = UDim2.fromScale(1, 1)
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollBarThickness = 4
		page.ScrollBarImageColor3 = BORDER
		page.Visible = tabName == activeTabName
		page.Parent = pageHost
		local pagePadding = Instance.new("UIPadding")
		pagePadding.PaddingTop = UDim.new(0, 12)
		pagePadding.PaddingBottom = UDim.new(0, 12)
		pagePadding.PaddingLeft = UDim.new(0, 12)
		pagePadding.PaddingRight = UDim.new(0, 12)
		pagePadding.Parent = page
		local pageLayout = Instance.new("UIListLayout")
		pageLayout.Padding = UDim.new(0, 14)
		pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
		pageLayout.Parent = page
		pages[tabName] = page

		local tabButton = Instance.new("TextButton")
		tabButton.Name = `Tab{tabName}`
		tabButton.AutoButtonColor = false
		tabButton.BackgroundTransparency = 1
		tabButton.BorderSizePixel = 0
		tabButton.Font = Enum.Font.GothamBold
		tabButton.RichText = true
		tabButton.Text = tabName
		tabButton.TextColor3 = MUTED
		tabButton.TextSize = 11
		tabButton.TextTruncate = Enum.TextTruncate.AtEnd
		tabButton.LayoutOrder = order
		tabButton.Parent = tabBar

		local indicator = Instance.new("Frame")
		indicator.Name = "Indicator"
		indicator.BackgroundColor3 = BUTTON_ACTIVE
		indicator.BorderSizePixel = 0
		indicator.AnchorPoint = Vector2.new(0.5, 1)
		indicator.Position = UDim2.fromScale(0.5, 1)
		indicator.Size = UDim2.new(0.8, 0, 0, 2)
		indicator.ZIndex = 3
		indicator.Visible = false
		indicator.Parent = tabButton
		round(indicator, 1)

		tabButtons[tabName] = tabButton
	end

	local function repaintTabs()
		for _, tabName in TAB_DEFS do
			local button = tabButtons[tabName]
			local count = issueCountByTab[tabName] or 0
			local selected = tabName == activeTabName
			button.Text = if count > 0
				then `{tabName} <font color="#{colorHex(AMBER)}">{count}</font>`
				else tabName
			button.TextColor3 = if selected then TEXT_ACTIVE elseif count > 0 then AMBER else MUTED
			local indicator = button:FindFirstChild("Indicator")
			if indicator ~= nil and indicator:IsA("Frame") then
				indicator.Visible = selected
			end
		end
	end

	local function selectTab(tabName: string)
		activeTabName = tabName
		for pageName, page in pages do
			page.Visible = pageName == tabName
		end
		repaintTabs()
	end

	for _, tabName in TAB_DEFS do
		local button = tabButtons[tabName]
		button.MouseButton1Click:Connect(function()
			selectTab(tabName)
		end)
		button.MouseEnter:Connect(function()
			if tabName ~= activeTabName then
				button.TextColor3 = TEXT
			end
		end)
		button.MouseLeave:Connect(function()
			repaintTabs()
		end)
	end

	-- Altar tab ---------------------------------------------------------------
	local altarPage = pages[TAB_ALTAR]

	local pacing = createSection(altarPage, "Pacing", "Altar Pacing")
	createHint(
		pacing.frame,
		"PacingHint",
		"How fast the altar drinks coins. Costs are in the primary currency."
	)
	for _, spec in PACING_SPECS do
		scalarRow(pacing.frame, spec)
	end

	local limits = createSection(altarPage, "Limits", "Circle & Safety Limits")
	for _, spec in LIMIT_SPECS do
		scalarRow(limits.frame, spec)
	end

	local pity = createSection(altarPage, "Pity", "Pity & Luck Floor")
	createHint(
		pity.frame,
		"PityHint",
		"The guarantee that rescues dry streaks, and how low luck may push Common."
	)
	for _, spec in PITY_SPECS do
		scalarRow(pity.frame, spec)
	end
	pillCaption(pity.frame, "PityRarityCaption", "Pity guarantees at least")
	optionPills(pity.frame, "PityRarity", 3, rarityOptions, function()
		return State.pityMinimumRarity
	end, function(value)
		State.pityMinimumRarity = value
	end)
	pillCaption(pity.frame, "RareAudioCaption", "Rare reveal sound plays from")
	optionPills(pity.frame, "RareAudioRarity", 3, rarityOptions, function()
		return State.rareAudioMinimumRarity
	end, function(value)
		State.rareAudioMinimumRarity = value
	end)

	-- Modes tab ---------------------------------------------------------------
	local modesPage = pages[TAB_MODES]

	local defaultSection = createSection(modesPage, "Default", "Default Mode")
	createHint(
		defaultSection.frame,
		"DefaultHint",
		"What brand-new players channel with. Must be one of the enabled modes below."
	)
	Refresh.defaultMode = segmentedControl(defaultSection.frame, "DefaultMode", function()
		local options: { PillOption } = {}
		for _, mode in Val.enabledModes() do
			if #mode.id > 0 then
				table.insert(options, { value = mode.id, text = mode.id })
			end
		end
		if #options == 0 then
			table.insert(options, { value = State.defaultChannelMode, text = State.defaultChannelMode })
		end
		return options
	end, function()
		return State.defaultChannelMode
	end, function(value)
		State.defaultChannelMode = value
	end)

	local modesSection = createSection(modesPage, "Modes", "Channel Modes")
	createHint(
		modesSection.frame,
		"ModesHint",
		"Up to four momentum strategies. LUCK bends odds; SURGE boosts earnings under the"
			.. " strongest-boost rule. Disabled cards keep their values and collapse to one row."
	)

	for index, mode in State.modes do
		local card = Instance.new("Frame")
		card.Name = `ModeCard{index}`
		card.BackgroundColor3 = SURFACE
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(1, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = 10 + index
		card.Parent = modesSection.frame
		round(card, 6)
		outline(card, 0.55)
		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 10)
		cardPadding.PaddingBottom = UDim.new(0, 10)
		cardPadding.PaddingLeft = UDim.new(0, 10)
		cardPadding.PaddingRight = UDim.new(0, 10)
		cardPadding.Parent = card
		local cardLayout = Instance.new("UIListLayout")
		cardLayout.Padding = UDim.new(0, 8)
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Parent = card

		local headRow = Instance.new("Frame")
		headRow.Name = "Head"
		headRow.BackgroundTransparency = 1
		headRow.Size = UDim2.new(1, 0, 0, 20)
		headRow.LayoutOrder = 1
		headRow.Parent = card
		local headTitle = createLabel(headRow, "Title", string.upper(`Mode {index}`), 20, HEADING)
		headTitle.Font = Enum.Font.GothamBold
		headTitle.TextSize = 11

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.LayoutOrder = 2
		body.Parent = card
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.Padding = UDim.new(0, 8)
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Parent = body

		local identityGrid = Instance.new("Frame")
		identityGrid.Name = "Identity"
		identityGrid.BackgroundTransparency = 1
		identityGrid.Size = UDim2.new(1, 0, 0, 44)
		identityGrid.LayoutOrder = 1
		identityGrid.Parent = body
		local identityLayout = Instance.new("UIGridLayout")
		identityLayout.CellPadding = UDim2.fromOffset(8, 0)
		identityLayout.CellSize = UDim2.new(0.5, -8, 0, 44)
		identityLayout.SortOrder = Enum.SortOrder.LayoutOrder
		identityLayout.Parent = identityGrid

		local function identityCell(
			name: string,
			caption: string,
			read: () -> string,
			write: (value: string) -> ()
		)
			local cell = Instance.new("Frame")
			cell.Name = name
			cell.BackgroundTransparency = 1
			cell.Parent = identityGrid
			local mini = createLabel(cell, "Caption", caption, 12, SUBTLE)
			mini.TextSize = 10
			mini.Size = UDim2.new(1, 0, 0, 14)
			local _, shell = textInput(cell, "Value", read, write)
			shell.Position = UDim2.fromOffset(0, 16)
			shell.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		end
		identityCell("Id", "Id (lowercase, save key)", function()
			return mode.id
		end, function(value)
			mode.id = string.lower(value)
			local repaintDefault = Refresh.defaultMode
			if repaintDefault ~= nil then
				repaintDefault()
			end
		end)
		identityCell("DisplayName", "Display name", function()
			return mode.name
		end, function(value)
			mode.name = value
		end)

		local explainer = createLabel(body, "KindExplainer", KIND_EXPLAINERS[mode.kind] or "", 14, MUTED)
		explainer.LayoutOrder = 3
		explainer.TextSize = 11
		explainer.TextWrapped = true
		explainer.AutomaticSize = Enum.AutomaticSize.Y
		explainer.Size = UDim2.fromScale(1, 0)

		local kindHost, kindRow = inlineChoiceRow(body, "KindRow", "Kind")
		kindRow.LayoutOrder = 2
		segmentedControl(kindHost, "Kind", function()
			return {
				{ value = "luck", text = "luck · bends odds" },
				{ value = "surge", text = "surge · boosts earnings" },
			}
		end, function()
			return mode.kind
		end, function(value)
			mode.kind = value
			explainer.Text = KIND_EXPLAINERS[value] or ""
		end)

		local thresholdRow: Frame? = nil
		local thresholdLabel: TextLabel? = nil
		local function repaintThreshold()
			local row = thresholdRow
			local label = thresholdLabel
			if row == nil or label == nil then
				return
			end
			local text = UNLOCK_VALUE_LABELS[mode.unlockKind]
			row.Visible = text ~= nil
			label.Text = text or ""
		end

		local unlockHost, unlockRow = inlineChoiceRow(body, "UnlockRow", "Unlock")
		unlockRow.LayoutOrder = 4
		segmentedControl(unlockHost, "Unlock", function()
			return {
				{ value = "always", text = "always" },
				{ value = "totalRolls", text = "after N rolls" },
				{ value = "runesOwned", text = "at N runes" },
				{ value = "provider", text = "provider" },
			}
		end, function()
			return mode.unlockKind
		end, function(value)
			mode.unlockKind = value
			repaintThreshold()
		end)

		local threshold = Instance.new("Frame")
		threshold.Name = "Threshold"
		threshold.BackgroundTransparency = 1
		threshold.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		threshold.LayoutOrder = 5
		threshold.Parent = body
		local thresholdCaption = createLabel(threshold, "Caption", "", INPUT_HEIGHT, TEXT)
		thresholdCaption.Size = UDim2.new(1, -104, 0, INPUT_HEIGHT)
		thresholdCaption.TextTruncate = Enum.TextTruncate.AtEnd
		local _, thresholdShell = numberInput(threshold, "UnlockValue", "Unlock threshold", function()
			return mode.unlockValue
		end, function(value)
			if value ~= nil then
				mode.unlockValue = value
			end
		end, false)
		thresholdShell.AnchorPoint = Vector2.new(1, 0)
		thresholdShell.Position = UDim2.fromScale(1, 0)
		thresholdShell.Size = UDim2.fromOffset(96, INPUT_HEIGHT)
		thresholdRow = threshold
		thresholdLabel = thresholdCaption
		repaintThreshold()

		local tiersHint = createLabel(
			body,
			"TiersHint",
			"MOMENTUM TIERS · rows appear as you fill them (up to 8) · times must strictly rise",
			14,
			SUBTLE
		)
		tiersHint.LayoutOrder = 6
		tiersHint.Font = Enum.Font.GothamBold
		tiersHint.TextSize = 10
		tiersHint.TextWrapped = true
		tiersHint.AutomaticSize = Enum.AutomaticSize.Y
		tiersHint.Size = UDim2.fromScale(1, 0)

		local tiersTable, addTierRow = valueTable(body, "Tiers", "after (s)", "boost ×", 88)
		tiersTable.LayoutOrder = 7
		for tierIndex, tier in mode.tiers do
			addTierRow(tierIndex, function()
				return tier.atSeconds
			end, function(value)
				tier.atSeconds = value
			end, function()
				return tier.value
			end, function(value)
				tier.value = value
			end)
		end

		local function repaintCard()
			body.Visible = mode.enabled
			local suffix = if not mode.enabled and #mode.id == 0 then " · EMPTY SLOT" else ""
			headTitle.Text = string.upper(`Mode {index}`) .. suffix
		end
		local _, switchHit = toggleSwitch(headRow, "Enabled", function()
			return mode.enabled
		end, function(value)
			mode.enabled = value
			repaintCard()
			local repaintDefault = Refresh.defaultMode
			if repaintDefault ~= nil then
				repaintDefault()
			end
			touch()
		end)
		switchHit.AnchorPoint = Vector2.new(1, 0)
		switchHit.Position = UDim2.fromScale(1, 0)
		repaintCard()
	end

	-- Rarity tab --------------------------------------------------------------
	local rarityPage = pages[TAB_RARITY]

	local raritiesSection = createSection(rarityPage, "Rarities", "Rarities & Odds")
	local totalLabel = raritiesSection.meta
	createHint(
		raritiesSection.frame,
		"RaritiesHint",
		"Weights are parts-per-10000 and must sum to exactly 10000 before Apply unlocks."
			.. " The bar and odds update as you type."
	)

	-- Live distribution: one stacked bar showing every rarity's share of the
	-- weight budget, so the shape of the economy reads before any number does.
	local oddsBar = Instance.new("Frame")
	oddsBar.Name = "OddsBar"
	oddsBar.BackgroundColor3 = PANEL_FIELD
	oddsBar.BorderSizePixel = 0
	oddsBar.ClipsDescendants = true
	oddsBar.Size = UDim2.new(1, 0, 0, 14)
	oddsBar.LayoutOrder = 5
	oddsBar.Parent = raritiesSection.frame
	round(oddsBar, 4)
	outline(oddsBar, 0.5)

	local oddsLabels: { TextLabel } = {}
	local weightBoxes: { TextBox } = {}
	for index, rarity in State.rarities do
		local row = Instance.new("Frame")
		row.Name = `Rarity{index}`
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = 10 + index * 3
		row.Parent = raritiesSection.frame

		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.BackgroundColor3 = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		swatch.BorderSizePixel = 0
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.fromScale(0, 0.5)
		swatch.Size = UDim2.fromOffset(12, 12)
		swatch.Parent = row
		round(swatch, 3)

		local _, nameShell = textInput(row, "DisplayName", function()
			return rarity.name
		end, function(value)
			rarity.name = value
		end)
		nameShell.Position = UDim2.new(0, 18, 0.5, -INPUT_HEIGHT // 2)
		nameShell.Size = UDim2.new(1, -(18 + 64 + 6 + 92 + 6), 0, INPUT_HEIGHT)

		local weightBox, weightShell = inputBox(row, "Weight", Gen.number(rarity.weight), function(text)
			local value = tonumber((string.gsub(text, "%s", "")))
			if value == nil or not Val.isFinite(value) then
				setStatus(`Weight: "{text}" is not a number`, AMBER)
				return Gen.number(rarity.weight)
			end
			rarity.weight = math.floor(value)
			local repaint = Refresh.odds
			if repaint ~= nil then
				repaint()
			end
			touch()
			return Gen.number(rarity.weight)
		end)
		weightShell.AnchorPoint = Vector2.new(1, 0.5)
		weightShell.Position = UDim2.new(1, -98, 0.5, 0)
		weightShell.Size = UDim2.fromOffset(64, INPUT_HEIGHT)
		weightBoxes[index] = weightBox

		local oddsLabel = createLabel(row, "Odds", "", ROW_HEIGHT, MUTED)
		oddsLabel.AnchorPoint = Vector2.new(1, 0)
		oddsLabel.Position = UDim2.fromScale(1, 0)
		oddsLabel.Size = UDim2.fromOffset(92, ROW_HEIGHT)
		oddsLabel.TextXAlignment = Enum.TextXAlignment.Right
		oddsLabel.TextSize = 10
		oddsLabels[index] = oddsLabel

		local rgbRow = Instance.new("Frame")
		rgbRow.Name = `Rgb{index}`
		rgbRow.BackgroundTransparency = 1
		rgbRow.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		rgbRow.LayoutOrder = 11 + index * 3
		rgbRow.Parent = raritiesSection.frame
		local rgbLayout = Instance.new("UIListLayout")
		rgbLayout.FillDirection = Enum.FillDirection.Horizontal
		rgbLayout.Padding = UDim.new(0, 6)
		rgbLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rgbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rgbLayout.Parent = rgbRow
		local rgbPad = Instance.new("UIPadding")
		rgbPad.PaddingLeft = UDim.new(0, 18)
		rgbPad.Parent = rgbRow
		local rgbCaption = createLabel(rgbRow, "Caption", "Color", INPUT_HEIGHT, SUBTLE)
		rgbCaption.TextSize = 10
		rgbCaption.Size = UDim2.fromOffset(28, INPUT_HEIGHT)

		local function rarityColor3(): Color3
			return Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		end
		local channelBoxes: { TextBox } = {}

		-- Hex and RGB edit the same color and keep each other in sync.
		local hexBox, hexShell = inputBox(rgbRow, "Hex", `#{colorHex(rarityColor3())}`, function(text)
			local r, g, b = parseHexColor(text)
			if r == nil or g == nil or b == nil then
				setStatus(`Color: "{text}" is not a hex color like #60A5FA`, AMBER)
				return `#{colorHex(rarityColor3())}`
			end
			rarity.color[1] = r
			rarity.color[2] = g
			rarity.color[3] = b
			swatch.BackgroundColor3 = rarityColor3()
			for channelIndex, channelBox in channelBoxes do
				channelBox.Text = Gen.number(rarity.color[channelIndex])
			end
			touch()
			return `#{colorHex(rarityColor3())}`
		end)
		hexBox.TextSize = 11
		hexShell.Size = UDim2.fromOffset(74, INPUT_HEIGHT)

		for channelIndex, channelName in { "R", "G", "B" } do
			local channelBox, channelShell = numberInput(rgbRow, `Color{channelName}`, channelName, function()
				return rarity.color[channelIndex]
			end, function(value)
				if value ~= nil then
					rarity.color[channelIndex] = math.clamp(math.floor(value), 0, 255)
					swatch.BackgroundColor3 = rarityColor3()
					hexBox.Text = `#{colorHex(rarityColor3())}`
				end
			end, false)
			channelBox.TextSize = 11
			channelShell.Size = UDim2.fromOffset(44, INPUT_HEIGHT)
			channelBoxes[channelIndex] = channelBox
		end

		if index < #State.rarities then
			local rule = Instance.new("Frame")
			rule.Name = `Rule{index}`
			rule.BackgroundColor3 = BORDER
			rule.BackgroundTransparency = 0.65
			rule.BorderSizePixel = 0
			rule.Size = UDim2.new(1, 0, 0, 1)
			rule.LayoutOrder = 12 + index * 3
			rule.Parent = raritiesSection.frame
		end
	end

	local normalizeButton = createButton(raritiesSection.frame, "Normalize", "Normalize Weights to 10000", 22)
	normalizeButton.LayoutOrder = 1000
	normalizeButton.TextSize = 11
	normalizeButton.MouseButton1Click:Connect(function()
		local total = Val.weightTotal()
		if total <= 0 then
			setStatus("Give every rarity a positive weight first.", AMBER)
			return
		end
		local assigned = 0
		for index, rarity in State.rarities do
			if index < #State.rarities then
				rarity.weight = math.max(math.floor(rarity.weight / total * 10000), 1)
				assigned += rarity.weight
			end
		end
		State.rarities[#State.rarities].weight = math.max(10000 - assigned, 1)
		local repaint = Refresh.odds
		if repaint ~= nil then
			repaint()
		end
		touch()
		setStatus("Weights rescaled. Nudge individual rows, then Apply.", GOOD)
	end)

	Refresh.odds = function()
		local total = Val.weightTotal()
		local ok = total == 10000
		totalLabel.Text = if ok then "Σ 10000 ✓ discloses correctly" else `Σ {total} — must equal 10000`
		totalLabel.TextColor3 = if ok then GOOD else AMBER

		for _, child in oddsBar:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		oddsBar.Visible = total > 0
		if total > 0 then
			local accumulated = 0
			for index, rarity in State.rarities do
				local fraction = math.max(rarity.weight, 0) / total
				local segment = Instance.new("Frame")
				segment.Name = `Share{rarity.id}`
				segment.BackgroundColor3 = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
				segment.BorderSizePixel = 0
				segment.Position = UDim2.fromScale(accumulated, 0)
				segment.Size = UDim2.fromScale(fraction, 1)
				segment.LayoutOrder = index
				segment.Parent = oddsBar
				accumulated += fraction
			end
		end
		for index, rarity in State.rarities do
			local label = oddsLabels[index]
			if label ~= nil then
				if total > 0 and rarity.weight > 0 then
					local percent = math.floor(rarity.weight / total * 10000) / 100
					local oneIn = math.floor(total / rarity.weight + 0.5)
					label.Text = `{percent}% · 1 in {oneIn}`
				else
					label.Text = ""
				end
			end
		end
		for index, rarity in State.rarities do
			local box = weightBoxes[index]
			if box ~= nil and not box:IsFocused() then
				box.Text = Gen.number(rarity.weight)
			end
		end
	end

	-- Runes tab ---------------------------------------------------------------
	local runesPage = pages[TAB_RUNES]

	local runesSection = createSection(runesPage, "Runes", "Rune Cards")
	local addRuneButton = createButton(runesSection.head, "AddRune", "Add Rune Card", 20)
	addRuneButton.AnchorPoint = Vector2.new(1, 0)
	addRuneButton.Position = UDim2.fromScale(1, 0)
	addRuneButton.Size = UDim2.fromOffset(104, 18)
	addRuneButton.TextSize = 11
	runesSection.meta.Visible = false
	createHint(
		runesSection.frame,
		"RunesHint",
		"Ids are save keys — renaming one orphans existing copies until the id returns."
			.. " Every rarity needs at least one card. Glyph takes an emoji or a Roblox image"
			.. " asset id (digits only) — the cell previews the actual image."
	)

	local runesList = Instance.new("Frame")
	runesList.Name = "RunesList"
	runesList.BackgroundTransparency = 1
	runesList.Size = UDim2.fromScale(1, 0)
	runesList.AutomaticSize = Enum.AutomaticSize.Y
	runesList.LayoutOrder = 10
	runesList.Parent = runesSection.frame
	local runesLayout = Instance.new("UIListLayout")
	runesLayout.Padding = UDim.new(0, 8)
	runesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	runesLayout.Parent = runesList

	local function buildRuneRow(index: number, rune: RuneRow)
		local card = Instance.new("Frame")
		card.Name = `Rune{index}`
		card.BackgroundColor3 = SURFACE
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.ClipsDescendants = true
		card.Size = UDim2.fromScale(1, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = index
		card.Parent = runesList
		round(card, 6)
		outline(card, 0.55)

		local edge = Instance.new("Frame")
		edge.Name = "Edge"
		edge.BackgroundColor3 = rarityColor(rune.rarityId)
		edge.BorderSizePixel = 0
		edge.Size = UDim2.new(0, 3, 1, 0)
		edge.Parent = card

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.Size = UDim2.fromScale(1, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
		content.Parent = card
		local contentPadding = Instance.new("UIPadding")
		contentPadding.PaddingTop = UDim.new(0, 8)
		contentPadding.PaddingBottom = UDim.new(0, 8)
		contentPadding.PaddingLeft = UDim.new(0, 14)
		contentPadding.PaddingRight = UDim.new(0, 8)
		contentPadding.Parent = content
		local contentLayout = Instance.new("UIListLayout")
		contentLayout.Padding = UDim.new(0, 6)
		contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
		contentLayout.Parent = content

		local topRow = Instance.new("Frame")
		topRow.Name = "Top"
		topRow.BackgroundTransparency = 1
		topRow.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		topRow.LayoutOrder = 1
		topRow.Parent = content

		-- The glyph cell previews digit glyphs as their actual Roblox image;
		-- focusing the cell swaps back to the raw id for editing.
		local glyphPreview = Instance.new("ImageLabel")
		glyphPreview.Name = "GlyphPreview"
		glyphPreview.BackgroundTransparency = 1
		glyphPreview.AnchorPoint = Vector2.new(0.5, 0.5)
		glyphPreview.Position = UDim2.fromScale(0.5, 0.5)
		glyphPreview.Size = UDim2.fromOffset(18, 18)
		glyphPreview.ScaleType = Enum.ScaleType.Fit
		glyphPreview.Visible = false

		local repaintGlyph: () -> ()
		local glyphBox, glyphShell = textInput(topRow, "Glyph", function()
			return rune.glyph
		end, function(value)
			rune.glyph = value
			repaintGlyph()
		end)
		glyphPreview.Parent = glyphShell
		glyphShell.Size = UDim2.fromOffset(36, INPUT_HEIGHT)
		glyphBox.TextXAlignment = Enum.TextXAlignment.Center
		glyphBox.Position = UDim2.fromOffset(0, 0)
		glyphBox.Size = UDim2.fromScale(1, 1)
		repaintGlyph = function()
			local image = glyphImageId(rune.glyph)
			glyphPreview.Image = image or ""
			glyphPreview.Visible = image ~= nil
			glyphBox.TextTransparency = if image ~= nil then 1 else 0
		end
		glyphBox.Focused:Connect(function()
			glyphPreview.Visible = false
			glyphBox.TextTransparency = 0
		end)
		glyphBox.FocusLost:Connect(repaintGlyph)
		repaintGlyph()

		local _, nameShell = textInput(topRow, "DisplayName", function()
			return rune.name
		end, function(value)
			rune.name = value
		end)
		nameShell.Position = UDim2.fromOffset(42, 0)
		nameShell.Size = UDim2.new(1, -(42 + 56 + 6 + 14), 0, INPUT_HEIGHT)

		local pctLabel = createLabel(topRow, "Pct", "%", INPUT_HEIGHT, SUBTLE)
		pctLabel.AnchorPoint = Vector2.new(1, 0)
		pctLabel.Position = UDim2.fromScale(1, 0)
		pctLabel.Size = UDim2.fromOffset(10, INPUT_HEIGHT)
		pctLabel.TextSize = 10

		local _, bonusShell = numberInput(topRow, "Bonus", "Bonus %", function()
			return rune.bonusPercent
		end, function(value)
			if value ~= nil then
				rune.bonusPercent = value
			end
		end, false)
		bonusShell.AnchorPoint = Vector2.new(1, 0)
		bonusShell.Position = UDim2.new(1, -14, 0, 0)
		bonusShell.Size = UDim2.fromOffset(56, INPUT_HEIGHT)

		local _, rarityPills = optionPills(content, "Rarity", 6, rarityOptions, function()
			return rune.rarityId
		end, function(value)
			rune.rarityId = value
			edge.BackgroundColor3 = rarityColor(value)
		end, true)
		rarityPills.LayoutOrder = 2

		local bottomRow = Instance.new("Frame")
		bottomRow.Name = "Bottom"
		bottomRow.BackgroundTransparency = 1
		bottomRow.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
		bottomRow.LayoutOrder = 3
		bottomRow.Parent = content

		local idBox, idShell = textInput(bottomRow, "Id", function()
			return rune.id
		end, function(value)
			rune.id = string.lower(value)
		end)
		idBox.TextSize = 11
		idShell.Size = UDim2.fromOffset(116, INPUT_HEIGHT)

		local removeButton = createButton(bottomRow, "Remove", "Remove Card", 20, false)
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.fromScale(1, 0.5)
		removeButton.Size = UDim2.fromOffset(84, 20)
		removeButton.TextSize = 10
		removeButton.TextColor3 = BAD
		removeButton.BackgroundTransparency = 1
		armButton(removeButton, "Confirm remove?", function()
			table.remove(State.runes, table.find(State.runes, rune) or index)
			local repaint = Refresh.runesList
			if repaint ~= nil then
				repaint()
			end
			touch()
			setStatus(
				`Removed {rune.name}. Existing saves keep the copies; they simply stop counting.`,
				MUTED
			)
		end)

		local flavorBox, flavorShell = textInput(bottomRow, "Flavor", function()
			return rune.flavor
		end, function(value)
			rune.flavor = value
		end)
		flavorBox.TextSize = 11
		flavorBox.PlaceholderText = "flavor text"
		flavorBox.PlaceholderColor3 = SUBTLE
		flavorShell.Position = UDim2.fromOffset(122, 0)
		flavorShell.Size = UDim2.new(1, -(122 + 84 + 6), 0, INPUT_HEIGHT)
	end

	Refresh.runesList = function()
		for _, child in runesList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for index, rune in State.runes do
			buildRuneRow(index, rune)
		end
		runesSection.title.Text = string.upper(`Rune Cards · {#State.runes}`)
	end

	addRuneButton.MouseButton1Click:Connect(function()
		local rarityId = if #State.rarities > 0 then State.rarities[1].id else "common"
		table.insert(State.runes, {
			id = `new_rune_{#State.runes + 1}`,
			name = "New Rune",
			rarityId = rarityId,
			glyph = "✨",
			bonusPercent = 1,
			flavor = "",
		})
		local repaint = Refresh.runesList
		if repaint ~= nil then
			repaint()
		end
		touch()
		setStatus("Card added at the bottom of the list. Give it an id, a rarity, and a bonus.", GOOD)
	end)

	local milestonesSection = createSection(runesPage, "Milestones", "Copy Milestones")
	createHint(
		milestonesSection.frame,
		"MilestonesHint",
		"Owning N copies multiplies that rune's whole contribution. Rows appear as you fill"
			.. " them (up to 8); copies must strictly rise and multipliers must never weaken."
	)
	local milestonesTable, addMilestoneRow =
		valueTable(milestonesSection.frame, "MilestonesGrid", "copies owned", "gives ×", 110)
	milestonesTable.LayoutOrder = 10
	for index, row in State.milestones do
		addMilestoneRow(index, function()
			return row.copies
		end, function(value)
			row.copies = value
		end, function()
			return row.multiplier
		end, function(value)
			row.multiplier = value
		end)
	end

	-- Review tab --------------------------------------------------------------
	local reviewPage = pages[TAB_REVIEW]

	local validationSection = createSection(reviewPage, "Validation", "Validation")
	createHint(
		validationSection.frame,
		"ValidationHint",
		"Rechecked after every edit. Apply to Place stays blocked while anything is listed;"
			.. " the tag on each line names the tab where it is fixed."
	)
	local issuesHost = Instance.new("Frame")
	issuesHost.Name = "Issues"
	issuesHost.BackgroundTransparency = 1
	issuesHost.Size = UDim2.fromScale(1, 0)
	issuesHost.AutomaticSize = Enum.AutomaticSize.Y
	issuesHost.LayoutOrder = 10
	issuesHost.Parent = validationSection.frame
	local issuesLayout = Instance.new("UIListLayout")
	issuesLayout.Padding = UDim.new(0, 4)
	issuesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	issuesLayout.Parent = issuesHost

	local workflowSection = createSection(reviewPage, "Workflow", "How Applying Works")
	local workflowText = createHint(
		workflowSection.frame,
		"WorkflowText",
		"Apply rewrites this place's DesignerConfig (runes overrides) and RuneCatalog"
			.. " ModuleScripts — undo-safe, playtest-ready, nothing publishes. Rojo serve"
			.. " overwrites those modules from the repo on sync, so make edits stick with Print"
			.. " Sources: paste the output into src/shared/DesignerConfig.luau and"
			.. " src/shared/RuneCatalog.luau. Changing a rune id orphans saved copies: they stay"
			.. " in player data but stop counting until the id returns."
	)
	workflowText.TextColor3 = MUTED

	local function addIssueRow(order: number, text: string, color: Color3)
		local issueLabel = createLabel(issuesHost, `Issue{order}`, text, 14, color)
		issueLabel.LayoutOrder = order
		issueLabel.TextSize = 11
		issueLabel.TextWrapped = true
		issueLabel.AutomaticSize = Enum.AutomaticSize.Y
		issueLabel.Size = UDim2.fromScale(1, 0)
	end

	Refresh.validation = function()
		local issues = Val.all()
		table.clear(issueCountByTab)
		for _, issue in issues do
			issueCountByTab[issue.tab] = (issueCountByTab[issue.tab] or 0) + 1
		end
		repaintTabs()

		if #issues == 0 then
			validationLabel.Text = "Ready to apply — no issues."
			validationLabel.TextColor3 = GOOD
		else
			local noun = if #issues == 1 then "issue" else "issues"
			validationLabel.Text = `{#issues} {noun} to fix — the Review tab lists them all.`
			validationLabel.TextColor3 = AMBER
		end
		applyButton.BackgroundColor3 = if #issues == 0 then BUTTON_ACTIVE else BUTTON_BG
		applyButton.TextColor3 = if #issues == 0 then ON_ACCENT else MUTED

		for _, child in issuesHost:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		if #issues == 0 then
			addIssueRow(1, "No issues — Apply to Place is ready.", GOOD)
		else
			for order, issue in issues do
				addIssueRow(order, `[{issue.tab}]  {issue.message}`, TEXT)
			end
		end
	end

	local repaintOdds = Refresh.odds
	if repaintOdds ~= nil then
		repaintOdds()
	end
	local repaintRunes = Refresh.runesList
	if repaintRunes ~= nil then
		repaintRunes()
	end
	touch()
end

rebuildPanel = function()
	for _, child in widget:GetChildren() do
		child:Destroy()
	end
	buildPanel()
end

Load.fromPlace()
rebuildPanel()
if State.loaded then
	setStatus("Loaded live values. Edit any tab, then Apply to Place.", GOOD)
else
	setStatus(State.problem or "Rune configuration unavailable in this place.", AMBER)
end

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	openButton:SetActive(widget.Enabled)
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
end)

--!strict

-- Runewright: private Studio workbench for the rune altar. Every adjustable
-- rune field lives here — altar pacing, pity, channel modes with momentum
-- tiers and unlock gates, copy milestones, rarity weights and colors, and the
-- rune cards themselves (names, glyphs, bonuses, flavor). Apply writes the
-- open place's DesignerConfig and RuneCatalog ModuleScripts (undo-safe) so a
-- playtest picks the values up immediately; Print emits the same sources to
-- the Output window for pasting back into the repo. Nothing publishes.
--
-- Compliance note: rarity weights are integer parts-per-ten-thousand and must
-- sum to exactly 10000 so disclosed odds always total 100%
-- (docs/internal/2026-07-12-rune-channel-modes.md). Apply refuses invalid
-- data instead of writing it.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLUGIN_NAME = "Runewright"
local PLUGIN_SUBTITLE = "Rune altar workbench"
local PLUGIN_BUTTON_ID = "RunewrightEditor"
local PLUGIN_WIDGET_ID = "RunewrightPanel"
local PLUGIN_ICON = "rbxasset://textures/StudioSharedUI/grid@2x.png"

local PANEL_BG = Color3.fromRGB(17, 18, 20)
local PANEL_HEADER = Color3.fromRGB(23, 24, 27)
local PANEL_SECTION = Color3.fromRGB(13, 14, 16)
local PANEL_STATUS = Color3.fromRGB(12, 13, 15)
local PANEL_FIELD = Color3.fromRGB(10, 12, 14)
local BUTTON_BG = Color3.fromRGB(15, 16, 18)
local BUTTON_ACTIVE = Color3.fromRGB(86, 128, 184)
local BUTTON_HOVER = Color3.fromRGB(30, 33, 38)
local BORDER = Color3.fromRGB(50, 54, 60)
local TEXT = Color3.fromRGB(229, 232, 237)
local TEXT_ACTIVE = Color3.fromRGB(245, 247, 250)
local MUTED = Color3.fromRGB(151, 158, 169)
local SUBTLE = Color3.fromRGB(99, 106, 118)
local AMBER = Color3.fromRGB(193, 155, 62)
local GOOD = Color3.fromRGB(74, 145, 98)
local BAD = Color3.fromRGB(156, 74, 74)

local MODE_KINDS = { "luck", "surge" }
local UNLOCK_KINDS = { "always", "totalRolls", "runesOwned", "provider" }
local MAX_MODES = 4
local TIER_ROWS = 4
local MILESTONE_ROWS = 5

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
-- repaint the derived readouts (odds preview, weight total, apply gating).
local Refresh = {
	odds = nil :: (() -> ())?,
	runesList = nil :: (() -> ())?,
	status = nil :: ((message: string, color: Color3?) -> ())?,
}

local function setStatus(message: string, color: Color3?)
	local apply = Refresh.status
	if apply ~= nil then
		apply(message, color)
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
	local configModule = sharedModule("TemplateConfig")
	local catalogModule = sharedModule("RuneCatalog")
	if configModule == nil or catalogModule == nil then
		return false, "Open a place built from bootstrap.project.json, then reopen Runewright."
	end
	local okConfig, config = pcall(require, configModule)
	local okCatalog, catalog = pcall(require, catalogModule)
	if not okConfig or type(config) ~= "table" or type(config.runes) ~= "table" then
		return false, "TemplateConfig could not be read; rebuild the place and reopen Runewright."
	end
	if not okCatalog or type(catalog) ~= "table" or type(catalog.rarities) ~= "table" then
		return false, "RuneCatalog could not be read; rebuild the place and reopen Runewright."
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
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Validation (mirrors RuneModeConfig + the Lune spec invariants)
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

function Val.all(): { string }
	local problems: { string } = {}
	local function fail(message: string)
		table.insert(problems, message)
	end

	for _, group in { PACING_SPECS, LIMIT_SPECS, PITY_SPECS } do
		for _, spec in group do
			local value = State.scalars[spec.key]
			if not Val.isFinite(value) or value < spec.min or value > spec.max then
				fail(`{spec.label} must be between {spec.min} and {spec.max}`)
			elseif spec.integer and math.floor(value) ~= value then
				fail(`{spec.label} must be a whole number`)
			end
		end
	end
	if not Val.rarityExists(State.pityMinimumRarity) then
		fail("Pity minimum rarity must be one of the rarities below")
	end
	if not Val.rarityExists(State.rareAudioMinimumRarity) then
		fail("Rare-audio rarity must be one of the rarities below")
	end

	local modes = Val.enabledModes()
	if #modes == 0 then
		fail("Enable at least one channel mode")
	end
	local usedModeIds: { [string]: boolean } = {}
	local defaultFound = false
	for _, mode in modes do
		local label = if #mode.id > 0 then mode.id else "(unnamed mode)"
		if not Val.validId(mode.id) then
			fail(`Mode id "{mode.id}" must be lowercase letters/digits/underscores`)
		elseif usedModeIds[mode.id] then
			fail(`Mode id "{mode.id}" is duplicated`)
		end
		usedModeIds[mode.id] = true
		if #mode.name < 1 or #mode.name > 32 then
			fail(`Mode {label} needs a name (1-32 characters)`)
		end
		if not table.find(MODE_KINDS, mode.kind) then
			fail(`Mode {label} has an unknown kind`)
		end
		if not table.find(UNLOCK_KINDS, mode.unlockKind) then
			fail(`Mode {label} has an unknown unlock kind`)
		end
		if
			(mode.unlockKind == "totalRolls" or mode.unlockKind == "runesOwned")
			and (not Val.isFinite(mode.unlockValue) or mode.unlockValue < 0)
		then
			fail(`Mode {label} unlock threshold must be 0 or more`)
		end
		local tiers = Val.filledTiers(mode)
		if #tiers == 0 then
			fail(`Mode {label} needs at least one momentum tier`)
		end
		local previousAt = 0
		for _, tier in tiers do
			if tier.atSeconds <= previousAt then
				fail(`Mode {label} tier times must strictly rise`)
				break
			end
			if tier.value < 1 or tier.value > 1000 then
				fail(`Mode {label} tier values must be between 1 and 1000`)
				break
			end
			previousAt = tier.atSeconds
		end
		if mode.id == State.defaultChannelMode then
			defaultFound = true
		end
	end
	if not defaultFound then
		fail(`Default mode "{State.defaultChannelMode}" must match an enabled mode id`)
	end

	local previousCopies = 1
	local previousMultiplier = 1
	for _, milestone in Val.filledMilestones() do
		if math.floor(milestone.copies) ~= milestone.copies or milestone.copies <= previousCopies then
			fail("Milestone copies must be whole numbers that strictly rise (2+)")
			break
		end
		if milestone.multiplier < previousMultiplier or milestone.multiplier > 1000 then
			fail("Milestone multipliers must never weaken (1+)")
			break
		end
		previousCopies = milestone.copies
		previousMultiplier = milestone.multiplier
	end

	local total = Val.weightTotal()
	if total ~= 10000 then
		fail(`Rarity weights sum to {total}; they must equal exactly 10000`)
	end
	for _, rarity in State.rarities do
		if #rarity.name < 1 or #rarity.name > 24 then
			fail(`Rarity {rarity.id} needs a name (1-24 characters)`)
		end
		if
			not Val.isFinite(rarity.weight)
			or rarity.weight < 1
			or math.floor(rarity.weight) ~= rarity.weight
		then
			fail(`Rarity {rarity.id} weight must be a positive whole number`)
		end
		for _, channel in rarity.color do
			if
				not Val.isFinite(channel)
				or channel < 0
				or channel > 255
				or math.floor(channel) ~= channel
			then
				fail(`Rarity {rarity.id} color channels must be whole numbers 0-255`)
				break
			end
		end
	end

	if #State.runes == 0 then
		fail("Add at least one rune")
	end
	local usedRuneIds: { [string]: boolean } = {}
	local runesPerRarity: { [string]: number } = {}
	for _, rune in State.runes do
		local label = if #rune.id > 0 then rune.id else "(unnamed rune)"
		if not Val.validId(rune.id) then
			fail(`Rune id "{rune.id}" must be lowercase letters/digits/underscores`)
		elseif usedRuneIds[rune.id] then
			fail(`Rune id "{rune.id}" is duplicated`)
		end
		usedRuneIds[rune.id] = true
		if #rune.name < 1 or #rune.name > 40 then
			fail(`Rune {label} needs a name (1-40 characters)`)
		end
		if #rune.glyph < 1 or #rune.glyph > 16 then
			fail(`Rune {label} needs a glyph (an emoji works great)`)
		end
		if not Val.isFinite(rune.bonusPercent) or rune.bonusPercent <= 0 then
			fail(`Rune {label} bonus must be a positive percent`)
		end
		if #rune.flavor > 120 then
			fail(`Rune {label} flavor text is limited to 120 characters`)
		end
		if not Val.rarityExists(rune.rarityId) then
			fail(`Rune {label} points at an unknown rarity`)
		else
			runesPerRarity[rune.rarityId] = (runesPerRarity[rune.rarityId] or 0) + 1
		end
	end
	for _, rarity in State.rarities do
		if (runesPerRarity[rarity.id] or 0) == 0 then
			fail(`Rarity {rarity.id} needs at least one rune`)
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
	local merged: { [string]: any } = {}
	for key, value in existing do
		merged[key] = value
	end
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

local function applyToPlace()
	local problems = Val.all()
	if #problems > 0 then
		setStatus(`Fix first: {problems[1]}`, AMBER)
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
	setStatus("Applied. Playtest to feel it; Print Sources to copy into the repo.", GOOD)
end

local function printSources()
	local problems = Val.all()
	if #problems > 0 then
		setStatus(`Fix first: {problems[1]}`, AMBER)
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
-- Panel
-- ---------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local openButton = toolbar:CreateButton(PLUGIN_BUTTON_ID, `Open {PLUGIN_NAME}`, PLUGIN_ICON, PLUGIN_NAME)
openButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, false, 420, 760, 360, 520)
local widget = plugin:CreateDockWidgetPluginGuiAsync(PLUGIN_WIDGET_ID, widgetInfo)
widget.Title = `{PLUGIN_NAME} — {PLUGIN_SUBTITLE}`
widget.Name = PLUGIN_WIDGET_ID

local function buildPanel()
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
		label.TextSize = 12
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

	local function outline(parent: Instance, transparency: number)
		local stroke = Instance.new("UIStroke")
		stroke.Color = BORDER
		stroke.Transparency = transparency
		stroke.Thickness = 1
		stroke.Parent = parent
	end

	local function createSection(parent: Instance, name: string, title: string, subtitle: string?): Frame
		local section = Instance.new("Frame")
		section.Name = name
		section.BackgroundColor3 = PANEL_SECTION
		section.BorderSizePixel = 0
		section.Size = UDim2.fromScale(1, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.Parent = parent
		round(section, 7)
		outline(section, 0.48)

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = section

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = section

		local titleLabel = createLabel(section, `{name}Title`, title, 16, TEXT)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 14
		if subtitle ~= nil and subtitle ~= "" then
			local subtitleLabel = createLabel(section, `{name}Subtitle`, subtitle, 18, MUTED)
			subtitleLabel.TextSize = 12
			subtitleLabel.TextWrapped = true
			subtitleLabel.AutomaticSize = Enum.AutomaticSize.Y
			subtitleLabel.Size = UDim2.new(1, 0, 0, 0)
		end
		return section
	end

	local function createButton(parent: Instance, name: string, text: string, height: number): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.BackgroundColor3 = BUTTON_BG
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = text
		button.TextColor3 = TEXT
		button.TextSize = 12
		button.Size = UDim2.new(1, 0, 0, height)
		button.Parent = parent
		round(button, 7)
		outline(button, 0.55)
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = BUTTON_HOVER
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = BUTTON_BG
		end)
		return button
	end

	local function createGrid(parent: Instance, name: string, columns: number, rowHeight: number): Frame
		local grid = Instance.new("Frame")
		grid.Name = name
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.fromScale(1, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Parent = parent
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.CellSize = UDim2.new(1 / columns, -6, 0, rowHeight)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		return grid
	end

	-- A labelled editable field. commit receives the raw text and returns the
	-- text to display (so numeric fields can reject bad input by reverting).
	local function createField(
		parent: Instance,
		name: string,
		labelText: string,
		initial: string,
		commit: (text: string) -> string
	): TextBox
		local field = Instance.new("Frame")
		field.Name = name
		field.BackgroundColor3 = PANEL_FIELD
		field.BorderSizePixel = 0
		field.Parent = parent
		round(field, 7)
		outline(field, 0.55)

		local label = createLabel(field, "Label", labelText, 14, MUTED)
		label.Position = UDim2.fromOffset(9, 4)
		label.Size = UDim2.new(1, -18, 0, 13)
		label.TextSize = 10
		label.TextTruncate = Enum.TextTruncate.AtEnd

		local box = Instance.new("TextBox")
		box.Name = "Value"
		box.BackgroundTransparency = 1
		box.ClearTextOnFocus = false
		box.Font = Enum.Font.GothamBold
		box.Text = initial
		box.TextColor3 = TEXT_ACTIVE
		box.TextSize = 13
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextTruncate = Enum.TextTruncate.AtEnd
		box.Position = UDim2.fromOffset(9, 18)
		box.Size = UDim2.new(1, -18, 0, 18)
		box.Parent = field
		box.FocusLost:Connect(function()
			box.Text = commit(box.Text)
		end)
		return box
	end

	local function numberField(
		parent: Instance,
		name: string,
		labelText: string,
		read: () -> number?,
		write: (value: number?) -> (),
		allowBlank: boolean
	)
		local function display(): string
			local value = read()
			return if value ~= nil then Gen.number(value) else ""
		end
		createField(parent, name, labelText, display(), function(text)
			local trimmed = string.gsub(text, "%s", "")
			if trimmed == "" and allowBlank then
				write(nil)
				return ""
			end
			local value = tonumber(trimmed)
			if value == nil or not Val.isFinite(value) then
				setStatus(`{labelText}: "{text}" is not a number`, AMBER)
				return display()
			end
			write(value)
			return display()
		end)
	end

	local function textField(
		parent: Instance,
		name: string,
		labelText: string,
		read: () -> string,
		write: (value: string) -> ()
	)
		createField(parent, name, labelText, read(), function(text)
			write(text)
			return read()
		end)
	end

	-- A button that cycles through fixed options (mode kind, unlock kind,
	-- rarity pickers) — no dropdown plumbing, one click per step.
	local function cycleField(
		parent: Instance,
		name: string,
		labelText: string,
		options: () -> { string },
		read: () -> string,
		write: (value: string) -> ()
	)
		local button = createButton(parent, name, "", 34)
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextYAlignment = Enum.TextYAlignment.Bottom
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 9)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = button
		local label = createLabel(button, "Hint", labelText, 12, SUBTLE)
		label.Position = UDim2.fromOffset(0, 2)
		label.Size = UDim2.new(1, -9, 0, 11)
		label.TextSize = 9
		local function repaint()
			button.Text = string.upper(read())
		end
		button.MouseButton1Click:Connect(function()
			local list = options()
			local index = table.find(list, read()) or 0
			write(list[(index % #list) + 1])
			repaint()
		end)
		repaint()
		return repaint
	end

	local function rarityIds(): { string }
		local ids = {}
		for _, rarity in State.rarities do
			table.insert(ids, rarity.id)
		end
		return ids
	end

	-- Header ---------------------------------------------------------------
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = PANEL_HEADER
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 54)
	header.Parent = root

	local title = createLabel(header, "Title", string.upper(PLUGIN_NAME), 20, TEXT_ACTIVE)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 20)
	local subtitle =
		createLabel(header, "Subtitle", PLUGIN_SUBTITLE .. " — every altar dial in one panel", 16, MUTED)
	subtitle.Position = UDim2.fromOffset(12, 30)
	subtitle.Size = UDim2.new(1, -24, 0, 16)

	-- Status + actions dock -------------------------------------------------
	local dock = Instance.new("Frame")
	dock.Name = "ActionDock"
	dock.BackgroundColor3 = PANEL_STATUS
	dock.BorderSizePixel = 0
	dock.AnchorPoint = Vector2.new(0, 1)
	dock.Position = UDim2.fromScale(0, 1)
	dock.Size = UDim2.new(1, 0, 0, 88)
	dock.Parent = root

	local statusLabel = createLabel(dock, "Status", "Loading current rune configuration...", 18, MUTED)
	statusLabel.Position = UDim2.fromOffset(12, 6)
	statusLabel.Size = UDim2.new(1, -24, 0, 18)
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Refresh.status = function(message: string, color: Color3?)
		statusLabel.Text = message
		statusLabel.TextColor3 = color or MUTED
	end

	local actionRow = Instance.new("Frame")
	actionRow.Name = "Actions"
	actionRow.BackgroundTransparency = 1
	actionRow.Position = UDim2.fromOffset(12, 30)
	actionRow.Size = UDim2.new(1, -24, 0, 48)
	actionRow.Parent = dock
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.Parent = actionRow

	local applyButton = createButton(actionRow, "Apply", "Apply to Place", 48)
	applyButton.Size = UDim2.new(0.5, -4, 1, 0)
	applyButton.BackgroundColor3 = BUTTON_ACTIVE
	applyButton.TextColor3 = TEXT_ACTIVE
	applyButton.MouseEnter:Connect(function()
		applyButton.BackgroundColor3 = BUTTON_ACTIVE
	end)
	applyButton.MouseLeave:Connect(function()
		applyButton.BackgroundColor3 = BUTTON_ACTIVE
	end)
	local printButton = createButton(actionRow, "Print", "Print Sources", 48)
	printButton.Size = UDim2.new(0.5, -4, 1, 0)

	-- Scrolling body ---------------------------------------------------------
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 54)
	scroll.Size = UDim2.new(1, 0, 1, -142)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = BORDER
	scroll.Parent = root

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingTop = UDim.new(0, 10)
	bodyPadding.PaddingBottom = UDim.new(0, 10)
	bodyPadding.PaddingLeft = UDim.new(0, 10)
	bodyPadding.PaddingRight = UDim.new(0, 10)
	bodyPadding.Parent = scroll

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 10)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = scroll

	-- Section: pacing ---------------------------------------------------------
	local function scalarGrid(section: Frame, name: string, specs: { ScalarSpec })
		local grid = createGrid(section, name, 3, 36)
		for _, spec in specs do
			numberField(grid, spec.key, spec.label, function()
				return State.scalars[spec.key]
			end, function(value)
				if value ~= nil then
					State.scalars[spec.key] = value
				end
			end, false)
		end
	end

	local pacing = createSection(
		scroll,
		"Pacing",
		"Altar Pacing",
		"How fast the altar drinks coins. Costs are in the primary currency."
	)
	scalarGrid(pacing, "PacingGrid", PACING_SPECS)

	local limits = createSection(
		scroll,
		"Limits",
		"Circle & Safety Limits",
		"Geometry forgiveness, anti-corruption caps, and reveal timing."
	)
	scalarGrid(limits, "LimitsGrid", LIMIT_SPECS)

	-- Section: pity -----------------------------------------------------------
	local pity = createSection(
		scroll,
		"Pity",
		"Pity & Luck Floor",
		"The guarantee that rescues dry streaks, and how low luck may push Common."
	)
	scalarGrid(pity, "PityGrid", PITY_SPECS)
	local pityPickers = createGrid(pity, "PityPickers", 2, 34)
	cycleField(pityPickers, "PityRarity", "Pity guarantees at least", rarityIds, function()
		return State.pityMinimumRarity
	end, function(value)
		State.pityMinimumRarity = value
	end)
	cycleField(pityPickers, "RareAudioRarity", "Rare reveal sound from", rarityIds, function()
		return State.rareAudioMinimumRarity
	end, function(value)
		State.rareAudioMinimumRarity = value
	end)

	-- Section: channel modes ----------------------------------------------------
	local modesSection = createSection(
		scroll,
		"Modes",
		"Channel Modes",
		"Up to four momentum strategies. LUCK bends odds; SURGE boosts earnings under the strongest-boost rule."
	)
	local defaultRow = createGrid(modesSection, "DefaultRow", 2, 34)
	local repaintDefault = cycleField(defaultRow, "DefaultMode", "Default mode", function()
		local ids = {}
		for _, mode in Val.enabledModes() do
			table.insert(ids, mode.id)
		end
		return if #ids > 0 then ids else { State.defaultChannelMode }
	end, function()
		return State.defaultChannelMode
	end, function(value)
		State.defaultChannelMode = value
	end)

	for index, mode in State.modes do
		local card = Instance.new("Frame")
		card.Name = `ModeCard{index}`
		card.BackgroundColor3 = PANEL_FIELD
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(1, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.Parent = modesSection
		round(card, 7)
		outline(card, 0.6)
		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 8)
		cardPadding.PaddingBottom = UDim.new(0, 8)
		cardPadding.PaddingLeft = UDim.new(0, 8)
		cardPadding.PaddingRight = UDim.new(0, 8)
		cardPadding.Parent = card
		local cardLayout = Instance.new("UIListLayout")
		cardLayout.Padding = UDim.new(0, 6)
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Parent = card

		local toggle = createButton(card, "Enabled", "", 26)
		local function repaintToggle()
			toggle.Text = if mode.enabled then `MODE {index}: ENABLED` else `MODE {index}: OFF`
			toggle.TextColor3 = if mode.enabled then TEXT_ACTIVE else SUBTLE
			local stroke = toggle:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				stroke.Color = if mode.enabled then GOOD else BORDER
			end
		end
		toggle.MouseButton1Click:Connect(function()
			mode.enabled = not mode.enabled
			repaintToggle()
			repaintDefault()
		end)
		repaintToggle()

		local identityGrid = createGrid(card, "Identity", 2, 36)
		textField(identityGrid, "Id", "Id (lowercase)", function()
			return mode.id
		end, function(value)
			mode.id = string.lower(value)
			repaintDefault()
		end)
		textField(identityGrid, "DisplayName", "Display name", function()
			return mode.name
		end, function(value)
			mode.name = value
		end)

		local behaviourGrid = createGrid(card, "Behaviour", 3, 34)
		cycleField(behaviourGrid, "Kind", "Kind", function()
			return MODE_KINDS
		end, function()
			return mode.kind
		end, function(value)
			mode.kind = value
		end)
		cycleField(behaviourGrid, "UnlockKind", "Unlock", function()
			return UNLOCK_KINDS
		end, function()
			return mode.unlockKind
		end, function(value)
			mode.unlockKind = value
		end)
		numberField(behaviourGrid, "UnlockValue", "Unlock threshold", function()
			return mode.unlockValue
		end, function(value)
			if value ~= nil then
				mode.unlockValue = value
			end
		end, false)

		local tiersGrid = createGrid(card, "Tiers", 4, 36)
		for tierIndex, tier in mode.tiers do
			numberField(tiersGrid, `Tier{tierIndex}At`, `T{tierIndex} at (s)`, function()
				return tier.atSeconds
			end, function(value)
				tier.atSeconds = value
			end, true)
			numberField(tiersGrid, `Tier{tierIndex}Value`, `T{tierIndex} value (x)`, function()
				return tier.value
			end, function(value)
				tier.value = value
			end, true)
		end
	end

	-- Section: milestones ---------------------------------------------------
	local milestonesSection = createSection(
		scroll,
		"Milestones",
		"Copy Milestones",
		"Owning N copies multiplies that rune's whole contribution. Blank rows are skipped; copies must strictly rise."
	)
	local milestonesGrid = createGrid(milestonesSection, "MilestonesGrid", 2, 36)
	for index, row in State.milestones do
		numberField(milestonesGrid, `Milestone{index}Copies`, `#{index} copies`, function()
			return row.copies
		end, function(value)
			row.copies = value
		end, true)
		numberField(milestonesGrid, `Milestone{index}Multiplier`, `#{index} multiplier (x)`, function()
			return row.multiplier
		end, function(value)
			row.multiplier = value
		end, true)
	end

	-- Section: rarities -------------------------------------------------------
	local raritiesSection = createSection(
		scroll,
		"Rarities",
		"Rarities & Odds",
		"Weights are parts-per-10000 and must sum to exactly 10000 — the live total below has to read 10000 before Apply unlocks."
	)
	local totalLabel = createLabel(raritiesSection, "WeightTotal", "", 16, TEXT)
	totalLabel.Font = Enum.Font.GothamBold
	local oddsLabels: { TextLabel } = {}
	for index, rarity in State.rarities do
		local row = Instance.new("Frame")
		row.Name = `Rarity{index}`
		row.BackgroundColor3 = PANEL_FIELD
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 64)
		row.Parent = raritiesSection
		round(row, 7)
		outline(row, 0.6)

		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.BackgroundColor3 = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromOffset(8, 8)
		swatch.Size = UDim2.fromOffset(10, 48)
		swatch.Parent = row
		round(swatch, 4)

		local idLabel = createLabel(row, "IdLabel", string.upper(rarity.id), 14, SUBTLE)
		idLabel.Position = UDim2.fromOffset(26, 4)
		idLabel.Size = UDim2.fromOffset(120, 12)
		idLabel.TextSize = 10

		local oddsLabel = createLabel(row, "Odds", "", 14, MUTED)
		oddsLabel.Position = UDim2.new(1, -104, 0, 4)
		oddsLabel.Size = UDim2.fromOffset(96, 12)
		oddsLabel.TextXAlignment = Enum.TextXAlignment.Right
		oddsLabel.TextSize = 10
		oddsLabels[index] = oddsLabel

		local rowGrid = Instance.new("Frame")
		rowGrid.Name = "Fields"
		rowGrid.BackgroundTransparency = 1
		rowGrid.Position = UDim2.fromOffset(26, 18)
		rowGrid.Size = UDim2.new(1, -34, 0, 40)
		rowGrid.Parent = row
		local rowLayout = Instance.new("UIGridLayout")
		rowLayout.CellPadding = UDim2.fromOffset(6, 0)
		rowLayout.CellSize = UDim2.new(0.2, -6, 0, 36)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = rowGrid

		textField(rowGrid, "DisplayName", "Name", function()
			return rarity.name
		end, function(value)
			rarity.name = value
		end)
		numberField(rowGrid, "Weight", "Weight /10000", function()
			return rarity.weight
		end, function(value)
			if value ~= nil then
				rarity.weight = math.floor(value)
			end
			local repaint = Refresh.odds
			if repaint ~= nil then
				repaint()
			end
		end, false)
		for channelIndex, channelName in { "R", "G", "B" } do
			numberField(rowGrid, `Color{channelName}`, channelName, function()
				return rarity.color[channelIndex]
			end, function(value)
				if value ~= nil then
					rarity.color[channelIndex] = math.clamp(math.floor(value), 0, 255)
					swatch.BackgroundColor3 =
						Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
				end
			end, false)
		end
	end

	Refresh.odds = function()
		local total = Val.weightTotal()
		local ok = total == 10000
		totalLabel.Text = if ok
			then "Weight total: 10000 — odds disclose correctly"
			else `Weight total: {total} — must equal 10000`
		totalLabel.TextColor3 = if ok then GOOD else AMBER
		for index, rarity in State.rarities do
			local label = oddsLabels[index]
			if label ~= nil then
				label.Text = if total > 0
					then `{math.floor(rarity.weight / total * 10000) / 100}% odds`
					else ""
			end
		end
	end

	local normalizeButton = createButton(raritiesSection, "Normalize", "Normalize Weights to 10000", 30)
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
		setStatus("Weights rescaled. Nudge individual rows, then Apply.", GOOD)
	end)

	-- Section: runes ----------------------------------------------------------
	local runesSection = createSection(
		scroll,
		"Runes",
		"Rune Cards",
		"The collection itself: glyph icon, display name, permanent bonus %, rarity, and flavor. Every rarity needs at least one card."
	)
	local runesList = Instance.new("Frame")
	runesList.Name = "RunesList"
	runesList.BackgroundTransparency = 1
	runesList.Size = UDim2.fromScale(1, 0)
	runesList.AutomaticSize = Enum.AutomaticSize.Y
	runesList.Parent = runesSection
	local runesLayout = Instance.new("UIListLayout")
	runesLayout.Padding = UDim.new(0, 6)
	runesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	runesLayout.Parent = runesList

	local function buildRuneRow(index: number, rune: RuneRow)
		local row = Instance.new("Frame")
		row.Name = `Rune{index}`
		row.BackgroundColor3 = PANEL_FIELD
		row.BorderSizePixel = 0
		row.Size = UDim2.fromScale(1, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = index
		row.Parent = runesList
		round(row, 7)
		outline(row, 0.6)
		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingTop = UDim.new(0, 6)
		rowPadding.PaddingBottom = UDim.new(0, 6)
		rowPadding.PaddingLeft = UDim.new(0, 6)
		rowPadding.PaddingRight = UDim.new(0, 6)
		rowPadding.Parent = row
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row

		local topGrid = createGrid(row, "Top", 4, 36)
		textField(topGrid, "Glyph", "Glyph / icon", function()
			return rune.glyph
		end, function(value)
			rune.glyph = value
		end)
		textField(topGrid, "DisplayName", "Name", function()
			return rune.name
		end, function(value)
			rune.name = value
		end)
		numberField(topGrid, "Bonus", "Bonus %", function()
			return rune.bonusPercent
		end, function(value)
			if value ~= nil then
				rune.bonusPercent = value
			end
		end, false)
		cycleField(topGrid, "Rarity", "Rarity", rarityIds, function()
			return rune.rarityId
		end, function(value)
			rune.rarityId = value
		end)

		local bottomGrid = createGrid(row, "Bottom", 3, 36)
		textField(bottomGrid, "Id", "Id (saves key on this)", function()
			return rune.id
		end, function(value)
			rune.id = string.lower(value)
		end)
		textField(bottomGrid, "Flavor", "Flavor text", function()
			return rune.flavor
		end, function(value)
			rune.flavor = value
		end)
		local removeButton = createButton(bottomGrid, "Remove", "Remove Card", 36)
		removeButton.TextColor3 = BAD
		removeButton.MouseButton1Click:Connect(function()
			table.remove(State.runes, table.find(State.runes, rune) or index)
			local repaint = Refresh.runesList
			if repaint ~= nil then
				repaint()
			end
			setStatus(
				`Removed {rune.name}. Existing saves keep the copies; they simply stop counting.`,
				MUTED
			)
		end)
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
	end

	local addRuneButton = createButton(runesSection, "AddRune", "Add Rune Card", 30)
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
	end)

	-- Section: workflow help ---------------------------------------------------
	createSection(
		scroll,
		"Workflow",
		"How Applying Works",
		"Apply rewrites this place's DesignerConfig (runes overrides) and RuneCatalog ModuleScripts — undo-safe, playtest-ready, nothing publishes. Print Sources emits both files to Output so you can paste them into the repo. Changing a rune id orphans saved copies: they stay in player data but stop counting until the id returns."
	)

	applyButton.MouseButton1Click:Connect(applyToPlace)
	printButton.MouseButton1Click:Connect(printSources)
end

local loadedOk, loadProblem = Load.fromPlace()
buildPanel()
if loadedOk then
	setStatus("Loaded live values. Edit, then Apply to Place.", GOOD)
	local repaintOdds = Refresh.odds
	if repaintOdds ~= nil then
		repaintOdds()
	end
	local repaintRunes = Refresh.runesList
	if repaintRunes ~= nil then
		repaintRunes()
	end
else
	setStatus(loadProblem or "Rune configuration unavailable in this place.", AMBER)
end

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	openButton:SetActive(widget.Enabled)
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
end)

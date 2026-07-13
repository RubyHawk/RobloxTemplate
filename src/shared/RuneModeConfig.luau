--!strict

-- Channel-mode and copy-milestone configuration for the rune altar. Kept
-- dependency-free like CurrencyConfig so TemplateConfig can normalize recipe
-- overrides and the Lune specs can exercise every validation branch without a
-- Roblox runtime.
--
-- Unlike currencies (where a bad entry is skipped), a mode registry is
-- all-or-nothing: a partially applied list could strand a player's persisted
-- mode selection or hide the default, so any structural problem falls back to
-- the authored defaults wholesale.

local RuneModeConfig = {}

RuneModeConfig.MAX_MODES = 4 -- matches the pre-authored ModeButton slots
RuneModeConfig.MAX_TIERS = 8
RuneModeConfig.MAX_MILESTONES = 8
RuneModeConfig.MAX_VALUE = 1000

export type ModeTier = {
	atSeconds: number,
	value: number,
}

export type ModeUnlock = {
	kind: string, -- "always" | "totalRolls" | "runesOwned" | "provider"
	value: number,
}

export type ChannelMode = {
	id: string,
	name: string,
	kind: string, -- "luck" | "surge"
	unlock: ModeUnlock,
	tiers: { ModeTier },
}

export type CopyMilestone = {
	copies: number,
	multiplier: number,
}

local MODE_KINDS: { [string]: boolean } = {
	luck = true,
	surge = true,
}

local UNLOCK_KINDS: { [string]: boolean } = {
	always = true,
	totalRolls = true,
	runesOwned = true,
	provider = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function copyModes(modes: { ChannelMode }): { ChannelMode }
	local result: { ChannelMode } = {}
	for _, mode in modes do
		local tiers: { ModeTier } = {}
		for _, tier in mode.tiers do
			table.insert(tiers, { atSeconds = tier.atSeconds, value = tier.value })
		end
		table.insert(result, {
			id = mode.id,
			name = mode.name,
			kind = mode.kind,
			unlock = { kind = mode.unlock.kind, value = mode.unlock.value },
			tiers = tiers,
		})
	end
	return result
end

local function copyMilestones(milestones: { CopyMilestone }): { CopyMilestone }
	local result: { CopyMilestone } = {}
	for _, milestone in milestones do
		table.insert(result, { copies = milestone.copies, multiplier = milestone.multiplier })
	end
	return result
end

-- Tier thresholds must strictly rise and tier values must stay in
-- [1, MAX_VALUE] so momentum can only ever help.
local function normalizedTiers(raw: any): { ModeTier }?
	if type(raw) ~= "table" or #raw < 1 or #raw > RuneModeConfig.MAX_TIERS then
		return nil
	end
	local tiers: { ModeTier } = {}
	local previousAt = 0
	for _, candidate in raw do
		if type(candidate) ~= "table" then
			return nil
		end
		local atSeconds = candidate.atSeconds
		local value = candidate.value
		if not isFiniteNumber(atSeconds) or atSeconds <= previousAt then
			return nil
		end
		if not isFiniteNumber(value) or value < 1 or value > RuneModeConfig.MAX_VALUE then
			return nil
		end
		previousAt = atSeconds
		table.insert(tiers, { atSeconds = atSeconds, value = value })
	end
	return tiers
end

local function normalizedUnlock(raw: any): ModeUnlock?
	if raw == nil then
		return { kind = "always", value = 0 }
	end
	if type(raw) ~= "table" or UNLOCK_KINDS[raw.kind] ~= true then
		return nil
	end
	local kind = raw.kind :: string
	if kind == "totalRolls" or kind == "runesOwned" then
		local value = raw.value
		if not isFiniteNumber(value) or value < 0 then
			return nil
		end
		return { kind = kind, value = math.floor(value) }
	end
	return { kind = kind, value = 0 }
end

function RuneModeConfig.normalize(raw: any, fallback: { ChannelMode }): { ChannelMode }
	if type(raw) ~= "table" then
		return copyModes(fallback)
	end
	local modes: { ChannelMode } = {}
	local used: { [string]: boolean } = {}
	for _, candidate in raw do
		if #modes >= RuneModeConfig.MAX_MODES then
			break
		end
		if type(candidate) ~= "table" then
			return copyModes(fallback)
		end
		local id = candidate.id
		if
			type(id) ~= "string"
			or #id < 1
			or #id > 24
			or string.match(id, "^[a-z][a-z0-9_]*$") == nil
			or used[id]
		then
			return copyModes(fallback)
		end
		if MODE_KINDS[candidate.kind] ~= true then
			return copyModes(fallback)
		end
		local unlock = normalizedUnlock(candidate.unlock)
		local tiers = normalizedTiers(candidate.tiers)
		if unlock == nil or tiers == nil then
			return copyModes(fallback)
		end
		local name = if type(candidate.name) == "string"
				and #candidate.name >= 1
				and #candidate.name <= 32
			then candidate.name
			else id
		used[id] = true
		table.insert(modes, {
			id = id,
			name = name,
			kind = candidate.kind :: string,
			unlock = unlock,
			tiers = tiers,
		})
	end
	if #modes == 0 then
		return copyModes(fallback)
	end
	return modes
end

-- Copy milestones must strictly rise in copies and never weaken, so owning
-- more duplicates can only ever help. An explicit empty table is a valid way
-- for a recipe to disable milestones entirely.
function RuneModeConfig.normalizeMilestones(raw: any, fallback: { CopyMilestone }): { CopyMilestone }
	if type(raw) ~= "table" then
		return copyMilestones(fallback)
	end
	local milestones: { CopyMilestone } = {}
	local previousCopies = 1
	local previousMultiplier = 1
	for _, candidate in raw do
		if #milestones >= RuneModeConfig.MAX_MILESTONES then
			break
		end
		if type(candidate) ~= "table" then
			return copyMilestones(fallback)
		end
		local copies = candidate.copies
		local multiplier = candidate.multiplier
		if not isFiniteNumber(copies) or math.floor(copies) < 2 or math.floor(copies) <= previousCopies then
			return copyMilestones(fallback)
		end
		if
			not isFiniteNumber(multiplier)
			or multiplier < previousMultiplier
			or multiplier > RuneModeConfig.MAX_VALUE
		then
			return copyMilestones(fallback)
		end
		previousCopies = math.floor(copies)
		previousMultiplier = multiplier
		table.insert(milestones, { copies = previousCopies, multiplier = multiplier })
	end
	return milestones
end

return table.freeze(RuneModeConfig)

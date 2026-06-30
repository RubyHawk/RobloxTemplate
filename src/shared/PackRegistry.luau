--!strict

-- Registry of UI packs. A pack is frozen data (see src/shared/packs/*) that maps
-- the finite slots inside a complete physical HUD root to player-state paths. The active
-- pack is chosen per game via Config.ui.defaultPackId, or per player via
-- profile.selectedPack when Config.ui.allowPlayerPackSelection is on.

local Config = require(script.Parent.TemplateConfig)
local Types = require(script.Parent.Types)
local PackValidation = require(script.Parent.PackValidation)

type PackDescriptor = Types.PackDescriptor

local packs: { [string]: PackDescriptor } = {
	incremental = require(script.Parent.packs.IncrementalPack),
	combat = require(script.Parent.packs.CombatPack),
}

local PackRegistry = {}

function PackRegistry.all(): { [string]: PackDescriptor }
	return packs
end

function PackRegistry.default(): PackDescriptor
	return packs[Config.ui.defaultPackId] or packs.incremental
end

-- Never errors: an unknown id falls back to the configured default, mirroring
-- IconCatalog's fallback philosophy so a bad save can't break the HUD.
function PackRegistry.get(id: string?): PackDescriptor
	if id ~= nil and id ~= "" and packs[id] then
		return packs[id]
	end
	return PackRegistry.default()
end

-- Resolves the active pack for a profile, honoring per-player selection only
-- when the game allows it.
function PackRegistry.resolveFor(profile: any): PackDescriptor
	if Config.ui.allowPlayerPackSelection and type(profile) == "table" then
		return PackRegistry.get(profile.selectedPack)
	end
	return PackRegistry.default()
end

-- Validates a descriptor against the authored pool bounds and its own references,
-- delegating to the pure PackValidation module (which the Lune suite tests). Used
-- at startup so a malformed pack surfaces loudly instead of half-binding.
function PackRegistry.validate(descriptor: PackDescriptor): (boolean, string?)
	return PackValidation.check(descriptor, {
		stat = Config.ui.statWidgetPoolSize,
		action = Config.ui.actionSlotPoolSize,
		progress = Config.ui.progressBarPoolSize,
	})
end

return PackRegistry

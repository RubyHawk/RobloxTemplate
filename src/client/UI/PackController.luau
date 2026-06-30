--!strict

-- Orchestrates the active UI pack: resolves it from the server snapshot, resolves
-- its physical authored root, feeds the reactive Store, binds that root via
-- WidgetBinder, gates which nav screens are reachable, hides the legacy single
-- currency pill, and routes widget actions. Keeps init.client.luau thin and holds
-- every pack-specific decision in one place.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local PackRegistry = require(Shared.PackRegistry)

local Store = require(script.Parent.Store)
local WidgetBinder = require(script.Parent.WidgetBinder)
local VitalsFeeder = require(script.Parent.VitalsFeeder)

local PackController = {}
PackController.__index = PackController

local STAMINA_PER_ABILITY = 25

-- Flattens the server snapshot into the dotted-path view the HUD binds against,
-- with safe fallbacks so a missing field never errors a widget.
local function buildView(snapshot: any): { [string]: any }
	local profile = snapshot.profile
	local multiplier = (1 + (snapshot.friendBonus or 0) + (snapshot.premiumBonus or 0))
		* (snapshot.potionMultiplier or 1)
	return {
		currencies = profile.currencies or { coins = profile.coins or 0 },
		multiplier = multiplier,
		daily = { streak = if profile.daily then profile.daily.streak else 0 },
		progress = profile.progress or { rebirths = 0, prestige = 0, objectives = {} },
		stats = profile.stats,
		friends = if profile.social then profile.social.friendCountInServer else 0,
	}
end

function PackController.start(options: any): any
	local self = setmetatable({
		options = options,
		store = Store.new(),
		binder = WidgetBinder.new(options.root),
		descriptor = nil :: any,
		vitals = nil :: any,
		cooldownActive = {} :: { [number]: boolean },
		cooldownTokens = {} :: { [number]: number },
		started = false,
	}, PackController)
	return self
end

function PackController.applySnapshot(self: any, snapshot: any)
	if snapshot == nil or snapshot.profile == nil then
		return
	end
	self.store:set(buildView(snapshot))
	if not self.started then
		self.started = true
		self:initPack(snapshot)
	end
end

function PackController.initPack(self: any, snapshot: any)
	local descriptor = PackRegistry.get(snapshot.packId)
	local ok, reason = PackRegistry.validate(descriptor)
	if not ok then
		warn(`[PackController] pack "{descriptor.id}" is invalid: {reason}; using default`)
		descriptor = PackRegistry.default()
	end
	self.descriptor = descriptor

	if descriptor.localFeeds and descriptor.localFeeds.health then
		self.vitals = VitalsFeeder.start(self.store)
	end

	self.binder:bind(descriptor, self.store, function(binding)
		self:onAction(binding)
	end)

	self:applyChrome()
end

-- Hides the legacy currency pill (the pack's StatRail replaces it) and gates nav
-- buttons to the pack's enabled screens. All toggling of pre-authored instances.
function PackController.applyChrome(self: any)
	if self.options.legacyHud then
		self.options.legacyHud.Visible = false
	end

	local allowed: { [string]: boolean } = {}
	for _, screen in self.descriptor.screens do
		allowed[screen] = true
	end
	local navButtons = self.options.navButtons or {}
	for screenName, button in navButtons do
		if button and button:IsA("GuiObject") then
			button.Visible = allowed[screenName] == true
		end
	end
end

function PackController.onAction(self: any, binding: any)
	if self.options.playClick then
		self.options.playClick()
	end
	if binding.action == "OpenScreen" and binding.screen then
		self.options.openScreen(binding.screen)
	elseif binding.action == "Ability" then
		self:triggerAbility(binding)
	else
		self.options.request(binding.action, { value = binding.value })
	end
end

function PackController.triggerAbility(self: any, binding: any)
	local slot = binding.slot
	if self.cooldownActive[slot] then
		return
	end
	if self.vitals then
		self.vitals:drainStamina(STAMINA_PER_ABILITY)
	end
	local duration = binding.cooldown or 0
	if duration <= 0 then
		return
	end

	self.cooldownActive[slot] = true
	self.cooldownTokens[slot] = (self.cooldownTokens[slot] or 0) + 1
	local token = self.cooldownTokens[slot]
	task.spawn(function()
		local elapsed = 0
		self.binder:setCooldown(slot, 1)
		while elapsed < duration and token == self.cooldownTokens[slot] do
			task.wait(0.05)
			elapsed += 0.05
			self.binder:setCooldown(slot, 1 - elapsed / duration)
		end
		if token == self.cooldownTokens[slot] then
			self.binder:setCooldown(slot, 0)
			self.cooldownActive[slot] = false
		end
	end)
end

function PackController.stop(self: any)
	self.binder:unbind()
	if self.vitals then
		self.vitals:stop()
	end
end

return PackController

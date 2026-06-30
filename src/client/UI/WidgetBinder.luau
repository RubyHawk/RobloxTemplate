--!strict

-- Generalizes the old hardcoded HUD block (and the Screens slot-pool pattern) into
-- a data-driven binder over a finite pool of PRE-AUTHORED widget slots. It only
-- reads authored instances and sets text/image/colour/size/visibility plus wires
-- one Activated handler per action slot -- it never creates, clones, or destroys
-- a GuiObject. A pack descriptor decides which slots are shown and what each binds
-- to, so different games get different HUDs with zero new instances.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local IconCatalog = require(Shared.IconCatalog)

local Store = require(script.Parent.Store)
local UIFactory = require(script.Parent.UIFactory)
local ThemeProvider = require(script.Parent.ThemeProvider)

type IconName = IconCatalog.IconName

local WidgetBinder = {}
WidgetBinder.__index = WidgetBinder

export type WidgetBinder = typeof(setmetatable(
	{} :: {
		statRail: Frame,
		progressRail: Frame,
		actionRail: Frame,
		statSlots: { Frame },
		progressSlots: { Frame },
		actionSlots: { TextButton },
		cleanup: { () -> () },
		actionConnections: { [number]: RBXScriptConnection },
	},
	WidgetBinder
))

local function child(parent: Instance, name: string): Instance
	return parent:WaitForChild(name)
end

local function numbered(parent: Instance, prefix: string, count: number): { any }
	local values = {}
	for index = 1, count do
		table.insert(values, child(parent, `{prefix}{string.format("%02d", index)}`))
	end
	return values
end

local function findGui(parent: Instance, name: string): GuiObject?
	local value = parent:FindFirstChild(name)
	return if value and value:IsA("GuiObject") then value else nil
end

local function formatValue(kind: string?, value: any): string
	local number = tonumber(value) or 0
	if kind == "raw" then
		return tostring(math.floor(number))
	elseif kind == "percent" then
		return `{math.floor(number * 100)}%`
	elseif kind == "ratio" then
		return `x{string.format("%.2f", number)}`
	elseif kind == "time" then
		local minutes = math.floor(number / 60)
		local seconds = math.floor(number % 60)
		return string.format("%d:%02d", minutes, seconds)
	end
	return UIFactory.formatNumber(number)
end

local function applyIcon(container: Instance, iconName: string?)
	local icon = findGui(container, "Icon")
	local symbol = findGui(container, "Symbol") or findGui(container, "Label")
	local image = if iconName ~= nil and iconName ~= "" then IconCatalog.get(iconName :: IconName) else ""
	if icon and icon:IsA("ImageLabel") then
		icon.Image = image
		icon.Visible = image ~= ""
	end
	if symbol and symbol:IsA("GuiObject") and findGui(container, "Symbol") == symbol then
		symbol.Visible = image == ""
	end
end

function WidgetBinder.new(root: Frame): WidgetBinder
	local statRail = child(root, "StatRail") :: Frame
	local progressRail = child(root, "ProgressRail") :: Frame
	local actionRail = child(root, "ActionRail") :: Frame
	return setmetatable({
		statRail = statRail,
		progressRail = progressRail,
		actionRail = actionRail,
		statSlots = numbered(statRail, "StatWidget", Config.ui.statWidgetPoolSize),
		progressSlots = numbered(progressRail, "ProgressBar", Config.ui.progressBarPoolSize),
		actionSlots = numbered(actionRail, "ActionSlot", Config.ui.actionSlotPoolSize),
		cleanup = {},
		actionConnections = {},
	}, WidgetBinder)
end

local function hideAll(slots: { any })
	for _, slot in slots do
		slot.Visible = false
	end
end

-- Tears down subscriptions/connections from a previous pack before re-binding.
function WidgetBinder.unbind(self: WidgetBinder)
	for _, dispose in self.cleanup do
		dispose()
	end
	table.clear(self.cleanup)
	for _, connection in self.actionConnections do
		connection:Disconnect()
	end
	table.clear(self.actionConnections)
end

local function bindStat(self: WidgetBinder, slot: Frame, binding: any, store: Store.Store, theme: any)
	local valueLabel = findGui(slot, "Value")
	local captionLabel = findGui(slot, "Caption")
	local bar = findGui(slot, "Bar")
	local fill = if bar then findGui(bar, "Fill") else nil
	local color = ThemeProvider.color(theme, binding.color, "text")

	applyIcon(slot, binding.icon)
	slot.BackgroundColor3 = theme.colors.surface
	if captionLabel and captionLabel:IsA("TextLabel") then
		captionLabel.Text = binding.caption or ""
		captionLabel.TextColor3 = theme.colors.textMuted
	end
	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.TextColor3 = color
	end

	local function readValue(): number
		return tonumber(store:get(binding.path, binding.default or 0)) or 0
	end
	local function update()
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = formatValue(binding.format, readValue())
		end
		if bar and binding.bar and fill and fill:IsA("GuiObject") then
			local maxValue = binding.bar.max
			if binding.bar.maxPath then
				maxValue = tonumber(store:get(binding.bar.maxPath, maxValue or 1))
			end
			maxValue = if maxValue and maxValue > 0 then maxValue else 1
			local fraction = math.clamp(readValue() / maxValue, 0, 1)
			fill.Size = UDim2.new(fraction, 0, 1, 0)
			fill.BackgroundColor3 = ThemeProvider.color(theme, binding.bar.color or binding.color, "primary")
		end
	end

	if bar then
		bar.Visible = binding.bar ~= nil
	end
	table.insert(self.cleanup, store:subscribe(binding.path, update))
	if binding.bar and binding.bar.maxPath then
		table.insert(self.cleanup, store:subscribe(binding.bar.maxPath, update))
	end
	slot.Visible = true
end

function WidgetBinder.bind(
	self: WidgetBinder,
	descriptor: any,
	store: Store.Store,
	theme: any,
	onAction: (any) -> ()
)
	WidgetBinder.unbind(self)

	self.statRail.Visible = true
	self.progressRail.Visible = true
	self.actionRail.Visible = true
	hideAll(self.statSlots)
	hideAll(self.progressSlots)
	hideAll(self.actionSlots)

	for _, binding in descriptor.hud.stats do
		local slot = self.statSlots[binding.slot]
		if slot then
			bindStat(self, slot, binding, store, theme)
		end
	end

	for _, binding in descriptor.hud.progress or {} do
		local slot = self.progressSlots[binding.slot]
		if slot then
			bindStat(self, slot, binding, store, theme)
		end
	end

	for _, binding in descriptor.hud.actions do
		local slot = self.actionSlots[binding.slot]
		if slot then
			local label = findGui(slot, "Label")
			applyIcon(slot, binding.icon)
			slot.BackgroundColor3 = ThemeProvider.color(theme, binding.color, "primary")
			if label and label:IsA("TextLabel") then
				label.Text = binding.label
				label.TextColor3 = theme.colors.text
			end
			local capturedBinding = binding
			self.actionConnections[binding.slot] = slot.Activated:Connect(function()
				onAction(capturedBinding)
			end)
			slot.Visible = true
		end
	end
end

-- Drives an ActionSlot's CooldownFill (0 = ready, 1 = full cooldown).
function WidgetBinder.setCooldown(self: WidgetBinder, slotIndex: number, fraction: number)
	local slot = self.actionSlots[slotIndex]
	if not slot then
		return
	end
	local fill = findGui(slot, "CooldownFill")
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.new(1, 0, math.clamp(fraction, 0, 1), 0)
	end
end

return WidgetBinder

--!strict

-- Binds data to one of several PHYSICALLY AUTHORED HUD roots. Every pack owns
-- its own editable geometry, colors, strokes, icons, and layout under
-- StarterGui.TemplateUI.Root.PackRoots. Runtime only selects a root, replaces
-- content, changes progress fill sizes, toggles authored slots, and connects
-- actions. It never constructs, clones, destroys, or code-themes GuiObjects.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local IconCatalog = require(Shared.IconCatalog)

local Store = require(script.Parent.Store)
local UIFactory = require(script.Parent.UIFactory)

type IconName = IconCatalog.IconName

local WidgetBinder = {}
WidgetBinder.__index = WidgetBinder

export type WidgetBinder = typeof(setmetatable(
	{} :: {
		packRoots: Frame,
		activeRoot: Frame?,
		statSlots: { Frame },
		progressSlots: { Frame },
		actionSlots: { TextButton },
		cleanup: { () -> () },
		actionConnections: { [number]: RBXScriptConnection },
	},
	WidgetBinder
))

local function frame(parent: Instance, name: string): Frame
	local value = parent:WaitForChild(name)
	assert(value:IsA("Frame"), `{value:GetFullName()} must be a Frame`)
	return value
end

local function numberedFrames(parent: Instance, prefix: string, count: number): { Frame }
	local values = {}
	for index = 1, count do
		table.insert(values, frame(parent, `{prefix}{string.format("%02d", index)}`))
	end
	return values
end

local function numberedButtons(parent: Instance, prefix: string, count: number): { TextButton }
	local values = {}
	for index = 1, count do
		local value = parent:WaitForChild(`{prefix}{string.format("%02d", index)}`)
		assert(value:IsA("TextButton"), `{value:GetFullName()} must be a TextButton`)
		table.insert(values, value)
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
	local symbol = findGui(container, "Symbol")
	local image = if iconName ~= nil and iconName ~= "" then IconCatalog.get(iconName :: IconName) else ""
	if icon and icon:IsA("ImageLabel") then
		icon.Image = image
		icon.Visible = image ~= ""
	end
	if symbol then
		symbol.Visible = image == ""
	end
end

function WidgetBinder.new(root: Frame): WidgetBinder
	return setmetatable({
		packRoots = frame(root, "PackRoots"),
		activeRoot = nil,
		statSlots = {},
		progressSlots = {},
		actionSlots = {},
		cleanup = {},
		actionConnections = {},
	}, WidgetBinder)
end

local function hideAll(values: { any })
	for _, value in values do
		value.Visible = false
	end
end

function WidgetBinder.unbind(self: WidgetBinder)
	for _, dispose in self.cleanup do
		dispose()
	end
	table.clear(self.cleanup)
	for _, connection in self.actionConnections do
		connection:Disconnect()
	end
	table.clear(self.actionConnections)
	if self.activeRoot then
		self.activeRoot.Visible = false
	end
end

function WidgetBinder.selectRoot(self: WidgetBinder, descriptor: any)
	for _, candidate in self.packRoots:GetChildren() do
		if candidate:IsA("GuiObject") then
			candidate.Visible = false
		end
	end
	local selected = frame(self.packRoots, descriptor.authoredRoot)
	local statRail = frame(selected, "StatRail")
	local progressRail = frame(selected, "ProgressRail")
	local actionRail = frame(selected, "ActionRail")
	self.activeRoot = selected
	self.statSlots = numberedFrames(statRail, "StatWidget", Config.ui.statWidgetPoolSize)
	self.progressSlots = numberedFrames(progressRail, "ProgressBar", Config.ui.progressBarPoolSize)
	self.actionSlots = numberedButtons(actionRail, "ActionSlot", Config.ui.actionSlotPoolSize)
	selected.Visible = true
	statRail.Visible = true
	progressRail.Visible = true
	actionRail.Visible = true
end

local function bindStat(self: WidgetBinder, slot: Frame, binding: any, store: Store.Store)
	local valueLabel = findGui(slot, "Value")
	local captionLabel = findGui(slot, "Caption")
	local bar = findGui(slot, "Bar")
	local fill = if bar then findGui(bar, "Fill") else nil

	applyIcon(slot, binding.icon)
	if captionLabel and captionLabel:IsA("TextLabel") then
		captionLabel.Text = binding.caption or ""
	end

	local function readValue(): number
		return tonumber(store:get(binding.path, binding.default or 0)) or 0
	end
	local function update()
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = formatValue(binding.format, readValue())
		end
		if bar and binding.bar and fill then
			local maxValue = binding.bar.max
			if binding.bar.maxPath then
				maxValue = tonumber(store:get(binding.bar.maxPath, maxValue or 1))
			end
			maxValue = if maxValue and maxValue > 0 then maxValue else 1
			fill.Size = UDim2.fromScale(math.clamp(readValue() / maxValue, 0, 1), 1)
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

function WidgetBinder.bind(self: WidgetBinder, descriptor: any, store: Store.Store, onAction: (any) -> ())
	WidgetBinder.unbind(self)
	WidgetBinder.selectRoot(self, descriptor)
	hideAll(self.statSlots)
	hideAll(self.progressSlots)
	hideAll(self.actionSlots)

	for _, binding in descriptor.hud.stats do
		local slot = self.statSlots[binding.slot]
		if slot then
			bindStat(self, slot, binding, store)
		end
	end

	for _, binding in descriptor.hud.progress or {} do
		local slot = self.progressSlots[binding.slot]
		if slot then
			bindStat(self, slot, binding, store)
		end
	end

	for _, binding in descriptor.hud.actions do
		local slot = self.actionSlots[binding.slot]
		if slot then
			local label = findGui(slot, "Label")
			applyIcon(slot, binding.icon)
			if label and label:IsA("TextLabel") then
				label.Text = binding.label
			end
			local capturedBinding = binding
			self.actionConnections[binding.slot] = slot.Activated:Connect(function()
				onAction(capturedBinding)
			end)
			slot.Visible = true
		end
	end
end

function WidgetBinder.setCooldown(self: WidgetBinder, slotIndex: number, fraction: number)
	local slot = self.actionSlots[slotIndex]
	if not slot then
		return
	end
	local fill = findGui(slot, "CooldownFill")
	if fill then
		fill.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
	end
end

return WidgetBinder

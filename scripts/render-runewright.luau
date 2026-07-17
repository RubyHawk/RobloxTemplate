--!strict
-- Headless visual verification for the Runewright Studio plugin.
--
-- Runs the real plugin source (src/plugins/RunewrightPlugin.server.luau)
-- against a stub of the Roblox plugin/Instance surface it uses, drives it the
-- way a designer would (tab clicks, text edits with focus-lost commits),
-- asserts the structural contract (tabs, segmented controls, toggle switches,
-- progressive tier rows, odds bar, glyph previews), then lays the resulting
-- tree out with a small UIListLayout/UIGridLayout engine and emits one HTML
-- page per tab so Chromium can screenshot what the panel actually looks like.
--
--   lune run scripts/render-runewright.luau [outputDirectory]
--
-- The output directory (default build/runewright-render) receives
-- tab-<n>-<name>.html files; screenshot them with any headless browser.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local RuneCatalog = require("../src/shared/RuneCatalog")
local DesignerConfig = require("../src/shared/DesignerConfig")

local OUTPUT_DIRECTORY = process.args[1] or "build/runewright-render"

-- ---------------------------------------------------------------------------
-- Roblox datatype stubs (only what the plugin touches)
-- ---------------------------------------------------------------------------

type AnyTable = { [any]: any }

local Color3Meta = {}
Color3Meta.__index = {
	Lerp = function(self: AnyTable, target: AnyTable, alpha: number): AnyTable
		local function mix(a: number, b: number): number
			return a + (b - a) * alpha
		end
		return setmetatable(
			{ R = mix(self.R, target.R), G = mix(self.G, target.G), B = mix(self.B, target.B) },
			Color3Meta
		)
	end,
}
Color3Meta.__eq = function(a: AnyTable, b: AnyTable): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end

local Color3Stub = {
	new = function(r: number?, g: number?, b: number?)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
	end,
	fromRGB = function(r: number, g: number, b: number)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Meta)
	end,
}

local UDimStub = {
	new = function(scale: number?, offset: number?)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}

local UDim2Stub = {}
function UDim2Stub.new(xs: number?, xo: number?, ys: number?, yo: number?)
	return {
		X = { Scale = xs or 0, Offset = xo or 0 },
		Y = { Scale = ys or 0, Offset = yo or 0 },
	}
end
function UDim2Stub.fromScale(xs: number?, ys: number?)
	return UDim2Stub.new(xs or 0, 0, ys or 0, 0)
end
function UDim2Stub.fromOffset(xo: number?, yo: number?)
	return UDim2Stub.new(0, xo or 0, 0, yo or 0)
end

local Vector2Stub = {
	new = function(x: number?, y: number?)
		return { X = x or 0, Y = y or 0 }
	end,
}

local enumCache: { [string]: AnyTable } = {}
local EnumStub = setmetatable({}, {
	__index = function(_, enumName: string)
		local class = enumCache[enumName]
		if class == nil then
			class = setmetatable({}, {
				__index = function(classTable, itemName: string)
					local token = { EnumType = enumName, Name = itemName }
					rawset(classTable :: AnyTable, itemName, token)
					return token
				end,
			})
			enumCache[enumName] = class
		end
		return class
	end,
})

-- ---------------------------------------------------------------------------
-- Instances and signals
-- ---------------------------------------------------------------------------

local function newSignal(): AnyTable
	local signal = { handlers = {} :: { (...any) -> () } }
	function signal.Connect(_: AnyTable, handler: (...any) -> ())
		table.insert(signal.handlers, handler)
		return { Disconnect = function() end }
	end
	function signal.Fire(_: AnyTable, ...)
		for _, handler in signal.handlers do
			handler(...)
		end
	end
	return signal
end

local EVENT_NAMES: { [string]: boolean } = {
	MouseButton1Click = true,
	MouseEnter = true,
	MouseLeave = true,
	Focused = true,
	FocusLost = true,
	Click = true,
}

local GUI_CLASSES: { [string]: boolean } = {
	Frame = true,
	ScrollingFrame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
}

local TEXT_CLASSES: { [string]: boolean } = {
	TextLabel = true,
	TextButton = true,
	TextBox = true,
}

local instanceCounter = 0

local function newInstance(className: string): AnyTable
	instanceCounter += 1
	local props: AnyTable = {
		Name = className,
		ClassName = className,
		Parent = nil,
		Visible = true,
		ZIndex = 1,
		BackgroundTransparency = 0,
		TextTransparency = 0,
		AutomaticSize = nil,
		AnchorPoint = Vector2Stub.new(0, 0),
		Position = UDim2Stub.new(),
		Size = UDim2Stub.new(),
		Text = "",
		TextSize = 14,
		RichText = false,
		TextWrapped = false,
	}
	local inst: AnyTable = {
		_props = props,
		_children = {} :: { AnyTable },
		_signals = {} :: { [string]: AnyTable },
		_order = instanceCounter,
		_destroyed = false,
	}

	local function signalFor(key: string): AnyTable
		local signal = inst._signals[key]
		if signal == nil then
			signal = newSignal()
			inst._signals[key] = signal
		end
		return signal
	end

	local methods: AnyTable = {}
	function methods.GetChildren(_: AnyTable)
		return table.clone(inst._children)
	end
	function methods.FindFirstChild(_: AnyTable, childName: string)
		for _, child in inst._children do
			if child._props.Name == childName then
				return child
			end
		end
		return nil
	end
	methods.WaitForChild = methods.FindFirstChild
	function methods.FindFirstChildOfClass(_: AnyTable, wanted: string)
		for _, child in inst._children do
			if child._props.ClassName == wanted then
				return child
			end
		end
		return nil
	end
	function methods.IsA(_: AnyTable, wanted: string)
		if wanted == className then
			return true
		end
		if wanted == "Instance" then
			return true
		end
		if wanted == "GuiObject" or wanted == "GuiBase2d" then
			return GUI_CLASSES[className] == true
		end
		return false
	end
	function methods.Destroy(_: AnyTable)
		local parent = props.Parent
		if parent ~= nil then
			local siblings = parent._children
			local index = table.find(siblings, inst)
			if index ~= nil then
				table.remove(siblings, index)
			end
		end
		props.Parent = nil
		inst._destroyed = true
	end
	function methods.GetPropertyChangedSignal(_: AnyTable, propertyName: string)
		return signalFor(`PropertyChanged:{propertyName}`)
	end
	function methods.IsFocused(_: AnyTable)
		return false
	end
	function methods.SetActive(_: AnyTable, _active: boolean) end

	setmetatable(inst, {
		__index = function(_, key: string)
			if methods[key] ~= nil then
				return methods[key]
			end
			if EVENT_NAMES[key] then
				return signalFor(key)
			end
			return props[key]
		end,
		__newindex = function(_, key: string, value: any)
			if key == "Parent" then
				local previous = props.Parent
				if previous ~= nil then
					local siblings = previous._children
					local index = table.find(siblings, inst)
					if index ~= nil then
						table.remove(siblings, index)
					end
				end
				props.Parent = value
				if value ~= nil then
					table.insert(value._children, inst)
				end
				return
			end
			props[key] = value
		end,
	})
	return inst
end

-- ---------------------------------------------------------------------------
-- Place stub: ReplicatedStorage.Template.Shared with the real config data
-- ---------------------------------------------------------------------------

-- TemplateConfig itself requires siblings via script.Parent, which Lune cannot
-- resolve, so the harness rebuilds its runes table from the same authored
-- defaults (mirrors src/shared/TemplateConfig.luau).
local templateConfigRunes = {
	baseCost = 75,
	costGrowth = 1,
	maxCost = 75,
	autoRollSeconds = 2,
	firstRollChargeSeconds = 1.25,
	circlePadding = 1.5,
	circleHeightTolerance = 8,
	pityThreshold = 40,
	pityMinimumRarity = "epic",
	tickSeconds = 0.25,
	maxTotalBonusPercent = 1_000_000,
	maxOwnedPerRune = 1_000_000_000,
	maxTotalRolls = 1_000_000_000,
	revealSeconds = 3,
	rareAudioMinimumRarity = "epic",
	minCommonWeight = 500,
	defaultChannelMode = "luck",
	channelModes = {
		{
			id = "luck",
			name = "Lucky Channel",
			kind = "luck",
			unlock = { kind = "always", value = 0 },
			tiers = {
				{ atSeconds = 10, value = 1.25 },
				{ atSeconds = 30, value = 1.75 },
				{ atSeconds = 60, value = 2.5 },
			},
		},
		{
			id = "surge",
			name = "Coin Surge",
			kind = "surge",
			unlock = { kind = "totalRolls", value = 25 },
			tiers = {
				{ atSeconds = 10, value = 1.25 },
				{ atSeconds = 30, value = 1.5 },
				{ atSeconds = 60, value = 2 },
			},
		},
	},
	copyMilestones = {
		{ copies = 5, multiplier = 1.25 },
		{ copies = 10, multiplier = 1.5 },
		{ copies = 25, multiplier = 2 },
	},
}

local moduleTables: { [AnyTable]: any } = {}

local replicatedStorage = newInstance("ReplicatedStorage")
local templateFolder = newInstance("Folder")
templateFolder.Name = "Template"
templateFolder.Parent = replicatedStorage
local sharedFolder = newInstance("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = templateFolder
for name, moduleTable in
	{
		TemplateConfig = { runes = templateConfigRunes },
		RuneCatalog = RuneCatalog,
		DesignerConfig = DesignerConfig,
	} :: { [string]: any }
do
	local moduleStub = newInstance("ModuleScript")
	moduleStub.Name = name
	moduleStub.Parent = sharedFolder
	moduleTables[moduleStub] = moduleTable
end

local services: { [string]: AnyTable } = {
	ReplicatedStorage = replicatedStorage,
	ChangeHistoryService = {
		TryBeginRecording = function()
			return "recording"
		end,
		FinishRecording = function() end,
	},
	TweenService = {
		Create = function(_, target: AnyTable, _info: any, goal: AnyTable)
			return {
				Play = function()
					for key, value in goal do
						target[key] = value
					end
				end,
			}
		end,
	},
}

local widget: AnyTable? = nil
local toolbarButton: AnyTable? = nil

local pluginStub: AnyTable = {
	CreateToolbar = function()
		return {
			CreateButton = function()
				toolbarButton = newInstance("PluginToolbarButton")
				return toolbarButton
			end,
		}
	end,
	CreateDockWidgetPluginGuiAsync = function()
		widget = newInstance("DockWidgetPluginGui")
		return widget
	end,
}

-- ---------------------------------------------------------------------------
-- Load and run the real plugin source
-- ---------------------------------------------------------------------------

local pluginSource = fs.readFile("src/plugins/RunewrightPlugin.server.luau")

local environment: AnyTable = {
	game = {
		GetService = function(_, serviceName: string)
			local service = services[serviceName]
			assert(service ~= nil, `plugin asked for unstubbed service {serviceName}`)
			return service
		end,
	},
	plugin = pluginStub,
	Instance = { new = newInstance },
	Color3 = Color3Stub,
	UDim = UDimStub,
	UDim2 = UDim2Stub,
	Vector2 = Vector2Stub,
	Enum = EnumStub,
	TweenInfo = {
		new = function()
			return {}
		end,
	},
	DockWidgetPluginGuiInfo = {
		new = function()
			return {}
		end,
	},
	task = { delay = function() end },
	require = function(moduleStub: AnyTable)
		local moduleTable = moduleTables[moduleStub]
		assert(moduleTable ~= nil, "plugin required an unknown module stub")
		return moduleTable
	end,
	print = print,
	warn = warn,
}

local runPlugin = luau.load(pluginSource, {
	debugName = "RunewrightPlugin",
	environment = environment,
	injectGlobals = true,
})
runPlugin()

assert(widget ~= nil, "plugin never created its dock widget")
local panelWidget = widget :: AnyTable

-- ---------------------------------------------------------------------------
-- Tree helpers, interaction simulation, structural assertions
-- ---------------------------------------------------------------------------

local failures: { string } = {}
local function check(condition: boolean, message: string)
	if condition then
		print(`  ok: {message}`)
	else
		table.insert(failures, message)
		print(`  FAIL: {message}`)
	end
end

local function child(parent: AnyTable, name: string): AnyTable
	local found = parent:FindFirstChild(name)
	assert(found ~= nil, `missing child {name} under {parent.Name}`)
	return found
end

local function descendantsNamed(rootInstance: AnyTable, name: string): { AnyTable }
	local found: { AnyTable } = {}
	local function walk(node: AnyTable)
		for _, nodeChild in node._children do
			if nodeChild._props.Name == name then
				table.insert(found, nodeChild)
			end
			walk(nodeChild)
		end
	end
	walk(rootInstance)
	return found
end

local function typeInto(box: AnyTable, text: string)
	box.Text = text
	box.FocusLost:Fire()
end

local root = child(panelWidget, "Root")
local tabBar = child(root, "TabBar")
local pageHost = child(root, "Pages")
local footer = child(root, "ActionDock")

print("structural checks:")

local tabNames = { "Altar", "Modes", "Rarity", "Runes", "Review" }
for _, tabName in tabNames do
	check(tabBar:FindFirstChild(`Tab{tabName}`) ~= nil, `tab button {tabName} exists`)
	check(pageHost:FindFirstChild(tabName) ~= nil, `page {tabName} exists`)
end
local altarIndicator = child(child(tabBar, "TabAltar"), "Indicator")
check(altarIndicator.Visible == true, "active tab carries the underline indicator")
check(child(tabBar, "TabModes"):FindFirstChild("Indicator").Visible == false, "inactive tabs hide it")

check(child(footer, "Readiness").Text == "Ready to apply — no issues.", "footer reports ready on defaults")
local actions = child(footer, "Actions")
check(child(actions, "Apply").Text == "Apply to Place", "Apply to Place present")
check(child(actions, "Print").Text == "Print Sources", "Print Sources present")
check(child(actions, "Reload").Text == "Reload", "Reload present")

-- Identity header: wordmark plus one rarity band per configured rarity.
local header = child(root, "Header")
check(child(header, "Wordmark").Text == "Runewright", "identity header shows the wordmark")
local headerBands = 0
for _, markChild in child(header, "Mark"):GetChildren() do
	if markChild._props.ClassName == "Frame" then
		headerBands += 1
	end
end
check(headerBands == 6, "header mark carries one rarity band per rarity")

-- Altar: scalar rows + entry-time range rejection.
local altarPage = child(pageHost, "Altar")
local pacing = child(altarPage, "Pacing")
local baseCostBox = child(child(pacing, "baseCost"), "Value"):FindFirstChild("Value")
check(baseCostBox.Text == "75", "Base Cost renders the loaded 75")
typeInto(baseCostBox, "0")
check(baseCostBox.Text == "75", "out-of-range Base Cost reverts at entry")
check(
	string.find(child(footer, "Status").Text, "must be between", 1, true) ~= nil,
	"rejection explains the accepted range"
)
typeInto(baseCostBox, "80")
check(baseCostBox.Text == "80", "valid Base Cost commits")
typeInto(baseCostBox, "75")

-- Modes: segmented controls, switches, progressive tier rows.
local modesPage = child(pageHost, "Modes")
local defaultTrack = child(child(modesPage, "Default"), "DefaultMode")
local defaultSegments = 0
for _, segment in defaultTrack:GetChildren() do
	if segment._props.ClassName == "TextButton" then
		defaultSegments += 1
	end
end
check(defaultSegments == 2, "default-mode segmented control offers the two enabled modes")

local modeCards = child(modesPage, "Modes")
local cardOne = child(modeCards, "ModeCard1")
local knobOne = child(child(child(cardOne, "Head"), "Enabled"), "Track"):FindFirstChild("Knob")
check(knobOne.Position.X.Offset == 18, "enabled mode switch knob sits at the on position")
local cardThree = child(modeCards, "ModeCard3")
check(child(cardThree, "Body").Visible == false, "disabled mode collapses to its header")
check(
	string.find(child(child(cardThree, "Head"), "Title").Text, "EMPTY SLOT", 1, true) ~= nil,
	"untouched slots read EMPTY SLOT"
)
local knobThree = child(child(child(cardThree, "Head"), "Enabled"), "Track"):FindFirstChild("Knob")
check(knobThree.Position.X.Offset == 2, "disabled switch knob sits at the off position")

local tiersOne = child(child(cardOne, "Body"), "Tiers")
local visibleTierRows = 0
local hiddenTierRows = 0
for rowIndex = 1, 8 do
	local row = child(tiersOne, `Row{rowIndex}`)
	if row.Visible then
		visibleTierRows += 1
	else
		hiddenTierRows += 1
	end
end
check(visibleTierRows == 4 and hiddenTierRows == 4, "3 filled tiers show plus one blank next row")
local tierFourWide = child(child(tiersOne, "Row4"), "Wide"):FindFirstChild("Value")
typeInto(tierFourWide, "120")
check(child(tiersOne, "Row5").Visible == true, "filling the blank tier row reveals the next")
typeInto(tierFourWide, "")
check(child(tiersOne, "Row5").Visible == false, "blanking it hides the follow-up row again")

local surgeThreshold = child(child(child(modeCards, "ModeCard2"), "Body"), "Threshold")
check(surgeThreshold.Visible == true, "surge unlock threshold row shows for totalRolls")
local luckThreshold = child(child(cardOne, "Body"), "Threshold")
check(luckThreshold.Visible == false, "always-unlocked mode hides the threshold row")

-- Rarity: odds bar, hex sync, live totals.
local rarityPage = child(pageHost, "Rarity")
local raritySection = child(rarityPage, "Rarities")
local oddsBar = child(raritySection, "OddsBar")
local segments = 0
local shareSum = 0
for _, barChild in oddsBar:GetChildren() do
	if barChild._props.ClassName == "Frame" then
		segments += 1
		shareSum += barChild.Size.X.Scale
	end
end
check(segments == 6, "odds bar draws one segment per rarity")
check(math.abs(shareSum - 1) < 1e-6, "odds bar segments cover the whole budget")
check(
	child(child(raritySection, "Head"), "Meta").Text == "Σ 10000 ✓ discloses correctly",
	"weight total meta reads correct"
)
local commonHexBox = child(child(raritySection, "Rgb1"), "Hex"):FindFirstChild("Value")
check(commonHexBox.Text == "#9CA3AF", "hex field renders the authored color")
typeInto(commonHexBox, "60a5fa")
check(commonHexBox.Text == "#60A5FA", "hex commits normalize to #RRGGBB")
local commonRed = child(child(raritySection, "Rgb1"), "ColorR"):FindFirstChild("Value")
check(commonRed.Text == "96", "hex edits sync the RGB channels")
typeInto(commonHexBox, "9CA3AF")
local commonWeightBox = child(child(raritySection, "Rarity1"), "Weight"):FindFirstChild("Value")
typeInto(commonWeightBox, "5000")
check(
	string.find(child(footer, "Readiness").Text, "issue", 1, true) ~= nil,
	"breaking the weight total flips the footer to issues"
)
check(
	string.find(child(tabBar, "TabRarity").Text, "1", 1, true) ~= nil,
	"the Rarity tab badges its issue count"
)
-- Click-to-fix: the footer readiness line jumps to the first issue's tab.
child(footer, "ReadinessJump").MouseButton1Click:Fire()
check(child(pageHost, "Rarity").Visible == true, "readiness line jumps to the offending tab")
-- And every Review issue row is itself a hit target that jumps to its tab.
child(tabBar, "TabReview").MouseButton1Click:Fire()
local firstIssue = child(child(child(pageHost, "Review"), "Validation"), "Issues"):FindFirstChild("Issue1")
check(firstIssue ~= nil, "Review lists the open issue as a row")
if firstIssue ~= nil then
	check(firstIssue._props.ClassName == "TextButton", "Review issue rows are clickable")
	firstIssue.MouseButton1Click:Fire()
	check(child(pageHost, "Rarity").Visible == true, "clicking a Review issue jumps to its tab")
end
typeInto(commonWeightBox, "5400")
check(child(footer, "Readiness").Text == "Ready to apply — no issues.", "fixing the weight restores ready")

-- Runes: cards, glyph image preview via the real edit path.
local runesPage = child(pageHost, "Runes")
local runesList = child(child(runesPage, "Runes"), "RunesList")
local runeCards = 0
for _, listChild in runesList:GetChildren() do
	if listChild._props.ClassName == "Frame" then
		runeCards += 1
	end
end
check(runeCards == 12, "all 12 catalog cards render")
local emberBonusBox =
	child(child(child(runesList, "Rune1"), "Content"), "Top"):FindFirstChild("Bonus"):FindFirstChild("Value")
check(emberBonusBox.Text == "2", "bonus fields render the loaded percent")
typeInto(emberBonusBox, "4")
check(emberBonusBox.Text == "4", "bonus edits commit through the numeric path")
typeInto(emberBonusBox, "2")

local stormCard = child(runesList, "Rune5")
local stormGlyphShell = child(child(stormCard, "Content"), "Top"):FindFirstChild("Glyph")
local stormGlyphBox = stormGlyphShell:FindFirstChild("Value")
local stormPreview = stormGlyphShell:FindFirstChild("GlyphPreview")
check(stormPreview.Visible == false, "emoji glyphs show no image preview")
typeInto(stormGlyphBox, "118295327505164")
check(stormPreview.Visible == true, "digit glyphs preview the Roblox image asset")
check(stormPreview.Image == "rbxassetid://118295327505164", "preview binds the rbxassetid content")
check(stormGlyphBox.TextTransparency == 1, "raw id hides behind the preview until focused")

print(`\n{#failures} structural failures`)
assert(#failures == 0, "structural checks failed:\n" .. table.concat(failures, "\n"))

-- The interaction simulations above leave their last rejection message in the
-- status line; reset it so renders show the resting state.
local statusLabel = child(footer, "Status")
statusLabel.Text = "Loaded live values. Edit any tab, then Apply to Place."
statusLabel.TextColor3 = Color3Stub.fromRGB(74, 145, 98)

-- ---------------------------------------------------------------------------
-- Layout engine (UIPadding, UIListLayout, UIGridLayout, AutomaticSize Y)
-- ---------------------------------------------------------------------------

type Rect = { x: number, y: number, w: number, h: number }

local function findLayout(node: AnyTable): (AnyTable?, AnyTable?, AnyTable?)
	local list, grid, padding
	for _, nodeChild in node._children do
		local class = nodeChild._props.ClassName
		if class == "UIListLayout" then
			list = nodeChild
		elseif class == "UIGridLayout" then
			grid = nodeChild
		elseif class == "UIPadding" then
			padding = nodeChild
		end
	end
	return list, grid, padding
end

local function paddingBox(padding: AnyTable?): (number, number, number, number)
	if padding == nil then
		return 0, 0, 0, 0
	end
	local function offsetOf(value: AnyTable?): number
		return if value ~= nil then value.Offset else 0
	end
	return offsetOf(padding.PaddingLeft),
		offsetOf(padding.PaddingTop),
		offsetOf(padding.PaddingRight),
		offsetOf(padding.PaddingBottom)
end

local function isBold(node: AnyTable): boolean
	local font = node._props.Font
	return font ~= nil and font.Name == "GothamBold"
end

local function plainText(text: string): string
	local stripped = string.gsub(text, "<[^>]->", "")
	return stripped
end

local function textWidth(node: AnyTable): number
	local size = node.TextSize or 14
	local factor = if isBold(node) then 0.64 else 0.58
	local content = plainText(node.Text or "")
	local characters = 0
	for _ in string.gmatch(content, "[%z\1-\127\194-\244][\128-\191]*") do
		characters += 1
	end
	return characters * size * factor
end

local function measureTextHeight(node: AnyTable, width: number): number
	local size = node.TextSize or 14
	if node.TextWrapped ~= true then
		return size + 4
	end
	local lines = math.max(1, math.ceil(textWidth(node) / math.max(width, 1)))
	return math.ceil(lines * size * 1.45) + 2
end

local guiChildrenSorted: (AnyTable) -> { AnyTable }
guiChildrenSorted = function(node: AnyTable): { AnyTable }
	local list: { AnyTable } = {}
	for _, nodeChild in node._children do
		if GUI_CLASSES[nodeChild._props.ClassName] and nodeChild.Visible ~= false then
			table.insert(list, nodeChild)
		end
	end
	table.sort(list, function(a, b)
		local orderA = a.LayoutOrder or 0
		local orderB = b.LayoutOrder or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a._order < b._order
	end)
	return list
end

local arrange: (AnyTable, number, number, number, number?) -> number

local function resolvedHeight(node: AnyTable, parentInnerH: number?, ownWidth: number): number
	if node.AutomaticSize ~= nil and node.AutomaticSize.Name == "Y" then
		if TEXT_CLASSES[node._props.ClassName] then
			return measureTextHeight(node, ownWidth)
		end
		return arrange(node, 0, 0, ownWidth, parentInnerH)
	end
	local size = node.Size
	return size.Y.Scale * (parentInnerH or 0) + size.Y.Offset
end

-- Arranges children of `node` given its absolute rect; returns the node's
-- content height (used for AutomaticSize.Y parents). Positions land on
-- node._rect for the HTML emitter.
arrange = function(node: AnyTable, x: number, y: number, w: number, parentInnerH: number?): number
	local list, grid, padding = findLayout(node)
	local padLeft, padTop, padRight, padBottom = paddingBox(padding)
	local innerX = x + padLeft
	local innerY = y + padTop
	local innerW = w - padLeft - padRight
	local declaredH = resolvedHeightRaw(node, parentInnerH)

	local contentH = 0
	local children = guiChildrenSorted(node)

	if grid ~= nil then
		local cell = grid.CellSize
		local cellPad = grid.CellPadding
		local innerH = math.max(declaredH - padTop - padBottom, 0)
		local cellW = cell.X.Scale * innerW + cell.X.Offset
		local cellH = cell.Y.Scale * innerH + cell.Y.Offset
		local gapX = cellPad.X.Offset
		local gapY = cellPad.Y.Offset
		local columns = math.max(math.floor((innerW + gapX) / (cellW + gapX) + 0.001), 1)
		for index, gridChild in children do
			local column = (index - 1) % columns
			local rowIndex = math.floor((index - 1) / columns)
			local cx = innerX + column * (cellW + gapX)
			local cy = innerY + rowIndex * (cellH + gapY)
			gridChild._rect = { x = cx, y = cy, w = cellW, h = cellH }
			arrange(gridChild, cx, cy, cellW, cellH)
			contentH = math.max(contentH, cy + cellH - y)
		end
	elseif list ~= nil then
		local gap = if list.Padding ~= nil then list.Padding.Offset else 0
		local horizontal = list.FillDirection ~= nil and list.FillDirection.Name == "Horizontal"
		local innerH = math.max(declaredH - padTop - padBottom, 0)
		if horizontal then
			local cx = innerX
			for _, listChild in children do
				local size = listChild.Size
				local cw = size.X.Scale * innerW + size.X.Offset
				local ch = resolvedHeight(listChild, innerH, cw)
				local cy = innerY
				if list.VerticalAlignment ~= nil and list.VerticalAlignment.Name == "Center" then
					cy = innerY + (innerH - ch) / 2
				end
				listChild._rect = { x = cx, y = cy, w = cw, h = ch }
				arrange(listChild, cx, cy, cw, ch)
				cx += cw + gap
				contentH = math.max(contentH, cy + ch - y)
			end
		else
			local cy = innerY
			for _, listChild in children do
				local size = listChild.Size
				local cw = size.X.Scale * innerW + size.X.Offset
				local ch = resolvedHeight(listChild, nil, cw)
				listChild._rect = { x = innerX, y = cy, w = cw, h = ch }
				arrange(listChild, innerX, cy, cw, ch)
				cy += ch + gap
			end
			contentH = cy - gap - y
		end
	else
		-- Absolute positioning; offset-height children first, then scale-height
		-- children once the final height is known.
		local scaleChildren: { AnyTable } = {}
		for _, absoluteChild in children do
			local size = absoluteChild.Size
			if size.Y.Scale ~= 0 and (absoluteChild.AutomaticSize == nil) then
				table.insert(scaleChildren, absoluteChild)
				continue
			end
			local cw = size.X.Scale * innerW + size.X.Offset
			local ch = resolvedHeight(absoluteChild, nil, cw)
			local anchor = absoluteChild.AnchorPoint or Vector2Stub.new(0, 0)
			local position = absoluteChild.Position
			local cx = innerX + position.X.Scale * innerW + position.X.Offset - anchor.X * cw
			local containerH = math.max(declaredH - padTop - padBottom, 0)
			local cy = innerY + position.Y.Scale * containerH + position.Y.Offset - anchor.Y * ch
			absoluteChild._rect = { x = cx, y = cy, w = cw, h = ch }
			arrange(absoluteChild, cx, cy, cw, ch)
			contentH = math.max(contentH, cy + ch - y)
		end
		local finalH = if node.AutomaticSize ~= nil and node.AutomaticSize.Name == "Y"
			then contentH + padBottom
			else declaredH
		for _, scaleChild in scaleChildren do
			local size = scaleChild.Size
			local cw = size.X.Scale * innerW + size.X.Offset
			local innerH = math.max(finalH - padTop - padBottom, 0)
			local ch = size.Y.Scale * innerH + size.Y.Offset
			local anchor = scaleChild.AnchorPoint or Vector2Stub.new(0, 0)
			local position = scaleChild.Position
			local cx = innerX + position.X.Scale * innerW + position.X.Offset - anchor.X * cw
			local cy = innerY + position.Y.Scale * innerH + position.Y.Offset - anchor.Y * ch
			scaleChild._rect = { x = cx, y = cy, w = cw, h = ch }
			arrange(scaleChild, cx, cy, cw, ch)
		end
	end
	return contentH + padBottom
end

-- Small forward-declared helper: a node's declared (non-auto) height.
function resolvedHeightRaw(node: AnyTable, parentInnerH: number?): number
	local rect = node._rect
	if rect ~= nil then
		return rect.h
	end
	local size = node.Size
	return size.Y.Scale * (parentInnerH or 0) + size.Y.Offset
end

-- ---------------------------------------------------------------------------
-- HTML emission
-- ---------------------------------------------------------------------------

local function cssColor(color: AnyTable?, transparency: number?): string
	if color == nil then
		return "transparent"
	end
	local alpha = 1 - (transparency or 0)
	if alpha <= 0 then
		return "transparent"
	end
	return string.format(
		"rgba(%d,%d,%d,%.3f)",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
		alpha
	)
end

local function escapeHtml(text: string): string
	local escaped = string.gsub(text, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

local function richToHtml(text: string): string
	local escaped = escapeHtml(text)
	escaped = string.gsub(escaped, '&lt;font color="(#%x+)"&gt;', '<span style="color:%1">')
	escaped = string.gsub(escaped, "&lt;/font&gt;", "</span>")
	return escaped
end

local emitNode: (AnyTable, { string }) -> ()
emitNode = function(node: AnyTable, out: { string })
	if node.Visible == false then
		return
	end
	local rect: Rect? = node._rect
	if rect == nil then
		for _, nodeChild in node._children do
			emitNode(nodeChild, out)
		end
		return
	end
	local class = node._props.ClassName
	local style = {
		`left:{math.floor(rect.x + 0.5)}px`,
		`top:{math.floor(rect.y + 0.5)}px`,
		`width:{math.floor(rect.w + 0.5)}px`,
		`height:{math.floor(rect.h + 0.5)}px`,
		`z-index:{node.ZIndex or 1}`,
	}
	table.insert(style, `background:{cssColor(node.BackgroundColor3, node.BackgroundTransparency)}`)
	-- Strokes (1px ring) and UIShadow drop shadows both map to CSS box-shadow, so
	-- collect every part and emit one combined declaration — a second box-shadow
	-- rule would otherwise clobber the first.
	local boxShadows: { string } = {}
	for _, decorator in node._children do
		local decoratorClass = decorator._props.ClassName
		if decoratorClass == "UICorner" then
			local radius = decorator.CornerRadius
			table.insert(style, `border-radius:{if radius ~= nil then radius.Offset else 4}px`)
		elseif decoratorClass == "UIStroke" then
			local color = cssColor(decorator.Color, decorator.Transparency)
			if color ~= "transparent" then
				table.insert(boxShadows, `0 0 0 1px {color}`)
			end
		elseif decoratorClass == "UIShadow" then
			local color = cssColor(decorator.Color, decorator.Transparency)
			if color ~= "transparent" then
				local offset = decorator.Offset
				local ox = if offset ~= nil then offset.X.Offset else 0
				local oy = if offset ~= nil then offset.Y.Offset else 0
				local blur = decorator.BlurRadius
				local b = if blur ~= nil then blur.Offset else 0
				local spread = decorator.Spread or 0
				table.insert(boxShadows, `{ox}px {oy}px {b}px {spread}px {color}`)
			end
		end
	end
	if #boxShadows > 0 then
		table.insert(style, `box-shadow:{table.concat(boxShadows, ",")}`)
	end
	if node.ClipsDescendants == true then
		table.insert(style, "overflow:hidden")
	end

	local body = ""
	if TEXT_CLASSES[class] then
		local text = node.Text or ""
		local color = node.TextColor3
		if class == "TextBox" and text == "" and node.PlaceholderText ~= nil then
			text = node.PlaceholderText
			color = node.PlaceholderColor3
		end
		local html = if node.RichText == true then richToHtml(text) else escapeHtml(text)
		local align = "center"
		if node.TextXAlignment ~= nil and node.TextXAlignment.Name == "Left" then
			align = "flex-start"
		elseif node.TextXAlignment ~= nil and node.TextXAlignment.Name == "Right" then
			align = "flex-end"
		end
		local vertical = "center"
		if node.TextYAlignment ~= nil and node.TextYAlignment.Name == "Top" then
			vertical = "flex-start"
		end
		table.insert(style, "display:flex")
		table.insert(style, `justify-content:{align}`)
		table.insert(style, `align-items:{vertical}`)
		table.insert(style, `font-size:{node.TextSize or 14}px`)
		table.insert(style, `font-weight:{if isBold(node) then 700 else 500}`)
		table.insert(style, `color:{cssColor(color, node.TextTransparency)}`)
		if node.TextWrapped == true then
			table.insert(style, "white-space:normal;line-height:1.4;text-align:left")
			table.insert(style, "align-items:flex-start")
		else
			table.insert(style, "white-space:nowrap;overflow:hidden;text-overflow:ellipsis")
		end
		body = html
	elseif class == "ImageLabel" and node.Image ~= nil and node.Image ~= "" then
		table.insert(
			style,
			"background:conic-gradient(from 210deg,#60a5fa,#2f6dd0,#9cc4f8,#60a5fa);border-radius:3px"
		)
	end

	table.insert(out, `<div class="n" style="{table.concat(style, ";")}">{body}</div>`)
	for _, nodeChild in node._children do
		emitNode(nodeChild, out)
	end
end

-- ---------------------------------------------------------------------------
-- Render each tab
-- ---------------------------------------------------------------------------

if not fs.isDir(OUTPUT_DIRECTORY) then
	fs.writeDir(OUTPUT_DIRECTORY)
end

local PANEL_WIDTH = 420
local HEADER_HEIGHT = 42
local TAB_BAR_HEIGHT = 34
local FOOTER_HEIGHT = 92

local function clearRects(node: AnyTable)
	node._rect = nil
	for _, nodeChild in node._children do
		clearRects(nodeChild)
	end
end

for index, tabName in tabNames do
	child(tabBar, `Tab{tabName}`).MouseButton1Click:Fire()

	clearRects(root)
	-- Measure the active page's canvas so the render shows the full content
	-- instead of a scroll viewport.
	local page = child(pageHost, tabName)
	local canvasH = arrange(page, 0, 0, PANEL_WIDTH)
	clearRects(root)
	local panelH = HEADER_HEIGHT + TAB_BAR_HEIGHT + math.max(canvasH, 578) + FOOTER_HEIGHT
	root._rect = { x = 0, y = 0, w = PANEL_WIDTH, h = panelH }
	arrange(root, 0, 0, PANEL_WIDTH, panelH)

	local out: { string } = {}
	table.insert(
		out,
		'<!doctype html><meta charset="utf-8"><style>'
			.. "body{margin:0;background:#111214;font-family:'DejaVu Sans','Segoe UI',system-ui,sans-serif;"
			.. "font-variant-numeric:tabular-nums}"
			.. ".n{position:absolute;box-sizing:border-box}"
			.. `#panel\{position:relative;width:{PANEL_WIDTH}px;height:{panelH}px;overflow:hidden\}`
			.. "</style>"
			.. `<div id="panel">`
	)
	emitNode(root, out)
	table.insert(out, "</div>")
	fs.writeFile(`{OUTPUT_DIRECTORY}/tab-{index}-{string.lower(tabName)}.html`, table.concat(out, "\n"))
	print(`rendered {tabName} ({PANEL_WIDTH}x{panelH})`)
end

print(`\nRunewright render complete → {OUTPUT_DIRECTORY}`)

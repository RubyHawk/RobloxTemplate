--!strict

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ResponsiveController = {}

-- Roblox offset units, not native pixels; tuned against phone/tablet/desktop
-- viewport ranges rather than the guide's device-category guesses. Uses the
-- shorter side so a landscape phone is still treated as a small screen.
local LANDSCAPE_ASPECT_RATIO = 1.1
local COMPACT_SHORT_SIDE = 380
local COMPACT_SCALE = 0.94

-- Clearance margins in the same offset units as the authored layout (see
-- docs/internal/2026-07-01-responsive-orientation.md for how these were
-- derived from actual overlap/overflow found on short viewports).
local NAV_EDGE_MARGIN = 16
local HUD_CLEARANCE_GAP = 10

local root: Frame? = nil
local uiScale: UIScale? = nil
local settingsScale = 1

local navigation: Frame? = nil
local hud: Frame? = nil
local modernBottomDock = false
local leftIconRail = false
local hudRequiresModalClearance = false
local currencySlots: ScrollingFrame? = nil
local currencyLayout: UIListLayout? = nil
local boostPanel: Frame? = nil
local modalRoots: { GuiObject } = {}
local originalMaxSize: { [GuiObject]: Vector2 } = {}
local modalNeedsHudHidden: { [GuiObject]: boolean } = {}

local function currentCamera(): Camera
	local camera = Workspace.CurrentCamera
	while camera == nil do
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		camera = Workspace.CurrentCamera
	end
	return camera :: Camera
end

local function deviceScaleFor(shortSide: number): number
	if shortSide <= 0 then
		return 1
	elseif shortSide < COMPACT_SHORT_SIDE then
		return COMPACT_SCALE
	end
	return 1
end

local function findSizeConstraint(instance: Instance): UISizeConstraint?
	for _, child in instance:GetChildren() do
		if child:IsA("UISizeConstraint") then
			return child
		end
	end
	return nil
end

local function collectModalRoots(rootFrame: Frame)
	modalRoots = {}
	local screens = rootFrame:FindFirstChild("Screens")
	if screens then
		for _, screen in screens:GetChildren() do
			if screen:IsA("GuiObject") and findSizeConstraint(screen) then
				table.insert(modalRoots, screen)
			end
		end
	end
	for _, name in { "MoreMenu" } do
		local inst = rootFrame:FindFirstChild(name)
		if inst and inst:IsA("GuiObject") and findSizeConstraint(inst) then
			table.insert(modalRoots, inst)
		end
	end
end

-- Navigation is authored as a fixed-offset rail (390 tall by default; its
-- Size scale component is 0, so it never shrinks with the viewport on its
-- own). Its MinSize/MaxSize UISizeConstraint is otherwise inert since 390
-- already sits inside [320, 450]. On short landscape phones (~375 tall)
-- that fixed height exceeds the viewport and the rail overflows both
-- edges. Tighten MaxSize.Y so it fits with a margin on both edges;
-- restores to the authored default the moment there's room again.
--
-- Navigation's Position Y-scale is 0.48, not 0.5, so it isn't perfectly
-- centered - solving for a single "viewport height minus 2*margin" bound
-- would under-shoot the margin on one edge and over-shoot on the other.
-- Solve each edge separately from the size-invariant anchor point instead.
local function clampNavigation(viewportSize: Vector2)
	local nav = navigation
	if not nav then
		return
	end
	local constraint = findSizeConstraint(nav)
	if not constraint then
		return
	end
	local original = originalMaxSize[nav]
	if not original then
		original = constraint.MaxSize
		originalMaxSize[nav] = original
	end
	local scale = if uiScale then math.max(uiScale.Scale, 0.0001) else 1
	local anchorX = nav.AnchorPoint.X
	local anchorY = nav.AnchorPoint.Y
	local centerXPx = nav.AbsolutePosition.X + anchorX * nav.AbsoluteSize.X
	local centerYPx = nav.AbsolutePosition.Y + anchorY * nav.AbsoluteSize.Y
	local safeByLeft = if anchorX > 0 then (centerXPx - NAV_EDGE_MARGIN) / anchorX else math.huge
	local safeByRight = if anchorX < 1
		then (viewportSize.X - NAV_EDGE_MARGIN - centerXPx) / (1 - anchorX)
		else math.huge
	local safeByTop = if anchorY > 0 then (centerYPx - NAV_EDGE_MARGIN) / anchorY else math.huge
	local safeByBottom = if anchorY < 1
		then (viewportSize.Y - NAV_EDGE_MARGIN - centerYPx) / (1 - anchorY)
		else math.huge
	local safeHeightRaw = math.min(safeByTop, safeByBottom) / scale
	local safeWidthRaw = math.min(safeByLeft, safeByRight) / scale
	constraint.MaxSize = Vector2.new(
		math.max(constraint.MinSize.X, math.min(original.X, safeWidthRaw)),
		math.max(constraint.MinSize.Y, math.min(original.Y, safeHeightRaw))
	)
end

-- The authored CurrencyTray can stay visible while a screen is open. Every
-- modal screen is vertically centered via a Scale-based Position, so on
-- short-enough viewports its clamped height can cover the tray.
-- AnchorPoint math ties AbsolutePosition + AnchorPoint*AbsoluteSize back to
-- the size-invariant center point, so this is stable across repeated calls
-- instead of ratcheting the constraint down permanently.
--
-- On any landscape phone (viewport height under ~560, which is every real
-- phone rotated sideways - not just unusually small ones) the modal's own
-- authored MinSize floor is taller than the space actually free below the
-- HUD, so shrinking alone can't fully clear it without also violating that
-- floor. Records which modals are in that state; updateHudVisibility()
-- hides the HUD only while one of those is actually the open screen,
-- rather than accepting a permanent partial overlap.
local function clampModalsAgainstHud()
	if modernBottomDock or not hudRequiresModalClearance then
		return
	end
	local hudFrame = hud
	if not hudFrame then
		return
	end
	local scale = if uiScale then math.max(uiScale.Scale, 0.0001) else 1
	local hudBottomPx = hudFrame.AbsolutePosition.Y + hudFrame.AbsoluteSize.Y
	for _, modal in modalRoots do
		local constraint = findSizeConstraint(modal)
		if not constraint then
			continue
		end
		local original = originalMaxSize[modal]
		if not original then
			original = constraint.MaxSize
			originalMaxSize[modal] = original
		end
		local centerYPx = modal.AbsolutePosition.Y + modal.AnchorPoint.Y * modal.AbsoluteSize.Y
		local safeHeightPx = 2 * (centerYPx - hudBottomPx - HUD_CLEARANCE_GAP)
		local safeHeightRaw = safeHeightPx / scale
		modalNeedsHudHidden[modal] = safeHeightRaw < constraint.MinSize.Y
		constraint.MaxSize =
			Vector2.new(original.X, math.max(constraint.MinSize.Y, math.min(original.Y, safeHeightRaw)))
	end
end

-- Only suppresses the HUD while a screen that actually can't fit under it
-- (see clampModalsAgainstHud above) is the one currently open; restores it
-- the instant that screen closes or the viewport gains enough height
-- (e.g. rotating back to portrait).
local function updateHudVisibility()
	local hudFrame = hud
	if not hudFrame then
		return
	end
	if modernBottomDock or not hudRequiresModalClearance then
		hudFrame.Visible = true
		return
	end
	local shouldHide = false
	for _, modal in modalRoots do
		if (modal :: GuiObject).Visible and modalNeedsHudHidden[modal] then
			shouldHide = true
			break
		end
	end
	hudFrame.Visible = not shouldHide
end

local function applyLeftIconRailLayout()
	if not leftIconRail then
		return
	end
	local nav = navigation
	if not nav then
		return
	end
	nav.AnchorPoint = Vector2.new(0, 0.5)
	nav.Position = UDim2.new(0, 24, 0.5, 0)
end

local function applyModernHudLayout(viewportSize: Vector2)
	if not modernBottomDock then
		return
	end
	local nav = navigation
	local tray = hud
	local slots = currencySlots
	local layout = currencyLayout
	if not nav or not tray or not slots or not layout then
		return
	end

	nav.AnchorPoint = Vector2.new(0.5, 1)
	nav.Position = UDim2.new(0.5, 0, 1, -14)
	local wide = viewportSize.X >= 780 and viewportSize.Y >= 500
	if wide then
		tray.AnchorPoint = Vector2.new(1, 0.5)
		tray.Position = UDim2.new(1, -16, 0.5, 0)
		tray.Size = UDim2.fromOffset(178, 348)
		slots.AutomaticCanvasSize = Enum.AutomaticSize.Y
		slots.ScrollingDirection = Enum.ScrollingDirection.Y
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		if boostPanel then
			boostPanel.Position = UDim2.new(0, 16, 0.58, 0)
		end
	else
		tray.AnchorPoint = Vector2.new(0.5, 0)
		tray.Position = UDim2.new(0.5, 0, 0, 16)
		tray.Size = UDim2.new(0.92, 0, 0, 72)
		slots.AutomaticCanvasSize = Enum.AutomaticSize.X
		slots.ScrollingDirection = Enum.ScrollingDirection.X
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		if boostPanel then
			boostPanel.Position = UDim2.fromOffset(12, 98)
		end
	end
end

local function apply()
	local currentRoot = root
	local currentUiScale = uiScale
	if not currentRoot or not currentUiScale then
		return
	end

	local size = currentCamera().ViewportSize
	local isLandscape = size.Y > 0 and (size.X / size.Y) >= LANDSCAPE_ASPECT_RATIO
	local deviceScale = deviceScaleFor(math.min(size.X, size.Y))

	-- Display-only attributes for any future style hook; never read by
	-- server-authoritative code (currency, rewards, purchases).
	currentRoot:SetAttribute("LayoutOrientation", if isLandscape then "Landscape" else "Portrait")
	currentRoot:SetAttribute("LayoutWidth", size.X)
	currentRoot:SetAttribute("LayoutHeight", size.Y)
	currentRoot:SetAttribute("LayoutTouch", UserInputService.TouchEnabled)

	currentUiScale.Scale = math.clamp(settingsScale * deviceScale, 0.6, 1.5)

	applyLeftIconRailLayout()
	applyModernHudLayout(size)
	clampNavigation(size)
	clampModalsAgainstHud()
	updateHudVisibility()
end

function ResponsiveController.initialize(rootFrame: Frame, scale: UIScale)
	root = rootFrame
	uiScale = scale
	navigation = rootFrame:FindFirstChild("Navigation") :: Frame?
	hud = rootFrame:FindFirstChild("CurrencyTray") :: Frame?
	modernBottomDock = navigation ~= nil and navigation.AnchorPoint.Y > 0.9
	leftIconRail = navigation ~= nil and navigation.AnchorPoint.X < 0.1
	hudRequiresModalClearance = hud ~= nil and hud.AnchorPoint.Y < 0.5 and hud.Position.Y.Scale < 0.25
	local slotsInstance = if hud then hud:FindFirstChild("Slots") else nil
	if slotsInstance and slotsInstance:IsA("ScrollingFrame") then
		currencySlots = slotsInstance
		currencyLayout = slotsInstance:FindFirstChildOfClass("UIListLayout")
	end
	local boostInstance = rootFrame:FindFirstChild("BoostPanel")
	if boostInstance and boostInstance:IsA("Frame") then
		boostPanel = boostInstance
	end
	collectModalRoots(rootFrame)

	-- A modal can open/close without any resize (e.g. tapping Shop while
	-- already in landscape phone mode), so HUD visibility has to react to
	-- that independently of apply()'s resize-driven pass.
	for _, modal in modalRoots do
		(modal :: GuiObject):GetPropertyChangedSignal("Visible"):Connect(updateHudVisibility)
	end

	local function hookCamera(camera: Camera)
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end

	hookCamera(currentCamera())
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera(currentCamera())
		apply()
	end)

	apply()
end

function ResponsiveController.setPlayerScale(value: number)
	settingsScale = value
	apply()
end

return ResponsiveController

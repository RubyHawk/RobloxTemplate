--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ResponsiveController = {}

-- Roblox offset units, not native pixels; tuned against phone/tablet/desktop
-- viewport ranges rather than the guide's device-category guesses. Uses the
-- shorter side so a landscape phone is still treated as a small screen.
local LANDSCAPE_ASPECT_RATIO = 1.1
local COMPACT_SHORT_SIDE = 380
local WIDE_SHORT_SIDE = 700
local COMPACT_SCALE = 0.94
local WIDE_SCALE = 1.06

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
local modalRoots: { GuiObject } = {}
local originalMaxSize: { [GuiObject]: Vector2 } = {}

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
	elseif shortSide > WIDE_SHORT_SIDE then
		return WIDE_SCALE
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
	for _, name in { "MoreMenu", "ScreenTemplate" } do
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
	local anchorY = nav.AnchorPoint.Y
	local centerYPx = nav.AbsolutePosition.Y + anchorY * nav.AbsoluteSize.Y
	local safeByTop = if anchorY > 0 then (centerYPx - NAV_EDGE_MARGIN) / anchorY else math.huge
	local safeByBottom = if anchorY < 1
		then (viewportSize.Y - NAV_EDGE_MARGIN - centerYPx) / (1 - anchorY)
		else math.huge
	local safeHeightRaw = math.min(safeByTop, safeByBottom) / scale
	constraint.MaxSize =
		Vector2.new(original.X, math.max(constraint.MinSize.Y, math.min(original.Y, safeHeightRaw)))
end

-- CurrencyHUD is fixed near the top of the screen and stays visible while a
-- screen is open (Screens has ZIndex 40 vs CurrencyHUD's 5, so it paints on
-- top wherever they overlap). Every modal screen is vertically centered via
-- a Scale-based Position, so on short-enough viewports its clamped height
-- puts its top edge above the HUD's bottom edge, covering the coin balance.
-- AnchorPoint math ties AbsolutePosition + AnchorPoint*AbsoluteSize back to
-- the size-invariant center point, so this is stable across repeated calls
-- instead of ratcheting the constraint down permanently.
local function clampModalsAgainstHud()
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
		constraint.MaxSize =
			Vector2.new(original.X, math.max(constraint.MinSize.Y, math.min(original.Y, safeHeightRaw)))
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

	clampNavigation(size)
	clampModalsAgainstHud()
end

function ResponsiveController.initialize(rootFrame: Frame, scale: UIScale)
	root = rootFrame
	uiScale = scale
	navigation = rootFrame:FindFirstChild("Navigation") :: Frame?
	hud = rootFrame:FindFirstChild("CurrencyHUD") :: Frame?
	collectModalRoots(rootFrame)

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

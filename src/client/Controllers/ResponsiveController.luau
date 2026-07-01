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

local root: Frame? = nil
local uiScale: UIScale? = nil
local settingsScale = 1

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
end

function ResponsiveController.initialize(rootFrame: Frame, scale: UIScale)
	root = rootFrame
	uiScale = scale

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

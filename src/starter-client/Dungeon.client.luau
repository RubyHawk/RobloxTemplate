--!strict

-- Dedicated dungeon presentation/input controller. Boss health, damage,
-- cooldown acceptance, dodge acceptance, rewards, and fight results remain
-- server-owned; this script only binds authored UI and applies local polish.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local RemoteNames = require(Shared.RemoteNames)

if Config.features.dungeon ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CORE_GUI_TYPES = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Health,
}
local rememberedCoreGuiStates: { [Enum.CoreGuiType]: boolean } = {}
local coreGuiSuppressionRevision = 0

local function setCoreGuiEnabledWithRetry(coreGuiType: Enum.CoreGuiType, enabled: boolean, revision: number)
	task.spawn(function()
		for _ = 1, 10 do
			if coreGuiSuppressionRevision ~= revision then
				return
			end
			local success = pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
			end)
			if success then
				return
			end
			task.wait(0.1)
		end
	end)
end

local function suppressCoreGui()
	coreGuiSuppressionRevision += 1
	local revision = coreGuiSuppressionRevision
	for _, coreGuiType in CORE_GUI_TYPES do
		if rememberedCoreGuiStates[coreGuiType] == nil then
			local success, wasEnabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(coreGuiType)
			end)
			rememberedCoreGuiStates[coreGuiType] = if success then wasEnabled else true
		end
		setCoreGuiEnabledWithRetry(coreGuiType, false, revision)
	end
end

local function restoreCoreGuiIfApplicable()
	if Template:GetAttribute("RuntimeMode") ~= "lobby" then
		return
	end
	coreGuiSuppressionRevision += 1
	local revision = coreGuiSuppressionRevision
	for _, coreGuiType in CORE_GUI_TYPES do
		local wasEnabled = rememberedCoreGuiStates[coreGuiType]
		if wasEnabled ~= nil then
			setCoreGuiEnabledWithRetry(coreGuiType, wasEnabled, revision)
			rememberedCoreGuiStates[coreGuiType] = nil
		end
	end
end

if Template:GetAttribute("RuntimeMode") == "dungeon" then
	suppressCoreGui()
end

local remotes = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local requestRemote = remotes:WaitForChild(RemoteNames.request) :: RemoteEvent
local stateRemote = remotes:WaitForChild(RemoteNames.state) :: RemoteEvent

local DEFAULT_ATTACK_COOLDOWN = 0.35
local DEFAULT_DODGE_COOLDOWN = 1.25
local DEFAULT_CAMERA_FOV = 74
local DEFAULT_CAMERA_MIN_ZOOM = 8
local DEFAULT_CAMERA_MAX_ZOOM = 28

local dungeonConfig: any = Config.dungeon
local cameraConfig: any = if type(dungeonConfig.camera) == "table" then dungeonConfig.camera else {}

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function configuredNumber(
	source: any,
	keys: { string },
	fallback: number,
	minimum: number,
	maximum: number
): number
	if type(source) == "table" then
		for _, key in keys do
			local value = source[key]
			if finiteNumber(value) then
				return math.clamp(value, minimum, maximum)
			end
		end
	end
	return fallback
end

local cameraFov = configuredNumber(cameraConfig, { "fieldOfView", "fov" }, DEFAULT_CAMERA_FOV, 40, 100)
local cameraMinZoom =
	configuredNumber(cameraConfig, { "minZoomDistance", "minZoom" }, DEFAULT_CAMERA_MIN_ZOOM, 0.5, 100)
local cameraMaxZoom = configuredNumber(
	cameraConfig,
	{ "maxZoomDistance", "maxZoom" },
	DEFAULT_CAMERA_MAX_ZOOM,
	cameraMinZoom,
	200
)
local attackCooldown = configuredNumber(
	dungeonConfig,
	{ "weaponCooldown", "attackCooldownSeconds" },
	DEFAULT_ATTACK_COOLDOWN,
	0.05,
	10
)
local dodgeCooldown = configuredNumber(
	dungeonConfig,
	{ "dodgeCooldown", "dodgeCooldownSeconds" },
	DEFAULT_DODGE_COOLDOWN,
	0.1,
	20
)

local function tweenInfo(duration: number, easingStyle: Enum.EasingStyle?): TweenInfo
	local adjusted = if GuiService.ReducedMotionEnabled then 0 else duration
	return TweenInfo.new(adjusted, easingStyle or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

local function childOfClass(parent: Instance?, name: string, className: string): any
	if parent == nil then
		return nil
	end
	local child = parent:FindFirstChild(name)
	if child ~= nil and child.ClassName == className then
		return child :: any
	end
	return nil
end

local hud: ScreenGui? = nil
local bossBar: Frame? = nil
local bossNameLabel: TextLabel? = nil
local bossStatusLabel: TextLabel? = nil
local bossPhaseLabel: TextLabel? = nil
local bossHealthFill: Frame? = nil
local bossHealthText: TextLabel? = nil
local playerPanel: Frame? = nil
local playerHealthFill: Frame? = nil
local playerHealthText: TextLabel? = nil
local weaponNameLabel: TextLabel? = nil
local cooldownLabel: TextLabel? = nil
local controls: Frame? = nil
local attackButton: TextButton? = nil
local dodgeButton: TextButton? = nil
local controlHint: TextLabel? = nil
local statusToast: TextLabel? = nil
local hitMarker: TextLabel? = nil
local dangerBanner: TextLabel? = nil
local dangerVignette: Frame? = nil
local resultPanel: Frame? = nil
local resultTitle: TextLabel? = nil
local resultDetail: TextLabel? = nil
local rewardText: TextLabel? = nil

local attackButtonConnection: RBXScriptConnection? = nil
local dodgeButtonConnection: RBXScriptConnection? = nil
local bossHealthTween: Tween? = nil
local playerHealthTween: Tween? = nil
local statusRevision = 0
local hitMarkerRevision = 0
local bossHitRevision = 0
local vignetteRevision = 0

local latestDungeonState: any = nil
local dungeonVisible = false
local fightActive = false
local combatActive = false
local localEliminated = false
local dangerActive = false
local lastResult: string? = nil
local lastAttackAt = -math.huge
local lastDodgeAt = -math.huge
local dodgePending = false
local dodgeRequestRevision = 0

local DODGE_ACK_TIMEOUT = 1.5

local character: Model? = nil
local humanoid: Humanoid? = nil
local healthConnection: RBXScriptConnection? = nil
local maxHealthConnection: RBXScriptConnection? = nil
local diedConnection: RBXScriptConnection? = nil
local lastHealth: number? = nil

local bossCore: BasePart? = nil
local bossVisual: Model? = nil
local bossVisualBase: CFrame? = nil
local bossIdleStartedAt = 0
local bossHitHighlight: Highlight? = nil
local bossResolveClock = 0

local cameraSession = false
local savedMinZoom = player.CameraMinZoomDistance
local savedMaxZoom = player.CameraMaxZoomDistance
local savedFov: number? = nil
local fovTween: Tween? = nil
local fovRevision = 0

local baseToolGrips: { [Tool]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local swingRevision = 0
local poseMotors: { [string]: Motor6D } = {}
local baseMotorC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local poseTweens: { Tween } = {}
local poseRevision = 0

local LOBBY_GUI_ROOTS: { [string]: boolean } = {
	TemplateUI = true,
	RuneCircleUI = true,
	RuneCircleSign = true,
	StagePlatformOwners = true,
	StarterSignUI = true,
	PortalSign = true,
	GalleryMenu = true,
	GalleryBackdrop = true,
	ZxglyV5Showroom = true,
	NotificationV2Showroom = true,
}
local suppressedLobbyGuiStates: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function disableRememberedGui(instance: Instance)
	if instance:IsA("LayerCollector") then
		if suppressedLobbyGuiStates[instance] == nil then
			suppressedLobbyGuiStates[instance] = instance.Enabled
		end
		instance.Enabled = false
	end
end

local function suppressLobbyGuiRoot(root: Instance)
	if LOBBY_GUI_ROOTS[root.Name] ~= true then
		return
	end
	disableRememberedGui(root)
	for _, descendant in root:GetDescendants() do
		disableRememberedGui(descendant)
	end
end

local function suppressLobbyGuis()
	for _, child in playerGui:GetChildren() do
		suppressLobbyGuiRoot(child)
	end
end

local function restoreLobbyGuisIfApplicable()
	if Template:GetAttribute("RuntimeMode") ~= "lobby" then
		return
	end
	for instance, wasEnabled in suppressedLobbyGuiStates do
		if instance.Parent ~= nil and instance:IsA("LayerCollector") then
			instance.Enabled = wasEnabled
		end
		suppressedLobbyGuiStates[instance] = nil
	end
end

local function setText(label: TextLabel?, text: string)
	if label ~= nil and label.Text ~= text then
		label.Text = text
	end
end

local function setVisible(gui: GuiObject?, visible: boolean)
	if gui ~= nil then
		gui.Visible = visible
	end
end

local function showStatus(message: string, color: Color3?, duration: number?)
	statusRevision += 1
	local revision = statusRevision
	local label = statusToast
	if label == nil then
		return
	end
	label.Text = message
	label.TextColor3 = color or Color3.fromRGB(236, 242, 255)
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.16
	label.Visible = true
	task.delay(duration or 1.6, function()
		if statusRevision ~= revision or statusToast ~= label or label.Parent == nil then
			return
		end
		local tween = TweenService:Create(label, tweenInfo(0.18), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		task.delay(if GuiService.ReducedMotionEnabled then 0 else 0.2, function()
			if statusRevision == revision and label.Parent ~= nil then
				label.Visible = false
			end
		end)
	end)
end

local function targetVignetteTransparency(): number
	return if dangerActive then 0.8 else 1
end

local function tweenVignette(transparency: number, duration: number)
	local vignette = dangerVignette
	if vignette == nil then
		return
	end
	vignetteRevision += 1
	local revision = vignetteRevision
	vignette.Visible = transparency < 1
	TweenService:Create(vignette, tweenInfo(duration), { BackgroundTransparency = transparency }):Play()
	if transparency >= 1 then
		task.delay(if GuiService.ReducedMotionEnabled then 0 else duration + 0.02, function()
			if vignetteRevision == revision and dangerVignette == vignette then
				vignette.Visible = false
			end
		end)
	end
end

local function flashDamage()
	vignetteRevision += 1
	local revision = vignetteRevision
	local vignette = dangerVignette
	if vignette == nil then
		return
	end
	vignette.Visible = true
	vignette.BackgroundTransparency = 0.48
	task.delay(if GuiService.ReducedMotionEnabled then 0 else 0.08, function()
		if vignetteRevision ~= revision or dangerVignette ~= vignette then
			return
		end
		TweenService:Create(vignette, tweenInfo(0.24), {
			BackgroundTransparency = targetVignetteTransparency(),
		}):Play()
	end)
end

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function applyCameraPresentation()
	if not cameraSession then
		return
	end
	player.CameraMaxZoomDistance = cameraMaxZoom
	player.CameraMinZoomDistance = cameraMinZoom
	local camera = currentCamera()
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid ~= nil and humanoid.Parent ~= nil then
			camera.CameraSubject = humanoid
		end
		fovTween = TweenService:Create(camera, tweenInfo(0.22), { FieldOfView = cameraFov })
		fovTween:Play()
	end
end

local function beginCameraPresentation()
	if cameraSession then
		applyCameraPresentation()
		return
	end
	cameraSession = true
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance
	local camera = currentCamera()
	savedFov = if camera ~= nil then camera.FieldOfView else nil
	applyCameraPresentation()
end

local function endCameraPresentation()
	if not cameraSession then
		return
	end
	cameraSession = false
	fovRevision += 1
	if fovTween ~= nil then
		fovTween:Cancel()
		fovTween = nil
	end
	player.CameraMinZoomDistance = savedMinZoom
	player.CameraMaxZoomDistance = savedMaxZoom
	local camera = currentCamera()
	if camera ~= nil and savedFov ~= nil then
		TweenService:Create(camera, tweenInfo(0.2), { FieldOfView = savedFov }):Play()
	end
end

local function pulseCamera(amount: number)
	if GuiService.ReducedMotionEnabled or not cameraSession then
		return
	end
	local camera = currentCamera()
	if camera == nil then
		return
	end
	fovRevision += 1
	local revision = fovRevision
	if fovTween ~= nil then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(camera, tweenInfo(0.08), {
		FieldOfView = math.clamp(cameraFov + amount, 40, 100),
	})
	fovTween:Play()
	task.delay(0.1, function()
		if fovRevision ~= revision or not cameraSession then
			return
		end
		local activeCamera = currentCamera()
		if activeCamera ~= nil then
			fovTween = TweenService:Create(activeCamera, tweenInfo(0.2), { FieldOfView = cameraFov })
			fovTween:Play()
		end
	end)
end

local function stopBossPresentation()
	if bossVisual ~= nil and bossVisual.Parent ~= nil and bossVisualBase ~= nil then
		bossVisual:PivotTo(bossVisualBase)
	end
	if bossHitHighlight ~= nil and bossHitHighlight.Parent ~= nil then
		bossHitHighlight.Enabled = false
	end
	bossCore = nil
	bossVisual = nil
	bossVisualBase = nil
	bossIdleStartedAt = 0
	bossHitHighlight = nil
end

local function resolveBossPresentation()
	if
		bossCore ~= nil
		and bossCore.Parent ~= nil
		and bossVisual ~= nil
		and bossVisual.Parent ~= nil
		and bossHitHighlight ~= nil
		and bossHitHighlight.Parent ~= nil
	then
		return
	end
	stopBossPresentation()
	local arena = Workspace:FindFirstChild("DungeonArena")
	local boss = if arena ~= nil then arena:FindFirstChild("Boss") else nil
	if boss == nil then
		return
	end
	local coreCandidate = boss:FindFirstChild("Core")
	if coreCandidate ~= nil and coreCandidate:IsA("BasePart") then
		bossCore = coreCandidate
	end
	local visualCandidate = boss:FindFirstChild("Visual")
	if visualCandidate ~= nil and visualCandidate:IsA("Model") then
		bossVisual = visualCandidate
		bossVisualBase = visualCandidate:GetPivot()
		bossIdleStartedAt = os.clock()
	end
	local highlightCandidate = boss:FindFirstChild("HitHighlight", true)
	if highlightCandidate ~= nil and highlightCandidate:IsA("Highlight") then
		bossHitHighlight = highlightCandidate
		highlightCandidate.Enabled = false
	end
end

local function pulseBossHit()
	resolveBossPresentation()
	local highlight = bossHitHighlight
	if highlight == nil or highlight.Parent == nil then
		return
	end
	bossHitRevision += 1
	local revision = bossHitRevision
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 0
	highlight.Enabled = true
	if GuiService.ReducedMotionEnabled then
		task.delay(0.2, function()
			if bossHitRevision == revision and bossHitHighlight == highlight and highlight.Parent ~= nil then
				highlight.Enabled = false
			end
		end)
		return
	end
	TweenService:Create(highlight, tweenInfo(0.22), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	task.delay(if GuiService.ReducedMotionEnabled then 0 else 0.24, function()
		if bossHitRevision == revision and bossHitHighlight == highlight and highlight.Parent ~= nil then
			highlight.Enabled = false
		end
	end)
end

local function cancelPoseTweens()
	for _, tween in poseTweens do
		tween:Cancel()
	end
	table.clear(poseTweens)
end

local function setAvatarPose(offsets: { [string]: CFrame }, duration: number, revision: number)
	if poseRevision ~= revision then
		return
	end
	cancelPoseTweens()
	for key, motor in poseMotors do
		local base = baseMotorC0[motor]
		if base ~= nil and motor.Parent ~= nil then
			local target = base * (offsets[key] or CFrame.identity)
			if GuiService.ReducedMotionEnabled or duration <= 0 then
				motor.C0 = target
			else
				local tween = TweenService:Create(motor, tweenInfo(duration), { C0 = target })
				table.insert(poseTweens, tween)
				tween:Play()
			end
		end
	end
end

local function restoreAvatarPose(duration: number?)
	poseRevision += 1
	local revision = poseRevision
	setAvatarPose({}, duration or 0, revision)
end

local function playAttackPose()
	if GuiService.ReducedMotionEnabled then
		return
	end
	poseRevision += 1
	local revision = poseRevision
	setAvatarPose({
		RightShoulder = CFrame.Angles(math.rad(-58), math.rad(-8), math.rad(24)),
		LeftShoulder = CFrame.Angles(math.rad(10), 0, math.rad(-8)),
		Waist = CFrame.Angles(0, math.rad(-14), 0),
		RootJoint = CFrame.Angles(0, math.rad(-8), 0),
	}, 0.07, revision)
	task.delay(0.075, function()
		if poseRevision ~= revision then
			return
		end
		setAvatarPose({
			RightShoulder = CFrame.Angles(math.rad(34), math.rad(10), math.rad(-30)),
			LeftShoulder = CFrame.Angles(math.rad(-10), 0, math.rad(8)),
			Waist = CFrame.Angles(0, math.rad(18), math.rad(-4)),
			RootJoint = CFrame.Angles(0, math.rad(10), 0),
		}, 0.1, revision)
		task.delay(0.11, function()
			if poseRevision == revision then
				restoreAvatarPose(0.12)
			end
		end)
	end)
end

local function playDodgePose()
	if GuiService.ReducedMotionEnabled then
		return
	end
	poseRevision += 1
	local revision = poseRevision
	setAvatarPose({
		RightShoulder = CFrame.Angles(math.rad(18), 0, math.rad(26)),
		LeftShoulder = CFrame.Angles(math.rad(18), 0, math.rad(-26)),
		Waist = CFrame.Angles(math.rad(-14), 0, math.rad(8)),
		RootJoint = CFrame.new(0, -0.55, 0) * CFrame.Angles(math.rad(-10), 0, 0),
	}, 0.08, revision)
	task.delay(0.3, function()
		if poseRevision == revision then
			restoreAvatarPose(0.1)
		end
	end)
end

local function restoreToolGrips()
	swingRevision += 1
	for tool, baseGrip in baseToolGrips do
		if tool.Parent ~= nil then
			tool.Grip = baseGrip
		end
	end
end

local function swingEquippedTool()
	if GuiService.ReducedMotionEnabled then
		return
	end
	local currentCharacter = character
	if currentCharacter == nil then
		return
	end
	local equipped = currentCharacter:FindFirstChildWhichIsA("Tool")
	if equipped == nil then
		return
	end
	local baseGrip = baseToolGrips[equipped]
	if baseGrip == nil then
		baseGrip = equipped.Grip
		baseToolGrips[equipped] = baseGrip
	end
	for tool, savedGrip in baseToolGrips do
		if tool ~= equipped and tool.Parent ~= nil then
			tool.Grip = savedGrip
		end
	end
	swingRevision += 1
	local revision = swingRevision
	local windup = TweenService:Create(equipped, tweenInfo(0.07, Enum.EasingStyle.Quad), {
		Grip = baseGrip * CFrame.Angles(math.rad(-68), 0, math.rad(-20)),
	})
	windup:Play()
	task.delay(0.075, function()
		if swingRevision ~= revision or equipped.Parent == nil then
			return
		end
		local strike = TweenService:Create(equipped, tweenInfo(0.11, Enum.EasingStyle.Back), {
			Grip = baseGrip * CFrame.Angles(math.rad(32), 0, math.rad(24)),
		})
		strike:Play()
		task.delay(0.12, function()
			if swingRevision ~= revision or equipped.Parent == nil then
				return
			end
			TweenService:Create(equipped, tweenInfo(0.1), { Grip = baseGrip }):Play()
		end)
	end)
end

local function showHitMarker(damage: number?)
	local marker = hitMarker
	if marker == nil then
		return
	end
	hitMarkerRevision += 1
	local revision = hitMarkerRevision
	marker.Text = if damage ~= nil and damage > 0 then `HIT  -{math.floor(damage + 0.5)}` else "HIT!"
	marker.TextTransparency = 0
	marker.Visible = true
	marker.Position = UDim2.fromScale(0.5, 0.43)
	if GuiService.ReducedMotionEnabled then
		task.delay(0.28, function()
			if hitMarkerRevision == revision and hitMarker == marker then
				marker.Visible = false
			end
		end)
		return
	end
	TweenService:Create(marker, tweenInfo(0.28, Enum.EasingStyle.Back), {
		Position = UDim2.fromScale(0.5, 0.38),
		TextTransparency = 1,
	}):Play()
	task.delay(if GuiService.ReducedMotionEnabled then 0 else 0.3, function()
		if hitMarkerRevision == revision and hitMarker == marker then
			marker.Visible = false
		end
	end)
end

local function updatePlayerHealth(value: number)
	local currentHumanoid = humanoid
	local maximum = if currentHumanoid ~= nil then math.max(currentHumanoid.MaxHealth, 1) else 1
	local fraction = math.clamp(value / maximum, 0, 1)
	if playerHealthTween ~= nil then
		playerHealthTween:Cancel()
	end
	if playerHealthFill ~= nil then
		playerHealthTween = TweenService:Create(playerHealthFill, tweenInfo(0.14), {
			Size = UDim2.fromScale(fraction, 1),
		})
		playerHealthTween:Play()
	end
	setText(playerHealthText, `{math.max(0, math.ceil(value))} / {math.ceil(maximum)}`)
	if lastHealth ~= nil and value < lastHealth then
		flashDamage()
		pulseCamera(-4)
	end
	lastHealth = value
end

local function disconnectCharacter()
	restoreToolGrips()
	restoreAvatarPose(0)
	table.clear(poseMotors)
	if healthConnection ~= nil then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if maxHealthConnection ~= nil then
		maxHealthConnection:Disconnect()
		maxHealthConnection = nil
	end
	if diedConnection ~= nil then
		diedConnection:Disconnect()
		diedConnection = nil
	end
	character = nil
	humanoid = nil
	lastHealth = nil
end

local function bindCharacter(nextCharacter: Model)
	disconnectCharacter()
	character = nextCharacter
	local humanoidCandidate = nextCharacter:FindFirstChildWhichIsA("Humanoid")
		or nextCharacter:WaitForChild("Humanoid", 8)
	if humanoidCandidate ~= nil and humanoidCandidate:IsA("Humanoid") then
		humanoid = humanoidCandidate
		lastHealth = humanoidCandidate.Health
		updatePlayerHealth(humanoidCandidate.Health)
		healthConnection = humanoidCandidate.HealthChanged:Connect(updatePlayerHealth)
		maxHealthConnection = humanoidCandidate:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			updatePlayerHealth(humanoidCandidate.Health)
		end)
		diedConnection = humanoidCandidate.Died:Connect(function()
			if fightActive then
				localEliminated = true
				combatActive = false
				dodgePending = false
				dodgeRequestRevision += 1
				restoreAvatarPose(0.08)
				restoreToolGrips()
				dangerActive = false
				setVisible(dangerBanner, false)
				tweenVignette(1, 0.08)
				setVisible(controls, false)
				setText(controlHint, "SPECTATING - YOU ARE DOWN")
				setVisible(controlHint, UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch)
				showStatus("YOU ARE DOWN - SPECTATING", Color3.fromRGB(255, 132, 132), 2.5)
			end
		end)
	end
	local poseMotorKeys = {
		RightShoulder = "RightShoulder",
		["Right Shoulder"] = "RightShoulder",
		LeftShoulder = "LeftShoulder",
		["Left Shoulder"] = "LeftShoulder",
		Waist = "Waist",
		RootJoint = "RootJoint",
	}
	for _, descendant in nextCharacter:GetDescendants() do
		if descendant:IsA("Motor6D") then
			local key = poseMotorKeys[descendant.Name]
			if key ~= nil and poseMotors[key] == nil then
				poseMotors[key] = descendant
				baseMotorC0[descendant] = descendant.C0
			end
		end
	end
	if cameraSession then
		applyCameraPresentation()
	end
end

local function updateBossHealth(fraction: number)
	local clamped = math.clamp(fraction, 0, 1)
	if bossHealthTween ~= nil then
		bossHealthTween:Cancel()
	end
	if bossHealthFill ~= nil then
		bossHealthTween = TweenService:Create(bossHealthFill, tweenInfo(0.16), {
			Size = UDim2.fromScale(clamped, 1),
		})
		bossHealthTween:Play()
	end
	setText(bossHealthText, `{math.floor(clamped * 100 + 0.5)}%`)
end

local function localUserRecord(records: any): any
	if type(records) ~= "table" then
		return nil
	end
	return records[tostring(player.UserId)] or records[player.UserId]
end

local function resultRewardLine(data: any): string
	local reward = localUserRecord(data.rewardByUserId)
	if type(reward) ~= "table" then
		return ""
	end
	local rewards = {}
	local rawAmount = if finiteNumber(reward.currencyAmount) then reward.currencyAmount else reward.amount
	local amount = if finiteNumber(rawAmount) then math.max(0, math.floor(rawAmount)) else nil
	if amount ~= nil and amount > 0 then
		local currencyId = if type(reward.currencyId) == "string" and reward.currencyId ~= ""
			then reward.currencyId
			else "CURRENCY"
		table.insert(rewards, `+{amount} {string.upper(currencyId)}`)
	end
	local itemQuantity = if finiteNumber(reward.itemQuantity)
		then math.max(0, math.floor(reward.itemQuantity))
		else 0
	if type(reward.itemName) == "string" and reward.itemName ~= "" and itemQuantity > 0 then
		table.insert(rewards, `ITEM: {string.upper(reward.itemName)} x{itemQuantity}`)
	end
	return table.concat(rewards, "   |   ")
end

local function localWeaponPresentation(data: any): (string, number?)
	local name = if type(data.weaponName) == "string" and data.weaponName ~= "" then data.weaponName else nil
	local cooldown = if finiteNumber(data.weaponCooldown) then data.weaponCooldown else nil
	local weaponByUserId = data.weaponByUserId
	if type(weaponByUserId) == "table" then
		local weapon = weaponByUserId[tostring(player.UserId)] or weaponByUserId[player.UserId]
		if type(weapon) == "table" then
			if type(weapon.name) == "string" and weapon.name ~= "" then
				name = weapon.name
			end
			if finiteNumber(weapon.cooldownSeconds) then
				cooldown = weapon.cooldownSeconds
			end
		end
	end
	return name or "DUNGEON WEAPON", cooldown
end

local function applyDanger(nextDanger: boolean)
	if dangerActive == nextDanger then
		return
	end
	dangerActive = nextDanger
	setVisible(dangerBanner, nextDanger)
	if nextDanger then
		if dangerBanner ~= nil then
			dangerBanner.TextTransparency = 0
		end
		tweenVignette(0.8, 0.12)
		showStatus("SLAM INCOMING - DODGE OR RUN!", Color3.fromRGB(255, 128, 128), 1.2)
		pulseCamera(6)
	else
		tweenVignette(1, 0.2)
	end
end

local function showResult(data: any, result: string)
	setVisible(resultPanel, true)
	local actualRewardText = ""
	if result == "victory" then
		setText(resultTitle, "VICTORY!")
		if resultTitle ~= nil then
			resultTitle.TextColor3 = Color3.fromRGB(255, 224, 112)
		end
		setText(resultDetail, "The dungeon guardian has fallen.")
		actualRewardText = resultRewardLine(data)
		pulseCamera(4)
	else
		setText(resultTitle, "DEFEATED")
		if resultTitle ~= nil then
			resultTitle.TextColor3 = Color3.fromRGB(255, 126, 132)
		end
		local reason = if type(data.resultReason) == "string" then data.resultReason else ""
		if reason == "partyWipe" then
			setText(resultDetail, "The party was defeated. Regroup and try again.")
		elseif reason == "timeout" then
			setText(resultDetail, "Time expired before the guardian fell.")
		else
			setText(resultDetail, "Regroup and try the dungeon again.")
		end
		pulseCamera(-5)
	end
	setText(rewardText, actualRewardText)
	setVisible(rewardText, actualRewardText ~= "")
end

local function applyDungeonState(data: any)
	if type(data) ~= "table" then
		return
	end
	latestDungeonState = data
	local active = data.active == true
	local result = if type(data.result) == "string" then data.result else nil
	local phase = if type(data.phase) == "string" then data.phase else ""
	local nextFightActive = if type(data.combatActive) == "boolean"
		then active and data.combatActive and result == nil
		else active and phase == "fight" and result == nil
	local eliminatedValue = localUserRecord(data.eliminatedByUserId)
	local nextLocalEliminated = eliminatedValue == true
		or (humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health <= 0)
	local wasDungeonVisible = dungeonVisible
	local wasFightActive = fightActive
	local wasLocalEliminated = localEliminated
	dungeonVisible = active
	fightActive = nextFightActive
	localEliminated = nextLocalEliminated
	combatActive = nextFightActive and not nextLocalEliminated
	if active then
		suppressLobbyGuis()
		if not wasDungeonVisible then
			suppressCoreGui()
		end
	elseif wasDungeonVisible then
		restoreLobbyGuisIfApplicable()
		restoreCoreGuiIfApplicable()
	end
	if
		(not active and wasDungeonVisible)
		or (wasFightActive and not nextFightActive)
		or (nextLocalEliminated and not wasLocalEliminated)
	then
		dodgePending = false
		dodgeRequestRevision += 1
		restoreAvatarPose(0.08)
		restoreToolGrips()
	end

	local currentHud = hud
	if currentHud ~= nil then
		currentHud.Enabled = active
	end
	setVisible(bossBar, active and result == nil)
	setVisible(playerPanel, active)
	setVisible(controls, combatActive and UserInputService.TouchEnabled)
	local inputType = UserInputService:GetLastInputType()
	if nextFightActive and nextLocalEliminated then
		setText(controlHint, "SPECTATING - YOU ARE DOWN")
		setVisible(controlHint, true)
	elseif inputType == Enum.UserInputType.Touch then
		setVisible(controlHint, false)
	else
		setVisible(controlHint, combatActive)
	end
	if not active then
		applyDanger(false)
		setVisible(resultPanel, false)
		setVisible(hitMarker, false)
		endCameraPresentation()
		stopBossPresentation()
		lastResult = nil
		return
	end
	if nextLocalEliminated and not wasLocalEliminated then
		showStatus("YOU ARE DOWN - SPECTATING", Color3.fromRGB(255, 132, 132), 2.5)
	end

	beginCameraPresentation()
	resolveBossPresentation()
	local weaponName, weaponCooldown = localWeaponPresentation(data)
	if weaponCooldown ~= nil then
		attackCooldown = math.clamp(weaponCooldown, 0.05, 10)
	end
	if finiteNumber(data.dodgeCooldown) then
		dodgeCooldown = math.clamp(data.dodgeCooldown, 0.1, 20)
	end
	setText(weaponNameLabel, weaponName)
	setText(bossNameLabel, if type(data.bossName) == "string" then data.bossName else "DUNGEON GUARDIAN")
	local phaseIndex = if finiteNumber(data.phaseIndex) then math.max(1, math.floor(data.phaseIndex)) else 1
	setText(bossPhaseLabel, `PHASE {phaseIndex}`)
	local statusText = ""
	if result == nil then
		if phase == "ready" then
			local readyTime = if finiteNumber(data.readyTime)
				then math.max(0, math.ceil(data.readyTime))
				else 0
			statusText = `READY IN {readyTime}s`
		elseif phase == "fight" then
			local timeLeft = if finiteNumber(data.timeLeft) then math.max(0, math.ceil(data.timeLeft)) else 0
			statusText = `{timeLeft}s LEFT`
		else
			statusText = string.upper(phase)
		end
	end
	if nextFightActive and nextLocalEliminated then
		statusText ..= " | SPECTATING"
	end
	setText(bossStatusLabel, statusText)
	updateBossHealth(if finiteNumber(data.fraction) then data.fraction else 0)
	applyDanger(combatActive and data.danger == true)

	if result ~= nil then
		if result ~= lastResult or (resultPanel ~= nil and not resultPanel.Visible) then
			showResult(data, result)
		elseif result == "victory" then
			local actualRewardText = resultRewardLine(data)
			setText(rewardText, actualRewardText)
			setVisible(rewardText, actualRewardText ~= "")
		else
			setText(rewardText, "")
			setVisible(rewardText, false)
		end
	else
		setVisible(resultPanel, false)
	end
	lastResult = result
end

local function applyAttackResult(data: any)
	if type(data) ~= "table" then
		return
	end
	local action = if type(data.action) == "string" then string.lower(data.action) else "attack"
	local isDodge = action == "dodge"
	local accepted = data.accepted == true or data.ok == true
	if isDodge then
		dodgePending = false
		dodgeRequestRevision += 1
		restoreAvatarPose(0.08)
	end
	if accepted then
		if isDodge then
			lastDodgeAt = os.clock()
			showStatus("DODGE!", Color3.fromRGB(124, 218, 255), 0.7)
			pulseCamera(2)
			return
		end
		local damage = if finiteNumber(data.damage) then math.max(0, data.damage) else nil
		showHitMarker(damage)
		pulseBossHit()
		pulseCamera(2.5)
		return
	end
	local reason = if type(data.reason) == "string" then string.lower(data.reason) else ""
	if not isDodge then
		if reason ~= "cooldown" then
			lastAttackAt = -math.huge
		end
		restoreAvatarPose(0.08)
		restoreToolGrips()
	end
	if string.find(reason, "range", 1, true) ~= nil or string.find(reason, "closer", 1, true) ~= nil then
		showStatus("GET CLOSER TO THE BOSS", Color3.fromRGB(255, 207, 112))
	elseif string.find(reason, "down", 1, true) ~= nil then
		showStatus("YOU CANNOT ACT WHILE DOWN", Color3.fromRGB(255, 132, 132))
	elseif reason == "facing" then
		showStatus("FACE THE BOSS TO ATTACK", Color3.fromRGB(255, 207, 112))
	elseif reason == "cooldown" then
		showStatus(
			if isDodge then "DODGE RECHARGING" else "WEAPON RECHARGING",
			Color3.fromRGB(168, 205, 255),
			0.8
		)
	elseif reason == "blocked" then
		showStatus("ATTACK BLOCKED - DODGE!", Color3.fromRGB(255, 160, 112), 1)
	elseif reason == "inactive" or reason == "unavailable" then
		showStatus("COMBAT IS NOT ACTIVE", Color3.fromRGB(255, 180, 132))
	elseif reason == "notparty" then
		showStatus("YOU ARE NOT IN THIS DUNGEON PARTY", Color3.fromRGB(255, 180, 132))
	elseif string.find(reason, "dodge", 1, true) ~= nil then
		showStatus("DODGE RECHARGING", Color3.fromRGB(168, 205, 255), 0.8)
	elseif isDodge then
		showStatus("DODGE NOT AVAILABLE", Color3.fromRGB(255, 180, 132), 0.9)
	elseif
		reason ~= ""
		and string.find(reason, "cooldown", 1, true) == nil
		and string.find(reason, "fast", 1, true) == nil
	then
		showStatus(string.upper(reason), Color3.fromRGB(255, 180, 132))
	end
end

local function applyPortalNotice(data: any)
	local message = if type(data) == "table" and type(data.message) == "string"
		then data.message
		else "The dungeon portal is unavailable right now."
	showStatus(string.upper(message), Color3.fromRGB(255, 150, 150), 4)
	if dungeonVisible then
		return
	end
	local currentHud = hud
	if currentHud == nil then
		return
	end
	currentHud.Enabled = true
	setVisible(resultPanel, true)
	setText(resultTitle, "DUNGEON NOTICE")
	setText(resultDetail, message)
	setVisible(rewardText, false)
	task.delay(5, function()
		if not dungeonVisible and hud == currentHud then
			currentHud.Enabled = false
			setVisible(resultPanel, false)
		end
	end)
end

local function tryAttack()
	if not combatActive or dodgePending or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	local now = os.clock()
	if now - lastAttackAt < attackCooldown then
		return
	end
	lastAttackAt = now
	playAttackPose()
	swingEquippedTool()
	requestRemote:FireServer({ action = "DungeonAttack" })
end

local function tryDodge()
	if not combatActive or dodgePending or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	local now = os.clock()
	if now - lastDodgeAt < dodgeCooldown then
		return
	end
	dodgePending = true
	dodgeRequestRevision += 1
	local revision = dodgeRequestRevision
	showStatus("DODGE REQUESTED", Color3.fromRGB(168, 205, 255), 0.7)
	playDodgePose()
	requestRemote:FireServer({ action = "DungeonDodge" })
	task.delay(DODGE_ACK_TIMEOUT, function()
		if not dodgePending or dodgeRequestRevision ~= revision then
			return
		end
		dodgePending = false
		dodgeRequestRevision += 1
		restoreAvatarPose(0.08)
		showStatus("DODGE NOT CONFIRMED - TRY AGAIN", Color3.fromRGB(255, 180, 132), 1.2)
	end)
end

local function updateInputHint(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		setVisible(controlHint, false)
		return
	elseif fightActive and localEliminated then
		setText(controlHint, "SPECTATING - YOU ARE DOWN")
	elseif string.find(inputType.Name, "Gamepad", 1, true) ~= nil then
		setText(controlHint, "R2 ATTACK   |   B DODGE")
	else
		setText(controlHint, "LMB / F ATTACK   |   Q DODGE")
	end
	setVisible(controlHint, combatActive or (fightActive and localEliminated))
end

local function disconnectHudButtons()
	if attackButtonConnection ~= nil then
		attackButtonConnection:Disconnect()
		attackButtonConnection = nil
	end
	if dodgeButtonConnection ~= nil then
		dodgeButtonConnection:Disconnect()
		dodgeButtonConnection = nil
	end
end

local function clearHudReferences()
	disconnectHudButtons()
	hud = nil
	bossBar = nil
	bossNameLabel = nil
	bossStatusLabel = nil
	bossPhaseLabel = nil
	bossHealthFill = nil
	bossHealthText = nil
	playerPanel = nil
	playerHealthFill = nil
	playerHealthText = nil
	weaponNameLabel = nil
	cooldownLabel = nil
	controls = nil
	attackButton = nil
	dodgeButton = nil
	controlHint = nil
	statusToast = nil
	hitMarker = nil
	dangerBanner = nil
	dangerVignette = nil
	resultPanel = nil
	resultTitle = nil
	resultDetail = nil
	rewardText = nil
end

local function bindHud(instance: Instance)
	if not instance:IsA("ScreenGui") then
		warn(
			"PlayerGui.DungeonHUD must be an authored ScreenGui; dungeon controls remain keyboard/gamepad enabled"
		)
		return
	end
	clearHudReferences()
	hud = instance
	bossBar = childOfClass(instance, "BossBar", "Frame")
	if bossBar ~= nil then
		bossNameLabel = childOfClass(bossBar, "BossName", "TextLabel")
		bossStatusLabel = childOfClass(bossBar, "StatusLine", "TextLabel")
		bossPhaseLabel = childOfClass(bossBar, "PhaseLabel", "TextLabel")
		local track = childOfClass(bossBar, "HealthTrack", "Frame")
		bossHealthFill = childOfClass(track, "Fill", "Frame")
		bossHealthText = childOfClass(track, "HealthText", "TextLabel")
	end
	playerPanel = childOfClass(instance, "PlayerPanel", "Frame")
	if playerPanel ~= nil then
		weaponNameLabel = childOfClass(playerPanel, "WeaponName", "TextLabel")
		cooldownLabel = childOfClass(playerPanel, "CooldownText", "TextLabel")
		local track = childOfClass(playerPanel, "HealthTrack", "Frame")
		playerHealthFill = childOfClass(track, "Fill", "Frame")
		playerHealthText = childOfClass(track, "HealthText", "TextLabel")
	end
	controls = childOfClass(instance, "Controls", "Frame")
	if controls ~= nil then
		attackButton = childOfClass(controls, "AttackButton", "TextButton")
		dodgeButton = childOfClass(controls, "DodgeButton", "TextButton")
	end
	controlHint = childOfClass(instance, "ControlHint", "TextLabel")
	statusToast = childOfClass(instance, "StatusToast", "TextLabel")
	hitMarker = childOfClass(instance, "HitMarker", "TextLabel")
	dangerBanner = childOfClass(instance, "DangerBanner", "TextLabel")
	dangerVignette = childOfClass(instance, "DangerVignette", "Frame")
	resultPanel = childOfClass(instance, "ResultPanel", "Frame")
	if resultPanel ~= nil then
		resultTitle = childOfClass(resultPanel, "ResultTitle", "TextLabel")
		resultDetail = childOfClass(resultPanel, "ResultDetail", "TextLabel")
		rewardText = childOfClass(resultPanel, "RewardText", "TextLabel")
	end
	if attackButton ~= nil then
		attackButtonConnection = attackButton.Activated:Connect(tryAttack)
	end
	if dodgeButton ~= nil then
		dodgeButtonConnection = dodgeButton.Activated:Connect(tryDodge)
	end
	updateInputHint(UserInputService:GetLastInputType())
	if latestDungeonState ~= nil then
		applyDungeonState(latestDungeonState)
	else
		instance.Enabled = false
	end
	if humanoid ~= nil then
		updatePlayerHealth(humanoid.Health)
	end
end

stateRemote.OnClientEvent:Connect(function(packet: any)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "DungeonState" then
		applyDungeonState(packet.data)
	elseif packet.kind == "DungeonAttackResult" then
		applyAttackResult(packet.data)
	elseif packet.kind == "PortalNotice" then
		applyPortalNotice(packet.data)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or not combatActive then
		return
	end
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.F
		or input.KeyCode == Enum.KeyCode.ButtonR2
	then
		tryAttack()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
		tryDodge()
	end
end)

UserInputService.LastInputTypeChanged:Connect(updateInputHint)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCameraPresentation)

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function(removingCharacter: Model)
	if removingCharacter == character then
		disconnectCharacter()
	end
end)
if player.Character ~= nil then
	task.spawn(bindCharacter, player.Character)
end

playerGui.ChildAdded:Connect(function(instance: Instance)
	if dungeonVisible or Template:GetAttribute("RuntimeMode") == "dungeon" then
		suppressLobbyGuiRoot(instance)
	end
	if instance.Name == "DungeonHUD" then
		bindHud(instance)
	end
end)
playerGui.DescendantAdded:Connect(function(instance: Instance)
	if not dungeonVisible and Template:GetAttribute("RuntimeMode") ~= "dungeon" then
		return
	end
	local root = instance
	while root.Parent ~= nil and root.Parent ~= playerGui do
		root = root.Parent
	end
	if root.Parent == playerGui and LOBBY_GUI_ROOTS[root.Name] == true then
		disableRememberedGui(instance)
	end
end)
playerGui.ChildRemoved:Connect(function(instance: Instance)
	if instance == hud then
		clearHudReferences()
	end
end)

local existingHud = playerGui:FindFirstChild("DungeonHUD")
if existingHud ~= nil then
	bindHud(existingHud)
end
if Template:GetAttribute("RuntimeMode") == "dungeon" then
	suppressLobbyGuis()
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	if fightActive then
		bossResolveClock += deltaTime
		if bossResolveClock >= 1 then
			bossResolveClock = 0
			resolveBossPresentation()
		end
		local visual = bossVisual
		local basePivot = bossVisualBase
		if
			not GuiService.ReducedMotionEnabled
			and visual ~= nil
			and visual.Parent ~= nil
			and basePivot ~= nil
		then
			local elapsed = os.clock() - bossIdleStartedAt
			local wave = math.sin(elapsed * math.pi * 0.8)
			visual:PivotTo(
				basePivot * CFrame.new(0, wave * 0.35, 0) * CFrame.Angles(0, wave * math.rad(2), 0)
			)
		end
	end
	local now = os.clock()
	local attackRemaining = math.max(0, attackCooldown - (now - lastAttackAt))
	local dodgeRemaining = math.max(0, dodgeCooldown - (now - lastDodgeAt))
	if fightActive and localEliminated then
		setText(cooldownLabel, "SPECTATING - DOWN")
	elseif attackRemaining > 0 then
		setText(cooldownLabel, `READY IN {string.format("%.1f", attackRemaining)}s`)
	elseif fightActive then
		setText(cooldownLabel, "WEAPON READY")
	else
		setText(cooldownLabel, "GET READY")
	end
	local currentAttackButton = attackButton
	if currentAttackButton ~= nil then
		currentAttackButton.Active = combatActive and not dodgePending and attackRemaining <= 0
		currentAttackButton.Text = if localEliminated
			then "DOWN"
			elseif attackRemaining > 0 then string.format("%.1f", attackRemaining)
			else "ATTACK"
		currentAttackButton.BackgroundColor3 = if localEliminated
				or attackRemaining > 0
				or dodgePending
			then Color3.fromRGB(51, 67, 82)
			else Color3.fromRGB(38, 151, 224)
	end
	local currentDodgeButton = dodgeButton
	if currentDodgeButton ~= nil then
		currentDodgeButton.Active = combatActive and not dodgePending and dodgeRemaining <= 0
		currentDodgeButton.Text = if localEliminated
			then "DOWN"
			elseif dodgePending then "WAIT..."
			elseif dodgeRemaining > 0 then string.format("%.1f", dodgeRemaining)
			else "DODGE"
		currentDodgeButton.BackgroundColor3 = if localEliminated
				or dodgePending
				or dodgeRemaining > 0
			then Color3.fromRGB(58, 61, 84)
			else Color3.fromRGB(96, 78, 194)
	end
end)

task.delay(12, function()
	if hud == nil then
		warn(
			"PlayerGui.DungeonHUD is unavailable; mouse, keyboard, and gamepad dungeon controls remain active"
		)
	end
end)

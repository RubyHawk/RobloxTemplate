--!strict

-- Lobby portal binder. Dungeon combat/HUD behavior lives in
-- Dungeon.client.luau; this script only owns the authored pad, roster sign, and
-- portal notices. All gameplay decisions remain server-authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local RemoteNames = require(Shared.RemoteNames)

if Config.features.dungeon ~= true then
	return
end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Reserved dungeon servers never need lobby portal remotes or world visuals.
-- Disable the authored sign whether it has replicated yet or arrives later,
-- then stop before waiting for any portal-specific instances.
if Template:GetAttribute("RuntimeMode") == "dungeon" then
	local function disablePortalSign(instance: Instance)
		if instance.Name == "PortalSign" and instance:IsA("BillboardGui") then
			instance.Enabled = false
		end
	end
	for _, instance in playerGui:GetChildren() do
		disablePortalSign(instance)
	end
	playerGui.ChildAdded:Connect(disablePortalSign)
	return
end

local sign: BillboardGui? = nil
local padModel: Model? = nil
local platform: BasePart? = nil
local glowRing: BasePart? = nil
local vortex: BasePart? = nil
local titleCountdown: TextLabel? = nil
local statusLine: TextLabel? = nil
local slots: { Frame } = {}
local bossNameLabel: TextLabel? = nil
local bossPrevButton: TextButton? = nil
local bossNextButton: TextButton? = nil
local bossSelectorConnections: { RBXScriptConnection } = {}
local currentBossId: string? = nil
-- Forward-declared so bindPortalSign (defined above the remote lookups) can wire
-- the authored selector buttons to it; assigned once the request remote exists.
local cycleBoss: (direction: number) -> ()
local latestPortalState: any = nil
local latestPortalNotice: string? = nil
local portalNoticeRevision = 0
local padChildAddedConnection: RBXScriptConnection? = nil
local padChildRemovedConnection: RBXScriptConnection? = nil

local function textChild(parent: Instance?, name: string): TextLabel?
	if parent == nil then
		return nil
	end
	local child = parent:FindFirstChild(name)
	return if child ~= nil and child:IsA("TextLabel") then child else nil
end

local function applyPortalState(data: any)
	if type(data) ~= "table" then
		return
	end
	local occupants = if type(data.occupants) == "table" then data.occupants else {}
	for index, slot in slots do
		local occupant = occupants[index]
		if type(occupant) == "table" and type(occupant.userId) == "number" then
			local portrait = slot:FindFirstChild("Portrait")
			if portrait ~= nil and portrait:IsA("ImageLabel") then
				portrait.Image = `rbxthumb://type=AvatarHeadShot&id={occupant.userId}&w=150&h=150`
			end
			local nameLabel = textChild(slot, "NameLabel")
			if nameLabel ~= nil then
				nameLabel.Text = if type(occupant.name) == "string" then occupant.name else ""
			end
			slot.Visible = true
		else
			slot.Visible = false
		end
	end

	local count = if type(data.count) == "number" then data.count else #occupants
	local partyMax = if type(data.partyMax) == "number" then data.partyMax else count
	local countdown = data.countdown
	local launching = data.launching == true
	local countdownLabel = titleCountdown
	if countdownLabel ~= nil then
		if launching then
			countdownLabel.Text = "GO"
			countdownLabel.Visible = true
		elseif type(countdown) == "number" and countdown > 0 then
			countdownLabel.Text = tostring(countdown)
			countdownLabel.Visible = true
		else
			countdownLabel.Visible = false
		end
	end

	local status = statusLine
	if status ~= nil then
		if launching then
			status.Text = "ENTERING THE DUNGEON..."
		elseif count > 0 then
			local seconds = if type(countdown) == "number" then countdown else 0
			status.Text = `PARTY {math.min(count, partyMax)}/{partyMax} - ENTERING IN {seconds}s`
		else
			status.Text = "STAND ON THE PORTAL TO ENTER THE DUNGEON"
		end
	end

	currentBossId = if type(data.bossId) == "string" then data.bossId else currentBossId
	local nameLabel = bossNameLabel
	if nameLabel ~= nil then
		nameLabel.Text = if type(data.bossName) == "string" then string.upper(data.bossName) else ""
	end
	-- Only the pad leader (or a player alone before anyone leads) can change the
	-- party's boss; others see the party's boss read-only.
	local leaderUserId = data.leaderUserId
	local canPick = leaderUserId == nil or leaderUserId == Players.LocalPlayer.UserId
	if bossPrevButton ~= nil then
		bossPrevButton.Visible = canPick
	end
	if bossNextButton ~= nil then
		bossNextButton.Visible = canPick
	end
end

local function applyPortalNotice(message: string)
	local status = statusLine
	if status ~= nil then
		status.Text = string.upper(message)
	end
end

local function restoreAfterPortalNotice()
	if latestPortalState ~= nil then
		applyPortalState(latestPortalState)
	end
end

local function refreshPortalAdornee()
	local currentSign = sign
	local currentPlatform = platform
	if
		currentSign ~= nil
		and currentSign.Parent ~= nil
		and currentPlatform ~= nil
		and currentPlatform.Parent ~= nil
	then
		currentSign.Adornee = currentPlatform
		currentSign.Enabled = true
	elseif currentSign ~= nil and currentSign.Parent ~= nil then
		currentSign.Adornee = nil
		currentSign.Enabled = false
	end
end

local function bindPortalSign(instance: Instance)
	if not instance:IsA("BillboardGui") then
		warn("PlayerGui.PortalSign must be an authored BillboardGui; lobby portal status is hidden")
		return
	end
	sign = instance
	table.clear(slots)
	local card = instance:FindFirstChild("Card")
	if card ~= nil and card:IsA("Frame") then
		titleCountdown = textChild(card, "Countdown")
		statusLine = textChild(card, "StatusLine")
		local roster = card:FindFirstChild("Roster")
		if roster ~= nil then
			for index = 1, 4 do
				local slot = roster:FindFirstChild(`Slot{index}`)
				if slot ~= nil and slot:IsA("Frame") then
					slots[index] = slot
				end
			end
		end
		for _, connection in bossSelectorConnections do
			connection:Disconnect()
		end
		table.clear(bossSelectorConnections)
		local selector = card:FindFirstChild("BossSelector")
		if selector ~= nil then
			bossNameLabel = textChild(selector, "BossName")
			local prev = selector:FindFirstChild("Prev")
			local nextButton = selector:FindFirstChild("Next")
			bossPrevButton = if prev ~= nil and prev:IsA("TextButton") then prev else nil
			bossNextButton = if nextButton ~= nil and nextButton:IsA("TextButton") then nextButton else nil
			if bossPrevButton ~= nil then
				table.insert(
					bossSelectorConnections,
					bossPrevButton.Activated:Connect(function()
						cycleBoss(-1)
					end)
				)
			end
			if bossNextButton ~= nil then
				table.insert(
					bossSelectorConnections,
					bossNextButton.Activated:Connect(function()
						cycleBoss(1)
					end)
				)
			end
		else
			bossNameLabel = nil
			bossPrevButton = nil
			bossNextButton = nil
		end
	else
		titleCountdown = nil
		statusLine = nil
		bossNameLabel = nil
		warn("PlayerGui.PortalSign.Card is unavailable; lobby portal status is hidden")
	end
	refreshPortalAdornee()
	if latestPortalState ~= nil then
		applyPortalState(latestPortalState)
	end
	if latestPortalNotice ~= nil then
		applyPortalNotice(latestPortalNotice)
	end
end

local function disconnectPadConnections()
	if padChildAddedConnection ~= nil then
		padChildAddedConnection:Disconnect()
		padChildAddedConnection = nil
	end
	if padChildRemovedConnection ~= nil then
		padChildRemovedConnection:Disconnect()
		padChildRemovedConnection = nil
	end
end

local function refreshPortalPadParts()
	local currentPad = padModel
	if currentPad == nil or currentPad.Parent == nil then
		platform = nil
		glowRing = nil
		vortex = nil
		refreshPortalAdornee()
		return
	end
	local candidatePlatform = currentPad:FindFirstChild("Platform")
	platform = if candidatePlatform ~= nil and candidatePlatform:IsA("BasePart")
		then candidatePlatform
		else nil
	local candidateGlow = currentPad:FindFirstChild("GlowRing")
	glowRing = if candidateGlow ~= nil and candidateGlow:IsA("BasePart") then candidateGlow else nil
	local candidateVortex = currentPad:FindFirstChild("Vortex")
	vortex = if candidateVortex ~= nil and candidateVortex:IsA("BasePart") then candidateVortex else nil
	refreshPortalAdornee()
end

local function bindPortalPad(instance: Instance)
	if not instance:IsA("Model") then
		warn("Workspace.PortalPad must be an authored Model; lobby portal visuals are disabled")
		return
	end
	disconnectPadConnections()
	padModel = instance
	padChildAddedConnection = instance.ChildAdded:Connect(refreshPortalPadParts)
	padChildRemovedConnection = instance.ChildRemoved:Connect(refreshPortalPadParts)
	refreshPortalPadParts()
end

local remotes = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local stateRemote = remotes:WaitForChild(RemoteNames.state) :: RemoteEvent
local requestRemote = remotes:WaitForChild(RemoteNames.request) :: RemoteEvent

-- The boss catalog is shared config, so the client cycles it locally and asks the
-- server to record the choice. The server validates the id, saves it as the
-- player's personal default, and (when they lead the pad) applies it to the party.
cycleBoss = function(direction: number)
	local bosses = Config.dungeon.bosses
	if #bosses == 0 then
		return
	end
	local index = 1
	for order, boss in bosses do
		if boss.id == currentBossId then
			index = order
			break
		end
	end
	local nextBoss = bosses[((index - 1 + direction) % #bosses) + 1]
	requestRemote:FireServer({ action = "SelectDungeonBoss", payload = { bossId = nextBoss.id } })
end

stateRemote.OnClientEvent:Connect(function(packet: any)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "PortalState" then
		latestPortalState = packet.data
		applyPortalState(packet.data)
		if latestPortalNotice ~= nil then
			applyPortalNotice(latestPortalNotice)
		end
	elseif packet.kind == "PortalNotice" then
		local message = if type(packet.data) == "table" and type(packet.data.message) == "string"
			then packet.data.message
			else "The dungeon portal is unavailable right now."
		portalNoticeRevision += 1
		local revision = portalNoticeRevision
		latestPortalNotice = message
		applyPortalNotice(message)
		task.delay(6, function()
			if portalNoticeRevision ~= revision then
				return
			end
			latestPortalNotice = nil
			restoreAfterPortalNotice()
		end)
	end
end)

playerGui.ChildAdded:Connect(function(instance: Instance)
	if instance.Name == "PortalSign" then
		bindPortalSign(instance)
	end
end)

playerGui.ChildRemoved:Connect(function(instance: Instance)
	if instance == sign then
		sign = nil
		titleCountdown = nil
		statusLine = nil
		bossNameLabel = nil
		bossPrevButton = nil
		bossNextButton = nil
		for _, connection in bossSelectorConnections do
			connection:Disconnect()
		end
		table.clear(bossSelectorConnections)
		table.clear(slots)
	end
end)

Workspace.ChildAdded:Connect(function(instance: Instance)
	if instance.Name == "PortalPad" then
		bindPortalPad(instance)
	end
end)

Workspace.ChildRemoved:Connect(function(instance: Instance)
	if instance == padModel then
		disconnectPadConnections()
		padModel = nil
		platform = nil
		glowRing = nil
		vortex = nil
		refreshPortalAdornee()
	end
end)

local existingSign = playerGui:FindFirstChild("PortalSign")
if existingSign ~= nil then
	bindPortalSign(existingSign)
end
local existingPad = Workspace:FindFirstChild("PortalPad")
if existingPad ~= nil then
	bindPortalPad(existingPad)
end

task.delay(15, function()
	if sign == nil and Template:GetAttribute("RuntimeMode") ~= "dungeon" then
		warn("PlayerGui.PortalSign is unavailable; lobby portal status is hidden")
	end
end)
task.delay(20, function()
	if platform == nil and Template:GetAttribute("RuntimeMode") ~= "dungeon" then
		warn("Workspace.PortalPad is unavailable; lobby portal visuals are disabled")
	end
end)

local clock = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	clock += deltaTime
	local pulse = 0.5 + 0.5 * math.sin(clock * 2.2)
	local currentGlow = glowRing
	if currentGlow ~= nil and currentGlow.Parent ~= nil then
		currentGlow.Transparency = 0.3 + 0.25 * (1 - pulse)
	end
	local currentVortex = vortex
	if currentVortex ~= nil and currentVortex.Parent ~= nil then
		currentVortex.CFrame = currentVortex.CFrame * CFrame.Angles(math.rad(60 * deltaTime), 0, 0)
	end
end)

--!strict

-- Client binder for the dungeon portal. Everything visual is already authored:
-- the BillboardGui above the pad (PortalSign) and the boss HUD (DungeonHUD). This
-- script only adorns, animates authored parts, and writes text/images/visibility
-- from the server's PortalState / DungeonState broadcasts. It never creates,
-- clones, or destroys GuiObjects, so the server stays the only authority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local RemoteNames = require(Shared.RemoteNames)

if Config.features.dungeon ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local sign = playerGui:WaitForChild("PortalSign", 15)
local hud = playerGui:WaitForChild("DungeonHUD", 15)
if sign == nil or not sign:IsA("BillboardGui") or hud == nil or not hud:IsA("ScreenGui") then
	warn("PortalSign/DungeonHUD are missing; rebuild the place to restore the dungeon portal UI")
	return
end

local padModel = Workspace:WaitForChild("PortalPad", 20)
if padModel == nil then
	warn("Workspace.PortalPad is missing; rebuild the playable place to restore the dungeon portal")
	return
end
local platform = padModel:WaitForChild("Platform") :: BasePart
local glowRing = padModel:FindFirstChild("GlowRing")
local vortex = padModel:FindFirstChild("Vortex")

sign.Adornee = platform
sign.Enabled = true

local function child(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name)
end

local card = sign:WaitForChild("Card") :: Frame
local titleCountdown = child(card, "Countdown")
local statusLine = child(card, "StatusLine")
local roster = child(card, "Roster")

local slots: { Frame } = {}
if roster ~= nil then
	for index = 1, 4 do
		local slot = roster:FindFirstChild(`Slot{index}`)
		if slot ~= nil and slot:IsA("Frame") then
			slots[index] = slot
		end
	end
end

local bossBar = child(hud, "BossBar")
local resultBanner = child(hud, "ResultBanner")

local function setText(instance: Instance?, text: string)
	if instance ~= nil and instance:IsA("TextLabel") then
		instance.Text = text
	end
end

local function setVisible(instance: Instance?, visible: boolean)
	if instance ~= nil and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

-- ---- Portal roster + countdown -------------------------------------------------

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
			setText(
				slot:FindFirstChild("NameLabel"),
				if type(occupant.name) == "string" then occupant.name else ""
			)
			slot.Visible = true
		else
			slot.Visible = false
		end
	end

	local count = if type(data.count) == "number" then data.count else #occupants
	local partyMax = if type(data.partyMax) == "number" then data.partyMax else count
	local countdown = data.countdown
	local launching = data.launching == true

	if titleCountdown ~= nil and titleCountdown:IsA("TextLabel") then
		if launching then
			titleCountdown.Text = "GO"
			titleCountdown.Visible = true
		elseif type(countdown) == "number" and countdown > 0 then
			titleCountdown.Text = tostring(countdown)
			titleCountdown.Visible = true
		else
			titleCountdown.Visible = false
		end
	end

	if launching then
		setText(statusLine, "ENTERING THE DUNGEON…")
	elseif count > 0 then
		local seconds = if type(countdown) == "number" then countdown else 0
		setText(statusLine, `PARTY {math.min(count, partyMax)}/{partyMax} • ENTERING IN {seconds}s`)
	else
		setText(statusLine, "STAND ON THE PORTAL TO ENTER THE DUNGEON")
	end
end

-- ---- Dungeon boss HUD ----------------------------------------------------------

local function applyDungeonState(data: any)
	if type(data) ~= "table" then
		return
	end
	local active = data.active == true
	hud.Enabled = active
	setVisible(bossBar, active)
	if not active then
		setVisible(resultBanner, false)
		return
	end

	if bossBar ~= nil then
		setText(
			bossBar:FindFirstChild("BossName"),
			if type(data.bossName) == "string" then data.bossName else "BOSS"
		)
		local track = bossBar:FindFirstChild("HealthTrack")
		local fraction = if type(data.fraction) == "number" then math.clamp(data.fraction, 0, 1) else 0
		if track ~= nil then
			local fill = track:FindFirstChild("Fill")
			if fill ~= nil and fill:IsA("GuiObject") then
				fill.Size = UDim2.fromScale(fraction, 1)
			end
			setText(track:FindFirstChild("HealthText"), `{math.floor(fraction * 100 + 0.5)}%`)
		end
		local timeLeft = if type(data.timeLeft) == "number" then data.timeLeft else 0
		setText(
			bossBar:FindFirstChild("StatusLine"),
			if data.phase == "fight" then `{timeLeft}s LEFT` else ""
		)
	end

	if resultBanner ~= nil and resultBanner:IsA("TextLabel") then
		if data.result == "victory" then
			resultBanner.Text = "VICTORY!"
			resultBanner.TextColor3 = Color3.fromRGB(255, 235, 153)
			resultBanner.Visible = true
		elseif data.result == "defeat" then
			resultBanner.Text = "DEFEATED"
			resultBanner.TextColor3 = Color3.fromRGB(255, 130, 130)
			resultBanner.Visible = true
		else
			resultBanner.Visible = false
		end
	end
end

-- ---- State channel -------------------------------------------------------------

local remotes = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local stateRemote = remotes:WaitForChild(RemoteNames.state) :: RemoteEvent

stateRemote.OnClientEvent:Connect(function(packet: any)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "PortalState" then
		applyPortalState(packet.data)
	elseif packet.kind == "DungeonState" then
		applyDungeonState(packet.data)
	elseif packet.kind == "PortalNotice" then
		local message = if type(packet.data) == "table" and type(packet.data.message) == "string"
			then packet.data.message
			else "The dungeon portal is unavailable right now."
		setText(statusLine, string.upper(message))
	end
end)

-- ---- Ambient pad animation -----------------------------------------------------

local clock = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	clock += deltaTime
	local pulse = 0.5 + 0.5 * math.sin(clock * 2.2)
	if glowRing ~= nil and glowRing:IsA("BasePart") then
		glowRing.Transparency = 0.3 + 0.25 * (1 - pulse)
	end
	if vortex ~= nil and vortex:IsA("BasePart") then
		vortex.CFrame = vortex.CFrame * CFrame.Angles(math.rad(60 * deltaTime), 0, 0)
	end
end)

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local StagePlatformService = {}

local slotsByPlayer: { [Player]: number } = {}
local playersBySlot: { [number]: Player } = {}
local warnedMissingCenter = false
local cachedCenter: CFrame? = nil
local cachedFirstRelative: CFrame? = nil
local started = false

local function publishedOrigin(slot: number): CFrameValue?
	local folder = Template:FindFirstChild(Config.towerDefense.platformOriginsFolderName)
	if folder == nil or not folder:IsA("Folder") then
		return nil
	end
	local value = folder:FindFirstChild(`Slot_{string.format("%02d", slot)}`)
	return if value ~= nil and value:IsA("CFrameValue") then value else nil
end

local function publishOwner(slot: number, player: Player?)
	local value = publishedOrigin(slot)
	if value == nil then
		return
	end
	-- OwnerUserId is written last so clients can treat its attribute signal as
	-- one atomic ownership refresh after the public display fields are ready.
	value:SetAttribute("OwnerName", if player ~= nil then player.Name else "")
	value:SetAttribute("OwnerDisplayName", if player ~= nil then player.DisplayName else "")
	value:SetAttribute("OwnerUserId", if player ~= nil then player.UserId else 0)
end

local function descendantNamed(names: { string }): BasePart?
	local allowed: { [string]: boolean } = {}
	for _, name in names do
		allowed[name] = true
	end
	for _, descendant in Workspace:GetDescendants() do
		if allowed[descendant.Name] and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function firstPlatformOrigin(): BasePart?
	local island = Workspace:FindFirstChild(Config.towerDefense.firstPlatformIslandName)
	local platform = if island ~= nil
		then island:FindFirstChild(Config.towerDefense.platformModelName)
		else nil
	local origin = if platform ~= nil
		then platform:FindFirstChild(Config.towerDefense.platformOriginName)
		else nil
	return if origin ~= nil and origin:IsA("BasePart") then origin else nil
end

local function configuredRelativeFrame(): CFrame
	local offset = Config.towerDefense.firstPlatformOffsetFromCenter
	return CFrame.new(offset[1], offset[2], offset[3])
		* CFrame.Angles(0, math.rad(Config.towerDefense.firstPlatformYawDegrees), 0)
end

local function layout(): (CFrame?, CFrame?)
	if cachedCenter ~= nil and cachedFirstRelative ~= nil then
		return cachedCenter, cachedFirstRelative
	end
	local center = descendantNamed(Config.towerDefense.centerPartNames)
	if center ~= nil then
		cachedCenter = center.CFrame
		cachedFirstRelative = configuredRelativeFrame()
		return cachedCenter, cachedFirstRelative
	end
	local firstOrigin = firstPlatformOrigin()
	if firstOrigin == nil then
		return nil, nil
	end
	if not warnedMissingCenter then
		warn("Stage platform center is missing; using the legacy slot-one GamePlatform origin")
		warnedMissingCenter = true
	end
	local relative = configuredRelativeFrame()
	cachedCenter = firstOrigin.CFrame * relative:Inverse()
	cachedFirstRelative = relative
	return cachedCenter, cachedFirstRelative
end

local function claimSlot(player: Player): number?
	local existing = slotsByPlayer[player]
	if existing ~= nil then
		player:SetAttribute("TowerDefensePlatformSlot", existing)
		publishOwner(existing, player)
		return existing
	end
	for slot = 1, Config.towerDefense.platformSlotCount do
		if playersBySlot[slot] == nil then
			slotsByPlayer[player] = slot
			playersBySlot[slot] = player
			player:SetAttribute("TowerDefensePlatformSlot", slot)
			publishOwner(slot, player)
			return slot
		end
	end
	return nil
end

function StagePlatformService.slotFor(player: Player): number?
	return claimSlot(player)
end

function StagePlatformService.hasPlatform(player: Player): boolean
	local center = layout()
	return center ~= nil and claimSlot(player) ~= nil
end

function StagePlatformService.originForSlot(slot: number): CFrame?
	if slot % 1 ~= 0 or slot < 1 or slot > Config.towerDefense.platformSlotCount then
		return nil
	end
	local center, firstRelative = layout()
	if center == nil or firstRelative == nil then
		return nil
	end
	local yaw = ((slot - 1) * math.pi * 2) / Config.towerDefense.platformSlotCount
	return center * CFrame.Angles(0, yaw, 0) * firstRelative
end

function StagePlatformService.originFor(player: Player, _stageId: string): CFrame
	local slot = claimSlot(player)
	local origin = if slot ~= nil then StagePlatformService.originForSlot(slot) else nil
	return origin or CFrame.new(0, -10_000, 0)
end

local function originsFolder(): Folder
	local existing = Template:FindFirstChild(Config.towerDefense.platformOriginsFolderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.towerDefense.platformOriginsFolderName
	folder.Parent = Template
	return folder
end

local function publishOrigins()
	local folder = originsFolder()
	local published = 0
	for slot = 1, Config.towerDefense.platformSlotCount do
		local name = `Slot_{string.format("%02d", slot)}`
		local existing = folder:FindFirstChild(name)
		local value: CFrameValue
		if existing ~= nil and existing:IsA("CFrameValue") then
			value = existing
		else
			if existing ~= nil then
				existing:Destroy()
			end
			value = Instance.new("CFrameValue")
			value.Name = name
			value.Parent = folder
		end
		local origin = StagePlatformService.originForSlot(slot)
		if origin ~= nil then
			value.Value = origin
			value:SetAttribute("Slot", slot)
			published += 1
		end
	end
	folder:SetAttribute("SlotCount", Config.towerDefense.platformSlotCount)
	folder:SetAttribute("LayoutAvailable", published == Config.towerDefense.platformSlotCount)
	folder:SetAttribute("ServerMaxPlayers", Players.MaxPlayers)
	folder:SetAttribute(
		"CapacityMatchesSlotCount",
		Players.MaxPlayers == Config.towerDefense.platformSlotCount
	)
	for slot = 1, Config.towerDefense.platformSlotCount do
		publishOwner(slot, playersBySlot[slot])
	end
end

function StagePlatformService.start()
	if started then
		return
	end
	started = true
	publishOrigins()
	if Players.MaxPlayers ~= Config.towerDefense.platformSlotCount then
		warn(
			`This place allows {Players.MaxPlayers} players but has {Config.towerDefense.platformSlotCount} Stagewright platforms. Set Configure Place > Maximum Players to {Config.towerDefense.platformSlotCount}.`
		)
	end
	Players.PlayerAdded:Connect(function(player)
		claimSlot(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		StagePlatformService.forget(player)
	end)
	for _, player in Players:GetPlayers() do
		claimSlot(player)
	end
end

function StagePlatformService.forget(player: Player)
	local slot = slotsByPlayer[player]
	if slot ~= nil then
		playersBySlot[slot] = nil
		publishOwner(slot, nil)
	end
	slotsByPlayer[player] = nil
	player:SetAttribute("TowerDefensePlatformSlot", nil)
end

return StagePlatformService

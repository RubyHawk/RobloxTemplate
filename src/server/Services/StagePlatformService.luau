--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local StageCatalog = require(Shared.StageCatalog)

local StagePlatformService = {}

local slotsByPlayer: { [Player]: number } = {}
local playersBySlot: { [number]: Player } = {}
local cachedCenter: CFrame? = nil
local cachedFirstRelative: CFrame? = nil
local cachedLayoutSource = "Unresolved"
local layoutAttempted = false
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
	local previousOwnerUserId = value:GetAttribute("OwnerUserId")
	-- OwnerUserId is written last so clients can treat its attribute signal as
	-- one atomic ownership refresh after the public display fields are ready.
	value:SetAttribute("OwnerName", if player ~= nil then player.Name else "")
	value:SetAttribute("OwnerDisplayName", if player ~= nil then player.DisplayName else "")
	if player == nil then
		value:SetAttribute("ActiveStageId", "")
	elseif previousOwnerUserId ~= player.UserId then
		value:SetAttribute("ActiveStageId", StageCatalog.defaultStageId())
	end
	value:SetAttribute("OwnerUserId", if player ~= nil then player.UserId else 0)
end

local function uniqueCenterAnchor(names: { string }): (BasePart?, boolean)
	local allowed: { [string]: boolean } = {}
	for _, name in names do
		allowed[name] = true
	end
	local found: BasePart? = nil
	for _, descendant in Workspace:GetDescendants() do
		if allowed[descendant.Name] and descendant:IsA("BasePart") then
			if found ~= nil then
				warn(
					`Stage platform layout is ambiguous: both {found:GetFullName()} and {descendant:GetFullName()} match the configured center anchor names`
				)
				return nil, false
			end
			found = descendant
		end
	end
	return found, true
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
	if layoutAttempted then
		return cachedCenter, cachedFirstRelative
	end
	layoutAttempted = true
	local center, centerContractValid = uniqueCenterAnchor(Config.towerDefense.centerPartNames)
	if not centerContractValid then
		cachedLayoutSource = "AmbiguousCenter"
		return nil, nil
	end
	if center ~= nil then
		cachedCenter = center.CFrame
		cachedFirstRelative = configuredRelativeFrame()
		cachedLayoutSource = "CenterAnchor"
		return cachedCenter, cachedFirstRelative
	end
	local firstOrigin = firstPlatformOrigin()
	if firstOrigin == nil then
		cachedLayoutSource = "Unavailable"
		warn(
			`Stage platform layout is unavailable: expected exactly one center anchor named {table.concat(
				Config.towerDefense.centerPartNames,
				", "
			)} or the legacy slot-one platform origin`
		)
		return nil, nil
	end
	warn("Stage platform center is missing; using the legacy slot-one GamePlatform origin")
	local relative = configuredRelativeFrame()
	cachedCenter = firstOrigin.CFrame * relative:Inverse()
	cachedFirstRelative = relative
	cachedLayoutSource = "LegacyPlatformOrigin"
	return cachedCenter, cachedFirstRelative
end

local function claimSlot(player: Player): number?
	if layout() == nil then
		player:SetAttribute("TowerDefensePlatformSlot", nil)
		return nil
	end
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

function StagePlatformService.publishActiveStage(player: Player, stageId: string): boolean
	if type(stageId) ~= "string" or stageId == "" or #stageId > 80 then
		return false
	end
	local slot = claimSlot(player)
	local value = if slot ~= nil then publishedOrigin(slot) else nil
	if value == nil then
		return false
	end
	value:SetAttribute("ActiveStageId", stageId)
	return true
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
	folder:SetAttribute("LayoutSource", cachedLayoutSource)
	folder:SetAttribute("ServerMaxPlayers", Players.MaxPlayers)
	folder:SetAttribute(
		"CapacityMatchesSlotCount",
		Players.MaxPlayers == Config.towerDefense.platformSlotCount
	)
	for slot = 1, Config.towerDefense.platformSlotCount do
		publishOwner(slot, playersBySlot[slot])
	end
end

local function stowAuthoringArea()
	local authoring = Config.towerDefense.authoringArea
	if type(authoring) ~= "table" or type(authoring.areaName) ~= "string" then
		return
	end
	local area = Workspace:FindFirstChild(authoring.areaName)
	if area == nil then
		return
	end
	area:SetAttribute("StagewrightRuntimeStowed", true)
	area.Parent = ServerStorage
end

function StagePlatformService.start()
	if started then
		return
	end
	started = true
	publishOrigins()
	stowAuthoringArea()
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

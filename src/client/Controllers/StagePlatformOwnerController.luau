--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Template = ReplicatedStorage:WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)

local StagePlatformOwnerController = {}

type SlotBinding = {
	slot: number,
	marker: BillboardGui,
	anchor: Part,
	card: CanvasGroup,
	avatar: ImageLabel,
	fallback: TextLabel,
	ownerName: TextLabel,
	ownerDetail: TextLabel,
}

local localPlayer = Players.LocalPlayer
local initialized = false
local requestedUserIds: { [number]: number } = {}
local bindings: { [number]: SlotBinding } = {}
local watchedPlayers: { [Player]: boolean } = {}
local leavingPlayers: { [Player]: boolean } = {}

local function thumbnailUrl(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

local function createAnchorFolder(): Folder
	local configuredName = Config.towerDefense.platformOwnerAnchorsFolderName
	local existing = Workspace:FindFirstChild(configuredName)
	if
		existing ~= nil
		and existing:IsA("Folder")
		and existing:GetAttribute("StagewrightClientOwned") == true
	then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = if Workspace:FindFirstChild(configuredName) == nil
		then configuredName
		else `{configuredName}_Local`
	folder:SetAttribute("StagewrightClientOwned", true)
	folder.Parent = Workspace
	return folder
end

local function createAnchor(parent: Folder, slot: number, origin: CFrame): Part
	local anchor = Instance.new("Part")
	anchor.Name = `Slot_{string.format("%02d", slot)}`
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Locked = true
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CFrame = origin * CFrame.new(0, Config.towerDefense.platformOwnerMarkerHeight, 0)
	anchor.Parent = parent
	return anchor
end

local function loadAvatar(slot: number, userId: number, avatar: ImageLabel, fallback: TextLabel)
	requestedUserIds[slot] = userId
	task.spawn(function()
		local success, content = pcall(function(): string
			local image = Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
			return image
		end)
		if requestedUserIds[slot] ~= userId then
			return
		end
		if success and content ~= "" then
			avatar.Image = content
			avatar.Visible = true
			fallback.Visible = false
		end
	end)
end

local function ownerForSlot(slot: number): Player?
	for _, player in Players:GetPlayers() do
		if leavingPlayers[player] ~= true and player:GetAttribute("TowerDefensePlatformSlot") == slot then
			return player
		end
	end
	return nil
end

local function applyOwner(binding: SlotBinding, owner: Player?)
	local slot = binding.slot
	local marker = binding.marker
	local anchor = binding.anchor
	local userId = if owner ~= nil then owner.UserId else 0
	requestedUserIds[slot] = userId
	binding.avatar.Image = ""
	binding.avatar.Visible = false
	binding.fallback.Visible = true
	anchor:SetAttribute("OwnerUserId", userId)
	anchor:SetAttribute("OwnerName", if owner ~= nil then owner.Name else "")
	anchor:SetAttribute("OwnerDisplayName", if owner ~= nil then owner.DisplayName else "")
	anchor:SetAttribute("LocalOwner", owner == localPlayer)
	marker:SetAttribute("OwnerUserId", userId)
	marker:SetAttribute("OwnerName", if owner ~= nil then owner.Name else "")
	marker:SetAttribute("OwnerDisplayName", if owner ~= nil then owner.DisplayName else "")
	marker:SetAttribute("LocalOwner", owner == localPlayer)

	if owner == nil then
		binding.card.GroupTransparency = 0.62
		binding.fallback.Text = "OPEN"
		binding.ownerName.Text = "AVAILABLE"
		binding.ownerDetail.Text = `WAITING FOR PLAYER  •  PLATFORM {string.format("%02d", slot)}`
		return
	end

	local isLocalOwner = owner == localPlayer
	binding.card.GroupTransparency = if isLocalOwner then 0 else 0.44
	binding.ownerName.Text = owner.DisplayName
	binding.ownerDetail.Text = if isLocalOwner
		then `@{owner.Name}  •  YOUR PLATFORM {string.format("%02d", slot)}`
		else `@{owner.Name}  •  PLATFORM {string.format("%02d", slot)}`
	if userId > 0 then
		-- Render the real headshot URL immediately while the async API resolves
		-- its canonical content ID.
		binding.avatar.Image = thumbnailUrl(userId)
		binding.avatar.Visible = true
		binding.fallback.Visible = false
		loadAvatar(slot, userId, binding.avatar, binding.fallback)
	else
		-- Studio multi-client players have synthetic negative IDs and no
		-- Roblox account/avatar to request. Never substitute another user.
		binding.fallback.Text = "TEST"
	end
end

local function refreshOwners()
	for slot, binding in bindings do
		applyOwner(binding, ownerForSlot(slot))
	end
end

local function watchPlayer(player: Player)
	if watchedPlayers[player] then
		return
	end
	watchedPlayers[player] = true
	leavingPlayers[player] = nil
	player:GetAttributeChangedSignal("TowerDefensePlatformSlot"):Connect(refreshOwners)
end

local function bindSlot(marker: BillboardGui, origin: CFrameValue, anchor: Part, slot: number)
	local card = marker:FindFirstChild("Card")
	if card == nil or not card:IsA("CanvasGroup") then
		warn(`Stage platform owner marker {slot} is missing Card`)
		return
	end
	local avatar = card:FindFirstChild("Avatar")
	local fallback = card:FindFirstChild("AvatarFallback")
	local ownerName = card:FindFirstChild("OwnerName")
	local ownerDetail = card:FindFirstChild("OwnerDetail")
	if
		avatar == nil
		or not avatar:IsA("ImageLabel")
		or fallback == nil
		or not fallback:IsA("TextLabel")
		or ownerName == nil
		or not ownerName:IsA("TextLabel")
		or ownerDetail == nil
		or not ownerDetail:IsA("TextLabel")
	then
		warn(`Stage platform owner marker {slot} has an invalid authored structure`)
		return
	end

	local function updateOrigin()
		anchor.CFrame = origin.Value * CFrame.new(0, Config.towerDefense.platformOwnerMarkerHeight, 0)
	end

	marker.Adornee = anchor
	marker.Enabled = true
	bindings[slot] = {
		slot = slot,
		marker = marker,
		anchor = anchor,
		card = card,
		avatar = avatar,
		fallback = fallback,
		ownerName = ownerName,
		ownerDetail = ownerDetail,
	}
	updateOrigin()
	origin:GetPropertyChangedSignal("Value"):Connect(updateOrigin)
end

function StagePlatformOwnerController.initialize()
	if initialized then
		return
	end
	initialized = true
	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local authored = playerGui:WaitForChild(Config.towerDefense.platformOwnerMarkersFolderName, 20)
		if authored == nil or not authored:IsA("Folder") then
			warn("Stage platform owner markers are missing from StarterGui")
			return
		end
		local origins = Template:WaitForChild(Config.towerDefense.platformOriginsFolderName, 20)
		if origins == nil or not origins:IsA("Folder") then
			warn("Stage platform owner markers could not find authoritative origins")
			return
		end
		if origins:GetAttribute("LayoutAvailable") ~= true then
			warn("Stage platform owner markers received an unavailable platform layout")
			return
		end

		local anchorFolder = createAnchorFolder()
		for slot = 1, Config.towerDefense.platformSlotCount do
			local slotName = `Slot_{string.format("%02d", slot)}`
			local marker = authored:FindFirstChild(slotName)
			local origin = origins:FindFirstChild(slotName)
			if
				marker ~= nil
				and marker:IsA("BillboardGui")
				and origin ~= nil
				and origin:IsA("CFrameValue")
			then
				local anchor = createAnchor(anchorFolder, slot, origin.Value)
				bindSlot(marker, origin, anchor, slot)
			else
				warn(`Stage platform owner marker or origin is missing for slot {slot}`)
			end
		end

		Players.PlayerAdded:Connect(function(player)
			watchPlayer(player)
			refreshOwners()
		end)
		Players.PlayerRemoving:Connect(function(player)
			leavingPlayers[player] = true
			refreshOwners()
		end)
		for _, player in Players:GetPlayers() do
			watchPlayer(player)
		end
		refreshOwners()
	end)
end

return StagePlatformOwnerController

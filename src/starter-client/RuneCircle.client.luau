--!strict

-- Client binder for the rune altar: adorns the authored sign, animates the
-- authored circle parts, and fills the authored reveal card and odds panel.
-- Everything visual already exists as StarterGui/Workspace instances; this
-- script only changes properties, so the server stays the only roll authority.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local RemoteNames = require(Shared.RemoteNames)
local RuneCatalog = require(Shared.RuneCatalog)
local RuneLogic = require(Shared.RuneLogic)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = playerGui:WaitForChild("RuneCircleUI", 10)
local sign = playerGui:WaitForChild("RuneCircleSign", 10)
if screenGui == nil or not screenGui:IsA("ScreenGui") or sign == nil or not sign:IsA("BillboardGui") then
	warn("RuneCircleUI/RuneCircleSign are missing; rebuild the place from bootstrap.project.json")
	return
end

local circleModel = Workspace:WaitForChild("RuneCircle", 15)
if circleModel == nil then
	warn("Workspace.RuneCircle is missing; rebuild the playable place to restore the rune altar")
	return
end
local platform = circleModel:WaitForChild("Platform") :: BasePart
local glowRing = circleModel:WaitForChild("GlowRing") :: BasePart
local coreGlow = circleModel:WaitForChild("CoreGlow") :: BasePart
local runeLight = coreGlow:WaitForChild("RuneLight") :: PointLight
local shards = {
	circleModel:WaitForChild("Shard1") :: BasePart,
	circleModel:WaitForChild("Shard2") :: BasePart,
	circleModel:WaitForChild("Shard3") :: BasePart,
}

local function optionalPart(name: string): BasePart?
	local child = circleModel:FindFirstChild(name)
	if child ~= nil and child:IsA("BasePart") then
		return child
	end
	return nil
end

local outerAura = optionalPart("OuterAura")
local middleGlow = optionalPart("MiddleGlow")
local innerWell = optionalPart("InnerWell")
local runeBlades: { BasePart } = {}
for index = 1, 8 do
	local blade = optionalPart(`RuneBlade{index}`)
	if blade ~= nil then
		table.insert(runeBlades, blade)
	end
end
local anchorCrystals: { BasePart } = {}
for index = 1, 6 do
	local crystal = optionalPart(`AnchorCrystal{index}`)
	if crystal ~= nil then
		table.insert(anchorCrystals, crystal)
	end
end
local forestEmitters: { ParticleEmitter } = {}
for _, descendant in circleModel:GetDescendants() do
	if descendant:IsA("ParticleEmitter") then
		table.insert(forestEmitters, descendant)
	end
end

if Config.features.runes ~= true then
	-- Recipe disabled the altar: keep the GUIs off and make the authored
	-- circle inert instead of advertising a dead feature.
	for _, descendant in circleModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Rate = 0
			descendant.Enabled = false
		end
	end
	return
end

local remotes = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local stateRemote = remotes:WaitForChild(RemoteNames.state) :: RemoteEvent
local queryRemote = remotes:WaitForChild(RemoteNames.query) :: RemoteFunction

local revealCard = screenGui:WaitForChild("RevealCard") :: Frame
local cardScale = revealCard:WaitForChild("UIScale") :: UIScale
local rarityBanner = revealCard:WaitForChild("RarityBanner") :: Frame
local bannerLabel = rarityBanner:WaitForChild("BannerLabel") :: TextLabel
local newTag = revealCard:WaitForChild("NewTag") :: Frame
local pityTag = revealCard:WaitForChild("PityTag") :: Frame
local glyphLabel = revealCard:WaitForChild("Glyph") :: TextLabel
local runeNameLabel = revealCard:WaitForChild("RuneName") :: TextLabel
local bonusLine = revealCard:WaitForChild("BonusLine") :: TextLabel
local ownedLine = revealCard:WaitForChild("OwnedLine") :: TextLabel
local cardTotalLine = revealCard:WaitForChild("TotalLine") :: TextLabel
local nextCostLine = revealCard:WaitForChild("NextCostLine") :: TextLabel

local oddsPanel = screenGui:WaitForChild("OddsPanel") :: Frame
local oddsTotalLine = oddsPanel:WaitForChild("TotalLine") :: TextLabel
local restrictedNote = oddsPanel:WaitForChild("RestrictedNote") :: TextLabel
local totalChip = screenGui:WaitForChild("TotalChip") :: Frame
local totalChipLabel = totalChip:WaitForChild("Label") :: TextLabel

local audioFolder = screenGui:WaitForChild("Audio") :: Folder
local rollPlayer = audioFolder:WaitForChild("RollPlayer") :: AudioPlayer
local revealPlayer = audioFolder:WaitForChild("RevealPlayer") :: AudioPlayer
local rarePlayer = audioFolder:WaitForChild("RarePlayer") :: AudioPlayer
local audioOutput = audioFolder:WaitForChild("Output") :: AudioDeviceOutput
local audioBaseVolumes = { [rollPlayer] = 0.6, [revealPlayer] = 0.7, [rarePlayer] = 0.8 }
for wireName, source in
	{ RollWire = rollPlayer, RevealWire = revealPlayer, RareWire = rarePlayer } :: { [string]: AudioPlayer }
do
	local wire = audioFolder:WaitForChild(wireName) :: Wire
	wire.SourceInstance = source
	wire.TargetInstance = audioOutput
end
rollPlayer.Asset = Config.audio.spin
revealPlayer.Asset = Config.audio.lootboxOpen
rarePlayer.Asset = Config.audio.reward

local currencyDefinition = Config.economy.currencies[1]
local currencyName = string.upper(Config.economy.primaryCurrency)
local currencySymbol = currencyDefinition.symbol

sign.Adornee = platform
sign.Enabled = true
screenGui.Enabled = true

local signCard = sign:WaitForChild("Card") :: Frame
local costLine = signCard:WaitForChild("CostLine") :: TextLabel
local statusLine = signCard:WaitForChild("StatusLine") :: TextLabel

-- Mirrors UIFactory.formatNumber so the starter layer stays decoupled from
-- template client internals.
local function formatAmount(value: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local index = 1
	while math.abs(value) >= 1000 and index < #suffixes do
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	return `{string.format("%.1f", value)}{suffixes[index]}`
end

local function rarityColor(rarityId: string): Color3
	local rarity = RuneCatalog.rarity(rarityId)
	local rgb = if rarity then rarity.color else { 156, 163, 175 }
	return Color3.fromRGB(rgb[1] or 156, rgb[2] or 163, rgb[3] or 175)
end

local state: any = nil
local standing = false
local reducedMotion = false
local flashUntil = 0
local revealToken = 0

local function isReducedMotion(): boolean
	if GuiService.ReducedMotionEnabled then
		return true
	end
	return reducedMotion
end

local function tweenInfo(duration: number, easingStyle: Enum.EasingStyle?): TweenInfo
	local adjusted = if isReducedMotion() then 0 else duration
	return if easingStyle then TweenInfo.new(adjusted, easingStyle) else TweenInfo.new(adjusted)
end

local function insideCircle(): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - platform.Position
	local radius = math.max(platform.Size.Y, platform.Size.Z) / 2 + Config.runes.circlePadding
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius
		and math.abs(offset.Y) <= Config.runes.circleHeightTolerance
end

local function applyOddsPanel()
	local runesState = if state then state.runes else nil
	local owned = if runesState then runesState.owned else nil
	for index, rarity in RuneCatalog.rarities do
		local row = oddsPanel:FindFirstChild(`RarityRow{index}`)
		if row == nil then
			continue
		end
		local swatch = row:FindFirstChild("Swatch")
		if swatch and swatch:IsA("GuiObject") then
			swatch.BackgroundColor3 = rarityColor(rarity.id)
		end
		local nameLabel = row:FindFirstChild("NameLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = string.upper(rarity.name)
		end
		local oddsLabel = row:FindFirstChild("OddsLabel")
		if oddsLabel and oddsLabel:IsA("TextLabel") then
			oddsLabel.Text = `{RuneLogic.oddsPercent(rarity)}%`
		end
		local ownedLabel = row:FindFirstChild("OwnedLabel")
		if ownedLabel and ownedLabel:IsA("TextLabel") then
			ownedLabel.Text = `x{RuneLogic.countOwnedForRarity(owned, rarity.id, RuneCatalog)}`
		end
	end
end

local function applyState(nextState: any)
	if nextState == nil or nextState.profile == nil then
		return
	end
	state = nextState
	local settings = nextState.profile.settings
	if type(settings) == "table" then
		reducedMotion = settings.reducedMotion == true
		local sfx = if type(settings.sfxVolume) == "number" then math.clamp(settings.sfxVolume, 0, 1) else 0.7
		for audioPlayer, baseVolume in audioBaseVolumes do
			audioPlayer.Volume = baseVolume * sfx
		end
	end

	local runesState = nextState.runes
	if type(runesState) ~= "table" then
		return
	end
	costLine.Text = `NEXT RUNE: {formatAmount(runesState.nextCost)} {currencySymbol}`
	local multiplierText = `RUNE BOOST x{string.format("%.2f", runesState.multiplier)}`
	oddsTotalLine.Text = multiplierText
	totalChipLabel.Text = multiplierText
	totalChip.Visible = RuneLogic.countOwned(runesState.owned) > 0
	restrictedNote.Visible = runesState.restricted == true
	applyOddsPanel()
end

local function currentStatusText(): string
	local runesState = if state then state.runes else nil
	if runesState == nil then
		return "STAND IN THE CIRCLE TO CHANNEL RUNES"
	end
	if runesState.restricted == true then
		return "RUNE ROLLS ARE UNAVAILABLE FOR THIS ACCOUNT"
	end
	if not standing then
		return "STAND IN THE CIRCLE TO CHANNEL RUNES"
	end
	local balances = state.profile.currencies
	local balance = if type(balances) == "table" then balances[runesState.currencyId] or 0 else 0
	if balance < runesState.nextCost then
		return `NEED {formatAmount(runesState.nextCost - balance)} MORE {currencyName}`
	end
	return "CHANNELING THE NEXT RUNE..."
end

local function showReveal(result: any)
	if type(result) ~= "table" then
		return
	end
	local rune = RuneCatalog.rune(result.runeId)
	local rarity = RuneCatalog.rarity(result.rarityId)
	if rune == nil or rarity == nil then
		return
	end
	revealToken += 1
	local token = revealToken
	rarityBanner.BackgroundColor3 = rarityColor(rarity.id)
	bannerLabel.Text = string.upper(`{rarity.name} RUNE`)
	glyphLabel.Text = rune.glyph
	runeNameLabel.Text = string.upper(rune.name)
	bonusLine.Text = `+{rune.bonusPercent}% {currencyName} GENERATION`
	ownedLine.Text = `OWNED x{result.ownedCount}`
	cardTotalLine.Text = `RUNE BOOST x{string.format("%.2f", result.multiplier)}`
	nextCostLine.Text = `NEXT RUNE: {formatAmount(result.nextCost)} {currencySymbol}`
	newTag.Visible = result.isNew == true
	pityTag.Visible = result.pityTriggered == true
	revealCard.Visible = true
	cardScale.Scale = if isReducedMotion() then 1 else 0.65
	TweenService:Create(cardScale, tweenInfo(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	flashUntil = os.clock() + 0.4

	revealPlayer:Play()
	local rarityIndex = RuneCatalog.rarityIndex(rarity.id) or 1
	local epicIndex = RuneCatalog.rarityIndex("epic") or math.huge
	if rarityIndex >= epicIndex then
		rarePlayer:Play()
	else
		rollPlayer:Play()
	end

	task.delay(3, function()
		if token == revealToken then
			revealCard.Visible = false
		end
	end)
end

stateRemote.OnClientEvent:Connect(function(packet: any)
	if type(packet) ~= "table" then
		return
	end
	if packet.kind == "Snapshot" then
		applyState(packet.data)
	elseif packet.kind == "RuneResult" then
		showReveal(packet.data)
	end
end)

task.spawn(function()
	for _ = 1, 30 do
		local success, response = pcall(function()
			return queryRemote:InvokeServer("InitialState", {})
		end)
		if success and type(response) == "table" and response.ok and response.data then
			applyState(response.data)
			return
		end
		task.wait(1)
	end
end)

-- Living altar: pulse the authored glow, orbit the authored shards, and speed
-- everything up while the player is channeling inside the circle.
local clock = 0
local shardPhases = { 0, (2 * math.pi) / 3, (4 * math.pi) / 3 }
local center = platform.Position
local staticApplied = false
RunService.Heartbeat:Connect(function(deltaTime: number)
	clock += deltaTime
	local nowStanding = insideCircle()
	if nowStanding ~= standing then
		standing = nowStanding
		oddsPanel.Visible = standing
	end
	statusLine.Text = currentStatusText()

	if isReducedMotion() then
		if not staticApplied then
			staticApplied = true
			glowRing.Transparency = 0.36
			coreGlow.Transparency = 0.24
			runeLight.Brightness = 3
			if outerAura ~= nil then
				outerAura.Transparency = 0.76
			end
			if middleGlow ~= nil then
				middleGlow.Transparency = 0.68
			end
			if innerWell ~= nil then
				innerWell.Transparency = 0.42
			end
			for _, emitter in forestEmitters do
				emitter.Rate = 3
			end
		end
		return
	end
	staticApplied = false

	local speed = if standing then 5 else 1.6
	local pulse = 0.5 + 0.5 * math.sin(clock * speed)
	local flashing = os.clock() < flashUntil
	glowRing.Transparency = if flashing then 0.08 else 0.34 + 0.22 * (1 - pulse)
	coreGlow.Transparency = if flashing then 0.08 else 0.2 + 0.3 * (1 - pulse)
	runeLight.Brightness = if flashing then 7 else 2.2 + 2.8 * pulse
	if outerAura ~= nil then
		outerAura.Transparency = if flashing then 0.48 else 0.68 + 0.14 * (1 - pulse)
	end
	if middleGlow ~= nil then
		middleGlow.Transparency = if flashing then 0.34 else 0.58 + 0.18 * (1 - pulse)
	end
	if innerWell ~= nil then
		innerWell.Transparency = if standing then 0.32 else 0.42
	end
	for _, emitter in forestEmitters do
		emitter.Rate = if standing then 18 else 7
	end

	local orbitSpeed = if standing then 1.1 else 0.35
	for index, shard in shards do
		local angle = shardPhases[index] + clock * orbitSpeed
		local bob = math.sin(clock * 1.4 + shardPhases[index]) * 0.45
		shard.CFrame = CFrame.new(
			center.X + math.cos(angle) * 5.6,
			center.Y + 2.4 + bob,
			center.Z + math.sin(angle) * 5.6
		) * CFrame.Angles(0, -angle, math.rad(12))
	end

	local bladeSpeed = if standing then 0.34 else 0.12
	for index, blade in runeBlades do
		local angle = ((index - 1) / math.max(#runeBlades, 1)) * math.pi * 2 + clock * bladeSpeed
		local radius = 8.65 + math.sin(clock * 1.2 + index) * 0.08
		blade.Transparency = if standing then 0.08 + 0.1 * (1 - pulse) else 0.16
		blade.CFrame = CFrame.new(
			center.X + math.cos(angle) * radius,
			center.Y + 0.44,
			center.Z + math.sin(angle) * radius
		) * CFrame.Angles(0, -angle + math.pi / 2, math.rad(7 * math.sin(clock + index)))
	end

	for index, crystal in anchorCrystals do
		local angle = ((index - 1) / math.max(#anchorCrystals, 1)) * math.pi * 2 + math.pi / 6
		local bob = math.sin(clock * 1.5 + index) * 0.22
		crystal.Transparency = if standing then 0.08 + 0.12 * (1 - pulse) else 0.18
		crystal.CFrame = CFrame.new(
			center.X + math.cos(angle) * 10.25,
			center.Y + 0.82 + bob,
			center.Z + math.sin(angle) * 10.25
		)
	end
end)

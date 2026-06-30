--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Config = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").TemplateConfig
)

local AudioController = {}
local players: { [string]: AudioPlayer } = {}
local initialized = false
local musicVolume = 0.5
local sfxVolume = 0.7

local function normalizeAssetId(assetId: string): string
	if string.match(assetId, "^%d+$") then
		return `rbxassetid://{assetId}`
	end
	return assetId
end

local function applyVolume(name: string, player: AudioPlayer)
	player.Volume = if name == "music" then musicVolume else sfxVolume
end

function AudioController.initialize()
	if initialized then
		return
	end
	initialized = true

	local container = Instance.new("Folder")
	container.Name = "TemplateAudio"
	container.Parent = SoundService

	local output = Instance.new("AudioDeviceOutput")
	output.Name = "PlayerOutput"
	output.Player = Players.LocalPlayer
	output.Parent = container

	for name, assetId in Config.audio do
		if type(assetId) == "string" and assetId ~= "" then
			local player = Instance.new("AudioPlayer")
			player.Name = name
			player.Asset = normalizeAssetId(assetId)
			player.AutoLoad = true
			player.Looping = name == "music"
			applyVolume(name, player)
			player.Parent = container
			players[name] = player

			local wire = Instance.new("Wire")
			wire.Name = `{name}ToOutput`
			wire.SourceInstance = player
			wire.TargetInstance = output
			wire.Parent = container
		end
	end
	if players.music then
		players.music:Play()
	end
end

function AudioController.applySettings(settings: any)
	musicVolume = math.clamp(settings.musicVolume or 0.5, 0, 1)
	sfxVolume = math.clamp(settings.sfxVolume or 0.7, 0, 1)
	for name, player in players do
		applyVolume(name, player)
	end
end

function AudioController.play(name: string)
	local player = players[name]
	if player then
		player:Stop()
		player.TimePosition = 0
		player:Play()
	end
end

return AudioController

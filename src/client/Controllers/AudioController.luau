--!strict

local SoundService = game:GetService("SoundService")

local Config = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared").TemplateConfig
)

local AudioController = {}
local sounds: { [string]: Sound } = {}
local musicGroup: SoundGroup
local sfxGroup: SoundGroup

local function group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end

function AudioController.initialize()
	musicGroup = group("TemplateMusic")
	sfxGroup = group("TemplateSFX")
	for name, assetId in Config.audio do
		if assetId ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = assetId
			sound.SoundGroup = if name == "music" then musicGroup else sfxGroup
			sound.Looped = name == "music"
			sound.Parent = SoundService
			sounds[name] = sound
		end
	end
	if sounds.music then
		sounds.music:Play()
	end
end

function AudioController.applySettings(settings: any)
	if musicGroup then
		musicGroup.Volume = math.clamp(settings.musicVolume or 0.5, 0, 1)
	end
	if sfxGroup then
		sfxGroup.Volume = math.clamp(settings.sfxVolume or 0.7, 0, 1)
	end
end

function AudioController.play(name: string)
	local sound = sounds[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

return AudioController

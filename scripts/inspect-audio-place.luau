--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local inputPath = process.args[1]
assert(inputPath, "Usage: lune run scripts/inspect-audio-place.luau <place-or-model-file>")
local xmlOutputPath = process.args[2]

local contents = fs.readFile(inputPath)
local roots: { Instance }
local xml: string

if string.match(string.lower(inputPath), "%.rbxmx?$") then
	roots = roblox.deserializeModel(contents)
	xml = roblox.serializeModel(roots, true)
else
	local dataModel = roblox.deserializePlace(contents)
	roots = { dataModel }
	xml = roblox.serializePlace(dataModel, true)
end

if xmlOutputPath then
	fs.writeFile(xmlOutputPath, xml)
end

local count = 0
for item in string.gmatch(xml, '<Item class="Sound".->(.-)</Item>') do
	local name = string.match(item, '<string name="Name">(.-)</string>') or "Sound"
	local assetId = string.match(item, '<Content name="AudioContent">.-<uri>(.-)</uri>.-</Content>') or ""
	count += 1
	print(string.format("%03d\t%s\t%s", count, name, assetId))
end

for item in string.gmatch(xml, '<Item class="AudioPlayer".->(.-)</Item>') do
	local name = string.match(item, '<string name="Name">(.-)</string>') or "AudioPlayer"
	local assetId = string.match(item, '<string name="AssetId">(.-)</string>') or ""
	count += 1
	print(string.format("%03d\t%s\t%s", count, name, assetId))
	if assetId == "" then
		print("\tAudioContent is present but not represented as a legacy asset ID")
	end
end

print(string.format("Found %d audio objects", count))

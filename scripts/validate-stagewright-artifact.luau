--!strict

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local pluginPath = "build/GridPlatformEditPlugin.rbxm"
local placePath = "exports/Playable_TowerDefense.rbxlx"
local safePatchPath = "build/RNGDefenderSafePatch.rbxlx"

assert(fs.isFile(pluginPath), `Missing Stagewright plugin artifact: {pluginPath}`)
assert(fs.isFile(placePath), `Missing tower-defense player-test artifact: {placePath}`)
assert(fs.isFile(safePatchPath), `Missing shared-place safe patch artifact: {safePatchPath}`)

local function descendantsWithRoots(roots: { Instance }): { Instance }
	local result: { Instance } = {}
	for _, root in roots do
		table.insert(result, root)
		for _, descendant in root:GetDescendants() do
			table.insert(result, descendant)
		end
	end
	return result
end

local function sourceAndNames(instances: { Instance }): (string, { [string]: boolean })
	local sources: { string } = {}
	local names: { [string]: boolean } = {}
	for _, instance in instances do
		names[instance.Name] = true
		if instance:IsA("LuaSourceContainer") then
			table.insert(sources, instance.Source)
		end
	end
	return table.concat(sources, "\n"), names
end

local pluginRoots = roblox.deserializeModel(fs.readFile(pluginPath))
local pluginSource, pluginNames = sourceAndNames(descendantsWithRoots(pluginRoots))
for _, requiredName in
	{
		"AuthoringArea",
		"ProjectStore",
		"Shared",
		"StageGraph",
		"StageLegacy",
		"StagePath",
		"StagePlatformLayout",
		"StageSchema",
		"StageExport",
		"StageTrace",
	}
do
	assert(pluginNames[requiredName], `Stagewright plugin artifact is missing {requiredName}`)
end
for _, marker in
	{
		"PromptSaveSelectionAsync",
		"PluginAction",
		"StagewrightPayload",
		"Trace Route",
		"StagewrightLayoutVersion",
		"Focus Admin",
		"StagewrightIslandOutlinePreview",
		"StagewrightToggleIslandOutlines",
		"CenterFacingGuide",
		"AlwaysOnTop",
	}
do
	assert(
		string.find(pluginSource, marker, 1, true),
		`Stagewright plugin artifact is missing source marker {marker}`
	)
end

local dataModel = roblox.deserializePlace(fs.readFile(placePath))
local runtimeSource, runtimeNames = sourceAndNames(descendantsWithRoots({ dataModel }))
local generatedCatalogSource = fs.readFile("src/shared/StageCatalog.generated.luau")
local expectedChecksum = string.match(generatedCatalogSource, "Stagewright checksum: ([%w%-]+)")
assert(expectedChecksum ~= nil, "Generated Stagewright catalog has no checksum marker")
for _, requiredName in
	{
		"StageCatalog",
		"StageCatalog.generated",
		"StageGraph",
		"StagePath",
		"StagePlatformLayout",
		"StagePlatformService",
		"StageRuntimeService",
		"StageEnemyRenderer",
		"StageGridRenderer",
	}
do
	assert(runtimeNames[requiredName], `Tower-defense artifact is missing {requiredName}`)
end
for _, marker in
	{
		expectedChecksum,
		"TowerEnemies",
		"maximum travel distance exceeded",
		"StagewrightClientGrids",
		"StagewrightEditorOnly",
		"StagewrightRuntimeStowed",
		"hideLegacyEditGridUi",
	}
do
	assert(
		string.find(runtimeSource, marker, 1, true),
		`Tower-defense artifact is missing source marker {marker}`
	)
end
for _, retiredMarker in { "catmullRomPosition", "createEnemyPart", "SPLINE_SAMPLES_PER_SEGMENT" } do
	assert(
		not string.find(runtimeSource, retiredMarker, 1, true),
		`Tower-defense artifact retained {retiredMarker}`
	)
end

local safePatch = roblox.deserializePlace(fs.readFile(safePatchPath))
local _, safePatchNames = sourceAndNames(descendantsWithRoots({ safePatch }))
for _, requiredName in
	{
		"TemplateConfig",
		"RuneModeConfig",
		"StagePlatformService",
		"StagePlatformOwnerController",
	}
do
	assert(safePatchNames[requiredName], `Shared-place safe patch is missing {requiredName}`)
end

print("Stagewright plugin, player-test, and shared-place artifacts passed structural validation.")

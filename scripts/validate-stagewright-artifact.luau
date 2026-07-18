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
		"AppShell",
		"HeaderController",
		"Persistence",
		"ProjectLoadPolicy",
		"ProjectStore",
		"ProjectStorage",
		"RouteOverview",
		"Shared",
		"StageGraph",
		"StageHierarchy",
		"StageLanes",
		"StageLegacy",
		"StagePath",
		"StagePayload",
		"StagePlatformLayout",
		"StageSchema",
		"StageExport",
		"StageTrace",
		"WorkspacePreview",
	}
do
	assert(pluginNames[requiredName], `Stagewright plugin artifact is missing {requiredName}`)
end
for _, marker in
	{
		"PromptSaveSelectionAsync",
		"PluginAction",
		"StagewrightPayload",
		"StagewrightPayloadChunks",
		"Play Trace",
		"StagewrightLayoutVersion",
		"Focus Stagewright Admin Area",
		"StagewrightIslandOutlinePreview",
		"StagewrightToggleIslandOutlines",
		"GridColumn_",
		"GridRow_",
		"AlwaysOnTop",
		"ProjectStore.createLevel",
		"+ Stage",
		"+ Level",
		"Delete spline",
		"Add Junction",
		"Lanes 1/2/3",
		"Preview in World",
		"ProjectStorage.writePayload",
		"WorkspacePreview.new",
		"StagewrightPanelV2",
		"STAGES & LEVELS",
		"Brush 1 x 1",
		"Shift + drag to paint",
		"LevelPreviewCanvas",
		"ValidationErrorValue",
		"StageMoreMenu",
		"World Path",
		"Route Logic",
		"PaintTool_",
		"HeaderSignature",
		"Export bundle",
		"Apply changes",
	}
do
	assert(
		string.find(pluginSource, marker, 1, true),
		`Stagewright plugin artifact is missing source marker {marker}`
	)
end
assert(
	not string.find(pluginSource, "CenterFacingGuide", 1, true),
	"Stagewright plugin artifact retained the misleading center-facing line"
)

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
		"StageHierarchy",
		"StageLanes",
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
		"StageRuntimeService.spawnNodes",
		"laneSequence",
		"hideLegacyEditGridUi",
		"ActiveStageId",
		"StageCatalog.nextLevelId",
		"stage_1_level_10",
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

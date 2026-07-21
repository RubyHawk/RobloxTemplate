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

local retiredLegacyInstanceNames = { "GridNpcDemo", "GridNpc", "PathPoints", "PathTiles", "GridOverlay" }

local pluginRoots = roblox.deserializeModel(fs.readFile(pluginPath))
local pluginSource, pluginNames = sourceAndNames(descendantsWithRoots(pluginRoots))
for _, requiredName in
	{
		"AuthoringArea",
		"AppShell",
		"CanvasTransform",
		"GraphToolController",
		"HeaderController",
		"HierarchyBrowserView",
		"HierarchyOptions",
		"HitTest",
		"MapBackdrop",
		"MapNavigationController",
		"MapPropertiesView",
		"Persistence",
		"PaintRouteDragSession",
		"PaintStrokeSession",
		"PaintCellOverlay",
		"PaintInspector",
		"PointerDrag",
		"ProjectLoadPolicy",
		"ProjectStore",
		"ProjectStorage",
		"RouteOverview",
		"Shared",
		"StageGraph",
		"StageCell",
		"StageHierarchy",
		"StageLanes",
		"StageLegacy",
		"StagePath",
		"StagePathAssets",
		"StagePayload",
		"StagePlatformLayout",
		"StageSchema",
		"StageExport",
		"StageTrace",
		"StageTypes",
		"StageWaveDefaults",
		"WorldPathController",
		"WorldPathEditSession",
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
		"StagewrightRuntime",
		"StagewrightPayloadChunks",
		"StagewrightBundle:v1",
		"verifyExportModel",
		"embedded authoring/runtime verified",
		"Play Trace",
		"StagewrightLayoutVersion",
		"Focus Stagewright Admin Area",
		"StagewrightIslandOutlinePreview",
		"StagewrightToggleIslandOutlines",
		"GridColumn_",
		"GridRow_",
		"AlwaysOnTop",
		"ProjectStore.createLevel",
		"ProjectStore.createMap",
		"+ Map",
		"+ Stage",
		"+ Level",
		"Delete spline",
		"Add Junction",
		"Lanes 1/2/3",
		"In Studio",
		"ProjectStorage.writePayload",
		"WorkspacePreview.new",
		"StagewrightPanelV2",
		"MapNavigation",
		"MapPlayable",
		"MapAdmin",
		"focusPlayable",
		"removeLegacyArtifacts",
		"StagewrightRequestedPathAsset",
		"UnknownPathAsset",
		"STAGES & LEVELS",
		"Brush 1 x 1",
		"SHIFT TO PAINT",
		"HoverCellOutline",
		"SelectedCellOutline",
		"Each cell has one Surface",
		"StageCell.resolve",
		"Enum.ModifierKey.Ctrl",
		"ScrollingEnabled",
		"isWorkspaceInputAllowed",
		"Panning canvas",
		"LevelPreviewCanvas",
		"ValidationErrorValue",
		"StageMoreMenu",
		"Level --",
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
		"StageCell",
		"StageGraph",
		"StageHierarchy",
		"StageLanes",
		"StagePath",
		"StagePathAssets",
		"StagePlatformLayout",
		"StagePlatformService",
		"StageRuntimeService",
		"StageTypes",
		"StageEnemyRenderer",
		"StageGridRenderer",
		"StageTowerRenderer",
		"TowerDefenseRequest",
	}
do
	assert(runtimeNames[requiredName], `Tower-defense artifact is missing {requiredName}`)
end
for _, retiredName in retiredLegacyInstanceNames do
	assert(not runtimeNames[retiredName], `Tower-defense artifact retained legacy instance {retiredName}`)
end
for _, marker in
	{
		expectedChecksum,
		"TowerEnemies",
		"TowerPlacements",
		"towerPlacementRevision",
		"maximum travel distance exceeded",
		"StagewrightClientGrids",
		"StagewrightClientTowers",
		"StagewrightEditorOnly",
		"StagewrightRuntimeStowed",
		"StageRuntimeService.spawnNodes",
		"laneSequence",
		"hideLegacyEditGridUi",
		"ActiveStageId",
		"StageCatalog.nextLevelId",
		"stage_1_level_10",
		"StagewrightLaneWidth",
		"StagewrightRequestedPathAsset",
		"UnknownPathAsset",
	}
do
	assert(
		string.find(runtimeSource, marker, 1, true),
		`Tower-defense artifact is missing source marker {marker}`
	)
end
for _, retiredMarker in
	{ "catmullRomPosition", "createEnemyPart", "SPLINE_SAMPLES_PER_SEGMENT", "DebugNameplate" }
do
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
		"StageCell",
		"StagePathAssets",
		"StagePlatformService",
		"StagePlatformOwnerController",
		"TowerDefenseRequest",
	}
do
	assert(safePatchNames[requiredName], `Shared-place safe patch is missing {requiredName}`)
end
for _, retiredName in retiredLegacyInstanceNames do
	assert(not safePatchNames[retiredName], `Shared-place safe patch retained legacy instance {retiredName}`)
end

print("Stagewright plugin, player-test, and shared-place artifacts passed structural validation.")

--!strict

local Calculations = require("../src/shared/Calculations")
local CurrencyConfig = require("../src/shared/CurrencyConfig")
local RuneCatalog = require("../src/shared/RuneCatalog")
local RuneLogic = require("../src/shared/RuneLogic")
local RuneModeConfig = require("../src/shared/RuneModeConfig")
local TowerDefenseCatalog = require("../src/shared/TowerDefenseCatalog")
local TowerDefenseLogic = require("../src/shared/TowerDefenseLogic")
local TowerDefenseRequest = require("../src/shared/TowerDefenseRequest")
local StageGraph = require("../src/shared/StageGraph")
local StageCell = require("../src/shared/StageCell")
local StageHierarchy = require("../src/shared/StageHierarchy")
local StageLanes = require("../src/shared/StageLanes")
local StageLegacy = require("../src/shared/StageLegacy")
local StagePath = require("../src/shared/StagePath")
local StagePathAssets = require("../src/shared/StagePathAssets")
local StagePlatformLayout = require("../src/shared/StagePlatformLayout")
local StageSchema = require("../src/shared/StageSchema")
local StageStarterProject = require("../src/shared/StageStarterProject")
local StageExport = require("../src/shared/StageExport")
local StageWaveDefaults = require("../src/shared/StageWaveDefaults")
local StageTrace = require("../src/shared/StageTrace")
local CanvasTransform = require("../src/plugins/Stagewright/Interaction/CanvasTransform")
local HitTest = require("../src/plugins/Stagewright/Interaction/HitTest")
local PointerDrag = require("../src/plugins/Stagewright/Interaction/PointerDrag")
local PaintRouteDragSession = require("../src/plugins/Stagewright/Controllers/PaintRouteDragSession")
local PaintStrokeSession = require("../src/plugins/Stagewright/Controllers/PaintStrokeSession")
local WorldPathEditSession = require("../src/plugins/Stagewright/Controllers/WorldPathEditSession")
local GraphToolController = require("../src/plugins/Stagewright/Controllers/GraphToolController")
local GraphOperations = require("../src/plugins/Stagewright/Graph/Operations")
local PredicateFields = require("../src/plugins/Stagewright/Graph/PredicateFields")
local PaintBrushes = require("../src/plugins/Stagewright/Paint/Brushes")
local ProjectLoadPolicy = require("../src/plugins/Stagewright/Persistence/ProjectLoadPolicy")
local StageSettings = require("../src/plugins/Stagewright/Stage/Settings")
local DataStoreNames = require("../src/shared/DataStoreNames")
local DataStoreKeys = require("../src/shared/DataStoreKeys")
local MigrationCore = require("../src/shared/MigrationCore")
local ReceiptLedger = require("../src/shared/ReceiptLedger")
local SessionLock = require("../src/server/Util/SessionLock")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local passed = 0

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
	passed += 1
end

local function expectCompiles(source: string, label: string)
	local chunk, compileError = luau.load(source)
	expectEqual(chunk ~= nil, true, `{label}: {tostring(compileError)}`)
end

do
	local function expectNear(actual: number, expected: number, label: string)
		expectEqual(math.abs(actual - expected) <= 1e-9, true, label)
	end

	local function expectPointNear(actual: any, expected: any, label: string)
		expectNear(actual.x, expected.x, `{label} x`)
		expectNear(actual.y, expected.y, `{label} y`)
	end

	local fitted = CanvasTransform.fit({ x = 1_000, y = 500 }, { x = 100, y = 100 }, 20)
	expectNear(CanvasTransform.scale(fitted), 4.6, "canvas fit uses one uniform limiting-axis scale")
	expectPointNear(
		CanvasTransform.worldToCanvas(fitted, { x = 0, y = 0 }),
		{ x = 500, y = 250 },
		"canvas fit centers the world"
	)
	expectPointNear(
		CanvasTransform.worldToCanvas(fitted, { x = -50, y = -50 }),
		{ x = 270, y = 20 },
		"canvas fit letterboxes the non-limiting axis"
	)
	expectPointNear(
		CanvasTransform.worldToCanvas(fitted, { x = 50, y = 50 }),
		{ x = 730, y = 480 },
		"canvas fit preserves padding on the limiting axis"
	)

	local worldPoint = { x = 17.25, y = -31.5 }
	local projectedPoint = CanvasTransform.worldToCanvas(fitted, worldPoint)
	expectPointNear(
		CanvasTransform.canvasToWorld(fitted, projectedPoint),
		worldPoint,
		"canvas forward and inverse transforms round trip"
	)

	local panned = CanvasTransform.pan(fitted, { x = 46, y = -92 })
	expectPointNear(fitted.center, { x = 0, y = 0 }, "canvas pan does not mutate its input")
	expectPointNear(panned.center, { x = -10, y = 20 }, "canvas pan converts pixel delta at current scale")
	local fittedOrigin = CanvasTransform.worldToCanvas(fitted, { x = 0, y = 0 })
	local pannedOrigin = CanvasTransform.worldToCanvas(panned, { x = 0, y = 0 })
	expectPointNear(
		{ x = pannedOrigin.x - fittedOrigin.x, y = pannedOrigin.y - fittedOrigin.y },
		{ x = 46, y = -92 },
		"canvas pan moves rendered content with the pointer"
	)

	local zoomAnchor = { x = 620, y = 310 }
	local anchoredWorldPoint = CanvasTransform.canvasToWorld(panned, zoomAnchor)
	local zoomed = CanvasTransform.zoomAt(panned, 2, zoomAnchor)
	expectNear(zoomed.zoom, 2, "canvas zoom applies the requested factor")
	expectNear(
		CanvasTransform.scale(zoomed),
		CanvasTransform.scale(panned) * 2,
		"canvas zoom changes both axes by the same factor"
	)
	expectPointNear(
		CanvasTransform.canvasToWorld(zoomed, zoomAnchor),
		anchoredWorldPoint,
		"canvas zoom preserves the world point beneath the cursor"
	)

	local resized = CanvasTransform.resize(zoomed, { x = 760, y = 900 })
	expectNear(resized.zoom, zoomed.zoom, "canvas resize preserves user zoom")
	expectPointNear(resized.center, zoomed.center, "canvas resize preserves the viewed world center")
	expectPointNear(
		CanvasTransform.canvasToWorld(resized, { x = 380, y = 450 }),
		zoomed.center,
		"canvas resize keeps the viewed center at the new viewport center"
	)

	local reset = CanvasTransform.resetFit(resized)
	expectNear(reset.zoom, 1, "canvas fit reset restores default zoom")
	expectPointNear(reset.center, { x = 0, y = 0 }, "canvas fit reset restores the authored world center")
	expectPointNear(
		CanvasTransform.worldToCanvas(reset, { x = 0, y = 0 }),
		{ x = 380, y = 450 },
		"canvas fit reset centers the authored world in the resized viewport"
	)

	local customFit = CanvasTransform.fit(
		{ x = 800, y = 600 },
		{ x = 200, y = 100 },
		10,
		{ x = 125, y = -40 }
	)
	local customMoved = CanvasTransform.pan(customFit, { x = -30, y = 60 })
	local customReset =
		CanvasTransform.resetFit(CanvasTransform.zoomAt(customMoved, 1.5, { x = 200, y = 200 }))
	expectPointNear(
		customReset.center,
		{ x = 125, y = -40 },
		"canvas fit reset honors a non-zero authored world center"
	)

	local maximumZoom = CanvasTransform.setZoomAt(fitted, 1_000, zoomAnchor)
	local minimumZoom = CanvasTransform.setZoomAt(fitted, 0.001, zoomAnchor)
	expectNear(maximumZoom.zoom, CanvasTransform.MAX_ZOOM, "canvas zoom clamps excessive magnification")
	expectNear(minimumZoom.zoom, CanvasTransform.MIN_ZOOM, "canvas zoom clamps excessive reduction")
	expectPointNear(
		CanvasTransform.canvasToWorld(maximumZoom, zoomAnchor),
		CanvasTransform.canvasToWorld(fitted, zoomAnchor),
		"clamped canvas zoom still preserves its cursor anchor"
	)

	local invalidWorldSizeAccepted = pcall(function()
		CanvasTransform.fit({ x = 800, y = 600 }, { x = 0, y = 100 }, 10)
	end)
	local invalidPaddingAccepted = pcall(function()
		CanvasTransform.fit({ x = 100, y = 100 }, { x = 20, y = 20 }, 50)
	end)
	local invalidZoomAccepted = pcall(function()
		CanvasTransform.zoomAt(fitted, 0, zoomAnchor)
	end)
	expectEqual(invalidWorldSizeAccepted, false, "canvas fit rejects zero-sized worlds")
	expectEqual(invalidPaddingAccepted, false, "canvas fit rejects padding that consumes the viewport")
	expectEqual(invalidZoomAccepted, false, "canvas zoom rejects non-positive factors")
end

do
	local defaultCell: any = {
		terrainId = "ground",
		buildPolicy = "Blocked",
		enemyTraversalPolicy = "Allowed",
		roles = {},
		metadata = { biome = "forest" },
	}
	local terrainOverride: any = { terrainId = "void" }
	local resolved = StageCell.resolve(defaultCell, terrainOverride)
	expectEqual(resolved.terrainId, "void", "cell resolver applies the authored layer value")
	expectEqual(resolved.buildPolicy, "Blocked", "cell resolver inherits omitted tower-placement policy")
	expectEqual(
		resolved.enemyTraversalPolicy,
		"Allowed",
		"cell resolver inherits omitted route-access policy"
	)
	expectEqual(resolved.metadata.biome, "forest", "cell resolver preserves default metadata")
	expectEqual(defaultCell.terrainId, "ground", "cell resolver does not mutate the level default")
	expectEqual(
		StageCell.resolve(defaultCell, nil),
		defaultCell,
		"cell resolver reuses the default when there is no authored override"
	)
end

do
	expectEqual(#StagePathAssets.ASSETS, 3, "path asset catalog exposes the built-in authoring styles")
	expectEqual(
		assert(StagePathAssets.find("dirt"), "dirt path asset").label,
		"Dirt",
		"path asset lookup resolves a stable ID"
	)
	expectEqual(
		assert(StagePathAssets.find("stone"), "stone path asset").materialName,
		"Cobblestone",
		"path assets expose a Studio material name"
	)
	expectEqual(
		assert(StagePathAssets.find("gravel"), "gravel path asset").rgb[1],
		166,
		"path assets expose RGB triplets"
	)
	expectEqual(StagePathAssets.find("custom_pack"), nil, "unknown path assets are not catalog entries")
	expectEqual(
		StagePathAssets.label("custom_pack"),
		"custom_pack (missing; using Gravel)",
		"unknown saved path assets identify the visible fallback"
	)
	expectEqual(StagePathAssets.resolve("stone").id, "stone", "known path assets resolve without fallback")
	expectEqual(
		StagePathAssets.resolve("custom_pack").id,
		StagePathAssets.DEFAULT_ASSET_ID,
		"unknown path assets resolve to the safe visual fallback"
	)
	local edgeAsset, requestedAssetId = StagePathAssets.forEdge({ metadata = { pathAssetId = "dirt" } })
	expectEqual(edgeAsset.id, "dirt", "edge asset resolution reads baked metadata")
	expectEqual(requestedAssetId, "dirt", "edge asset resolution preserves the requested ID")
	expectEqual(StagePathAssets.next("gravel"), "dirt", "path assets cycle in catalog order")
	expectEqual(
		StagePathAssets.next("custom_pack"),
		StagePathAssets.DEFAULT_ASSET_ID,
		"cycling an unknown path asset starts from the safe default"
	)
end

do
	local nextId = 0
	local project = StageStarterProject.build(1, function(prefix: string): string
		nextId += 1
		return `{prefix}_asset_test_{nextId}`
	end, "stage_asset_test", "stage_group_asset_test")
	local stage = project.stages.stage_asset_test
	local graph: any = nil
	for _, candidate in stage.pathGraphs do
		graph = candidate
		break
	end
	local edgeId: string? = nil
	for candidateId, edge in graph.edges do
		edgeId = candidateId
		edge.metadata.pathAssetId = "dirt"
		break
	end
	local preview = assert(StageExport.preview(stage), "path asset preview")
	local bakedEdge = preview.pathGraphs[graph.id].edges[assert(edgeId, "path asset edge")]
	expectEqual(bakedEdge.metadata.pathAssetId, "dirt", "path style metadata survives deterministic baking")
	graph.edges[edgeId].metadata.pathAssetId = "custom_pack"
	local foundUnknownAssetWarning = false
	for _, issue in StageSchema.validateStage(stage) do
		if issue.code == "UnknownPathAsset" and issue.objectId == edgeId then
			foundUnknownAssetWarning = true
		end
	end
	expectEqual(foundUnknownAssetWarning, true, "validation reports unavailable imported path assets")
end

do
	local edge: any = {
		kind = "Edge",
		id = "edge_main",
		points = { { x = -10, y = 0 }, { x = 10, y = 0 } },
		radius = 6,
	}
	local node: any = {
		kind = "Node",
		id = "node_main",
		center = { x = 1, y = 0 },
		radius = 6,
	}
	local handle: any = {
		kind = "Handle",
		id = "edge_main",
		handleId = "Out",
		center = { x = 3, y = 0 },
		radius = 6,
	}

	local handleHit = HitTest.resolve({ x = 0, y = 0 }, { edge, node, handle })
	expectEqual(
		handleHit and handleHit.kind,
		"Handle",
		"hit test prioritizes handles over closer nodes and edges"
	)
	expectEqual(handleHit and handleHit.id, "edge_main", "handle hit preserves its owning edge id")
	expectEqual(handleHit and handleHit.handleId, "Out", "handle hit preserves its handle id")
	expectEqual(handleHit and handleHit.distance, 3, "handle hit reports screen-space distance")

	local nodeHit = HitTest.resolve({ x = 0, y = 0 }, { edge, node })
	expectEqual(nodeHit and nodeHit.kind, "Node", "hit test prioritizes nodes over closer edges")
	expectEqual(nodeHit and nodeHit.id, "node_main", "node hit preserves its stable id")

	local nearestNodeHit = HitTest.resolve({ x = 0, y = 0 }, {
		{ kind = "Node", id = "node_far", center = { x = 5, y = 0 }, radius = 8 },
		{ kind = "Node", id = "node_near", center = { x = 2, y = 0 }, radius = 8 },
	})
	expectEqual(
		nearestNodeHit and nearestNodeHit.id,
		"node_near",
		"hit test chooses the nearest same-kind target"
	)

	local layeredNodeHits = HitTest.resolveAll({ x = 0, y = 0 }, {
		{
			kind = "Node",
			id = "nearby_label",
			center = { x = 0, y = 0 },
			radius = 13,
			area = "Label",
		},
		{
			kind = "Node",
			id = "visible_marker",
			center = { x = 5, y = 0 },
			radius = 24,
			area = "Marker",
		},
	})
	expectEqual(
		layeredNodeHits[1] and layeredNodeHits[1].id,
		"visible_marker",
		"visible node markers outrank overlapping labels from nearby nodes"
	)
	expectEqual(
		layeredNodeHits[2] and layeredNodeHits[2].id,
		"nearby_label",
		"overlapping labels remain available as secondary node candidates"
	)

	local sharedIdHits = HitTest.resolveAll({ x = 0, y = 0 }, {
		{ kind = "Node", id = "shared", center = { x = 0, y = 0 }, radius = 8 },
		{ kind = "Edge", id = "shared", points = { { x = -4, y = 0 }, { x = 4, y = 0 } }, radius = 8 },
	})
	expectEqual(#sharedIdHits, 2, "node and edge namespaces do not suppress one another")
	expectEqual(sharedIdHits[1].kind, "Node", "shared-id node keeps normal hit priority")
	expectEqual(sharedIdHits[2].kind, "Edge", "shared-id spline remains available to Split")

	local coincidentNodeHits = HitTest.resolveAll({ x = 0, y = 0 }, {
		{ kind = "Node", id = "node_a", center = { x = 0, y = 0 }, radius = 8 },
		{ kind = "Node", id = "node_b", center = { x = 0, y = 0 }, radius = 8 },
	})
	expectEqual(
		HitTest.preferSelectedNode(coincidentNodeHits, "node_b")
			and HitTest.preferSelectedNode(coincidentNodeHits, "node_b").id,
		"node_b",
		"a cycled overlapping node remains the next drag target"
	)
	local handleAndNodes = table.clone(coincidentNodeHits)
	table.insert(handleAndNodes, 1, {
		kind = "Handle",
		id = "edge",
		handleId = "Out",
		distance = 0,
	})
	expectEqual(
		HitTest.preferSelectedNode(handleAndNodes, "node_b")
			and HitTest.preferSelectedNode(handleAndNodes, "node_b").kind,
		"Handle",
		"selected nodes never steal handle drag priority"
	)
	expectEqual(
		HitTest.preferSelectedNode(layeredNodeHits, "nearby_label")
			and HitTest.preferSelectedNode(layeredNodeHits, "nearby_label").id,
		"visible_marker",
		"a selected label never overrides another node's visible marker"
	)
	local overlappingLabelHits = HitTest.resolveAll({ x = 0, y = 0 }, {
		{ kind = "Node", id = "label_a", center = { x = 0, y = 0 }, radius = 8, area = "Label" },
		{ kind = "Node", id = "label_b", center = { x = 0, y = 0 }, radius = 8, area = "Label" },
	})
	expectEqual(
		HitTest.preferSelectedNode(overlappingLabelHits, "label_b")
			and HitTest.preferSelectedNode(overlappingLabelHits, "label_b").id,
		"label_b",
		"a cycled overlapping label remains the next drag target"
	)

	local duplicateLabelHits = HitTest.resolveAll({ x = 0, y = 0 }, {
		{ kind = "Node", id = "wide_label", center = { x = -4, y = 0 }, radius = 8, area = "Label" },
		{ kind = "Node", id = "wide_label", center = { x = 4, y = 0 }, radius = 8, area = "Label" },
	})
	expectEqual(#duplicateLabelHits, 1, "repeated hit circles for one label collapse to one candidate")
	expectEqual(
		HitTest.cycleNode(layeredNodeHits, nil) and HitTest.cycleNode(layeredNodeHits, nil).id,
		"visible_marker",
		"node cycling starts with the highest-ranked candidate"
	)
	expectEqual(
		HitTest.cycleNode(layeredNodeHits, "visible_marker")
			and HitTest.cycleNode(layeredNodeHits, "visible_marker").id,
		"nearby_label",
		"node cycling advances to an overlapping node"
	)
	expectEqual(
		HitTest.cycleNode(layeredNodeHits, "nearby_label")
			and HitTest.cycleNode(layeredNodeHits, "nearby_label").id,
		"visible_marker",
		"node cycling wraps deterministically"
	)

	local tiedNodes = {
		{ kind = "Node", id = "node_z", center = { x = 2, y = 0 }, radius = 8 },
		{ kind = "Node", id = "node_a", center = { x = -2, y = 0 }, radius = 8 },
	}
	local tiedNodeHit = HitTest.resolve({ x = 0, y = 0 }, tiedNodes :: any)
	local reversedTiedNodeHit = HitTest.resolve(
		{ x = 0, y = 0 },
		{
			tiedNodes[2],
			tiedNodes[1],
		} :: any
	)
	expectEqual(tiedNodeHit and tiedNodeHit.id, "node_a", "equal-distance node hits use stable id order")
	expectEqual(
		reversedTiedNodeHit and reversedTiedNodeHit.id,
		"node_a",
		"node tie-breaking is independent of primitive order"
	)

	local tiedHandleHit = HitTest.resolve({ x = 0, y = 0 }, {
		{ kind = "Handle", id = "edge_b", handleId = "Out", center = { x = 0, y = 2 }, radius = 5 },
		{ kind = "Handle", id = "edge_a", handleId = "In", center = { x = 0, y = -2 }, radius = 5 },
	})
	expectEqual(
		tiedHandleHit and tiedHandleHit.id,
		"edge_a",
		"equal-distance handles use owning edge id order"
	)
	expectEqual(
		tiedHandleHit and tiedHandleHit.handleId,
		"In",
		"handle tie-breaking preserves the winning handle"
	)
	local sameEdgeHandles = {
		{ kind = "Handle", id = "edge_same", handleId = "Out", center = { x = 0, y = 2 }, radius = 5 },
		{ kind = "Handle", id = "edge_same", handleId = "In", center = { x = 0, y = -2 }, radius = 5 },
	}
	local sameEdgeHandleHit = HitTest.resolve({ x = 0, y = 0 }, sameEdgeHandles :: any)
	local reversedSameEdgeHandleHit =
		HitTest.resolve({ x = 0, y = 0 }, { sameEdgeHandles[2], sameEdgeHandles[1] } :: any)
	expectEqual(
		sameEdgeHandleHit and sameEdgeHandleHit.handleId,
		"In",
		"equal-distance handles on one edge use stable handle id order"
	)
	expectEqual(
		reversedSameEdgeHandleHit and reversedSameEdgeHandleHit.handleId,
		"In",
		"same-edge handle tie-breaking is independent of primitive order"
	)

	local nearestEdgeHit = HitTest.resolve({ x = 4, y = 2 }, {
		{
			kind = "Edge",
			id = "edge_far",
			points = { { x = 0, y = 7 }, { x = 10, y = 7 } },
			radius = 8,
		},
		{
			kind = "Edge",
			id = "edge_near",
			points = { { x = 0, y = 0 }, { x = 10, y = 0 } },
			radius = 8,
		},
	})
	expectEqual(nearestEdgeHit and nearestEdgeHit.id, "edge_near", "edge hit uses nearest segment distance")
	expectEqual(
		nearestEdgeHit and nearestEdgeHit.distance,
		2,
		"edge hit reports perpendicular segment distance"
	)

	local tiedEdgeHit = HitTest.resolve({ x = 0, y = 0 }, {
		{
			kind = "Edge",
			id = "edge_z",
			points = { { x = -5, y = 2 }, { x = 5, y = 2 } },
			radius = 3,
		},
		{
			kind = "Edge",
			id = "edge_a",
			points = { { x = -5, y = -2 }, { x = 5, y = -2 } },
			radius = 3,
		},
	})
	expectEqual(tiedEdgeHit and tiedEdgeHit.id, "edge_a", "equal-distance edge hits use stable id order")

	local singlePointEdgeHit = HitTest.resolve({ x = 13, y = 14 }, {
		{ kind = "Edge", id = "edge_point", points = { { x = 10, y = 10 } }, radius = 5 },
	})
	expectEqual(
		singlePointEdgeHit and singlePointEdgeHit.id,
		"edge_point",
		"single-point edge geometry remains hittable"
	)
	expectEqual(
		singlePointEdgeHit and singlePointEdgeHit.distance,
		5,
		"edge radius includes its exact boundary"
	)

	local noHit = HitTest.resolve({ x = 20, y = 20 }, {
		{ kind = "Edge", id = "edge_empty", points = {}, radius = 100 },
		{ kind = "Node", id = "node_outside", center = { x = 0, y = 0 }, radius = 5 },
	})
	expectEqual(noHit, nil, "empty and out-of-radius primitives do not create hidden hits")

	local invalidRadiusAccepted = pcall(function()
		HitTest.resolve({ x = 0, y = 0 }, {
			{ kind = "Node", id = "node_bad", center = { x = 0, y = 0 }, radius = -1 },
		})
	end)
	local invalidPointAccepted = pcall(function()
		HitTest.resolve({ x = math.huge, y = 0 }, {})
	end)
	local invalidNodeAreaAccepted = pcall(function()
		HitTest.resolve({ x = 0, y = 0 }, {
			{
				kind = "Node",
				id = "node_bad_area",
				center = { x = 0, y = 0 },
				radius = 5,
				area = "Badge",
			} :: any,
		})
	end)
	expectEqual(invalidRadiusAccepted, false, "hit test rejects negative target radii")
	expectEqual(invalidPointAccepted, false, "hit test rejects non-finite pointer positions")
	expectEqual(invalidNodeAreaAccepted, false, "hit test rejects unknown node hit areas")
end

do
	local target: any = { kind = "Node", id = "node_1" }
	local idle = PointerDrag.idle()
	expectEqual(PointerDrag.isActive(idle), false, "pointer drag starts idle")
	expectEqual(PointerDrag.isDragging(idle), false, "idle pointer is not dragging")

	local idleMove = PointerDrag.move(idle, "mouse-primary", { x = 100, y = 100 })
	expectEqual(idleMove.state, idle, "pointer movement before a press preserves idle state")
	expectEqual(#idleMove.actions, 0, "pointer movement before a press emits no action")
	local invalidPress = PointerDrag.press(idle, "mouse-primary", nil, { x = 10, y = 10 })
	expectEqual(invalidPress.state, idle, "press without a hit target remains idle")
	expectEqual(#invalidPress.actions, 0, "press without a hit target emits no action")

	local pressed = PointerDrag.press(idle, "mouse-primary", target, { x = 10, y = 10 })
	expectEqual(pressed.state.phase, "Pressed", "valid primary press captures the pointer")
	expectEqual(pressed.state.pointerId, "mouse-primary", "pressed state records pointer identity")
	expectEqual(
		pressed.state.target and pressed.state.target.id,
		"node_1",
		"pressed state records its target"
	)
	expectEqual(pressed.actions[1].kind, "Pressed", "valid press emits a pure pressed action")
	target.id = "mutated_after_press"
	expectEqual(
		pressed.state.target and pressed.state.target.id,
		"node_1",
		"pressed state snapshots its target"
	)

	local secondPress = PointerDrag.press(
		pressed.state,
		"touch-2",
		{ kind = "Node", id = "node_2" },
		{ x = 12, y = 12 }
	)
	expectEqual(secondPress.state, pressed.state, "captured pointer ignores a second press")
	expectEqual(#secondPress.actions, 0, "second press emits no action while captured")

	local wrongPointerMove = PointerDrag.move(pressed.state, "touch-2", { x = 100, y = 100 })
	expectEqual(wrongPointerMove.state, pressed.state, "captured drag ignores movement from another pointer")
	expectEqual(#wrongPointerMove.actions, 0, "wrong-pointer movement emits no action")

	local belowThreshold = PointerDrag.move(pressed.state, "mouse-primary", { x = 12.8, y = 12.8 })
	expectEqual(belowThreshold.state.phase, "Pressed", "movement below four pixels remains a press")
	expectEqual(#belowThreshold.actions, 0, "movement below threshold emits no drag action")
	expectEqual(
		belowThreshold.state.lastPosition and belowThreshold.state.lastPosition.x,
		12.8,
		"pressed state tracks its latest point"
	)

	local dragStarted = PointerDrag.move(belowThreshold.state, "mouse-primary", { x = 14, y = 10 })
	expectEqual(dragStarted.state.phase, "Dragging", "movement at four pixels starts dragging")
	expectEqual(PointerDrag.isDragging(dragStarted.state), true, "dragging state is reported explicitly")
	expectEqual(dragStarted.actions[1].kind, "DragStarted", "threshold crossing emits one drag-start action")
	expectEqual(dragStarted.actions[1].position.x, 14, "drag-start action carries the current point")

	local worldPress = PointerDrag.press(idle, "mouse-primary", target, { x = 0, y = 0 })
	local worldBelowThreshold = PointerDrag.move(worldPress.state, "mouse-primary", { x = 7, y = 0 }, 8)
	expectEqual(
		worldBelowThreshold.state.phase,
		"Pressed",
		"World Path can use an eight-pixel threshold to tolerate selection jitter"
	)
	local worldClicked = PointerDrag.release(worldBelowThreshold.state, "mouse-primary", { x = 7, y = 0 }, 8)
	expectEqual(worldClicked.actions[1].kind, "Clicked", "seven-pixel World Path motion remains a click")
	local worldDragStarted = PointerDrag.move(worldPress.state, "mouse-primary", { x = 8, y = 0 }, 8)
	expectEqual(
		worldDragStarted.actions[1].kind,
		"DragStarted",
		"eight-pixel World Path motion starts a deliberate drag"
	)

	local dragMoved = PointerDrag.move(dragStarted.state, "mouse-primary", { x = 18, y = 16 })
	expectEqual(dragMoved.state.phase, "Dragging", "captured movement remains dragging")
	expectEqual(dragMoved.actions[1].kind, "DragMoved", "captured movement emits a drag action")
	expectEqual(dragMoved.actions[1].startPosition.x, 10, "drag actions retain the original press point")

	local wrongRelease = PointerDrag.release(dragMoved.state, "touch-2", { x = 18, y = 16 })
	expectEqual(wrongRelease.state, dragMoved.state, "wrong pointer cannot release the captured drag")
	expectEqual(#wrongRelease.actions, 0, "wrong-pointer release emits no action")

	local committed = PointerDrag.release(dragMoved.state, "mouse-primary", { x = 20, y = 18 })
	expectEqual(committed.state.phase, "Idle", "captured release returns to idle")
	expectEqual(committed.actions[1].kind, "Committed", "drag release emits one commit action")
	expectEqual(committed.actions[1].position.x, 20, "commit action carries the final release point")
	expectEqual(PointerDrag.isActive(committed.state), false, "committed drag releases pointer capture")
	local staleRelease = PointerDrag.release(committed.state, "mouse-primary", { x = 30, y = 30 })
	expectEqual(#staleRelease.actions, 0, "release after commit cannot commit twice")

	local clickPress = PointerDrag.press(
		idle,
		"mouse-primary",
		{ kind = "Edge", id = "edge_1" },
		{ x = 0, y = 0 }
	)
	local clickMove = PointerDrag.move(clickPress.state, "mouse-primary", { x = 2, y = 2 })
	local clicked = PointerDrag.release(clickMove.state, "mouse-primary", { x = 2, y = 2 })
	expectEqual(clicked.state.phase, "Idle", "short click releases pointer capture")
	expectEqual(clicked.actions[1].kind, "Clicked", "release below threshold emits click instead of commit")

	local farReleasePress = PointerDrag.press(
		idle,
		"mouse-primary",
		{ kind = "Handle", id = "edge_1", handleId = "In" },
		{ x = 0, y = 0 }
	)
	local farRelease = PointerDrag.release(farReleasePress.state, "mouse-primary", { x = 5, y = 0 })
	expectEqual(#farRelease.actions, 2, "far release without a move still crosses the drag threshold")
	expectEqual(farRelease.actions[1].kind, "DragStarted", "far release first emits drag start")
	expectEqual(farRelease.actions[2].kind, "Committed", "far release then commits exactly once")

	local pressedCancel = PointerDrag.cancel(clickPress.state, "Escape")
	expectEqual(pressedCancel.state.phase, "Idle", "cancelling a press releases pointer capture")
	expectEqual(pressedCancel.actions[1].kind, "Cancelled", "cancelling a press emits cancellation")
	expectEqual(pressedCancel.actions[1].reason, "Escape", "cancellation records its lifecycle reason")

	local draggingCancel = PointerDrag.cancel(dragMoved.state, "WidgetFocusReleased")
	expectEqual(draggingCancel.state.phase, "Idle", "cancelling a drag returns to idle")
	expectEqual(draggingCancel.actions[1].kind, "Cancelled", "active drag cancellation is explicit")
	expectEqual(draggingCancel.actions[1].position.x, 18, "cancellation reports the last captured point")
	local releaseAfterCancel = PointerDrag.release(draggingCancel.state, "mouse-primary", { x = 20, y = 18 })
	expectEqual(#releaseAfterCancel.actions, 0, "release after cancellation cannot commit")

	local invalidPointerAccepted = pcall(function()
		PointerDrag.press(idle, "", { kind = "Node", id = "node_bad" }, { x = 0, y = 0 })
	end)
	local invalidTargetAccepted = pcall(function()
		PointerDrag.press(idle, "mouse-primary", { kind = "Node", id = "" }, { x = 0, y = 0 })
	end)
	local invalidTargetKindAccepted = pcall(function()
		PointerDrag.press(
			idle,
			"mouse-primary",
			{ kind = "Hnadle", id = "edge_bad" } :: any,
			{ x = 0, y = 0 }
		)
	end)
	local missingHandleIdAccepted = pcall(function()
		PointerDrag.press(
			idle,
			"mouse-primary",
			{ kind = "Handle", id = "edge_bad" } :: any,
			{ x = 0, y = 0 }
		)
	end)
	local invalidCancelReasonAccepted = pcall(function()
		PointerDrag.cancel(clickPress.state, "")
	end)
	local invalidThresholdAccepted = pcall(function()
		PointerDrag.move(worldPress.state, "mouse-primary", { x = 1, y = 0 }, -1)
	end)
	expectEqual(invalidPointerAccepted, false, "pointer drag rejects empty pointer ids")
	expectEqual(invalidTargetAccepted, false, "pointer drag rejects empty target ids")
	expectEqual(invalidTargetKindAccepted, false, "pointer drag rejects unknown target kinds")
	expectEqual(missingHandleIdAccepted, false, "pointer drag requires handle target ids")
	expectEqual(invalidCancelReasonAccepted, false, "pointer drag rejects empty cancellation reasons")
	expectEqual(invalidThresholdAccepted, false, "pointer drag rejects invalid custom thresholds")
end

do
	local allowBegin = true
	local beginThrows = false
	local applySucceeds = true
	local commitSucceeds = true
	local finishThrows = false
	local beginLabels: { string } = {}
	local finishCommits: { boolean } = {}
	local finishSawInactive: { boolean } = {}
	local appliedTargets: { any } = {}
	local appliedPositions: { any } = {}
	local previewCount = 0
	local committedCount = 0
	local failedActions: { string } = {}
	local failedPhases: { PaintRouteDragSession.FailurePhase } = {}
	local blockedActions: { string } = {}
	local releasedWithoutEditCount = 0
	local nextTransaction = 0
	local session: PaintRouteDragSession.Session
	session = PaintRouteDragSession.new({
		beginEdit = function(label: string): number?
			table.insert(beginLabels, label)
			if beginThrows then
				error("simulated route begin failure")
			end
			if not allowBegin then
				return nil
			end
			nextTransaction += 1
			return nextTransaction
		end,
		finishEdit = function(_transaction: number, commit: boolean): boolean
			table.insert(finishCommits, commit)
			table.insert(finishSawInactive, not session:isActive())
			if finishThrows then
				error("simulated route persistence failure")
			end
			return if commit then commitSucceeds else false
		end,
		applyTarget = function(target: any, position: any): boolean
			table.insert(appliedTargets, target)
			table.insert(appliedPositions, position)
			return applySucceeds
		end,
		onPreview = function()
			previewCount += 1
		end,
		reportBlocked = function(action: string)
			table.insert(blockedActions, action)
		end,
		onCommitted = function()
			committedCount += 1
		end,
		onFailed = function(action: string, phase: PaintRouteDragSession.FailurePhase)
			table.insert(failedActions, action)
			table.insert(failedPhases, phase)
		end,
		onReleasedWithoutEdit = function()
			releasedWithoutEditCount += 1
		end,
	})

	local nodeTarget = { kind = "Node", id = "node_1" } :: PaintRouteDragSession.Target
	local handleTarget = {
		kind = "Handle",
		id = "edge_1",
		handleId = "Out",
	} :: PaintRouteDragSession.Target
	local origin = { x = 0, y = 0 }
	local firstPosition = { x = 10, y = 7, z = 20 }
	local secondPosition = { x = 11, y = 7, z = 21 }

	expectEqual(session:press(nodeTarget, origin), true, "route session captures a node press")
	expectEqual(
		session:move({ x = 3, y = 0 }, firstPosition),
		true,
		"route session owns a below-threshold press"
	)
	expectEqual(#beginLabels, 0, "below-threshold route movement starts no transaction")
	expectEqual(
		session:release({ x = 3, y = 0 }, firstPosition),
		true,
		"route session consumes a node click release"
	)
	expectEqual(releasedWithoutEditCount, 1, "route click reports selection without an edit")
	expectEqual(#appliedTargets, 0, "route click never mutates the graph")

	session:press(nodeTarget, origin)
	session:move({ x = 4, y = 0 }, firstPosition)
	session:move({ x = 8, y = 0 }, secondPosition)
	expectEqual(#beginLabels, 1, "one route drag begins exactly one transaction")
	expectEqual(beginLabels[1], "Move Stagewright route node", "node drag uses the stable undo label")
	expectEqual(#appliedTargets, 2, "captured route movement reuses its transaction")
	expectEqual(previewCount, 2, "every accepted route movement refreshes the preview")
	expectEqual(session:isActive(), true, "route drag stays active until release")
	session:release({ x = 9, y = 0 }, { x = 12, y = 7, z = 22 })
	expectEqual(#appliedTargets, 3, "route release applies its final pointer position")
	expectEqual(appliedTargets[3].kind, "Node", "node drag stays routed to the node adapter")
	expectEqual(appliedPositions[3].x, 12, "route release forwards the final local position")
	expectEqual(finishCommits[1], true, "route release commits one undo transaction")
	expectEqual(finishSawInactive[1], true, "route state clears before the commit adapter runs")
	expectEqual(committedCount, 1, "successful route release emits one committed callback")
	expectEqual(session:isActive(), false, "route release clears pointer and transaction state")
	expectEqual(
		session:release({ x = 10, y = 0 }, secondPosition),
		false,
		"stale route release cannot commit twice"
	)
	expectEqual(#finishCommits, 1, "stale route release does not finish twice")

	session:press(handleTarget, origin)
	session:release({ x = 5, y = 0 }, firstPosition)
	expectEqual(
		beginLabels[2],
		"Shape Stagewright route spline",
		"far handle release starts the spline undo transaction"
	)
	expectEqual(appliedTargets[4].kind, "Handle", "handle release uses the handle adapter")
	expectEqual(appliedTargets[4].handleId, "Out", "handle release preserves the handle id")
	expectEqual(finishCommits[2], true, "far release without movement still commits exactly once")

	session:press(nodeTarget, origin)
	session:move({ x = 5, y = 0 }, nil)
	expectEqual(#beginLabels, 2, "outside-grid route movement does not begin an empty edit")
	session:release({ x = 8, y = 0 }, nil)
	expectEqual(releasedWithoutEditCount, 2, "outside-only drag releases without an edit")
	session:press(nodeTarget, origin)
	session:move({ x = 5, y = 0 }, firstPosition)
	session:move({ x = 9, y = 0 }, nil)
	session:release({ x = 12, y = 0 }, nil)
	expectEqual(finishCommits[3], true, "outside release commits the last valid route position")
	expectEqual(#appliedTargets, 5, "outside release does not invent another route position")

	session:press(nodeTarget, origin)
	session:move({ x = 5, y = 0 }, firstPosition)
	expectEqual(session:cancel("Escape"), true, "route drag can be centrally cancelled")
	expectEqual(finishCommits[4], false, "route cancellation rolls back its transaction")
	expectEqual(finishSawInactive[4], true, "route rollback clears state before its adapter")
	expectEqual(session:cancel("Escape"), false, "repeated route cancellation is idempotent")
	expectEqual(#finishCommits, 4, "idle route cancellation does not finish twice")

	allowBegin = false
	session:press(nodeTarget, origin)
	session:move({ x = 5, y = 0 }, firstPosition)
	expectEqual(blockedActions[#blockedActions], "Move route node", "blocked route begin reports its action")
	expectEqual(session:isActive(), false, "blocked route begin releases pointer capture")
	session:move({ x = 8, y = 0 }, secondPosition)
	expectEqual(#blockedActions, 1, "blocked route begin is reported only once per gesture")
	allowBegin = true
	beginThrows = true
	session:press(nodeTarget, origin)
	local thrownBeginEscaped = not pcall(function()
		session:move({ x = 5, y = 0 }, firstPosition)
	end)
	expectEqual(thrownBeginEscaped, false, "route session contains a throwing begin adapter")
	expectEqual(#blockedActions, 2, "throwing route begin reports one blocked gesture")
	expectEqual(session:isActive(), false, "throwing route begin releases pointer capture")
	beginThrows = false

	applySucceeds = false
	session:press(handleTarget, origin)
	session:move({ x = 5, y = 0 }, firstPosition)
	expectEqual(finishCommits[5], false, "failed route apply rolls back its transaction")
	expectEqual(failedActions[#failedActions], "Shape route spline", "failed handle apply is reported")
	expectEqual(failedPhases[#failedPhases], "Apply", "failed handle mutation is not reported as a commit")
	expectEqual(session:isActive(), false, "failed route apply clears pointer and transaction state")
	applySucceeds = true

	commitSucceeds = false
	session:press(nodeTarget, origin)
	session:release({ x = 5, y = 0 }, firstPosition)
	expectEqual(finishCommits[6], true, "rejected route commit still requests commit once")
	expectEqual(failedActions[#failedActions], "Move route node", "rejected route commit is reported")
	expectEqual(failedPhases[#failedPhases], "Commit", "rejected route commit identifies its phase")
	expectEqual(session:isActive(), false, "rejected route commit cannot leave stale state")
	commitSucceeds = true

	finishThrows = true
	session:press(nodeTarget, origin)
	local thrownCommitEscaped = not pcall(function()
		session:release({ x = 5, y = 0 }, firstPosition)
	end)
	expectEqual(thrownCommitEscaped, false, "route session contains a throwing finish adapter")
	expectEqual(failedActions[#failedActions], "Move route node", "throwing route commit is reported")
	expectEqual(failedPhases[#failedPhases], "Commit", "throwing route commit identifies its phase")
	expectEqual(session:isActive(), false, "throwing route commit leaves the session idle")
	finishThrows = false

	local finishesBeforeReplacement = #finishCommits
	session:press(nodeTarget, origin)
	session:move({ x = 5, y = 0 }, firstPosition)
	expectEqual(session:press(handleTarget, origin), true, "new press replaces a missed route release")
	expectEqual(
		#finishCommits,
		finishesBeforeReplacement + 1,
		"new press rolls back the stale route transaction once"
	)
	expectEqual(finishCommits[#finishCommits], false, "replaced route transaction is rolled back")
	session:move({ x = 5, y = 0 }, secondPosition)
	session:release({ x = 6, y = 0 }, secondPosition)
	expectEqual(appliedTargets[#appliedTargets].kind, "Handle", "replacement drag targets the new handle")
	expectEqual(finishCommits[#finishCommits], true, "replacement drag commits its own transaction")
	expectEqual(session:isActive(), false, "replacement drag finishes without stale capture")
end

do
	local nextTransaction = 0
	local beginLabels: { string } = {}
	local finishCommits: { boolean } = {}
	local finishSawInactive: { boolean } = {}
	local applications: { any } = {}
	local previews = 0
	local committedActions: { string } = {}
	local failedActions: { string } = {}
	local failedPhases: { PaintStrokeSession.FailurePhase } = {}
	local blockedActions: { string } = {}
	local allowBegin = true
	local beginThrows = false
	local applySucceeds = true
	local applyThrows = false
	local commitSucceeds = true
	local finishThrows = false
	local tokens: { [string]: string } = {
		["1:1"] = "A",
		["2:1"] = "A",
		["3:1"] = "B",
		["1:2"] = "A",
		["2:2"] = "B",
		["3:2"] = "B",
	}
	local session: PaintStrokeSession.Session
	session = PaintStrokeSession.new({
		beginEdit = function(label: string): number?
			table.insert(beginLabels, label)
			if beginThrows then
				error("simulated paint begin failure")
			end
			if not allowBegin then
				return nil
			end
			nextTransaction += 1
			return nextTransaction
		end,
		finishEdit = function(_transaction: number, commit: boolean): boolean
			table.insert(finishCommits, commit)
			table.insert(finishSawInactive, not session:isActive())
			if finishThrows then
				error("simulated paint finish failure")
			end
			return if commit then commitSucceeds else true
		end,
		dimensions = function(): (number, number)
			return 3, 2
		end,
		fillToken = function(column: number, row: number): string
			return tokens[`{column}:{row}`]
		end,
		applyArea = function(
			brushId: string,
			column: number,
			row: number,
			brushSize: number,
			visited: PaintStrokeSession.Visited
		): boolean
			if applyThrows then
				error("simulated paint apply failure")
			end
			if not applySucceeds then
				return false
			end
			local key = `{column}:{row}`
			if visited[key] then
				return true
			end
			visited[key] = true
			table.insert(applications, {
				brushId = brushId,
				column = column,
				row = row,
				brushSize = brushSize,
			})
			if brushId == "fill_brush" then
				tokens[key] = "X"
			end
			return true
		end,
		onPreview = function()
			previews += 1
		end,
		reportBlocked = function(action: string)
			table.insert(blockedActions, action)
		end,
		onCommitted = function(action: string)
			table.insert(committedActions, action)
		end,
		onFailed = function(action: string, phase: PaintStrokeSession.FailurePhase)
			table.insert(failedActions, action)
			table.insert(failedPhases, phase)
		end,
	})

	local pencilSpec: PaintStrokeSession.Spec = {
		tool = "Pencil",
		brushId = "ground",
		brushSize = 3,
	}
	expectEqual(session:begin(pencilSpec, 1, 1), true, "paint stroke begins from a valid cell")
	expectEqual(beginLabels[1], "Paint Stagewright cells", "paint stroke uses the stable undo label")
	pencilSpec.brushId = "changed_mid_stroke"
	pencilSpec.brushSize = 5
	expectEqual(session:move(1, 1, true), true, "paint stroke consumes repeated visited movement")
	expectEqual(#applications, 1, "paint stroke shares visited cells across movement")
	expectEqual(session:move(2, 1, false), false, "paint stroke pauses when Shift is released")
	expectEqual(#applications, 1, "Shift-off movement does not mutate cells")
	expectEqual(session:move(2, 1, true), true, "paint stroke resumes while Shift is held")
	expectEqual(applications[2].brushId, "ground", "paint stroke snapshots the starting brush")
	expectEqual(applications[2].brushSize, 3, "paint stroke snapshots the starting brush size")
	expectEqual(session:release(2, 1), true, "paint stroke release commits")
	expectEqual(finishCommits[1], true, "paint stroke requests one committed transaction")
	expectEqual(finishSawInactive[1], true, "paint stroke clears state before commit")
	expectEqual(committedActions[1], "Paint stroke", "paint stroke reports its stable action")
	expectEqual(session:release(2, 1), false, "stale paint release cannot commit twice")
	local applicationsAfterRelease = #applications
	expectEqual(session:move(3, 1, true), false, "movement after a missed paint release stays inactive")
	expectEqual(#applications, applicationsAfterRelease, "movement without a held paint stroke cannot mutate")

	local rectangleStart = #applications
	session:begin({ tool = "Rect", brushId = "blocked", brushSize = 5 }, 3, 2)
	session:release(1, 1)
	expectEqual(#applications - rectangleStart, 6, "reversed rectangle paints inclusive bounds")
	for index = rectangleStart + 1, #applications do
		expectEqual(applications[index].brushSize, 1, "rectangle ignores the configured area brush size")
	end
	expectEqual(previews, 4, "pencil begin, accepted moves, and rectangle each preview once")

	local fillStart = #applications
	expectEqual(
		session:begin({ tool = "Fill", brushId = "fill_brush", brushSize = 5 }, 1, 1),
		true,
		"paint fill completes from begin"
	)
	expectEqual(session:isActive(), false, "paint fill commits immediately")
	expectEqual(#applications - fillStart, 3, "paint fill visits one connected color region")
	for index = fillStart + 1, #applications do
		expectEqual(applications[index].brushSize, 1, "paint fill never mutates configured brush size")
	end
	expectEqual(committedActions[#committedActions], "Paint fill", "paint fill reports its action")

	session:begin({ tool = "Erase", brushId = "reset", brushSize = 1 }, 3, 2)
	expectEqual(session:cancel("Escape"), true, "active paint stroke can be cancelled")
	expectEqual(finishCommits[#finishCommits], false, "paint cancellation rolls back once")
	expectEqual(
		finishSawInactive[#finishSawInactive],
		true,
		"paint cancellation clears state before rollback"
	)
	expectEqual(session:cancel("Escape"), false, "repeated paint cancellation is idempotent")

	allowBegin = false
	expectEqual(
		session:begin({ tool = "Pencil", brushId = "ground", brushSize = 1 }, 1, 1),
		false,
		"rejected paint begin returns false"
	)
	expectEqual(blockedActions[#blockedActions], "Paint stroke", "rejected paint begin reports its action")
	allowBegin = true
	beginThrows = true
	local beginEscaped = not pcall(function()
		session:begin({ tool = "Fill", brushId = "ground", brushSize = 1 }, 1, 1)
	end)
	expectEqual(beginEscaped, false, "paint session contains a throwing begin adapter")
	expectEqual(blockedActions[#blockedActions], "Paint fill", "throwing paint begin reports its action")
	beginThrows = false

	applySucceeds = false
	session:begin({ tool = "Pencil", brushId = "ground", brushSize = 1 }, 1, 1)
	expectEqual(finishCommits[#finishCommits], false, "rejected paint apply rolls back")
	expectEqual(failedActions[#failedActions], "Paint stroke", "rejected paint apply reports its action")
	expectEqual(failedPhases[#failedPhases], "Apply", "rejected paint apply identifies its phase")
	expectEqual(session:isActive(), false, "rejected paint apply clears state")
	applySucceeds = true
	applyThrows = true
	local applyEscaped = not pcall(function()
		session:begin({ tool = "Erase", brushId = "reset", brushSize = 1 }, 1, 1)
	end)
	expectEqual(applyEscaped, false, "paint session contains a throwing apply adapter")
	expectEqual(failedPhases[#failedPhases], "Apply", "throwing paint apply identifies its phase")
	applyThrows = false

	commitSucceeds = false
	session:begin({ tool = "Pencil", brushId = "ground", brushSize = 1 }, 1, 1)
	session:release(1, 1)
	expectEqual(failedPhases[#failedPhases], "Commit", "rejected paint commit identifies its phase")
	expectEqual(session:isActive(), false, "rejected paint commit leaves no stale state")
	commitSucceeds = true
	finishThrows = true
	session:begin({ tool = "Pencil", brushId = "ground", brushSize = 1 }, 1, 1)
	local finishEscaped = not pcall(function()
		session:release(1, 1)
	end)
	expectEqual(finishEscaped, false, "paint session contains a throwing finish adapter")
	expectEqual(failedPhases[#failedPhases], "Commit", "throwing paint finish identifies its phase")
	expectEqual(session:isActive(), false, "throwing paint finish leaves the session idle")
	finishThrows = false

	local finishesBeforeReplacement = #finishCommits
	session:begin({ tool = "Pencil", brushId = "ground", brushSize = 1 }, 1, 1)
	session:begin({ tool = "Rect", brushId = "blocked", brushSize = 3 }, 2, 2)
	expectEqual(
		#finishCommits,
		finishesBeforeReplacement + 1,
		"new paint press rolls back a stale transaction once"
	)
	expectEqual(finishCommits[#finishCommits], false, "replacement paint press rolls back the old stroke")
	session:release(nil, nil)
	expectEqual(session:isActive(), false, "replacement paint stroke finishes without stale state")
end

do
	local graph = {
		nodes = {
			node_1 = { position = { x = 0, y = 7, z = 0 } },
			node_2 = { position = { x = 30, y = 9, z = 40 } },
		},
		edges = {
			edge_1 = {
				fromNodeId = "node_1",
				toNodeId = "node_2",
				outHandleOffset = { x = 1, y = 2, z = 3 },
				inHandleOffset = { x = -1, y = -2, z = -3 },
			},
		},
	}
	expectEqual(
		GraphOperations.moveNode(graph, "node_1", { x = 10, y = 100, z = 20 }),
		true,
		"route node mutation accepts an existing node"
	)
	expectEqual(graph.nodes.node_1.position.x, 10, "route node mutation updates local x")
	expectEqual(graph.nodes.node_1.position.z, 20, "route node mutation updates local z")
	expectEqual(graph.nodes.node_1.position.y, 7, "route node mutation preserves authored height")
	expectEqual(
		GraphOperations.moveNode(graph, "node_missing", { x = 0, y = 0, z = 0 }),
		false,
		"route node mutation rejects a missing target"
	)
	expectEqual(
		GraphOperations.moveHandle(graph, "edge_1", "Out", { x = 15, y = 100, z = 25 }),
		true,
		"route handle mutation accepts an existing outgoing handle"
	)
	expectEqual(graph.edges.edge_1.outHandleOffset.x, 5, "outgoing handle stores anchor-relative x")
	expectEqual(graph.edges.edge_1.outHandleOffset.z, 5, "outgoing handle stores anchor-relative z")
	expectEqual(graph.edges.edge_1.outHandleOffset.y, 2, "outgoing handle preserves authored height")
	expectEqual(
		GraphOperations.moveHandle(graph, "edge_1", "In", { x = 24, y = 100, z = 32 }),
		true,
		"route handle mutation accepts an existing incoming handle"
	)
	expectEqual(graph.edges.edge_1.inHandleOffset.x, -6, "incoming handle stores anchor-relative x")
	expectEqual(graph.edges.edge_1.inHandleOffset.z, -8, "incoming handle stores anchor-relative z")
	expectEqual(graph.edges.edge_1.inHandleOffset.y, -2, "incoming handle preserves authored height")
	expectEqual(
		GraphOperations.moveHandle(graph, "edge_1", "Side", { x = 0, y = 0, z = 0 }),
		false,
		"route handle mutation rejects an unsupported handle"
	)
	expectEqual(
		GraphOperations.moveHandle(graph, "edge_missing", "Out", { x = 0, y = 0, z = 0 }),
		false,
		"route handle mutation rejects a missing edge"
	)
end

do
	local graph = {
		nodes = {
			spawn = { id = "spawn", kind = "Spawn", name = "Spawn", position = { x = 0, y = 0, z = 0 } },
			junction = {
				id = "junction",
				kind = "Junction",
				name = "Junction",
				position = { x = 10, y = 0, z = 0 },
			},
			goal = { id = "goal", kind = "Goal", name = "Goal", position = { x = 20, y = 0, z = 0 } },
		},
		edges = {},
		laneProfiles = {},
	}
	local edgeId = GraphOperations.connect(graph, "spawn", "junction")
	expectEqual(type(edgeId), "string", "graph connect creates a valid directed spline")
	local edge = graph.edges[assert(edgeId, "connected edge ID")]
	expectEqual(edge.metadata.pathAssetId, "gravel", "new graph edge receives path asset metadata")
	expectEqual(edge.metadata.curveMode, "Smooth", "new graph edge receives curve metadata")
	expectEqual(edge.metadata.laneWidth, 4, "new graph edge receives lane width metadata")
	local parallelEdgeId = GraphOperations.connect(graph, "spawn", "junction")
	expectEqual(type(parallelEdgeId), "string", "graph connect preserves parallel directed splines")
	expectEqual(parallelEdgeId ~= edgeId, true, "parallel graph splines keep independent stable IDs")
	expectEqual(GraphOperations.connect(graph, "goal", "junction"), nil, "goal nodes reject outgoing splines")
	expectEqual(
		GraphOperations.connect(graph, "junction", "spawn"),
		nil,
		"spawn nodes reject incoming splines"
	)
	expectEqual(GraphOperations.setLaneCount(graph, edgeId, 2), true, "lane count mutates a selected spline")
	local profile = graph.laneProfiles[edge.laneProfileId]
	expectEqual(profile.offsets[1], -2, "two-lane route uses the authored lane width as spacing")
	expectEqual(profile.offsets[2], 2, "two-lane route remains centered")
	expectEqual(GraphOperations.setLaneWidth(graph, edgeId, 6), true, "lane width mutates route clearance")
	expectEqual(profile.offsets[1], -3, "lane width updates negative lane offset")
	expectEqual(profile.offsets[2], 3, "lane width updates positive lane offset")
	expectEqual(profile.clearanceRadius, 6, "lane width updates the no-build clearance radius")
	expectEqual(GraphOperations.setPriority(graph, edgeId, 200), true, "priority mutation accepts a spline")
	expectEqual(edge.priority, 99, "priority mutation clamps unsafe values")
	edge.metadata.pathAssetId = "external_path_pack"
	edge.metadata.surfaceMode = "ProjectedSurface"
	expectEqual(
		GraphOperations.setPathAsset(graph, edgeId, "external_path_pack"),
		false,
		"path asset mutation rejects unknown catalog IDs"
	)
	expectEqual(
		edge.metadata.pathAssetId,
		"external_path_pack",
		"rejecting a path asset preserves unknown loaded metadata"
	)
	expectEqual(
		edge.metadata.surfaceMode,
		"ProjectedSurface",
		"editing other spline properties preserves legacy surface metadata"
	)
	expectEqual(GraphOperations.setPathAsset(graph, edgeId, "dirt"), true, "path asset metadata is editable")
	expectEqual(edge.metadata.pathAssetId, "dirt", "valid path asset mutation persists")
	expectEqual(
		GraphOperations.setEdgeProperty(graph, edgeId, "PathAsset", "stone"),
		true,
		"generic inspector mutation delegates to the validated graph operation"
	)
	expectEqual(edge.metadata.pathAssetId, "stone", "generic inspector mutation persists the selected style")
	expectEqual(
		GraphOperations.setEdgeProperty(graph, edgeId, "UnknownProperty", "value"),
		false,
		"generic inspector mutation rejects undeclared properties"
	)
	expectEqual(
		GraphOperations.setPathAsset(graph, "missing_edge", "stone"),
		false,
		"path asset mutation rejects a missing spline"
	)
	expectEqual(GraphOperations.setCurveMode(graph, edgeId, "Free"), true, "curve metadata is editable")
	expectEqual(edge.metadata.curveMode, "Free", "curve mutation persists on the selected spline")
	local previousIncomingX = edge.inHandleOffset.x
	expectEqual(
		GraphOperations.setHandleOffset(graph, edgeId, "Out", { x = 2, y = 0, z = 3 }),
		true,
		"free curve mode accepts an authored handle"
	)
	expectEqual(edge.inHandleOffset.x, previousIncomingX, "free curve mode leaves the opposite handle alone")
	expectEqual(GraphOperations.setCurveMode(graph, edgeId, "Mirrored"), true, "mirrored mode is editable")
	expectEqual(edge.inHandleOffset.x, -2, "mirrored mode aligns the opposite handle")
	expectEqual(edge.inHandleOffset.z, -3, "mirrored mode mirrors the full handle vector")
	expectEqual(GraphOperations.setLaneCount(graph, edgeId, 0), false, "lane count rejects invalid values")
	expectEqual(GraphOperations.setLaneWidth(graph, edgeId, math.huge), false, "lane width rejects infinity")
	expectEqual(GraphOperations.setPriority(graph, edgeId, -math.huge), false, "priority rejects infinity")
	expectEqual(
		GraphOperations.setCurveMode(graph, edgeId, "Decorative"),
		false,
		"curve mutation rejects unsupported modes"
	)
end

do
	local graph = {
		nodes = {
			spawn = { id = "spawn", kind = "Spawn", name = "Spawn", position = { x = 0, y = 0, z = 0 } },
			spawn_2 = {
				id = "spawn_2",
				kind = "Spawn",
				name = "Spawn 2",
				position = { x = 0, y = 0, z = 10 },
			},
			junction = {
				id = "junction",
				kind = "Junction",
				name = "Junction",
				position = { x = 10, y = 0, z = 0 },
			},
			junction_2 = {
				id = "junction_2",
				kind = "Junction",
				name = "Junction 2",
				position = { x = 20, y = 0, z = 0 },
			},
			goal = { id = "goal", kind = "Goal", name = "Goal", position = { x = 30, y = 0, z = 0 } },
		},
		edges = {},
		laneProfiles = {},
	}
	local sourceNodeId: string? = nil
	local selectedNodeId: string? = nil
	local selectedEdgeId: string? = nil
	local lastStatus = ""
	local statusWasError = false
	local finishCount = 0
	local renderCount = 0
	local mutateCount = 0
	local allowMutation = true
	local controller = GraphToolController.new({
		currentGraph = function()
			return graph
		end,
		sourceNodeId = function()
			return sourceNodeId
		end,
		setSourceNodeId = function(value: string?)
			sourceNodeId = value
		end,
		mutate = function(_label: string, operation: () -> ()): boolean
			mutateCount += 1
			if not allowMutation then
				return false
			end
			operation()
			return true
		end,
		select = function(nodeId: string?, edgeId: string?)
			selectedNodeId = nodeId
			selectedEdgeId = edgeId
		end,
		setStatus = function(message: string, isError: boolean?)
			lastStatus = message
			statusWasError = isError == true
		end,
		finishTool = function()
			finishCount += 1
		end,
		render = function()
			renderCount += 1
		end,
	})

	sourceNodeId = "spawn"
	expectEqual(controller:beginSource("goal"), false, "Connect rejects Goal as a source")
	expectEqual(sourceNodeId, nil, "rejected Goal source cannot wedge Connect")
	expectEqual(statusWasError, true, "rejected Goal source reports a useful error")
	sourceNodeId = "spawn"
	expectEqual(controller:beginSource("missing"), false, "Connect rejects a deleted source")
	expectEqual(sourceNodeId, nil, "deleted source is cleared")
	expectEqual(controller:beginSource("spawn"), true, "Connect explicitly arms a valid source")
	expectEqual(sourceNodeId, "spawn", "Connect stores the armed source")
	expectEqual(selectedNodeId, "spawn", "arming Connect selects its source")
	expectEqual(renderCount, 1, "arming Connect refreshes its source feedback")
	expectEqual(controller:activateNode("spawn"), nil, "Connect rejects a node connected to itself")
	expectEqual(sourceNodeId, "spawn", "self-connect rejection keeps the valid source armed")
	expectEqual(
		controller:activateNode("spawn_2"),
		nil,
		"Connect rejects directions that would enter a Spawn"
	)
	expectEqual(sourceNodeId, "spawn", "invalid destination keeps the source for a retry")
	expectEqual(controller:activateNode("junction"), true, "Connect creates a directed spline on valid retry")
	expectEqual(sourceNodeId, nil, "successful Connect clears its source")
	expectEqual(selectedNodeId, nil, "successful Connect clears node selection")
	expectEqual(type(selectedEdgeId), "string", "successful Connect selects the created spline")
	expectEqual(finishCount, 1, "successful Connect returns to Select exactly once")
	expectEqual(renderCount, 2, "successful Connect refreshes the graph")

	sourceNodeId = "deleted"
	expectEqual(controller:activateNode("missing"), nil, "Connect rejects a deleted destination")
	expectEqual(sourceNodeId, nil, "a deleted destination also clears a stale source")
	sourceNodeId = "deleted"
	expectEqual(
		controller:activateNode("junction_2"),
		false,
		"Connect recovers from a stale source by arming the clicked node"
	)
	expectEqual(sourceNodeId, "junction_2", "stale source recovery stores the replacement source")
	sourceNodeId = "goal"
	expectEqual(controller:activateNode("junction"), false, "Connect recovers from an invalid Goal source")
	expectEqual(sourceNodeId, "junction", "Goal source recovery arms the clicked valid node")
	expectEqual(
		controller:connectNodes("goal", "junction"),
		nil,
		"port-drag Connect rejects an invalid explicit source"
	)
	expectEqual(sourceNodeId, nil, "invalid port-drag source is never retained")
	expectEqual(
		controller:connectNodes("missing", "junction"),
		nil,
		"port-drag Connect rejects a deleted explicit source"
	)
	expectEqual(sourceNodeId, nil, "deleted port-drag source is never retained")
	expectEqual(
		controller:connectNodes("junction", "goal"),
		true,
		"port-drag Connect creates a valid directed spline"
	)
	expectEqual(sourceNodeId, nil, "successful port-drag Connect clears its shared source")
	expectEqual(finishCount, 2, "successful port-drag Connect returns to Select")

	allowMutation = false
	expectEqual(
		controller:connectNodes("spawn", "junction_2"),
		nil,
		"Connect reports a transaction that did not commit"
	)
	expectEqual(sourceNodeId, "spawn", "failed Connect transaction keeps its valid source for retry")
	expectEqual(
		lastStatus,
		"The route connection could not be created.",
		"failed Connect explains the result"
	)
	allowMutation = true
	expectEqual(controller:activateNode("junction_2"), true, "Connect can retry after a failed transaction")

	local edgeToSplit = assert(selectedEdgeId, "connected edge selected for split")
	allowMutation = false
	expectEqual(controller:splitEdge(edgeToSplit), false, "Split reports a transaction that did not commit")
	expectEqual(graph.edges[edgeToSplit] ~= nil, true, "failed Split preserves the original spline")
	allowMutation = true
	expectEqual(controller:splitEdge(edgeToSplit), true, "Split replaces a valid spline with two halves")
	expectEqual(graph.edges[edgeToSplit], nil, "successful Split retires the original spline")
	expectEqual(type(selectedNodeId), "string", "successful Split selects its inserted junction")
	expectEqual(selectedEdgeId, nil, "successful Split clears spline selection")
	expectEqual(finishCount, 4, "Connect and Split each finish their tool after success")
	local mutationCountBeforeMissingSplit = mutateCount
	expectEqual(controller:splitEdge("missing"), false, "Split rejects a deleted spline")
	expectEqual(mutateCount, mutationCountBeforeMissingSplit, "deleted spline never opens a mutation")
	graph.edges.corrupt = {
		id = "corrupt",
		fromNodeId = "missing",
		toNodeId = "goal",
	}
	expectEqual(
		controller:splitEdge("corrupt"),
		false,
		"Split rejects a corrupt spline with a deleted endpoint"
	)
	expectEqual(graph.edges.corrupt ~= nil, true, "rejected corrupt Split preserves imported data")
end

do
	local openRange, openRangeError = PredicateFields.fromText("WaveRange", "", "5", "", {
		fromNodeId = "spawn",
	})
	expectEqual(openRangeError, nil, "open-ended wave condition parses without a fake maximum")
	local resolvedOpenRange = assert(openRange, "open wave range")
	expectEqual(resolvedOpenRange.minimum, 5, "open-ended wave condition preserves its minimum")
	expectEqual(resolvedOpenRange.maximum, nil, "open-ended wave condition omits its maximum")
	expectEqual(
		PredicateFields.describe(resolvedOpenRange),
		"Wave >= 5",
		"wave condition has truthful UI copy"
	)
	local invalidRange, invalidRangeError = PredicateFields.fromText("WaveRange", "", "8", "4", {
		fromNodeId = "spawn",
	})
	expectEqual(invalidRange, nil, "reversed wave range is rejected")
	expectEqual(type(invalidRangeError), "string", "reversed wave range reports a useful error")
	for _, invalidMinimum in { "0", "1.5", "1e999" } do
		local invalid = PredicateFields.fromText("WaveRange", "", invalidMinimum, "", {
			fromNodeId = "spawn",
		})
		expectEqual(invalid, nil, `wave condition rejects unsafe value {invalidMinimum}`)
	end
	local invalidVisit = PredicateFields.fromText("VisitCountBelow", "spawn", "-1", "", {
		fromNodeId = "spawn",
	})
	expectEqual(invalidVisit, nil, "visit condition rejects negative counts")
	local invalidUpgrade = PredicateFields.fromText("UpgradeLevelAtLeast", "tower", "2.5", "", {
		fromNodeId = "spawn",
	})
	expectEqual(invalidUpgrade, nil, "upgrade condition rejects fractional levels")
	local invalidCurrency = PredicateFields.fromText("CurrencyAtLeast", "coins", "1e999", "", {
		fromNodeId = "spawn",
	})
	expectEqual(invalidCurrency, nil, "currency condition rejects infinity")
	expectEqual(
		PredicateFields.describe({ kind = "CurrencyAtLeast", currencyId = "Coins", amount = 50 }),
		"Coins >= 50",
		"currency condition has truthful UI copy"
	)
end

do
	local graph = {
		nodes = {
			start = { id = "start", kind = "Spawn", name = "Start", position = { x = 0, y = 0, z = 0 } },
			finish = { id = "finish", kind = "Goal", name = "Finish", position = { x = 10, y = 0, z = 0 } },
		},
		edges = {
			edge = {
				id = "edge",
				fromNodeId = "start",
				toNodeId = "finish",
				outHandleOffset = { x = 3, y = 0, z = 0 },
				inHandleOffset = { x = -3, y = 0, z = 0 },
				laneProfileId = "lane",
				metadata = {
					pathAssetId = "gravel",
					curveMode = "Smooth",
					surfaceMode = "FollowTerrain",
					laneWidth = 4,
					custom = { value = 7 },
				},
				priority = 3,
				predicates = { { kind = "WaveRange", minimum = 5 } },
			},
		},
		laneProfiles = {
			lane = { id = "lane", offsets = { -2, 2 }, clearanceRadius = 4 },
		},
	}
	local splitNodeId = GraphOperations.splitEdge(graph, "edge")
	expectEqual(type(splitNodeId), "string", "graph split creates a junction")
	local splitNode = graph.nodes[assert(splitNodeId, "split node ID")]
	expectEqual(splitNode.position.x, 5, "De Casteljau split preserves the cubic midpoint")
	expectEqual(graph.edges.edge, nil, "graph split retires the original spline")
	local firstEdge: any? = nil
	local secondEdge: any? = nil
	for _, candidate in graph.edges do
		if candidate.fromNodeId == "start" then
			firstEdge = candidate
		elseif candidate.toNodeId == "finish" then
			secondEdge = candidate
		end
	end
	expectEqual(firstEdge ~= nil, true, "graph split creates the first exact half")
	expectEqual(secondEdge ~= nil, true, "graph split creates the second exact half")
	local resolvedFirstEdge = assert(firstEdge, "first split edge")
	local resolvedSecondEdge = assert(secondEdge, "second split edge")
	expectEqual(resolvedFirstEdge.metadata.laneWidth, 4, "graph split preserves edge metadata")
	expectEqual(resolvedFirstEdge.predicates[1].minimum, 5, "graph split preserves entry predicates")
	expectEqual(resolvedSecondEdge.metadata.curveMode, "Smooth", "graph split copies curve metadata")
	resolvedFirstEdge.metadata.custom.value = 9
	expectEqual(resolvedSecondEdge.metadata.custom.value, 7, "split metadata copies stay independent")
	expectEqual(resolvedSecondEdge.priority, 3, "graph split preserves priority on both halves")
	expectEqual(resolvedFirstEdge.outHandleOffset.x, 1.5, "first split handle follows De Casteljau")
	expectEqual(resolvedFirstEdge.inHandleOffset.x, -1.75, "first split incoming handle preserves shape")
	expectEqual(resolvedSecondEdge.outHandleOffset.x, 1.75, "second split outgoing handle preserves shape")
	expectEqual(resolvedSecondEdge.inHandleOffset.x, -1.5, "second split handle follows De Casteljau")
	expectEqual(GraphOperations.deleteEdge(graph, resolvedFirstEdge.id), true, "edge deletion succeeds")
	expectEqual(graph.laneProfiles.lane ~= nil, true, "shared lane profile remains while referenced")
	expectEqual(
		GraphOperations.deleteEdge(graph, resolvedSecondEdge.id),
		true,
		"second edge deletion succeeds"
	)
	expectEqual(
		graph.laneProfiles.lane ~= nil,
		true,
		"edge deletion preserves reusable authored lane profiles"
	)
end

do
	local graph = {
		nodes = {
			a = { id = "a", kind = "Spawn", name = "A", position = { x = 0, y = 0, z = 0 } },
			b = { id = "b", kind = "Junction", name = "B", position = { x = 10, y = 0, z = 0 } },
			c = { id = "c", kind = "Goal", name = "C", position = { x = 20, y = 0, z = 0 } },
		},
		edges = {
			edge = {
				id = "edge",
				fromNodeId = "a",
				toNodeId = "c",
				outHandleOffset = { x = 4, y = 0, z = 0 },
				inHandleOffset = { x = -4, y = 0, z = 0 },
				laneProfileId = "lane_default",
				priority = 1,
				predicates = { { kind = "VisitCountBelow", nodeId = "b", maximum = 2 } },
			},
		},
		laneProfiles = {
			lane_default = { id = "lane_default", offsets = { -2, 2 }, clearanceRadius = 5 },
		},
	}
	expectEqual(GraphOperations.deleteNode(graph, "b"), false, "referenced nodes cannot be deleted")
	expectEqual(graph.nodes.b ~= nil, true, "failed referenced-node deletion preserves graph data")
	expectEqual(GraphOperations.setLaneCount(graph, "edge", 2), true, "starter lane count can be reapplied")
	expectEqual(
		graph.edges.edge.laneProfileId,
		"lane_default",
		"reapplying a lane count does not fork an unchanged shared profile"
	)
	expectEqual(
		graph.laneProfiles.lane_default.clearanceRadius,
		5,
		"reapplying the starter lane count preserves its authored shoulder"
	)
end

do
	local graph = {
		nodes = {},
		edges = {
			first = {
				id = "first",
				laneProfileId = "shared",
				metadata = { laneWidth = 4, curveMode = "Free" },
			},
			second = {
				id = "second",
				laneProfileId = "shared",
				metadata = { laneWidth = 4, curveMode = "Free" },
			},
		},
		laneProfiles = {
			shared = { id = "shared", offsets = { -2, 2 }, clearanceRadius = 5, preserved = "yes" },
		},
	}
	expectEqual(GraphOperations.setLaneCount(graph, "first", 3), true, "shared lane profile can be edited")
	expectEqual(graph.edges.first.laneProfileId ~= "shared", true, "lane edits use copy-on-write")
	expectEqual(graph.edges.second.laneProfileId, "shared", "sibling spline keeps the original lane profile")
	expectEqual(graph.laneProfiles.shared.offsets[1], -2, "copy-on-write preserves sibling lane offsets")
	expectEqual(
		graph.laneProfiles[graph.edges.first.laneProfileId].preserved,
		"yes",
		"copy-on-write preserves unknown profile fields"
	)
end

do
	local writable = false
	local allowBegin = true
	local commitSucceeds = true
	local finishThrows = false
	local applyNodeSucceeds = true
	local beginCount = 0
	local finishCommits: { boolean } = {}
	local finishSawInactive: { boolean } = {}
	local nodeApplyCount = 0
	local handleApplyCount = 0
	local previewCount = 0
	local committedCount = 0
	local failedCount = 0
	local blockedCount = 0
	local nextTransaction = 0
	local session: WorldPathEditSession.Session
	session = WorldPathEditSession.new({
		beginEdit = function(): number?
			beginCount += 1
			if not writable or not allowBegin then
				return nil
			end
			nextTransaction += 1
			return nextTransaction
		end,
		finishEdit = function(_transaction: number, commit: boolean): boolean
			table.insert(finishCommits, commit)
			table.insert(finishSawInactive, not session:isActive())
			if finishThrows then
				error("simulated persistence failure")
			end
			return if commit then commitSucceeds else false
		end,
		applyNode = function(nodeId: string, position: any): boolean
			expectEqual(nodeId, "node_1", "world-path edit session forwards the node id")
			expectEqual(position.y, 7, "world-path edit session forwards the complete node position")
			nodeApplyCount += 1
			return applyNodeSucceeds
		end,
		applyHandle = function(edgeId: string, handleId: string, offset: any): boolean
			expectEqual(edgeId, "edge_1", "world-path edit session forwards the edge id")
			expectEqual(handleId, "Out", "world-path edit session forwards the handle id")
			expectEqual(offset.z, 9, "world-path edit session forwards the handle offset")
			handleApplyCount += 1
			return true
		end,
		currentPreview = function()
			return { revision = nodeApplyCount + handleApplyCount }
		end,
		onPreview = function(preview: any?)
			expectEqual(type(preview), "table", "accepted world-path edits publish a fresh preview")
			previewCount += 1
		end,
		reportBlocked = function()
			blockedCount += 1
		end,
		onCommitted = function()
			committedCount += 1
		end,
		onFailed = function()
			failedCount += 1
		end,
	})

	expectEqual(
		session:moveNode("node_1", { x = 1, y = 7, z = 2 }, false),
		false,
		"read-only world-path edits are rejected"
	)
	expectEqual(beginCount, 1, "read-only world-path edits consult the transaction gate once")
	expectEqual(nodeApplyCount, 0, "read-only world-path edits do not mutate the graph")
	expectEqual(blockedCount, 1, "read-only world-path edits report the blocked action")

	writable = true
	expectEqual(
		session:moveNode("node_1", { x = 2, y = 7, z = 3 }, false),
		true,
		"first valid node move begins an edit"
	)
	expectEqual(
		session:moveNode("node_1", { x = 3, y = 7, z = 4 }, false),
		true,
		"subsequent node movement reuses the edit"
	)
	expectEqual(beginCount, 2, "one captured drag begins exactly one additional transaction")
	expectEqual(#finishCommits, 0, "preview movement does not finish the transaction")
	expectEqual(previewCount, 0, "preview movement defers the expensive baked preview")
	expectEqual(session:isActive(), true, "node preview keeps its edit transaction active")
	expectEqual(
		session:moveNode("node_1", { x = 4, y = 7, z = 5 }, true),
		true,
		"finished node movement commits"
	)
	expectEqual(beginCount, 2, "the final node update does not begin a second transaction")
	expectEqual(finishCommits[1], true, "the captured node drag commits once")
	expectEqual(committedCount, 1, "successful commit emits one committed callback")
	expectEqual(previewCount, 1, "release publishes one fresh baked preview")
	expectEqual(session:isActive(), false, "successful commit clears the active edit")
	expectEqual(finishSawInactive[1], true, "transaction identity clears before the finish adapter runs")
	expectEqual(session:cancel(), false, "cancel after commit is idempotent")
	expectEqual(#finishCommits, 1, "idle cancellation does not finish twice")

	session:moveHandle("edge_1", "Out", { x = 5, y = 0, z = 9 }, false)
	expectEqual(handleApplyCount, 1, "handle movement uses the same edit coordinator")
	expectEqual(session:cancel(), true, "active handle movement can be cancelled")
	expectEqual(finishCommits[2], false, "cancelling a handle drag rolls back its transaction")
	expectEqual(finishSawInactive[2], true, "rollback clears transaction identity before the adapter")
	expectEqual(session:cancel(), false, "repeated handle cancellation is idempotent")

	allowBegin = false
	expectEqual(
		session:moveNode("node_1", { x = 6, y = 7, z = 7 }, false),
		false,
		"failed transaction begin rejects the mutation"
	)
	expectEqual(nodeApplyCount, 3, "failed transaction begin does not apply a node mutation")
	expectEqual(blockedCount, 2, "failed transaction begin reports the blocked action")
	allowBegin = true

	applyNodeSucceeds = false
	expectEqual(
		session:moveNode("node_1", { x = 7, y = 7, z = 8 }, false),
		false,
		"missing edit targets fail through the mutation adapter"
	)
	expectEqual(finishCommits[#finishCommits], false, "failed mutation adapters roll back")
	expectEqual(failedCount, 1, "failed mutation adapters request one failure refresh")
	expectEqual(session:isActive(), false, "failed mutation adapter does not leak a transaction")
	applyNodeSucceeds = true

	commitSucceeds = false
	expectEqual(
		session:moveNode("node_1", { x = 8, y = 7, z = 9 }, true),
		false,
		"failed store commit is not reported as success"
	)
	expectEqual(committedCount, 1, "failed store commit does not emit a committed callback")
	expectEqual(failedCount, 2, "failed store commit requests a rollback refresh")
	expectEqual(session:isActive(), false, "failed store commit clears the transaction")

	commitSucceeds = true
	finishThrows = true
	local throwingCommitRaised, throwingCommitResult = pcall(function(): boolean
		return session:moveNode("node_1", { x = 9, y = 7, z = 10 }, true)
	end)
	expectEqual(throwingCommitRaised, true, "throwing store commits do not escape the input callback")
	expectEqual(throwingCommitResult, false, "throwing store commits are reported as failed")
	expectEqual(committedCount, 1, "throwing store commits do not emit a committed callback")
	expectEqual(failedCount, 3, "throwing store commits request a rollback refresh")
	expectEqual(session:isActive(), false, "throwing store commits clear the transaction")
	finishThrows = false

	writable = true
	session:moveNode("node_1", { x = 10, y = 7, z = 11 }, false)
	local finishesBeforeLostWrite = #finishCommits
	writable = false
	commitSucceeds = false
	session:moveNode("node_1", { x = 11, y = 7, z = 12 }, true)
	expectEqual(
		#finishCommits,
		finishesBeforeLostWrite + 1,
		"an active edit still reaches the finish adapter after writability is lost"
	)
	expectEqual(session:isActive(), false, "lost writability cannot strand an active edit transaction")
	expectEqual(failedCount, 4, "lost writability follows the failed-commit refresh path")
end

do
	local placement = TowerDefenseRequest.parsePlacement({
		unitId = "unit_scout",
		column = 12,
		row = 7,
	})
	expectEqual(placement ~= nil and placement.column, 12, "tower placement accepts an integer column")
	expectEqual(placement ~= nil and placement.row, 7, "tower placement accepts an integer row")

	for _, invalidCoordinate in
		{
			0,
			TowerDefenseRequest.MAX_GRID_INDEX + 1,
			1.5,
			0 / 0,
			math.huge,
			-math.huge,
			"2",
		}
	do
		expectEqual(
			TowerDefenseRequest.parsePlacement({
				unitId = "unit_scout",
				column = invalidCoordinate,
				row = 1,
			}),
			nil,
			`tower placement rejects invalid column {tostring(invalidCoordinate)}`
		)
		expectEqual(
			TowerDefenseRequest.parsePlacement({
				unitId = "unit_scout",
				column = 1,
				row = invalidCoordinate,
			}),
			nil,
			`tower placement rejects invalid row {tostring(invalidCoordinate)}`
		)
	end

	for _, invalidUnitId in
		{
			"",
			string.rep("u", TowerDefenseRequest.MAX_UNIT_ID_LENGTH + 1),
			123,
		}
	do
		expectEqual(
			TowerDefenseRequest.parsePlacement({
				unitId = invalidUnitId,
				column = 1,
				row = 1,
			}),
			nil,
			`tower placement rejects invalid unit ID {tostring(invalidUnitId)}`
		)
	end
	expectEqual(
		TowerDefenseRequest.parsePlacement({
			unitId = "unit_scout",
			column = 1,
			row = 1,
			clientPrice = 0,
		}),
		nil,
		"tower placement rejects undeclared client fields"
	)

	local activation = TowerDefenseRequest.parseStageActivation({ stageId = "stage_default" })
	expectEqual(
		activation ~= nil and activation.stageId,
		"stage_default",
		"tower stage activation accepts a bounded ID"
	)
	for _, invalidStagePayload in
		{
			{},
			{ stageId = "" },
			{ stageId = string.rep("s", TowerDefenseRequest.MAX_STAGE_ID_LENGTH + 1) },
			{ stageId = 1 },
			{ stageId = "stage_default", unlocked = true },
		}
	do
		expectEqual(
			TowerDefenseRequest.parseStageActivation(invalidStagePayload),
			nil,
			"tower stage activation rejects malformed or unauthorized fields"
		)
	end

	local playtestWave = TowerDefenseRequest.parseWavePlaytest({
		stageId = "stage_default",
		waveNumber = 3,
	})
	expectEqual(
		playtestWave ~= nil and playtestWave.stageId == "stage_default" and playtestWave.waveNumber == 3,
		true,
		"tower playtest accepts an exact authored stage and wave"
	)
	for _, invalidPlaytestPayload in
		{
			{},
			{ stageId = "", waveNumber = 1 },
			{ stageId = "stage_default", waveNumber = 0 },
			{ stageId = "stage_default", waveNumber = 1.5 },
			{ stageId = "stage_default", waveNumber = math.huge },
			{ stageId = "stage_default", waveNumber = 1, unlocked = true },
		}
	do
		expectEqual(
			TowerDefenseRequest.parseWavePlaytest(invalidPlaytestPayload),
			nil,
			"tower playtest rejects malformed or unauthorized fields"
		)
	end

	expectEqual(TowerDefenseRequest.acceptsNoPayload(nil), true, "tower wave accepts omitted payload")
	expectEqual(TowerDefenseRequest.acceptsNoPayload({}), true, "tower wave accepts an empty payload")
	expectEqual(TowerDefenseRequest.acceptsNoPayload(1), false, "tower wave rejects wrong payload type")
	expectEqual(
		TowerDefenseRequest.acceptsNoPayload({ wave = 2 }),
		false,
		"tower wave rejects a client-selected wave"
	)
	expectEqual(
		TowerDefenseRequest.acceptsNoPayload({ wave = 1.5 }),
		false,
		"tower wave rejects a fractional client-selected wave"
	)
	expectEqual(
		TowerDefenseRequest.acceptsNoPayload({ wave = math.huge }),
		false,
		"tower wave rejects a non-finite client-selected wave"
	)

	local loadout = TowerDefenseRequest.parseLoadout({
		unitIds = { "unit_scout", "unit_guard" },
	}, 4)
	expectEqual(loadout ~= nil and #loadout.unitIds, 2, "tower loadout accepts a bounded dense array")
	expectEqual(
		loadout ~= nil and loadout.unitIds[2],
		"unit_guard",
		"tower loadout preserves declared unit order"
	)
	do
		local duplicateLoadout = TowerDefenseRequest.parseLoadout({
			unitIds = { "unit_scout", "unit_scout" },
		}, 2)
		expectEqual(
			duplicateLoadout ~= nil
				and #duplicateLoadout.unitIds == 2
				and duplicateLoadout.unitIds[1] == "unit_scout"
				and duplicateLoadout.unitIds[2] == "unit_scout",
			true,
			"tower loadout accepts separate equipped copies of one owned unit"
		)
	end
	local keyedUnitIds: any = { "unit_scout" }
	keyedUnitIds.metadata = true
	for _, invalidLoadoutPayload in
		{
			{},
			{ unitIds = "unit_scout" },
			{ unitIds = { "" } },
			{ unitIds = { "unit_scout", "unit_guard", "unit_mage" } },
			{ unitIds = { [2] = "unit_scout" } },
			{ unitIds = keyedUnitIds },
			{ unitIds = { "unit_scout" }, selectedByClient = true },
		}
	do
		expectEqual(
			TowerDefenseRequest.parseLoadout(invalidLoadoutPayload, 2),
			nil,
			"tower loadout rejects malformed, oversized, or undeclared data"
		)
	end
end

do
	local grid: any = {
		columns = 3,
		rows = 2,
		cells = {},
	}
	local paintedKeys: { [string]: boolean } = {}
	PaintBrushes.applyArea(grid, PaintBrushes.find("build_blocked"), 1, 1, 3, paintedKeys)
	expectEqual(grid.cells["1:1"].buildPolicy, "Blocked", "paint brush mutates the selected cell")
	expectEqual(grid.cells["2:2"].buildPolicy, "Blocked", "paint brush covers its bounded area")
	expectEqual(grid.cells["3:1"], nil, "paint brush clamps at the grid edge")

	PaintBrushes.applyArea(grid, PaintBrushes.find(PaintBrushes.RESET_ID), 1, 1, 3, paintedKeys)
	expectEqual(
		grid.cells["1:1"].buildPolicy,
		"Blocked",
		"painted-key tracking prevents repeated drag mutations"
	)
	PaintBrushes.applyArea(grid, PaintBrushes.find(PaintBrushes.RESET_ID), 1, 1, 1, {})
	expectEqual(grid.cells["1:1"], nil, "reset brush removes an empty authored override")

	grid.cells["3:2"] = { buildPolicy = "Blocked" }
	PaintBrushes.applyArea(grid, PaintBrushes.find("role_AutoPlace"), 3, 2, 1, {})
	expectEqual(grid.cells["3:2"].roles.AutoPlace, true, "role brush toggles the requested role")
	expectEqual(grid.cells["3:2"].buildPolicy, "Allowed", "auto-place role preserves its compatibility rule")
	PaintBrushes.applyArea(grid, PaintBrushes.find("role_EnemySpawn"), 3, 2, 1, {})
	expectEqual(
		grid.cells["3:2"].roles.AutoPlace,
		nil,
		"enabling a primary role clears an incompatible primary role"
	)
	expectEqual(grid.cells["3:2"].roles.EnemySpawn, true, "the newly painted primary role remains")
	expectEqual(
		grid.cells["3:2"].buildPolicy,
		"Blocked",
		"enabling an enemy endpoint visibly enforces its placement rule"
	)
	PaintBrushes.applyArea(grid, PaintBrushes.find("role_EnemySpawn"), 3, 2, 1, {})
	expectEqual(grid.cells["3:2"].roles, nil, "disabling the last optional role removes dead state")
	expectEqual(
		grid.cells["3:2"].buildPolicy,
		"Blocked",
		"disabling a role does not silently rewrite another cell property"
	)
	grid.cells["2:1"] = { buildPolicy = "Allowed" }
	PaintBrushes.applyArea(grid, PaintBrushes.find("terrain_ground"), 2, 1, 1, {})
	expectEqual(
		grid.cells["2:1"].buildPolicy,
		"Allowed",
		"surface painting preserves the independent tower-placement layer"
	)
	grid.cells["1:2"] = {
		terrainId = "void",
		buildPolicy = "Blocked",
		roles = { Hazard = true },
	}
	PaintBrushes.applyArea(grid, PaintBrushes.find(PaintBrushes.eraseId("Build")), 1, 2, 1, {})
	expectEqual(grid.cells["1:2"].buildPolicy, nil, "Erase restores only the active property")
	expectEqual(grid.cells["1:2"].terrainId, "void", "property Erase preserves Surface")
	expectEqual(grid.cells["1:2"].roles.Hazard, true, "property Erase preserves optional roles")
	expectEqual(
		PaintBrushes.find("terrain_ground").layer,
		"Terrain",
		"surface brushes declare their visualization layer"
	)
	expectEqual(
		PaintBrushes.layerLabel(PaintBrushes.find("build_allowed").layer),
		"Tower placement",
		"tower brushes expose an unambiguous layer label"
	)
	expectEqual(
		PaintBrushes.find("unknown-brush").id,
		PaintBrushes.RESET_ID,
		"unknown brush IDs fail safely to reset"
	)
end

do
	local update, parseError = StageSettings.parse({
		name = "Forest Pass",
		waveSetId = "wave_forest",
		themeId = "forest",
		columns = "32.9",
		rows = "27.4",
		cellSize = "4",
	})
	expectEqual(parseError, nil, "valid stage settings parse without an error")
	expectEqual(update and update.columns, 32, "stage width floors to a whole cell")
	expectEqual(update and update.rows, 27, "stage height floors to a whole cell")

	local invalidUpdate, invalidError = StageSettings.parse({
		name = "",
		waveSetId = "default",
		themeId = "default",
		columns = "513",
		rows = "27",
		cellSize = "4",
	})
	expectEqual(invalidUpdate, nil, "out-of-range stage settings are rejected")
	expectEqual(invalidError, StageSettings.INVALID_GRID_MESSAGE, "invalid stage settings explain limits")

	local definition: any = {
		name = "Original",
		waveSetId = "old_wave",
		themeId = "old_theme",
		grid = {
			columns = 4,
			rows = 3,
			cellSize = 2,
			cells = {
				["1:1"] = { metadata = { keep = true } },
				["4:3"] = { buildPolicy = "Blocked" },
				malformed = { metadata = { unknown = true } },
			},
		},
	}
	expectEqual(
		StageSettings.countTruncated(definition.grid, 2, 2),
		2,
		"grid shrink reports out-of-bounds and malformed overrides"
	)
	local blankNameUpdate = StageSettings.parse({
		name = "",
		waveSetId = "new_wave",
		themeId = "new_theme",
		columns = "2",
		rows = "2",
		cellSize = "3",
	})
	StageSettings.apply(definition, blankNameUpdate :: any)
	expectEqual(definition.name, "Original", "blank stage name preserves the existing name")
	expectEqual(definition.waveSetId, "new_wave", "stage settings update catalog references")
	expectEqual(definition.grid.cells["1:1"].metadata.keep, true, "grid shrink preserves in-bounds data")
	expectEqual(definition.grid.cells["4:3"], nil, "grid shrink removes out-of-bounds data")
	expectEqual(definition.grid.cells.malformed, nil, "grid shrink removes malformed cell keys")
	local pickerRejected, pickerMessage = StageSettings.parse({
		name = "Level",
		waveSetId = "missing_set",
		themeId = "default",
		columns = "4",
		rows = "4",
		cellSize = "4",
	}, { default = true })
	expectEqual(pickerRejected, nil, "stage settings reject a wave set the project does not define")
	expectEqual(
		type(pickerMessage) == "string" and string.find(pickerMessage, "missing_set", 1, true) ~= nil,
		true,
		"unknown wave set rejection names the missing set"
	)
	local pickerAccepted = StageSettings.parse({
		name = "Level",
		waveSetId = "default",
		themeId = "default",
		columns = "4",
		rows = "4",
		cellSize = "4",
	}, { default = true })
	expectEqual(pickerAccepted ~= nil, true, "stage settings accept an authored wave set")
end

-- Wave Designer model: pure enemy-type and wave-set mutations with guards.
do
	local WavesModel = require("../src/plugins/Stagewright/Waves/Model")
	local designerGuid = 0
	local designerProject = StageStarterProject.build(1, function(prefix: string): string
		designerGuid += 1
		return `{prefix}_wave_designer_{designerGuid}`
	end, "stage_wave_designer", "stage_group_wave_designer")

	expectEqual(
		WavesModel.sortedWaveSetIds(designerProject)[1],
		"default",
		"wave designer lists the seeded default set"
	)
	expectEqual(
		table.find(WavesModel.sortedEnemyTypeIds(designerProject), "forest_grunt") ~= nil,
		true,
		"wave designer lists the seeded roster"
	)

	local parsedEnemy, enemyParseError = WavesModel.parseEnemyType({
		name = "Ember Imp",
		tags = "Ground, Fast",
		health = "60",
		speed = "9",
		reward = "14",
		baseDamage = "1",
		modelId = "forest_runner",
		renderScale = "1.1",
	})
	expectEqual(enemyParseError, nil, "valid enemy type input parses")
	expectEqual(
		parsedEnemy ~= nil and parsedEnemy.tags[2] == "Fast" and parsedEnemy.health == 60,
		true,
		"enemy type parsing splits tags and converts stats"
	)
	local normalizedTagEnemy = WavesModel.parseEnemyType({
		name = "Case-safe Enemy",
		tags = "ground, FLYING, spooky_custom",
		health = "60",
		speed = "9",
		reward = "14",
		baseDamage = "1",
		modelId = "forest_runner",
		renderScale = "1.1",
	})
	expectEqual(
		normalizedTagEnemy ~= nil
			and normalizedTagEnemy.tags[1] == "Ground"
			and normalizedTagEnemy.tags[2] == "Flying"
			and normalizedTagEnemy.tags[3] == "spooky_custom",
		true,
		"enemy type parsing canonicalizes known tags without rewriting custom tags"
	)
	local invalidEnemy, invalidEnemyError = WavesModel.parseEnemyType({
		name = "Broken",
		tags = "Ground",
		health = "0",
		speed = "7",
		reward = "10",
		baseDamage = "1",
		modelId = "",
		renderScale = "1",
	})
	expectEqual(
		invalidEnemy == nil and type(invalidEnemyError) == "string",
		true,
		"out-of-range enemy stats are rejected with the schema message"
	)

	local createdEnemyId = WavesModel.createEnemyType(designerProject, "ember_imp")
	expectEqual(createdEnemyId, "ember_imp", "new enemy types are created with a sanitized ID")
	local duplicateEnemyId, duplicateEnemyError = WavesModel.createEnemyType(designerProject, "ember_imp")
	expectEqual(
		duplicateEnemyId == nil and type(duplicateEnemyError) == "string",
		true,
		"duplicate enemy type IDs are rejected"
	)
	local badEnemyId = WavesModel.createEnemyType(designerProject, "Bad Name!")
	expectEqual(badEnemyId, nil, "enemy type IDs must be lowercase identifiers")
	expectEqual(
		parsedEnemy ~= nil and (WavesModel.applyEnemyType(designerProject, "ember_imp", parsedEnemy)),
		true,
		"parsed enemy updates apply to the roster"
	)
	expectEqual(
		designerProject.enemyTypes.ember_imp.name == "Ember Imp"
			and designerProject.enemyTypes.ember_imp.modelId == "forest_runner",
		true,
		"applied enemy updates persist stats and model binding"
	)

	local referencedDelete, referencedDeleteError =
		WavesModel.deleteEnemyType(designerProject, "forest_grunt")
	expectEqual(
		referencedDelete == false and type(referencedDeleteError) == "string",
		true,
		"enemy types referenced by wave entries cannot be deleted"
	)
	expectEqual(
		(WavesModel.deleteEnemyType(designerProject, "ember_imp")),
		true,
		"unreferenced enemy types delete cleanly"
	)

	local copiedSetId = WavesModel.createWaveSet(designerProject, "hard_mode", "default")
	expectEqual(copiedSetId, "hard_mode", "wave sets can be created as copies of an existing set")
	expectEqual(
		#designerProject.waveSets.hard_mode.waves,
		#designerProject.waveSets.default.waves,
		"copied wave sets duplicate every wave"
	)
	designerProject.waveSets.hard_mode.waves[1].entries[1].count = 999
	expectEqual(
		designerProject.waveSets.default.waves[1].entries[1].count ~= 999,
		true,
		"copied wave sets are deep copies, not aliases"
	)
	designerProject.waveSets.hard_mode.waves[1].entries[1].count = 8
	local defaultDelete, defaultDeleteError = WavesModel.deleteWaveSet(designerProject, "default")
	expectEqual(
		defaultDelete == false and type(defaultDeleteError) == "string",
		true,
		"the default wave set cannot be deleted"
	)
	designerProject.stages.stage_wave_designer.waveSetId = "hard_mode"
	local referencedSetDelete = WavesModel.deleteWaveSet(designerProject, "hard_mode")
	expectEqual(referencedSetDelete, false, "wave sets referenced by a level cannot be deleted")
	designerProject.stages.stage_wave_designer.waveSetId = "default"
	expectEqual(
		(WavesModel.deleteWaveSet(designerProject, "hard_mode")),
		true,
		"unreferenced wave sets delete cleanly"
	)

	local editSetId = WavesModel.createWaveSet(designerProject, "edit_lab", nil)
	expectEqual(editSetId, "edit_lab", "wave sets can start from the starter wave template")
	expectEqual((WavesModel.addWave(designerProject, "edit_lab")), true, "waves append to a set")
	expectEqual(
		(WavesModel.setBossFlag(designerProject, "edit_lab", 2, true)),
		true,
		"waves can be flagged as boss waves"
	)
	expectEqual(designerProject.waveSets.edit_lab.waves[2].isBoss, true, "boss flags persist on the wave")
	expectEqual(
		(WavesModel.moveWave(designerProject, "edit_lab", 2, -1)),
		true,
		"waves reorder within their set"
	)
	expectEqual(
		designerProject.waveSets.edit_lab.waves[1].isBoss,
		true,
		"reordering carries the wave payload"
	)
	expectEqual(
		WavesModel.moveWave(designerProject, "edit_lab", 1, -1),
		false,
		"waves cannot move past the start of the set"
	)

	local enemyTypeIds = WavesModel.enemyTypeIdSet(designerProject)
	local parsedEntry, entryParseError = WavesModel.parseEntry({
		enemyTypeId = "forest_runner",
		count = "6",
		spacingSeconds = "0.4",
		startDelaySeconds = "2",
		healthScale = "1.5",
		rewardScale = "",
		speedScale = "",
	}, enemyTypeIds)
	expectEqual(entryParseError, nil, "valid wave entry input parses")
	expectEqual(
		parsedEntry ~= nil and parsedEntry.healthScale == 1.5 and parsedEntry.rewardScale == nil,
		true,
		"blank entry scales stay unset instead of defaulting to text"
	)
	local danglingEntry = WavesModel.parseEntry({
		enemyTypeId = "missing_enemy",
		count = "6",
		spacingSeconds = "0.4",
		startDelaySeconds = "0",
		healthScale = "",
		rewardScale = "",
		speedScale = "",
	}, enemyTypeIds)
	expectEqual(danglingEntry, nil, "wave entries must reference an authored enemy type")
	expectEqual(
		(WavesModel.addEntry(designerProject, "edit_lab", 1, parsedEntry)),
		true,
		"entries append to a wave"
	)
	expectEqual(
		(WavesModel.updateEntry(designerProject, "edit_lab", 1, 2, parsedEntry)),
		true,
		"entries update in place"
	)
	local overCapEntry =
		{ enemyTypeId = "forest_grunt", count = 200, spacingSeconds = 0.5, startDelaySeconds = 0 }
	expectEqual(
		(WavesModel.addEntry(designerProject, "edit_lab", 1, overCapEntry))
			and (WavesModel.addEntry(designerProject, "edit_lab", 1, overCapEntry)),
		true,
		"waves accept entries up to the spawn cap"
	)
	local cappedAdd = WavesModel.addEntry(designerProject, "edit_lab", 1, overCapEntry)
	expectEqual(cappedAdd, false, "waves reject entries beyond the runtime spawn cap")
	expectEqual(
		(WavesModel.deleteEntry(designerProject, "edit_lab", 1, 4)),
		true,
		"entries delete from a wave"
	)
	local soloWaveIndex = #designerProject.waveSets.edit_lab.waves
	local soloEntryDelete = WavesModel.deleteEntry(designerProject, "edit_lab", soloWaveIndex, 1)
	expectEqual(soloEntryDelete, false, "the final entry of a wave cannot be deleted")
	expectEqual(
		(WavesModel.deleteWave(designerProject, "edit_lab", 1)),
		true,
		"waves delete while at least one remains"
	)
	local soloWaveDelete = WavesModel.deleteWave(designerProject, "edit_lab", 1)
	expectEqual(soloWaveDelete, false, "the final wave of a set cannot be deleted")
end

expectEqual(StageSchema.AUTHORING_VERSION, 5, "Stagewright wave-authoring schema is version 5")
expectEqual(StageSchema.RUNTIME_VERSION, 3, "Stagewright runtime exports include the wave registries")

-- Stagewright wave authoring: enemy types + wave sets live at project scope,
-- migrate in from schema 4, validate strictly, and bake into the bundle.
do
	local waveGuid = 0
	local waveProject = StageStarterProject.build(2, function(prefix: string): string
		waveGuid += 1
		return `{prefix}_wave_test_{waveGuid}`
	end, "stage_wave_test", "stage_group_wave_test")

	-- v4 -> v5 migration seeds the collections and clones dangling wave set ids.
	local legacyWaveProject = serde.decode("json", StageSchema.encodeCanonical(waveProject))
	legacyWaveProject.enemyTypes = nil
	legacyWaveProject.waveSets = nil
	legacyWaveProject.schemaVersion = 4
	local danglingWaveStageId: string? = nil
	for stageId, stage in legacyWaveProject.stages do
		stage.schemaVersion = 4
		if danglingWaveStageId == nil then
			danglingWaveStageId = stageId
			stage.waveSetId = "hard_mode"
		end
	end
	local seededWaveProject = StageSchema.migrateProject(legacyWaveProject)
	expectEqual(seededWaveProject.schemaVersion, 5, "schema 4 projects migrate to the wave-authoring schema")
	expectEqual(
		type(seededWaveProject.enemyTypes) == "table"
			and seededWaveProject.enemyTypes.forest_grunt ~= nil
			and seededWaveProject.enemyTypes.grove_titan ~= nil,
		true,
		"wave migration seeds the starter enemy roster"
	)
	expectEqual(
		type(seededWaveProject.waveSets) == "table" and seededWaveProject.waveSets.default ~= nil,
		true,
		"wave migration seeds the default wave set"
	)
	expectEqual(
		seededWaveProject.waveSets.hard_mode ~= nil
			and seededWaveProject.waveSets.hard_mode.id == "hard_mode"
			and #seededWaveProject.waveSets.hard_mode.waves == #seededWaveProject.waveSets.default.waves,
		true,
		"wave migration clones the default set under formerly free-text wave set ids"
	)
	local reMigrated =
		StageSchema.migrateProject(serde.decode("json", StageSchema.encodeCanonical(seededWaveProject)))
	expectEqual(
		StageSchema.encodeCanonical(reMigrated),
		StageSchema.encodeCanonical(seededWaveProject),
		"wave migration is idempotent"
	)

	-- The seeded default wave set reproduces the legacy hardcoded wave loop exactly.
	local TowerDefenseCatalogForWaves = require("../src/shared/TowerDefenseCatalog")
	local seededDefault = StageWaveDefaults.defaultWaveSet()
	for waveIndex, legacyWave in TowerDefenseCatalogForWaves.waves do
		local seededWave = seededDefault.waves[waveIndex]
		local seededEntry = seededWave.entries[1]
		expectEqual(
			#seededWave.entries == 1
				and seededEntry.enemyTypeId == legacyWave.enemyId
				and seededEntry.count == legacyWave.count
				and seededEntry.spacingSeconds == legacyWave.spacingSeconds
				and seededEntry.healthScale == legacyWave.healthScale
				and seededEntry.rewardScale == legacyWave.rewardScale,
			true,
			`seeded default wave {waveIndex} matches the legacy catalog wave`
		)
	end
	local seededGrunt = StageWaveDefaults.enemyTypes().forest_grunt
	local legacyGrunt = TowerDefenseCatalogForWaves.enemy("forest_grunt")
	expectEqual(
		legacyGrunt ~= nil
			and seededGrunt.health == legacyGrunt.health
			and seededGrunt.speed == legacyGrunt.speed
			and seededGrunt.reward == legacyGrunt.reward
			and seededGrunt.baseDamage == legacyGrunt.baseDamage,
		true,
		"seeded forest grunt keeps the legacy catalog stats"
	)

	-- Enemy type and wave set validators.
	local enemyTypeIds: { [string]: boolean } = { forest_grunt = true }
	local badEnemy = {
		id = "bad_enemy",
		name = "",
		tags = { "Ground", "Mysterious" },
		health = 0,
		speed = 5000,
		reward = -1,
		baseDamage = 1,
		modelId = "bad_enemy",
		renderScale = 99,
		tint = { r = 2, g = 0, b = 0 },
	}
	local badEnemyCodes: { [string]: boolean } = {}
	for _, issue in StageSchema.validateEnemyType(badEnemy) do
		badEnemyCodes[issue.code] = true
	end
	expectEqual(
		badEnemyCodes.InvalidEnemyTypeName == true
			and badEnemyCodes.EnemyTypeHealth == true
			and badEnemyCodes.EnemyTypeSpeed == true
			and badEnemyCodes.EnemyTypeReward == true
			and badEnemyCodes.EnemyTypeRenderScale == true
			and badEnemyCodes.EnemyTypeTint == true,
		true,
		"enemy type validation rejects out-of-range stats"
	)
	local unknownTagIssues = StageSchema.validateEnemyType(StageWaveDefaults.enemyTypes().forest_grunt)
	expectEqual(#unknownTagIssues, 0, "seeded enemy types validate cleanly")
	local taggedEnemy = StageWaveDefaults.enemyTypes().forest_grunt
	taggedEnemy.tags = { "Ground", "Spooky" }
	local foundUnknownTagWarning = false
	for _, issue in StageSchema.validateEnemyType(taggedEnemy) do
		if issue.code == "UnknownEnemyTag" and issue.severity == "Warning" then
			foundUnknownTagWarning = true
		end
	end
	expectEqual(foundUnknownTagWarning, true, "unknown enemy tags warn without blocking export")

	local danglingEntrySet = {
		id = "broken",
		name = "Broken",
		waves = {
			{
				entries = {
					{ enemyTypeId = "missing_enemy", count = 3, spacingSeconds = 0.5, startDelaySeconds = 0 },
				},
			},
		},
	}
	local foundMissingEnemyType = false
	for _, issue in StageSchema.validateWaveSet(danglingEntrySet, enemyTypeIds) do
		if issue.code == "MissingEnemyType" then
			foundMissingEnemyType = true
		end
	end
	expectEqual(foundMissingEnemyType, true, "wave entries must reference an authored enemy type")
	local cappedSet = {
		id = "capped",
		name = "Capped",
		waves = {
			{
				entries = {
					{
						enemyTypeId = "forest_grunt",
						count = 200,
						spacingSeconds = 0.5,
						startDelaySeconds = 0,
					},
					{
						enemyTypeId = "forest_grunt",
						count = 200,
						spacingSeconds = 0.5,
						startDelaySeconds = 0,
					},
					{
						enemyTypeId = "forest_grunt",
						count = 200,
						spacingSeconds = 0.5,
						startDelaySeconds = 0,
					},
				},
			},
		},
	}
	local foundSpawnCap = false
	for _, issue in StageSchema.validateWaveSet(cappedSet, enemyTypeIds) do
		if issue.code == "WaveSpawnCap" then
			foundSpawnCap = true
		end
	end
	expectEqual(foundSpawnCap, true, "waves cannot schedule more spawns than the runtime enemy cap")
	expectEqual(#StageSchema.validateWaveSet(StageWaveDefaults.defaultWaveSet(), {
		forest_grunt = true,
		forest_runner = true,
		bark_bruiser = true,
		sky_wisp = true,
		grove_titan = true,
	}), 0, "seeded default wave set validates cleanly")

	-- Baking requires the collections and carries them into the bundle.
	local function cloneWaveProject(): any
		return serde.decode("json", StageSchema.encodeCanonical(waveProject))
	end
	local function bakeIssueCodes(project: any): { [string]: boolean }
		local codes: { [string]: boolean } = {}
		for _, issue in StageExport.bake(project).issues do
			codes[issue.code] = true
		end
		return codes
	end
	local missingRosterProject = cloneWaveProject()
	missingRosterProject.enemyTypes = nil
	missingRosterProject.waveSets = nil
	local missingRosterCodes = bakeIssueCodes(missingRosterProject)
	expectEqual(
		missingRosterCodes.MissingEnemyTypes == true and missingRosterCodes.MissingWaveSets == true,
		true,
		"baking rejects projects without the wave-authoring collections"
	)
	local missingDefaultProject = cloneWaveProject()
	missingDefaultProject.waveSets = {
		alternate = { id = "alternate", name = "Alternate", waves = StageWaveDefaults.defaultWaveSet().waves },
	}
	for _, stage in missingDefaultProject.stages do
		stage.waveSetId = "alternate"
	end
	expectEqual(
		bakeIssueCodes(missingDefaultProject).MissingDefaultWaveSet,
		true,
		"baking requires the default wave set fallback"
	)
	local danglingWaveSetProject = cloneWaveProject()
	danglingWaveSetProject.stages.stage_wave_test.waveSetId = "wave_set_missing"
	expectEqual(
		bakeIssueCodes(danglingWaveSetProject).MissingWaveSet,
		true,
		"baking rejects levels that reference a missing wave set"
	)
	local wavesBundle = assert(StageExport.bake(cloneWaveProject()).bundle, "wave project bakes a bundle")
	expectEqual(
		wavesBundle.enemyTypes.forest_grunt ~= nil
			and wavesBundle.waveSets.default ~= nil
			and #wavesBundle.enemyTypeOrder > 0
			and #wavesBundle.waveSetOrder > 0
			and wavesBundle.enemyTypeOrder[1] <= wavesBundle.enemyTypeOrder[#wavesBundle.enemyTypeOrder]
			and table.find(wavesBundle.waveSetOrder, "default") ~= nil,
		true,
		"runtime bundle carries sorted enemy type and wave set registries"
	)
	local editorOnlyProject = cloneWaveProject()
	editorOnlyProject.enemyTypes.forest_grunt.editorOnlyField = true
	editorOnlyProject.waveSets.default.waves[1].entries[1].editorOnlyField = true
	local editorOnlyBundle =
		assert(StageExport.bake(editorOnlyProject).bundle, "editor-only wave project bakes")
	expectEqual(
		editorOnlyBundle.enemyTypes.forest_grunt.editorOnlyField == nil
			and editorOnlyBundle.waveSets.default.waves[1].entries[1].editorOnlyField == nil,
		true,
		"wave projection strips undeclared authoring fields"
	)
	local cleanWavesBundle = assert(StageExport.bake(cloneWaveProject()).bundle, "clean wave project bakes")
	expectEqual(
		editorOnlyBundle.checksum,
		cleanWavesBundle.checksum,
		"unknown wave-authoring fields do not change the runtime bundle checksum"
	)
end

do
	local StagePayload = require("../src/shared/StagePayload")
	local StagePlaytestArtifact = require("../src/shared/StagePlaytestArtifact")
	expectEqual(
		StagePayload.BUNDLE_FORMAT,
		"StagewrightBundle:v1",
		"Stagewright exports declare one stable authoring/runtime bundle format"
	)
	expectEqual(
		StagePayload.BUNDLE_FORMAT_ATTRIBUTE,
		"StagewrightBundleFormat",
		"Stagewright exports use one shared bundle-format attribute"
	)
	local largePayload = string.rep("a", StagePayload.CHUNK_SIZE)
		.. string.rep("b", StagePayload.CHUNK_SIZE)
		.. string.rep("c", 121_372)
	local payloadChunks = StagePayload.split(largePayload)
	expectEqual(#payloadChunks, 3, "large Stagewright payload splits below the StringValue limit")
	expectEqual(#payloadChunks[1], 180_000, "Stagewright payload chunk uses the safe byte limit")
	local payloadManifest = StagePayload.manifest("fnv1a32-deadbeef", #payloadChunks, #largePayload)
	local oversizedManifestAccepted =
		pcall(StagePayload.manifest, "fnv1a32-deadbeef", 1, StagePayload.MAX_PAYLOAD_SIZE + 1)
	expectEqual(oversizedManifestAccepted, false, "oversized Stagewright payload manifests are rejected")
	local parsedPayloadManifest = StagePayload.parseManifest(payloadManifest)
	expectEqual(parsedPayloadManifest ~= nil, true, "Stagewright chunk manifest parses")
	expectEqual(
		parsedPayloadManifest and parsedPayloadManifest.chunkCount,
		3,
		"chunk manifest preserves count"
	)
	local joinedPayload, joinedPayloadError = StagePayload.join(payloadChunks, #payloadChunks, #largePayload)
	expectEqual(joinedPayloadError, nil, "complete Stagewright payload joins without an error")
	expectEqual(joinedPayload, largePayload, "chunked Stagewright payload round trips byte-for-byte")
	local missingPayload, missingPayloadError =
		StagePayload.join({ payloadChunks[1] }, #payloadChunks, #largePayload)
	expectEqual(missingPayload, nil, "missing Stagewright chunk is rejected")
	expectEqual(type(missingPayloadError), "string", "missing Stagewright chunk reports a diagnostic")
	local shortPayload, shortPayloadError =
		StagePayload.join(payloadChunks, #payloadChunks, #largePayload - 1)
	expectEqual(shortPayload, nil, "Stagewright payload length mismatch is rejected")
	expectEqual(type(shortPayloadError), "string", "Stagewright payload length mismatch reports a diagnostic")
	expectEqual(
		StagePayload.parseManifest("StagewrightChunked:v1:999999999:1:fnv1a32-deadbeef"),
		nil,
		"impossible Stagewright chunk count is rejected before allocation"
	)
	local checksumFixture = { label = "canonical", value = 0.48000000000000004 }
	local canonicalChecksumFixture = StageSchema.encodeCanonical(checksumFixture)
	expectEqual(
		StageSchema.checksumEncoded(canonicalChecksumFixture),
		StageSchema.checksum(checksumFixture),
		"Stagewright transport checksum hashes canonical payload bytes without reparsing numbers"
	)
	local preparedPayload = string.rep("prepared-stagewright-runtime", 20_000)
	local preparedChunks = StagePayload.split(preparedPayload)
	local chunksByName: { [string]: any } = {}
	for index, chunk in preparedChunks do
		chunksByName[StagePayload.chunkName(index)] = chunk
	end
	local preparedManifest = StagePayload.manifest("fnv1a32-playtest", #preparedChunks, #preparedPayload)
	local decodedPrepared, decodedPreparedError = StagePlaytestArtifact.decode(preparedManifest, chunksByName)
	expectEqual(decodedPreparedError, nil, "prepared playtest snapshot decodes without an error")
	expectEqual(
		decodedPrepared,
		preparedPayload,
		"prepared playtest snapshot round trips through the shared chunk format"
	)
	chunksByName[StagePayload.chunkName(2)] = nil
	local missingPreparedChunk, missingPreparedError =
		StagePlaytestArtifact.decode(preparedManifest, chunksByName)
	expectEqual(missingPreparedChunk, nil, "prepared snapshot rejects a missing runtime chunk")
	expectEqual(type(missingPreparedError), "string", "missing prepared chunks report a diagnostic")
	local generatedFixture = { checksum = "generated" }
	local preparedFixture = { checksum = "prepared" }
	local staticSelection, staticUsesPlaytest =
		StagePlaytestArtifact.selectCatalog(generatedFixture, preparedFixture, false)
	expectEqual(
		staticSelection == generatedFixture and staticUsesPlaytest == false,
		true,
		"published servers keep the generated static catalog"
	)
	local studioSelection, studioUsesPlaytest =
		StagePlaytestArtifact.selectCatalog(generatedFixture, preparedFixture, true)
	expectEqual(
		studioSelection == preparedFixture and studioUsesPlaytest == true,
		true,
		"Studio selects the prepared Stagewright catalog"
	)
end

do
	local StagePayload = require("../src/shared/StagePayload")

	local function decodeJson(encoded: string): any
		return serde.decode("json", encoded)
	end

	local function snapshotFingerprint(snapshot: any): string
		return StageSchema.encodeCanonical(snapshot)
	end

	local function directSnapshot(encoded: string): any
		return {
			containerState = "Present",
			containerClassName = "Folder",
			valueState = "Present",
			valueClassName = "StringValue",
			value = encoded,
			chunksState = "Missing",
			chunks = {},
		}
	end

	local function planWithoutMutation(snapshot: any, label: string): any
		local before = snapshotFingerprint(snapshot)
		local result = ProjectLoadPolicy.plan(snapshot, decodeJson)
		expectEqual(snapshotFingerprint(snapshot), before, `{label} preserves the complete input snapshot`)
		return result
	end

	local function expectCorrupt(snapshot: any, code: string, label: string): any
		local result = planWithoutMutation(snapshot, label)
		expectEqual(result.kind, "Corrupt", `{label} is classified as corrupt`)
		expectEqual(result.code, code, `{label} reports {code}`)
		return result
	end

	local function cloneJson(value: any): any
		return serde.decode("json", StageSchema.encodeCanonical(value))
	end

	local starterGuid = 0
	local renderableProject = StageStarterProject.build(1, function(prefix: string): string
		starterGuid += 1
		return `{prefix}_{starterGuid}`
	end, "stage_renderable", "stage_group_renderable")
	local currentProject = cloneJson(renderableProject)
	currentProject.unknownProjectField = { preserved = true }
	local currentEncoded = StageSchema.encodeCanonical(currentProject)
	local currentChecksum = StageSchema.checksum(currentProject)
	local readySnapshot = directSnapshot(currentEncoded)
	readySnapshot.workingChecksumAttribute = currentChecksum
	readySnapshot.schemaVersionAttribute = StageSchema.AUTHORING_VERSION
	local ready = planWithoutMutation(readySnapshot, "current direct payload")
	expectEqual(ready.kind, "Ready", "current authoring schema is ready without migration")
	expectEqual(ready.sourceVersion, StageSchema.AUTHORING_VERSION, "ready payload reports its source schema")
	expectEqual(ready.persistedChecksum, currentChecksum, "ready payload reports the persisted checksum")
	expectEqual(
		ready.project.unknownProjectField.preserved,
		true,
		"ready payload preserves unknown project fields"
	)
	local missingSchemaAttribute = planWithoutMutation(
		directSnapshot(currentEncoded),
		"backward-compatible store without root schema attribute"
	)
	expectEqual(
		missingSchemaAttribute.kind,
		"Ready",
		"embedded payload schema stays authoritative when legacy root metadata is absent"
	)
	local mismatchedSchemaAttribute = directSnapshot(currentEncoded)
	mismatchedSchemaAttribute.schemaVersionAttribute = StageSchema.AUTHORING_VERSION - 1
	expectCorrupt(mismatchedSchemaAttribute, "SchemaVersionMismatch", "root schema attribute mismatch")
	local invalidSchemaAttribute = directSnapshot(currentEncoded)
	invalidSchemaAttribute.schemaVersionAttribute = "three"
	expectCorrupt(invalidSchemaAttribute, "InvalidSchemaAttribute", "invalid root schema attribute")
	local renderableReady = planWithoutMutation(
		directSnapshot(StageSchema.encodeCanonical(renderableProject)),
		"renderable current project"
	)
	expectEqual(renderableReady.kind, "Ready", "complete current project shape is ready")
	local repositoryProjectReady = planWithoutMutation(
		directSnapshot(fs.readFile("stage-data/stagewright-project.json")),
		"repository Stagewright project"
	)
	expectEqual(
		repositoryProjectReady.kind,
		"Ready",
		"repository Stagewright authoring data satisfies the safe editor shape"
	)
	local missingMapRegistry = cloneJson(renderableProject)
	missingMapRegistry.maps = nil
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(missingMapRegistry)),
		"InvalidProjectShape",
		"current Map-first project without a Map registry"
	)
	local danglingMapReference = cloneJson(renderableProject)
	danglingMapReference.stages[danglingMapReference.startingStageId].mapId = "map_missing"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(danglingMapReference)),
		"InvalidProjectShape",
		"current Level that references a missing Map"
	)
	local malformedMapArtwork = cloneJson(renderableProject)
	local malformedMapId = malformedMapArtwork.stages[malformedMapArtwork.startingStageId].mapId
	malformedMapArtwork.maps[malformedMapId].backdropImageId = 110986082479051
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedMapArtwork)),
		"InvalidProjectShape",
		"current Map with a numeric backdrop ID instead of the persisted string contract"
	)
	local sharedStageAcrossMaps = cloneJson(renderableProject)
	sharedStageAcrossMaps.maps.map_second = {
		id = "map_second",
		name = "Map 2",
		displayOrder = 2,
		backdropImageId = "",
		metadata = {},
	}
	local originalLevel = sharedStageAcrossMaps.stages[sharedStageAcrossMaps.startingStageId]
	local secondLevel = cloneJson(originalLevel)
	secondLevel.id = "level_second_map"
	secondLevel.mapId = "map_second"
	secondLevel.levelNumber = 2
	secondLevel.displayOrder = 2
	sharedStageAcrossMaps.stages[secondLevel.id] = secondLevel
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(sharedStageAcrossMaps)),
		"InvalidProjectShape",
		"one Stage group split across two Maps"
	)
	local orphanMapProject = cloneJson(renderableProject)
	orphanMapProject.maps.map_orphan = {
		id = "map_orphan",
		name = "Orphan Map",
		displayOrder = 2,
		backdropImageId = "",
		metadata = { preservedUnknown = true },
	}
	local orphanMapResult = expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(orphanMapProject)),
		"InvalidProjectShape",
		"current Map without a Stage or Level"
	)
	expectEqual(
		type(orphanMapResult.message) == "string"
			and string.find(
					orphanMapResult.message,
					"Map map_orphan must contain at least one Level",
					1,
					true
				)
				~= nil,
		true,
		"orphan Map load rejection identifies the unsafe Map clearly"
	)

	local malformedStageMap = {
		schemaVersion = StageSchema.AUTHORING_VERSION,
		startingStageId = "bad",
		stages = { bad = "not a stage" },
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedStageMap)),
		"InvalidProjectShape",
		"current project with a non-table stage"
	)
	local malformedProjectMetadata = cloneJson(renderableProject)
	malformedProjectMetadata.metadata = "not metadata"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedProjectMetadata)),
		"InvalidProjectShape",
		"current project with non-table root metadata"
	)
	local malformedModifier = cloneJson(renderableProject)
	malformedModifier.stages[malformedModifier.startingStageId].modifierIds = { "double_health", 42 }
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedModifier)),
		"InvalidProjectShape",
		"current project with a non-string modifier ID"
	)
	local mappedModifiers = cloneJson(renderableProject)
	mappedModifiers.stages[mappedModifiers.startingStageId].modifierIds = { primary = "double_health" }
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(mappedModifiers)),
		"InvalidProjectShape",
		"current project with a mapped modifier collection"
	)
	local malformedUnlockAmount = cloneJson(renderableProject)
	malformedUnlockAmount.stages[malformedUnlockAmount.startingStageId].unlockRequirements = {
		{ kind = "CurrencyAtLeast", currencyId = "coins", amount = "many" },
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedUnlockAmount)),
		"InvalidProjectShape",
		"current project with a non-numeric currency unlock amount"
	)
	local unknownUnlockKind = cloneJson(renderableProject)
	unknownUnlockKind.stages[unknownUnlockKind.startingStageId].unlockRequirements = {
		{ kind = "AlwaysUnlocked" },
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(unknownUnlockKind)),
		"InvalidProjectShape",
		"current project with an unknown unlock requirement kind"
	)
	local mappedUnlockRequirements = cloneJson(renderableProject)
	mappedUnlockRequirements.stages[mappedUnlockRequirements.startingStageId].unlockRequirements = {
		gate = { kind = "StageUnlocked", stageId = renderableProject.startingStageId },
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(mappedUnlockRequirements)),
		"InvalidProjectShape",
		"current project with a mapped unlock requirement collection"
	)
	local missingGrid = serde.decode("json", StageSchema.encodeCanonical(renderableProject))
	missingGrid.stages[missingGrid.startingStageId].grid = nil
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(missingGrid)),
		"InvalidProjectShape",
		"current project with a missing grid"
	)
	local malformedGraph = serde.decode("json", StageSchema.encodeCanonical(renderableProject))
	malformedGraph.stages[malformedGraph.startingStageId].pathGraphs = { bad = "not a graph" }
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedGraph)),
		"InvalidProjectShape",
		"current project with a malformed graph"
	)
	local missingEnemyRoster = cloneJson(renderableProject)
	missingEnemyRoster.enemyTypes = nil
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(missingEnemyRoster)),
		"InvalidProjectShape",
		"current project without an enemy type registry"
	)
	local malformedEnemyStat = cloneJson(renderableProject)
	malformedEnemyStat.enemyTypes.forest_grunt.health = "many"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedEnemyStat)),
		"InvalidProjectShape",
		"current project with a non-numeric enemy stat"
	)
	local missingDefaultWaveSet = cloneJson(renderableProject)
	missingDefaultWaveSet.waveSets = {}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(missingDefaultWaveSet)),
		"InvalidProjectShape",
		"current project without the default wave set"
	)
	local danglingWaveSetReference = cloneJson(renderableProject)
	danglingWaveSetReference.stages[danglingWaveSetReference.startingStageId].waveSetId = "wave_set_missing"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(danglingWaveSetReference)),
		"InvalidProjectShape",
		"current Level that references a missing wave set"
	)
	local danglingWaveEntry = cloneJson(renderableProject)
	danglingWaveEntry.waveSets.default.waves[1].entries[1].enemyTypeId = "enemy_missing"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(danglingWaveEntry)),
		"InvalidProjectShape",
		"current wave entry that references a missing enemy type"
	)

	-- ProjectStore.createStage clones an existing definition and deleteStage preserves the final one,
	-- so persisted editable projects must uphold the same nonempty-stage invariant.
	local emptyCurrentProject = {
		schemaVersion = StageSchema.AUTHORING_VERSION,
		startingStageId = "",
		stages = {},
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(emptyCurrentProject)),
		"InvalidProjectShape",
		"current project without a source stage"
	)
	local danglingStartingStage = cloneJson(renderableProject)
	danglingStartingStage.startingStageId = "stage_missing"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(danglingStartingStage)),
		"InvalidProjectShape",
		"current project with a dangling starting stage"
	)

	local malformedDefaultRoles = cloneJson(renderableProject)
	malformedDefaultRoles.stages[malformedDefaultRoles.startingStageId].grid.defaultCell.roles = "EnemySpawn"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedDefaultRoles)),
		"InvalidProjectShape",
		"current project with non-table default cell roles"
	)
	local malformedDefaultMetadata = cloneJson(renderableProject)
	malformedDefaultMetadata.stages[malformedDefaultMetadata.startingStageId].grid.defaultCell.metadata =
		"not metadata"
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(malformedDefaultMetadata)),
		"InvalidProjectShape",
		"current project with non-table default cell metadata"
	)

	local function firstValue(values: any): any
		for _, value in values do
			return value
		end
		error("expected a populated fixture map")
	end

	local hugeCoordinate = cloneJson(renderableProject)
	local hugeStage = hugeCoordinate.stages[hugeCoordinate.startingStageId]
	firstValue(firstValue(hugeStage.pathGraphs).nodes).position.x = 1e200
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(hugeCoordinate)),
		"InvalidProjectShape",
		"current project with a finite but unsafe graph coordinate"
	)
	local mappedNodeTags = cloneJson(renderableProject)
	local mappedTagsStage = mappedNodeTags.stages[mappedNodeTags.startingStageId]
	firstValue(firstValue(mappedTagsStage.pathGraphs).nodes).tags = { role = "Spawn" }
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(mappedNodeTags)),
		"InvalidProjectShape",
		"current project with a mapped node tag collection"
	)
	local mappedLaneOffsets = cloneJson(renderableProject)
	local mappedOffsetsStage = mappedLaneOffsets.stages[mappedLaneOffsets.startingStageId]
	firstValue(firstValue(mappedOffsetsStage.pathGraphs).laneProfiles).offsets = { center = 0 }
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(mappedLaneOffsets)),
		"InvalidProjectShape",
		"current project with a mapped lane offset collection"
	)
	local unsafeRouteRadius = cloneJson(renderableProject)
	local unsafeRadiusStage = unsafeRouteRadius.stages[unsafeRouteRadius.startingStageId]
	firstValue(firstValue(unsafeRadiusStage.pathGraphs).laneProfiles).clearanceRadius = unsafeRadiusStage.grid.cellSize
		* 65
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(unsafeRouteRadius)),
		"InvalidProjectShape",
		"current project with a route mask radius too large for its grid cells"
	)

	local function projectWithPredicate(predicate: any): any
		local value = cloneJson(renderableProject)
		local stage = value.stages[value.startingStageId]
		firstValue(firstValue(stage.pathGraphs).edges).predicates = { predicate }
		return value
	end
	local mappedPredicates = cloneJson(renderableProject)
	local mappedPredicateStage = mappedPredicates.stages[mappedPredicates.startingStageId]
	firstValue(firstValue(mappedPredicateStage.pathGraphs).edges).predicates = {
		rule = { kind = "WaveRange", minimum = 1, maximum = 10 },
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(mappedPredicates)),
		"InvalidProjectShape",
		"current project with a mapped predicate collection"
	)

	local malformedPredicateCases: { any } = {
		{ predicate = { kind = "WaveRange", minimum = "5" }, label = "string wave minimum" },
		{ predicate = { kind = "WaveRange", maximum = "10" }, label = "string wave maximum" },
		{
			predicate = { kind = "StageFlagEquals", key = 7, value = true },
			label = "non-string stage flag key",
		},
		{
			predicate = { kind = "StageFlagEquals", key = "boss", value = "true" },
			label = "non-boolean stage flag value",
		},
		{ predicate = { kind = "EnemyTag", tag = 7 }, label = "non-string enemy tag" },
		{
			predicate = { kind = "VisitCountBelow", nodeId = 7, maximum = 3 },
			label = "non-string visit node ID",
		},
		{
			predicate = { kind = "VisitCountBelow", nodeId = "spawn", maximum = "3" },
			label = "non-numeric visit maximum",
		},
		{ predicate = { kind = "StageUnlocked", stageId = 7 }, label = "non-string stage ID" },
		{
			predicate = { kind = "UpgradeLevelAtLeast", upgradeId = 7, level = 4 },
			label = "non-string upgrade ID",
		},
		{
			predicate = { kind = "UpgradeLevelAtLeast", upgradeId = "range", level = "4" },
			label = "non-numeric upgrade level",
		},
		{
			predicate = { kind = "CurrencyAtLeast", currencyId = 7, amount = 250 },
			label = "non-string currency ID",
		},
		{
			predicate = { kind = "CurrencyAtLeast", currencyId = "coins", amount = "250" },
			label = "non-numeric currency amount",
		},
	}
	for _, case in malformedPredicateCases do
		expectCorrupt(
			directSnapshot(StageSchema.encodeCanonical(projectWithPredicate(case.predicate))),
			"InvalidProjectShape",
			case.label
		)
	end

	local missingContainer = directSnapshot("")
	missingContainer.containerState = "Missing"
	missingContainer.containerClassName = nil
	missingContainer.valueState = "Missing"
	missingContainer.valueClassName = nil
	missingContainer.value = nil
	local initialize = planWithoutMutation(missingContainer, "missing project container")
	expectEqual(initialize.kind, "Initialize", "only a missing project container initializes new storage")

	local missingPayload = directSnapshot(currentEncoded)
	missingPayload.valueState = "Missing"
	missingPayload.valueClassName = nil
	missingPayload.value = nil
	expectCorrupt(missingPayload, "MissingPayload", "missing payload value")
	expectCorrupt(directSnapshot(""), "EmptyPayload", "empty payload value")

	local invalidContainer = directSnapshot(currentEncoded)
	invalidContainer.containerState = "Invalid"
	invalidContainer.containerClassName = "Model"
	expectCorrupt(invalidContainer, "InvalidContainer", "wrong-class project container")

	local invalidValue = directSnapshot(currentEncoded)
	invalidValue.valueState = "Invalid"
	invalidValue.valueClassName = "Folder"
	expectCorrupt(invalidValue, "InvalidPayloadValue", "wrong-class payload value")

	expectCorrupt(directSnapshot("{not-json"), "InvalidJson", "malformed raw JSON")
	expectCorrupt(directSnapshot("[]"), "InvalidProjectShape", "raw JSON without a stages map")

	for _, case in
		{
			{ value = "three", label = "string schema version" },
			{ value = -1, label = "negative schema version" },
			{ value = 1.5, label = "fractional schema version" },
		}
	do
		local encoded = StageSchema.encodeCanonical({ schemaVersion = case.value, stages = {} })
		expectCorrupt(directSnapshot(encoded), "InvalidSchemaVersion", case.label)
	end

	local nanSchema = ProjectLoadPolicy.planEncoded("ignored", nil, function(_encoded: string): any
		return { schemaVersion = 0 / 0, stages = {} }
	end)
	expectEqual(nanSchema.kind, "Corrupt", "non-finite schema version is corrupt")
	expectEqual(nanSchema.code, "InvalidSchemaVersion", "non-finite schema version reports its cause")

	local futureProject = {
		schemaVersion = StageSchema.AUTHORING_VERSION + 1,
		startingStageId = "",
		stages = {},
	}
	local future = planWithoutMutation(
		directSnapshot(StageSchema.encodeCanonical(futureProject)),
		"future authoring schema"
	)
	expectEqual(future.kind, "UnsupportedFutureVersion", "future schema is preserved without migration")
	expectEqual(
		future.foundVersion,
		StageSchema.AUTHORING_VERSION + 1,
		"future schema reports the found version"
	)
	expectEqual(
		future.supportedVersion,
		StageSchema.AUTHORING_VERSION,
		"future schema reports the supported version"
	)

	local unversionedProject = cloneJson(renderableProject)
	unversionedProject.schemaVersion = nil
	unversionedProject.unknownRoot = "keep"
	local unversioned = planWithoutMutation(
		directSnapshot(StageSchema.encodeCanonical(unversionedProject)),
		"unversioned legacy project"
	)
	expectEqual(unversioned.kind, "LegacyMigratedInMemory", "unversioned project migrates in memory")
	expectEqual(unversioned.sourceVersion, 0, "unversioned project reports schema zero")
	expectEqual(unversioned.project.unknownRoot, "keep", "unversioned migration preserves unknown fields")

	for _, version in { 0, 2, 3 } do
		local legacyProjectForVersion = cloneJson(renderableProject)
		legacyProjectForVersion.schemaVersion = version
		local legacy = planWithoutMutation(
			directSnapshot(StageSchema.encodeCanonical(legacyProjectForVersion)),
			`schema {version} legacy project`
		)
		expectEqual(legacy.kind, "LegacyMigratedInMemory", `schema {version} migrates in memory`)
		expectEqual(legacy.sourceVersion, version, `schema {version} retains its source version`)
		expectEqual(
			legacy.project.schemaVersion,
			StageSchema.AUTHORING_VERSION,
			`schema {version} reaches the current authoring schema`
		)
	end

	local legacyProject = {
		schemaVersion = 1,
		startingStageId = "legacy",
		unknownRoot = { preserved = "root" },
		stages = {
			legacy = {
				id = "legacy",
				name = "Legacy",
				waveSetId = "default",
				themeId = "default",
				displayOrder = 1,
				unknownStage = { preserved = "stage" },
				grid = {
					columns = 1,
					rows = 1,
					cellSize = 4,
					cells = {},
					unknownGrid = { preserved = "grid" },
				},
				pathGraphs = {},
			},
		},
	}
	local migratedLegacy = planWithoutMutation(
		directSnapshot(StageSchema.encodeCanonical(legacyProject)),
		"schema one legacy project"
	)
	expectEqual(migratedLegacy.kind, "LegacyMigratedInMemory", "schema one project migrates in memory")
	expectEqual(
		migratedLegacy.project.unknownRoot.preserved,
		"root",
		"legacy migration preserves unknown root data"
	)
	expectEqual(
		migratedLegacy.project.stages.legacy.unknownStage.preserved,
		"stage",
		"legacy migration preserves unknown stage data"
	)
	expectEqual(
		migratedLegacy.project.stages.legacy.grid.unknownGrid.preserved,
		"grid",
		"legacy migration preserves unknown nested data"
	)

	local nestedMigrationFailure = {
		schemaVersion = 1,
		startingStageId = "broken",
		stages = {
			broken = {
				id = "broken",
				displayOrder = 1,
				pathGraphs = {},
			},
		},
	}
	expectCorrupt(
		directSnapshot(StageSchema.encodeCanonical(nestedMigrationFailure)),
		"MigrationFailed",
		"nested migration failure"
	)

	local largeProject = cloneJson(renderableProject)
	largeProject.preservedBlob = string.rep("stagewright", StagePayload.CHUNK_SIZE / 5)
	local largeEncoded = StageSchema.encodeCanonical(largeProject)
	local largeChecksum = StageSchema.checksum(largeProject)
	local largeChunks = StagePayload.split(largeEncoded)
	expectEqual(#largeChunks > 1, true, "chunk policy fixture spans multiple chunks")

	local function chunkedSnapshot(storedChecksum: string?): any
		local checksum = storedChecksum or largeChecksum
		local snapshot = directSnapshot(StagePayload.manifest(checksum, #largeChunks, #largeEncoded))
		snapshot.chunksState = "Present"
		snapshot.chunksClassName = "Folder"
		snapshot.chunkCountAttribute = #largeChunks
		snapshot.payloadLengthAttribute = #largeEncoded
		snapshot.payloadChecksumAttribute = checksum
		for index = #largeChunks, 1, -1 do
			table.insert(snapshot.chunks, {
				name = StagePayload.chunkName(index),
				className = "StringValue",
				value = largeChunks[index],
			})
		end
		return snapshot
	end

	local shuffledChunks = planWithoutMutation(chunkedSnapshot(), "valid shuffled chunks")
	expectEqual(shuffledChunks.kind, "Ready", "chunk order does not affect a valid payload")
	expectEqual(
		shuffledChunks.persistedChecksum,
		largeChecksum,
		"valid shuffled chunks retain their checksum"
	)
	expectEqual(
		shuffledChunks.project.preservedBlob,
		largeProject.preservedBlob,
		"valid shuffled chunks reconstruct the exact project"
	)

	local missingChunksFolder = chunkedSnapshot()
	missingChunksFolder.chunksState = "Missing"
	missingChunksFolder.chunksClassName = nil
	missingChunksFolder.chunks = {}
	expectCorrupt(missingChunksFolder, "MissingChunks", "missing chunks folder")

	local invalidChunksFolder = chunkedSnapshot()
	invalidChunksFolder.chunksState = "Invalid"
	invalidChunksFolder.chunksClassName = "Model"
	expectCorrupt(invalidChunksFolder, "InvalidChunks", "wrong-class chunks folder")

	local missingChunk = chunkedSnapshot()
	table.remove(missingChunk.chunks, 1)
	expectCorrupt(missingChunk, "MissingChunk", "missing indexed chunk")

	local duplicateChunk = chunkedSnapshot()
	table.insert(duplicateChunk.chunks, {
		name = duplicateChunk.chunks[1].name,
		className = "StringValue",
		value = duplicateChunk.chunks[1].value,
	})
	expectCorrupt(duplicateChunk, "DuplicateChunk", "duplicate indexed chunk")

	local extraChunk = chunkedSnapshot()
	table.insert(extraChunk.chunks, {
		name = StagePayload.chunkName(#largeChunks + 1),
		className = "StringValue",
		value = "extra",
	})
	expectCorrupt(extraChunk, "UnexpectedChunk", "extra indexed chunk")

	local wrongClassChunk = chunkedSnapshot()
	wrongClassChunk.chunks[1].className = "Folder"
	expectCorrupt(wrongClassChunk, "InvalidChunkClass", "wrong-class chunk child")

	local truncatedChunk = chunkedSnapshot()
	for _, chunk in truncatedChunk.chunks do
		if chunk.name == StagePayload.chunkName(1) then
			chunk.value = string.sub(chunk.value, 1, #chunk.value - 1)
			break
		end
	end
	expectCorrupt(truncatedChunk, "InvalidChunkLength", "truncated non-final chunk")

	local wrongStoredChecksum = "fnv1a32-deadbeef"
	expectEqual(wrongStoredChecksum == largeChecksum, false, "checksum mismatch fixture differs from payload")
	expectCorrupt(
		chunkedSnapshot(wrongStoredChecksum),
		"ChecksumMismatch",
		"chunk manifest checksum mismatch"
	)

	local directChecksumMismatch = directSnapshot(currentEncoded)
	directChecksumMismatch.workingChecksumAttribute = wrongStoredChecksum
	expectCorrupt(directChecksumMismatch, "ChecksumMismatch", "direct payload checksum mismatch")

	for _, case in
		{
			{ field = "chunkCountAttribute", value = #largeChunks + 1, label = "chunk-count metadata" },
			{
				field = "payloadLengthAttribute",
				value = #largeEncoded + 1,
				label = "payload-length metadata",
			},
			{
				field = "payloadChecksumAttribute",
				value = wrongStoredChecksum,
				label = "payload-checksum metadata",
			},
		}
	do
		local metadataMismatch = chunkedSnapshot()
		metadataMismatch[case.field] = case.value
		expectCorrupt(metadataMismatch, "ChunkMetadataMismatch", case.label)
	end

	local malformedManifest =
		directSnapshot(`{StagePayload.FORMAT}:{#largeChunks + 1}:{#largeEncoded}:{largeChecksum}`)
	expectCorrupt(malformedManifest, "InvalidManifest", "malformed chunk manifest")

	local invalidWorkingChecksum = directSnapshot(currentEncoded)
	invalidWorkingChecksum.workingChecksumAttribute = 42
	expectCorrupt(invalidWorkingChecksum, "InvalidWorkingChecksum", "non-string working checksum")

	local unexpectedDirectChunks = directSnapshot(currentEncoded)
	unexpectedDirectChunks.chunksState = "Present"
	unexpectedDirectChunks.chunksClassName = "Folder"
	table.insert(unexpectedDirectChunks.chunks, {
		name = StagePayload.chunkName(1),
		className = "StringValue",
		value = "orphaned",
	})
	expectCorrupt(unexpectedDirectChunks, "UnexpectedChunks", "raw payload with orphaned chunks")
end

local normalizedCurrencies = CurrencyConfig.normalize({
	{
		id = "coins",
		name = "Coins",
		symbol = "$",
		iconAssetId = "105300168575798",
		color = { 999, -2, 20 },
		startingAmount = 5,
	},
	{ id = "coins", name = "Duplicate", symbol = "D" },
	{ id = "gems", name = "Gems", symbol = "◆", startingAmount = 10 },
	{ id = "stars", name = "Stars", symbol = "★" },
	{ id = "tokens", name = "Tokens", symbol = "T" },
	{ id = "event", name = "Event", symbol = "!" },
	{ id = "sixth", name = "Sixth", symbol = "6" },
})
expectEqual(#normalizedCurrencies, 5, "currency configuration caps authored slots at five")
expectEqual(normalizedCurrencies[1].color[1], 255, "currency color clamps high channels")
expectEqual(normalizedCurrencies[1].color[2], 0, "currency color clamps low channels")
expectEqual(normalizedCurrencies[2].id, "gems", "duplicate currency IDs are rejected")
expectEqual(normalizedCurrencies[1].iconAssetId, "105300168575798", "currency icon keeps numeric asset ID")

local configuredCurrencies = CurrencyConfig.normalize({
	{ id = "gold", name = "Gold", symbol = "G", iconAssetId = "rbxassetid://123", startingAmount = 500 },
	{ id = "crystals", name = "Crystals", symbol = "C", iconAssetId = "not-an-id", startingAmount = 10 },
})
expectEqual(configuredCurrencies[1].iconAssetId, "123", "currency icon normalizes rbxassetid prefix")
expectEqual(configuredCurrencies[2].iconAssetId, "", "invalid currency icon uses symbol fallback")
local seededBalances = CurrencyConfig.startingBalances(configuredCurrencies)
expectEqual(seededBalances.gold, 500, "fresh profiles seed the configured starting balance")
expectEqual(seededBalances.crystals, 10, "fresh profiles seed every configured currency")
local legacyCurrencyProfile = { coins = 100 }
CurrencyConfig.reconcileProfileCurrencies(legacyCurrencyProfile, configuredCurrencies, "gold", 1)
expectEqual(legacyCurrencyProfile.currencies.gold, 100, "legacy coins migrate to primary currency")
expectEqual(legacyCurrencyProfile.currencies.crystals, 10, "new currencies receive starting balance")
local savedCurrencyProfile = { coins = 42, currencies = { gold = 42, crystals = "corrupt" } }
CurrencyConfig.reconcileProfileCurrencies(savedCurrencyProfile, configuredCurrencies, "gold", 4)
expectEqual(savedCurrencyProfile.currencies.gold, 42, "saved balances are not re-granted")
expectEqual(savedCurrencyProfile.currencies.crystals, 10, "corrupt balances recover safely")
expectEqual(
	DataStoreNames.scoped("RobloxTemplate_Profile_v1", "incremental"),
	"RobloxTemplate_Profile_v1_incremental",
	"preset namespace isolates profile stores inside the shared sandbox"
)
expectEqual(
	pcall(function()
		DataStoreNames.validateNamespace("bad-preset")
	end),
	false,
	"DataStore namespaces reject unsafe characters"
)

local canClaim, streak = Calculations.dailyClaim(9, 2, 10 * 86400, 7)
expectEqual(canClaim, true, "daily can claim")
expectEqual(streak, 3, "daily increments")

local missed, resetStreak = Calculations.dailyClaim(7, 6, 10 * 86400, 7)
expectEqual(missed, true, "missed day can claim")
expectEqual(resetStreak, 1, "missed day resets")

local amount, elapsed = Calculations.offlineEarnings(0, 20 * 3600, 2, 4, 1.1)
expectEqual(elapsed, 4 * 3600, "offline cap")
expectEqual(amount, math.floor(4 * 3600 * 2 * 1.1), "offline reward")

expectEqual(
	Calculations.potionMultiplier(
		{ { multiplier = 2, expiresAt = 100 }, { multiplier = 3, expiresAt = 90 } },
		95
	),
	2,
	"strongest active potion"
)
expectEqual(Calculations.friendBonus(8, 0.1, 0.5), 0.5, "friend cap")
expectEqual(Calculations.normalizeCode(" welcome "), "WELCOME", "code normalization")
expectEqual(Calculations.normalizeCode("bad code!"), nil, "invalid code")

expectEqual(SessionLock.canClaim(nil, "job", 100, 180), true, "empty lock")
expectEqual(
	SessionLock.canClaim({ jobId = "other", placeId = 1, touchedAt = 50 }, "job", 100, 180),
	false,
	"fresh foreign lock"
)
expectEqual(
	SessionLock.canClaim({ jobId = "other", placeId = 1, touchedAt = 0 }, "job", 200, 180),
	true,
	"expired lock"
)

local migrated = MigrationCore.migrate({ schemaVersion = 0, coins = 5, unknown = "keep" }, {
	schemaVersion = 1,
	coins = 0,
	settings = { musicVolume = 0.5 },
}, 1)
expectEqual(migrated.schemaVersion, 1, "profile version migration")
expectEqual(migrated.settings.musicVolume, 0.5, "profile reconciliation")
expectEqual(migrated.unknown, "keep", "migration preserves unknown data")

local repaired = MigrationCore.migrate({ schemaVersion = 1, settings = "broken", coins = 0 / 0 }, {
	schemaVersion = 1,
	coins = 0,
	settings = { musicVolume = 0.5 },
}, 1)
expectEqual(type(repaired.settings), "table", "migration repairs invalid nested table types")
expectEqual(repaired.coins, 0, "migration repairs non-finite persisted numbers")
local futureOk = pcall(function()
	MigrationCore.migrate({ schemaVersion = 99 }, { schemaVersion = 1 }, 1)
end)
expectEqual(futureOk, false, "future profile schemas are refused instead of overwritten")
local migrationsSource = fs.readFile("src/shared/Migrations.luau")
local profileTemplateSource = fs.readFile("src/shared/ProfileTemplate.luau")
expectEqual(
	string.find(migrationsSource, "Migrations.CURRENT_VERSION = 9", 1, true) ~= nil,
	true,
	"profile schema version is current"
)
for _, dungeonMigrationMarker in { "previousVersion < 8", "selectedBossId" } do
	expectEqual(
		string.find(migrationsSource, dungeonMigrationMarker, 1, true) ~= nil,
		true,
		`dungeon profile migration includes {dungeonMigrationMarker}`
	)
end
expectEqual(
	string.find(profileTemplateSource, "schemaVersion = 9", 1, true) ~= nil
		and string.find(profileTemplateSource, "selectedBossId", 1, true) ~= nil,
	true,
	"profile template seeds the dungeon boss choice at the current version"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 9", 1, true) ~= nil
		and string.find(migrationsSource, "existingLoadoutCount", 1, true) ~= nil
		and string.find(migrationsSource, "startingLoadoutSlots", 1, true) ~= nil
		and string.find(profileTemplateSource, "unlockedLoadoutSlots", 1, true) ~= nil,
	true,
	"slot-capacity migration preserves existing equipped units and seeds new profiles"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 6", 1, true) ~= nil,
	true,
	"schema 5 profiles gain tower defense state"
)
expectEqual(
	string.find(migrationsSource, "previousVersion < 7", 1, true) ~= nil,
	true,
	"schema 6 profiles gain the rune channel mode selection"
)
expectEqual(
	string.find(migrationsSource, "ownedUnits = {}", 1, true) ~= nil,
	true,
	"tower defense migration creates owned unit storage"
)
expectEqual(
	string.find(migrationsSource, "bestWave = 0", 1, true) ~= nil,
	true,
	"tower defense migration initializes best wave"
)
for _, stageMigrationMarker in
	{ "previousVersion < 7", "selectedStageId", "stageProgress", "startingProgress.unlocked = true" }
do
	expectEqual(
		string.find(migrationsSource, stageMigrationMarker, 1, true) ~= nil,
		true,
		`stage profile migration includes {stageMigrationMarker}`
	)
end
expectEqual(
	string.find(migrationsSource, "StageCatalog.defaultStageId()", 1, true) ~= nil
		and string.find(profileTemplateSource, "StageCatalog.defaultStageId()", 1, true) ~= nil,
	true,
	"new and migrated profiles seed the exported runtime starting stage"
)
expectEqual(
	string.find(migrationsSource .. profileTemplateSource, "Config.towerDefense.startingStageId", 1, true),
	nil,
	"profile defaults do not override the exported runtime starting stage"
)

expectEqual(DataStoreKeys.profile(123), "player:123", "profile key is documented and stable")
expectEqual(DataStoreKeys.publicProfile(123), "user:123", "public profile key is documented")
expectEqual(
	DataStoreKeys.feedback(123, 456, "abc"),
	"user:123:report:456:abc",
	"feedback keys can be listed or erased by user prefix"
)

local rewardServiceSource = fs.readFile("src/server/Services/RewardService.luau")
expectEqual(
	string.find(rewardServiceSource, "profile.offline.pendingAmount", 1, true) ~= nil,
	true,
	"unclaimed offline earnings live in the saved profile"
)

local receipts = {}
expectEqual(ReceiptLedger.claim(receipts, "purchase"), true, "first receipt grants")
expectEqual(ReceiptLedger.claim(receipts, "purchase"), false, "duplicate receipt rejected")

for _, servicePath in
	{
		"src/server/Services/FeedbackService.luau",
		"src/server/Services/LeaderboardService.luau",
		"src/server/Services/ProfileService.luau",
		"src/server/Services/PublicProfileService.luau",
	}
do
	local source = fs.readFile(servicePath)
	expectEqual(
		string.find(source, "local store = DataStoreService:Get", 1, true),
		nil,
		`{servicePath} does not open DataStores while loading`
	)
end

local templateConfigSource = fs.readFile("src/shared/TemplateConfig.luau")
expectEqual(
	string.find(templateConfigSource, "useLiveDataStore", 1, true),
	nil,
	"ambiguous live DataStore switch was removed"
)
expectEqual(
	string.find(
		templateConfigSource,
		'dataStoreMode = if DesignerConfig.experienceMode == "template"',
		1,
		true
	) ~= nil,
	true,
	"persistence mode follows the generated experience kind"
)
expectEqual(
	string.find(templateConfigSource, "DataStoreNames.scoped", 1, true) ~= nil,
	true,
	"all persistent stores are isolated by preset namespace"
)
expectEqual(
	string.find(templateConfigSource, "IconAssets.ids", 1, true) ~= nil,
	true,
	"connected icons come from the shared tracked manifest"
)
do
	local optionalFiniteVec3Start = assert(
		string.find(templateConfigSource, "local function optionalFiniteVec3", 1, true),
		"TemplateConfig optional finite vec3 validator exists"
	)
	local optionalFiniteVec3End = assert(
		string.find(templateConfigSource, "local function runeNumber", optionalFiniteVec3Start, true),
		"TemplateConfig optional finite vec3 validator has a stable boundary"
	)
	local optionalFiniteVec3Source =
		string.sub(templateConfigSource, optionalFiniteVec3Start, optionalFiniteVec3End - 1)
	for _, validationMarker in
		{
			"local function optionalFiniteVec3(value: any): { number }?",
			'type(value) ~= "table"',
			'type(x) ~= "number"',
			'type(y) ~= "number"',
			'type(z) ~= "number"',
			"x ~= x",
			"y ~= y",
			"z ~= z",
			"math.abs(x) == math.huge",
			"math.abs(y) == math.huge",
			"math.abs(z) == math.huge",
			"return { x, y, z }",
		}
	do
		expectEqual(
			string.find(optionalFiniteVec3Source, validationMarker, 1, true) ~= nil,
			true,
			`TemplateConfig validates optional platform centers: {validationMarker}`
		)
	end
	expectEqual(
		string.find(
			templateConfigSource,
			"platformCenterPosition = optionalFiniteVec3(designerTowerDefense.platformCenterPosition)",
			1,
			true
		) ~= nil,
		true,
		"TemplateConfig passes through a validated optional platform center"
	)
end
local presetBuilderSource = fs.readFile("scripts/build-game-preset.ps1")
expectEqual(
	string.find(presetBuilderSource, 'experienceMode = `"playable`"', 1, true) ~= nil,
	true,
	"generated playable experiences select real persistence"
)
expectEqual(
	string.find(presetBuilderSource, '$preset -notin @("incremental", "rpg")', 1, true),
	nil,
	"preset builder accepts independently authored packs"
)
local gameDesignerSource = fs.readFile("scripts/game-designer.ps1")
expectEqual(
	string.find(gameDesignerSource, "src\\ui\\presets", 1, true) ~= nil,
	true,
	"Game Designer discovers authored preset folders"
)
local sandboxSource = fs.readFile("scripts/sandbox.ps1")
expectEqual(
	string.find(sandboxSource, '"-task", "EditPlace"', 1, true) ~= nil,
	true,
	"sandbox launcher opens the existing cloud place"
)
expectEqual(
	string.find(sandboxSource, "build-game-preset.ps1", 1, true) ~= nil,
	true,
	"sandbox launcher rebuilds the selected preset before opening"
)
expectEqual(
	string.find(sandboxSource, "experiences.config.json", 1, true) ~= nil,
	true,
	"sandbox launcher reads the two-experience config"
)
do
	local smokeGuard = string.find(sandboxSource, "if (-not $SmokeTest) {", 1, true)
	local machinePluginCheck = string.find(sandboxSource, "Get-RojoStudioPluginState", 1, true)
	expectEqual(
		smokeGuard ~= nil and machinePluginCheck ~= nil and smokeGuard < machinePluginCheck,
		true,
		"sandbox smoke validation never installs a host-specific Studio plugin"
	)
end

do
	local setupSource = fs.readFile("scripts/setup.ps1")
	local doctorSource = fs.readFile("scripts/doctor.ps1")
	local rngDefenderLauncherSource = fs.readFile("scripts/rng-defender.ps1")
	local rngDefenderAssetHelperSource = fs.readFile("scripts/rng-defender-ui-assets.ps1")
	local rojoPluginStateSource = fs.readFile("scripts/rojo-plugin-state.ps1")
	for _, pluginStateMarker in
		{
			"RojoManagedPlugin.rbxm",
			"InstalledPlugins\\13916111004",
			"HasManaged",
			"HasCreatorStore",
			"HasConflict",
			'Filter "Plugin.rbxm"',
			"Where-Object Length -gt 0",
		}
	do
		expectEqual(
			string.find(rojoPluginStateSource, pluginStateMarker, 1, true) ~= nil,
			true,
			`Rojo plugin state detects {pluginStateMarker}`
		)
	end
	for scriptName, launcherSource in
		{
			setup = setupSource,
			doctor = doctorSource,
			sandbox = sandboxSource,
			rngDefender = rngDefenderLauncherSource,
		}
	do
		expectEqual(
			string.find(launcherSource, "rojo-plugin-state.ps1", 1, true) ~= nil,
			true,
			`{scriptName} shares the one-copy Rojo plugin detector`
		)
	end
	local rngCreatorStoreBranch =
		string.find(rngDefenderLauncherSource, "if ($rojoPluginState.HasCreatorStore)", 1, true)
	local rngPluginInstall = string.find(rngDefenderLauncherSource, "& rojo plugin install", 1, true)
	expectEqual(
		rngCreatorStoreBranch ~= nil and rngPluginInstall ~= nil and rngCreatorStoreBranch < rngPluginInstall,
		true,
		"RNG Defender preserves a verified Creator Store plugin and refreshes the sole managed copy"
	)
	expectEqual(
		string.find(rngDefenderLauncherSource, "roles.PSObject.Properties", 1, true) ~= nil
			and string.find(rngDefenderLauncherSource, '"pending-upload"', 1, true) ~= nil
			and string.find(rngDefenderLauncherSource, '@("rollDice", "talentUpgrade")', 1, true) == nil,
		true,
		"RNG Defender launcher discovers pending icon uploads from manifest state"
	)
	expectEqual(
		string.find(rngDefenderAssetHelperSource, "deliverySets.PSObject.Properties", 1, true) ~= nil
			and string.find(rngDefenderAssetHelperSource, "[string]$DeliverySet", 1, true) ~= nil
			and string.find(rngDefenderAssetHelperSource, '@("rollDice", "talentUpgrade")', 1, true)
				== nil,
		true,
		"RNG Defender asset helper reads its configurable manifest delivery set"
	)
end

local experiences = serde.decode("json", fs.readFile("experiences.config.json"))
expectEqual(type(experiences.template) == "table", true, "template experience entry exists")
expectEqual(type(experiences.playerTest) == "table", true, "player-test experience entry exists")
expectEqual(
	experiences.playerTest.universeId > 0 and experiences.playerTest.placeId > 0,
	true,
	"player-test experience keeps its permanent cloud IDs"
)
expectEqual(
	type(experiences.playerTest.defaultPreset) == "string",
	true,
	"player-test default preset is configured"
)

local startSource = fs.readFile("scripts/start.ps1")
expectEqual(
	string.find(startSource, "experiences.config.json", 1, true) ~= nil,
	true,
	"template launcher reads the two-experience config"
)
expectEqual(
	string.find(startSource, '"-task", "EditPlace"', 1, true) ~= nil,
	true,
	"template launcher opens the existing template experience when configured"
)
expectEqual(
	string.find(startSource, "servePlaceIds", 1, true) ~= nil,
	true,
	"template serve project is restricted to the template place"
)
expectEqual(
	string.find(startSource, "rojo-plugin-state.ps1", 1, true) ~= nil,
	true,
	"template launcher recognizes either official Rojo installation without creating a duplicate"
)

local figmaUiSource = fs.readFile("scripts/figma-ui.ps1")
expectEqual(
	string.find(figmaUiSource, "ValidateSet", 1, true),
	nil,
	"Figma apply path accepts independently authored packs"
)
expectEqual(
	string.find(figmaUiSource, "src/ui/presets", 1, true) ~= nil,
	true,
	"Figma apply path discovers authored preset folders"
)
expectEqual(
	string.find(figmaUiSource, "figma-patch(?:", 1, true) ~= nil,
	true,
	"Figma apply path accepts both exported patch filename extensions"
)
expectEqual(
	string.find(figmaUiSource, 'Write-Host ("Workspace: {0}"', 1, true) ~= nil,
	true,
	"Figma apply path prints the selected workspace before changing authored models"
)

local dataStoreRuntimeSource = fs.readFile("src/server/Util/DataStoreRuntime.luau")
expectEqual(
	string.find(dataStoreRuntimeSource, 'if Config.studio.dataStoreMode == "mock"', 1, true) ~= nil,
	true,
	"template mock persistence applies outside Studio too"
)
expectEqual(
	string.find(dataStoreRuntimeSource, "RunService:IsStudio() and Config.studio.dataStoreMode", 1, true),
	nil,
	"mock mode no longer depends on running inside Studio"
)

local profileServiceSource = fs.readFile("src/server/Services/ProfileService.luau")
expectEqual(
	string.find(profileServiceSource, "local releasing: { [Player]: boolean }", 1, true) ~= nil,
	true,
	"profile releases track an in-flight owner"
)
expectEqual(
	string.find(profileServiceSource, "while releasing[player] do", 1, true) ~= nil,
	true,
	"overlapping shutdown releases wait instead of clearing the same lock twice"
)
expectEqual(
	string.find(profileServiceSource, "RunService:IsStudio()", 1, true) ~= nil
		and string.find(
				profileServiceSource,
				"math.max(loaded.currencies[definition.id], definition.startingAmount)",
				1,
				true
			)
			~= nil,
	true,
	"Studio playtests top up existing profiles to the configured starting currency"
)

local leaderboardSource = fs.readFile("src/server/Services/LeaderboardService.luau")
expectEqual(
	string.find(leaderboardSource, 'Name = "Coins"', 1, true),
	nil,
	"leaderstat name is not hardcoded to Coins"
)
expectEqual(
	string.find(leaderboardSource, "Config.leaderboards.metric", 1, true) ~= nil,
	true,
	"leaderstat column follows the configured metric"
)
expectEqual(
	string.find(templateConfigSource, 'metric = "Coins"', 1, true),
	nil,
	"leaderboard metric is not hardcoded to Coins"
)
expectEqual(
	string.find(templateConfigSource, "metric = configuredCurrencies[1].name", 1, true) ~= nil,
	true,
	"leaderboard metric follows the recipe primary currency"
)
expectEqual(
	string.find(templateConfigSource, 'if DesignerConfig.preset == "rpg"', 1, true),
	nil,
	"ui preset is not collapsed to two hardcoded packs"
)
expectEqual(
	string.find(templateConfigSource, '"^[a-z][a-z0-9_-]*$"', 1, true) ~= nil,
	true,
	"ui preset validates any authored pack name"
)
expectEqual(
	string.find(templateConfigSource, "preset = configuredPreset", 1, true) ~= nil,
	true,
	"ui preset passes through the validated pack name"
)

local chatSource = fs.readFile("src/client/init.client.luau") .. fs.readFile("default.project.json")
for _, legacyToken in
	{
		'GetService("Chat")',
		"LegacyChatService",
		"DefaultChatSystemChatEvents",
		"SayMessageRequest",
		"ChatVersion",
		"LoadDefaultChat",
	}
do
	expectEqual(string.find(chatSource, legacyToken, 1, true), nil, `legacy chat token: {legacyToken}`)
end
expectEqual(string.find(chatSource, "RBXSystem", 1, true) ~= nil, true, "announcements use RBXSystem")

local iconCatalogSource = fs.readFile("src/shared/IconCatalog.luau")
expectEqual(
	string.find(iconCatalogSource, 'string.find(assetId, "^rbxgameasset")', 1, true) ~= nil,
	true,
	"icon catalog preserves experience-local Asset Manager image names"
)

for _, showroomPath in
	{
		"assets/ui/ZxglyV5Showroom.rbxmx",
		"assets/ui/NotificationV2Showroom.rbxmx",
	}
do
	local showroom = fs.readFile(showroomPath)
	expectEqual(
		string.find(showroom, '<bool name="Enabled">false</bool>', 1, true) ~= nil,
		true,
		`{showroomPath} is disabled until selected`
	)
	for _, scriptClass in { "LocalScript", "ModuleScript", "Script" } do
		expectEqual(
			string.find(showroom, `<Item class="{scriptClass}"`, 1, true),
			nil,
			`{showroomPath} contains no {scriptClass}`
		)
	end
end

local bootstrap = fs.readFile("bootstrap.project.json")
expectEqual(
	string.find(bootstrap, "TemplateLoading.model.json", 1, true) ~= nil,
	true,
	"loading screen is bootstrapped from an authored StarterGui model"
)
expectEqual(
	string.find(bootstrap, "StarterSignUI.model.json", 1, true) ~= nil,
	true,
	"playable sign is bootstrapped from an authored StarterGui model"
)
if string.find(bootstrap, "ZxglyV5Showroom", 1, true) then
	expectEqual(string.find(bootstrap, "GalleryMenu", 1, true) ~= nil, true, "gallery menu is bootstrapped")
	expectEqual(
		string.find(bootstrap, "GalleryBackdrop", 1, true) ~= nil,
		true,
		"gallery backdrop is bootstrapped"
	)
else
	expectEqual(string.find(bootstrap, "GalleryMenu", 1, true), nil, "starter excludes gallery menu")
	expectEqual(string.find(bootstrap, "GalleryBackdrop", 1, true), nil, "starter excludes gallery backdrop")
end
local connectedUi = fs.readFile("src/ui/TemplateUI.model.json")
local compactConnectedUi = string.gsub(connectedUi, "%s+", "")
for _, requiredObject in
	{
		'"Name":"CurrencyHUD"',
		'"Name":"Navigation"',
		'"Name":"MoreButton"',
		'"Name":"MoreMenu"',
		'"Name":"ScreenTemplate"',
		'"Name":"ItemCardTemplate"',
		'"Name":"RewardTileTemplate"',
		'"Name":"AddCoinsButton"',
	}
do
	expectEqual(
		string.find(compactConnectedUi, requiredObject, 1, true) ~= nil,
		true,
		`connected UI includes {requiredObject}`
	)
end
for _, preset in { "incremental", "rpg" } do
	local presetUi = fs.readFile(`src/ui/presets/{preset}/TemplateUI.model.json`)
	expectEqual(
		string.find(presetUi, '"Name": "CurrencySlot05"', 1, true) ~= nil
			or string.find(presetUi, '"Name":"CurrencySlot05"', 1, true) ~= nil,
		true,
		`{preset} preset pre-authors all five configurable currency slots`
	)
	expectEqual(
		string.find(presetUi, '"Enabled": false', 1, true) ~= nil
			or string.find(presetUi, '"Enabled":false', 1, true) ~= nil,
		true,
		`{preset} preset stays isolated until selected`
	)
	local compactPresetUi = string.gsub(presetUi, "%s+", "")
	local iconCount = 0
	for _ in string.gmatch(compactPresetUi, '"Name":"Icon","ClassName":"ImageLabel"') do
		iconCount += 1
	end
	expectEqual(iconCount >= 5, true, `{preset} preset pre-authors currency ImageLabels`)
end
local incrementalPreset = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
local rpgPreset = fs.readFile("src/ui/presets/rpg/TemplateUI.model.json")
expectEqual(incrementalPreset == rpgPreset, false, "RPG and Incremental are independent visual files")
local compactIncrementalPreset = string.gsub(incrementalPreset, "%s+", "")
for _, modernObject in
	{
		'"Name":"CategoryTabs"',
		'"Name":"AllButton"',
		'"Name":"ConsumableButton"',
		'"Name":"EquipmentButton"',
		'"Name":"MiscButton"',
		'"Name":"BoostPanel"',
		'"Name":"SummaryButton"',
		'"Name":"TotalValue"',
	}
do
	expectEqual(
		string.find(compactIncrementalPreset, modernObject, 1, true) ~= nil,
		true,
		`Incremental preset physically authors {modernObject}`
	)
end
do
	local incrementalModel =
		serde.decode("json", fs.readFile("src/ui/presets/incremental/TemplateUI.model.json"))
	local function descendant(root: any, name: string): any
		if type(root) ~= "table" then
			return nil
		end
		if root.Name == name then
			return root
		end
		for _, child in root.Children or {} do
			local found = descendant(child, name)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	local function directChildByClass(root: any, className: string): any
		for _, child in root.Children or {} do
			if child.ClassName == className then
				return child
			end
		end
		return nil
	end
	local inventoryScreen = descendant(incrementalModel, "InventoryScreen")
	local currencyTray = descendant(incrementalModel, "CurrencyTray")
	local inventoryHeader = descendant(inventoryScreen, "Header")
	local inventoryTitle = descendant(inventoryScreen, "Title")
	expectEqual(
		currencyTray.Properties.Position.UDim2[1][2] == -22
			and currencyTray.Properties.Position.UDim2[2][2] == 78,
		true,
		"incremental currency tray clears the authored rune-boost chip instead of rendering behind it"
	)
	expectEqual(
		inventoryHeader.Properties.Size.UDim2[1][1] == 0
			and inventoryHeader.Properties.Size.UDim2[1][2] == 361
			and inventoryTitle.Properties.Size.UDim2[1][1] == 0
			and inventoryTitle.Properties.Size.UDim2[1][2] == 223,
		true,
		"inventory header and title retain their fixed Figma widths when the responsive modal reaches max size"
	)
	for _, buttonName in { "AllButton", "ConsumableButton", "EquipmentButton", "MiscButton" } do
		local button = descendant(inventoryScreen, buttonName)
		local stroke = directChildByClass(button, "UIStroke")
		expectEqual(
			button.Properties.BackgroundTransparency == 1 and stroke.Properties.Transparency == 1,
			true,
			`inventory category {buttonName} stays icon-driven without a generic button plate`
		)
	end
end
expectEqual(
	string.find(rpgPreset, '"Text": "MERCHANT"', 1, true) ~= nil
		or string.find(rpgPreset, '"Text":"MERCHANT"', 1, true) ~= nil,
	true,
	"RPG preset carries its own game-specific labels"
)

local loadingUi = fs.readFile("src/ui/TemplateLoading.model.json")
for _, authoredLoadingObject in
	{ '"Name": "Card"', '"Name": "Status"', '"Name": "ProgressTrack"', '"Name": "Fill"' }
do
	expectEqual(
		string.find(loadingUi, authoredLoadingObject, 1, true) ~= nil,
		true,
		`loading UI pre-authors {authoredLoadingObject}`
	)
end

local starterSignUi = fs.readFile("src/ui/StarterSignUI.model.json")
for _, authoredSignObject in { '"Name": "Header"', '"Name": "Instruction"', '"Name": "Reward"' } do
	expectEqual(
		string.find(starterSignUi, authoredSignObject, 1, true) ~= nil,
		true,
		`starter sign pre-authors {authoredSignObject}`
	)
end

local authoredVisualBinders = fs.readFile("src/ReplicatedFirst/Loading.client.luau")
	.. fs.readFile("src/starter/StarterExample.server.luau")
	.. fs.readFile("src/starter-client/StarterExample.client.luau")
	.. fs.readFile("src/starter/RuneCircle.server.luau")
	.. fs.readFile("src/starter-client/RuneCircle.client.luau")
for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
	expectEqual(
		string.find(authoredVisualBinders, forbiddenConstructor, 1, true),
		nil,
		`loading and starter sign binders do not use {forbiddenConstructor}`
	)
end

local playableProject = fs.readFile("default.project.json")
for _, authoredWorldObject in
	{
		'"ExampleEarningPad"',
		'"EarnPrompt"',
		'"BonusEarningPad"',
		'"BonusPrompt"',
		'"FirstPrivateIsland"',
		'"PlayableStarterClient"',
		'"RuneCircle"',
		'"GlowRing"',
		'"CoreGlow"',
		'"RuneCircleSign"',
		'"RuneCircleUI"',
	}
do
	expectEqual(
		string.find(playableProject, authoredWorldObject, 1, true) ~= nil,
		true,
		`playable project pre-authors {authoredWorldObject}`
	)
end
local firstPrivateIsland = fs.readFile("src/world/FirstPrivateIslandGridDemo.model.json")
for _, authoredGridObject in
	{
		'"Name": "GamePlatform"',
		'"Name": "PlatformBase"',
		'"Name": "PlatformOrigin"',
		'"Name": "CellMap"',
		'"Name": "Row_01"',
		'"Name": "Row_27"',
		'"Value": "................................"',
		'"Name": "CellSize"',
		'"Name": "Columns"',
		'"Name": "Rows"',
		'"Name": "PlatformEnabled"',
		'"Name": "GridVisible"',
	}
do
	expectEqual(
		string.find(firstPrivateIsland, authoredGridObject, 1, true) ~= nil,
		true,
		`first private island pre-authors {authoredGridObject}`
	)
end
for _, retiredGridObject in
	{
		'"Name": "GridOverlay"',
		'"Name": "Cells"',
		'"Name": "Cell_01_01"',
		'"Name": "Cell_32_27"',
		'"Name": "PathTiles"',
		'"Name": "PathPoints"',
		'"Name": "GridNpc"',
	}
do
	expectEqual(
		string.find(firstPrivateIsland, retiredGridObject, 1, true),
		nil,
		`first private island omits retired authored artifact {retiredGridObject}`
	)
end
expectEqual(
	string.find(firstPrivateIsland, '"Name": "VisibilityMarker"', 1, true),
	nil,
	"first private island no longer includes the temporary visibility marker"
)
local firstPrivateIslandModel = serde.decode("json", firstPrivateIsland)
local function namedChild(parent: { Children: { any } }, name: string): any?
	for _, child in parent.Children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
local gamePlatformModel = namedChild(firstPrivateIslandModel, "GamePlatform")
expectEqual(gamePlatformModel ~= nil, true, "first private island has a game platform model")
local cellMapModel = namedChild(gamePlatformModel, "CellMap")
expectEqual(cellMapModel ~= nil, true, "first private island keeps an authored cell map folder")
expectEqual(#cellMapModel.Children, 27, "empty stage template keeps 27 authored map rows")
for _, rowValue in cellMapModel.Children do
	expectEqual(
		rowValue.Properties.Value,
		"................................",
		`empty stage template row {rowValue.Name} starts fully buildable`
	)
end
expectEqual(
	string.find(firstPrivateIsland, '"Name": "PathCurve_', 1, true),
	nil,
	"empty stage template does not pre-bake route path tiles"
)
expectEqual(
	string.find(firstPrivateIsland, '"Name": "Control_', 1, true),
	nil,
	"empty stage template does not pre-bake spline control handles"
)
expectEqual(
	namedChild(gamePlatformModel, "PathPoints"),
	nil,
	"empty stage template does not retain legacy spline control folders"
)
expectEqual(
	namedChild(gamePlatformModel, "PathTiles"),
	nil,
	"empty stage template does not retain legacy route visual folders"
)
local platformBaseModel = namedChild(gamePlatformModel, "PlatformBase")
expectEqual(platformBaseModel ~= nil, true, "first private island has a platform base")
expectEqual(
	namedChild(platformBaseModel, "GridOverlay"),
	nil,
	"empty stage template does not retain the legacy SurfaceGui grid"
)
expectEqual(
	namedChild(firstPrivateIslandModel, "GridNpc"),
	nil,
	"first private island does not retain the retired demo walker"
)
expectEqual(
	namedChild(firstPrivateIslandModel, "PathPoints"),
	nil,
	"spline controls are not orphaned at island root"
)
expectEqual(
	namedChild(firstPrivateIslandModel, "PathTiles"),
	nil,
	"spline visuals are not orphaned at island root"
)
local gridPatchProject = fs.readFile("patches/rng-defender-grid-demo.project.json")
for _, patchObject in
	{
		'"Template"',
		'"Shared"',
		'"TemplateServer"',
		'"TemplateUI"',
		'"TemplateLoading"',
		'"StarterSignUI"',
		'"RuneCircle"',
		'"RuneCircleSign"',
		'"RuneCircleUI"',
		'"RuneCircleClient"',
		'"servePlaceIds": [128136881672145]',
		'"$path": "rng-defender/DesignerConfig.luau"',
		'"TowerDefenseCatalog"',
		'"TowerDefenseLogic"',
		'"RuneModeConfig"',
	}
do
	expectEqual(
		string.find(gridPatchProject, patchObject, 1, true) ~= nil,
		true,
		`RNG Defender grid patch includes {patchObject}`
	)
end
for _, connectedUiModel in
	{
		"../src/ui/presets/incremental/TemplateUI.model.json",
		"../src/ui/presets/incremental/TemplateLoading.model.json",
		"../src/ui/presets/incremental/StarterSignUI.model.json",
	}
do
	expectEqual(
		string.find(gridPatchProject, connectedUiModel, 1, true) ~= nil,
		true,
		`RNG Defender ships its configured independent UI pack: {connectedUiModel}`
	)
end
for _, unmanagedWorldMarker in { "SixIslandWorldLayout.rbxmx", "StagewrightPlayableWorld" } do
	expectEqual(
		string.find(gridPatchProject, unmanagedWorldMarker, 1, true),
		nil,
		`RNG Defender patch leaves the Team Create world unmanaged: {unmanagedWorldMarker}`
	)
end
expectEqual(
	string.find(gridPatchProject, '"$ignoreUnknownInstances": true', 1, true) ~= nil,
	true,
	"RNG Defender patch preserves unknown Team Create instances"
)
expectEqual(
	serde.decode("json", gridPatchProject).tree.StarterGui["$ignoreUnknownInstances"],
	false,
	"RNG Defender patch removes stale StarterGui roots while preserving the Team Create world"
)
expectEqual(
	string.find(gridPatchProject, '"GridNpcDemo"', 1, true),
	nil,
	"RNG Defender grid patch retires the unreachable duplicate NPC presenter"
)
local rngPatchDesignerConfig = fs.readFile("patches/rng-defender/DesignerConfig.luau")
for _, patchConfigObject in
	{
		'experienceMode = "playable"',
		'dataNamespace = "rngdefender"',
		"universeId = 10479279603",
		"placeId = 128136881672145",
		"startingAmount = 100_000_000_000",
		"towerDefense = true",
		"dungeon = true",
		"requirePlatformOnJoin = false",
		"platformCenterPosition = { 0, 15.5, 0 }",
	}
do
	expectEqual(
		string.find(rngPatchDesignerConfig, patchConfigObject, 1, true) ~= nil,
		true,
		`RNG Defender patch config includes {patchConfigObject}`
	)
end
expectEqual(
	string.find(gridPatchProject, '"FirstPrivateIsland"', 1, true),
	nil,
	"RNG Defender safe patch does not take ownership of the Team Create platform world"
)
local runeCircleWorld = fs.readFile("src/world/RuneCircle.model.json")
for _, runeCircleObject in
	{
		'"Name": "OuterAura"',
		'"Name": "OuterGlass"',
		'"Name": "Platform"',
		'"Name": "GlowRing"',
		'"Name": "MiddleGlow"',
		'"Name": "InnerWell"',
		'"Name": "CoreGlow"',
		'"Name": "RuneLight"',
		'"Name": "RuneSigilPlate"',
		'"Name": "ForestMotes"',
		'"Name": "RuneMist"',
		'"Name": "RootBand1"',
		'"Name": "LeafRune1"',
		'"Name": "MossStone1"',
		'"Name": "RuneBlade8"',
		'"Name": "AnchorCrystal6"',
		'"Name": "Shard1"',
		'"Name": "Shard2"',
		'"Name": "Shard3"',
		"FOREST RUNES",
		"rbxassetid://125907024425133",
	}
do
	expectEqual(
		string.find(runeCircleWorld, runeCircleObject, 1, true) ~= nil,
		true,
		`rune test altar pre-authors {runeCircleObject}`
	)
end
for _, removedPatchObject in
	{
		'"GridPlatformEditorRemote"',
		'"GridPlatformEditor"',
		'"GridPlatformEditorClient"',
		'"GridPlatformEditorService"',
		'"GridForgeEditor"',
		'"GridForgePanel"',
		'"StagewrightEditor"',
		'"StagewrightPanel"',
		'"StarterPack"',
	}
do
	expectEqual(
		string.find(gridPatchProject, removedPatchObject, 1, true),
		nil,
		`RNG Defender grid patch keeps edit-only plugin object out of Rojo patch: {removedPatchObject}`
	)
end
expectEqual(
	string.find(gridPatchProject, '"FirstPrivateIsland"', 1, true),
	nil,
	"shared tower-defense patch never manages the Team Create island"
)
expectEqual(
	string.find(gridPatchProject, '"StageCatalog.generated"', 1, true) ~= nil,
	true,
	"shared tower-defense patch includes generated Stagewright runtime data"
)
do
	local gridPluginProject = fs.readFile("plugins/grid-platform-editor.project.json")
	local gridPluginSource = fs.readFile("src/plugins/GridPlatformEditPlugin.server.luau")
	local stagewrightProjectStoreSource = fs.readFile("src/plugins/Stagewright/ProjectStore.luau")
	local stagewrightAuthoringAreaSource = fs.readFile("src/plugins/Stagewright/AuthoringArea.luau")
	local stagewrightHierarchyOptionsSource = fs.readFile("src/plugins/Stagewright/HierarchyOptions.luau")
	local stagewrightMapBackdropSource = fs.readFile("src/plugins/Stagewright/MapBackdrop.luau")
	local stagewrightStorageSource = fs.readFile("src/plugins/Stagewright/Persistence/ProjectStorage.luau")
	local stagewrightLoadPolicySource =
		fs.readFile("src/plugins/Stagewright/Persistence/ProjectLoadPolicy.luau")
	local stagewrightWorkspacePreviewSource = fs.readFile("src/plugins/Stagewright/WorkspacePreview.luau")
	local stagewrightRouteOverviewSource = fs.readFile("src/plugins/Stagewright/RouteOverview.luau")
	local stagewrightWorldPathSource = fs.readFile("src/plugins/Stagewright/WorldPathView.luau")
	local stagewrightWorldPathControllerSource =
		fs.readFile("src/plugins/Stagewright/Controllers/WorldPathController.luau")
	local stagewrightGraphToolControllerSource =
		fs.readFile("src/plugins/Stagewright/Controllers/GraphToolController.luau")
	local stagewrightMapNavigationControllerSource =
		fs.readFile("src/plugins/Stagewright/Controllers/MapNavigationController.luau")
	local stagewrightWorldPathEditSessionSource =
		fs.readFile("src/plugins/Stagewright/Controllers/WorldPathEditSession.luau")
	local stagewrightPaintRouteDragSessionSource =
		fs.readFile("src/plugins/Stagewright/Controllers/PaintRouteDragSession.luau")
	local stagewrightPaintStrokeSessionSource =
		fs.readFile("src/plugins/Stagewright/Controllers/PaintStrokeSession.luau")
	local stagewrightAppShellSource = fs.readFile("src/plugins/Stagewright/UI/AppShell.luau")
	local stagewrightThemeSource = fs.readFile("src/plugins/Stagewright/UI/Theme.luau")
	local stagewrightFactorySource = fs.readFile("src/plugins/Stagewright/UI/Factory.luau")
	local stagewrightHeaderControllerSource = fs.readFile("src/plugins/Stagewright/UI/HeaderController.luau")
	local stagewrightHierarchyBrowserSource =
		fs.readFile("src/plugins/Stagewright/UI/HierarchyBrowserView.luau")
	local stagewrightMapPropertiesSource = fs.readFile("src/plugins/Stagewright/UI/MapPropertiesView.luau")
	local stagewrightPaintAppearanceSource = fs.readFile("src/plugins/Stagewright/UI/PaintAppearance.luau")
	local stagewrightPaintCellOverlaySource = fs.readFile("src/plugins/Stagewright/UI/PaintCellOverlay.luau")
	local stagewrightPaintInspectorSource = fs.readFile("src/plugins/Stagewright/UI/PaintInspector.luau")
	local stagewrightToolbarSource = fs.readFile("src/plugins/Stagewright/UI/Toolbar.luau")
	local stagewrightGraphOperationsSource = fs.readFile("src/plugins/Stagewright/Graph/Operations.luau")
	local stagePathAssetsSource = fs.readFile("src/shared/StagePathAssets.luau")
	local stageTypesSource = fs.readFile("src/shared/StageTypes.luau")
	local stagewrightPredicateFieldsSource = fs.readFile("src/plugins/Stagewright/Graph/PredicateFields.luau")
	local stagewrightPaintBrushesSource = fs.readFile("src/plugins/Stagewright/Paint/Brushes.luau")
	local stagewrightStageSettingsSource = fs.readFile("src/plugins/Stagewright/Stage/Settings.luau")
	local stagewrightIssueModelSource = fs.readFile("src/plugins/Stagewright/Validation/IssueModel.luau")
	local stagewrightWaveModelSource = fs.readFile("src/plugins/Stagewright/Waves/Model.luau")
	local stagewrightWaveDesignerSource = fs.readFile("src/plugins/Stagewright/UI/WaveDesignerView.luau")
	local stagewrightImportSource = fs.readFile("scripts/stagewright-import.luau")
	local stagePlaytestArtifactSource = fs.readFile("src/shared/StagePlaytestArtifact.luau")
	local stagewrightPlaytestControllerSource =
		fs.readFile("src/client/Controllers/StagewrightPlaytestController.luau")
	local stagewrightPlaytestPreparationSource =
		fs.readFile("src/plugins/Stagewright/PlaytestPreparation.luau")
	local stagewrightPlaytestHudSource = fs.readFile("src/ui/StagewrightPlaytestHUD.model.json")
	local stagewrightUiSource = stagewrightAppShellSource
		.. stagewrightThemeSource
		.. stagewrightFactorySource
		.. stagewrightHeaderControllerSource
		.. stagewrightPaintAppearanceSource
		.. stagewrightPaintCellOverlaySource
		.. stagewrightPaintInspectorSource
		.. stagewrightToolbarSource
	local stagewrightGraphSource = stagewrightGraphOperationsSource .. stagewrightPredicateFieldsSource
	local stagewrightPaintSource = stagewrightPaintBrushesSource
	local stagewrightStageSource = stagewrightStageSettingsSource
	expectCompiles(gridPluginSource, "modern Stagewright plugin shell compiles as Luau")
	expectCompiles(stagewrightProjectStoreSource, "Stagewright project store compiles as Luau")
	expectCompiles(stagewrightHierarchyOptionsSource, "Stagewright hierarchy options compile as Luau")
	expectCompiles(stagewrightMapBackdropSource, "Stagewright map backdrop manager compiles as Luau")
	expectCompiles(stagewrightStorageSource, "Stagewright storage adapter compiles as Luau")
	expectCompiles(stagewrightLoadPolicySource, "Stagewright load policy compiles as Luau")
	expectCompiles(stagewrightWorkspacePreviewSource, "Stagewright Workspace preview compiles as Luau")
	expectCompiles(stagewrightRouteOverviewSource, "Stagewright 2D route overview compiles as Luau")
	expectCompiles(stagewrightWorldPathSource, "Stagewright real-world path view compiles as Luau")
	expectCompiles(stagewrightWorldPathControllerSource, "Stagewright world-path controller compiles as Luau")
	expectCompiles(stagewrightGraphToolControllerSource, "Stagewright graph-tool controller compiles as Luau")
	expectCompiles(
		stagewrightMapNavigationControllerSource,
		"Stagewright map navigation controller compiles as Luau"
	)
	expectCompiles(
		stagewrightWorldPathEditSessionSource,
		"Stagewright world-path edit session compiles as Luau"
	)
	expectCompiles(
		stagewrightPaintRouteDragSessionSource,
		"Stagewright paint-route drag session compiles as Luau"
	)
	expectCompiles(stagewrightPaintStrokeSessionSource, "Stagewright paint-stroke session compiles as Luau")
	expectCompiles(stagewrightAppShellSource, "Stagewright app shell compiles as Luau")
	expectCompiles(stagewrightThemeSource, "Stagewright UI theme compiles as Luau")
	expectCompiles(stagewrightFactorySource, "Stagewright UI factory compiles as Luau")
	expectCompiles(stagewrightHeaderControllerSource, "Stagewright header controller compiles as Luau")
	expectCompiles(stagewrightHierarchyBrowserSource, "Stagewright hierarchy browser compiles as Luau")
	expectCompiles(stagewrightMapPropertiesSource, "Stagewright Map Properties view compiles as Luau")
	expectCompiles(stagewrightPaintAppearanceSource, "Stagewright paint appearance compiles as Luau")
	expectCompiles(stagewrightPaintCellOverlaySource, "Stagewright paint cell overlay compiles as Luau")
	expectCompiles(stagewrightPaintInspectorSource, "Stagewright paint inspector compiles as Luau")
	expectCompiles(stagewrightToolbarSource, "Stagewright toolbar compiles as Luau")
	expectCompiles(stagewrightGraphOperationsSource, "Stagewright graph operations compile as Luau")
	expectCompiles(stagePathAssetsSource, "shared Stagewright path asset catalog compiles as Luau")
	expectCompiles(stageTypesSource, "shared Stagewright Map-first types compile as Luau")
	expectCompiles(stagewrightPredicateFieldsSource, "Stagewright predicate fields compile as Luau")
	expectCompiles(stagewrightPaintBrushesSource, "Stagewright paint brushes compile as Luau")
	expectCompiles(stagewrightStageSettingsSource, "Stagewright stage settings compile as Luau")
	expectCompiles(stagewrightIssueModelSource, "Stagewright validation issue model compiles as Luau")
	expectCompiles(stagewrightWaveModelSource, "Stagewright wave designer model compiles as Luau")
	expectCompiles(stagewrightWaveDesignerSource, "Stagewright wave designer view compiles as Luau")
	expectCompiles(stagewrightImportSource, "Stagewright repository importer compiles as Luau")
	expectCompiles(stagePlaytestArtifactSource, "Stagewright playtest artifact contract compiles as Luau")
	expectCompiles(
		stagewrightPlaytestPreparationSource,
		"Stagewright playtest preparation module compiles as Luau"
	)
	expectCompiles(
		stagewrightPlaytestControllerSource,
		"Stagewright playtest HUD controller compiles as Luau"
	)
	for _, prepareMarker in
		{
			"local function preparePlaytest()",
			"ProjectStore.export()",
			"ProjectStorage.writePayload(",
			"StagePlaytestArtifact.SOURCE_CHECKSUM_ATTRIBUTE",
			"StagePlaytestArtifact.RUNTIME_CHECKSUM_ATTRIBUTE",
			"preparePlaytest = preparePlaytest",
		}
	do
		expectEqual(
			string.find(gridPluginSource .. stagewrightPlaytestPreparationSource, prepareMarker, 1, true)
				~= nil,
			true,
			`Stagewright prepares a checked chunked runtime snapshot: {prepareMarker}`
		)
	end
	for _, hudObject in
		{
			'"Name": "Level1Button"',
			'"Name": "Level2Button"',
			'"Name": "Level3Button"',
			'"Name": "WaveLabel"',
			'"Name": "RunButton"',
			'"Name": "ResetButton"',
			'"Name": "StatsLabel"',
			'"Name": "StatusLabel"',
		}
	do
		expectEqual(
			string.find(stagewrightPlaytestHudSource, hudObject, 1, true) ~= nil,
			true,
			`playtest HUD pre-authors {hudObject}`
		)
	end
	expectEqual(
		string.find(gridPluginProject, '"StagePlaytestArtifact"', 1, true) ~= nil
			and string.find(gridPatchProject, '"StagewrightPlaytestRuntime"', 1, true) ~= nil
			and string.find(gridPatchProject, '"StagewrightPlaytestHUD"', 1, true) ~= nil
			and string.find(gridPatchProject, '"StagePayload"', 1, true) ~= nil,
		true,
		"plugin and RNG Defender patch map the prepared snapshot transport and authored HUD"
	)
	expectEqual(
		string.find(
			stagewrightAppShellSource,
			'local usesFullWorkspace = mode == "Graph" or mode == "Waves"',
			1,
			true
		) ~= nil,
		true,
		"Graph and Waves modes both receive the unclipped full workspace"
	)
	expectEqual(
		string.find(stagewrightAppShellSource, "CellSize = UDim2.new(0.2, -1.6, 1, 0)", 1, true) ~= nil
			and string.find(
					gridPluginSource,
					'{ "Graph", "Paint", "Stage", "Waves", "Validate" }',
					1,
					true
				)
				~= nil,
		true,
		"five Stagewright workspace modes remain on one unclipped navigation row"
	)
	for _, waveDesignerMarker in
		{
			'"Waves"',
			"WaveDesignerView.new",
			"WaveDesignerView.newWaveSetPicker",
			"revision = ProjectStore.workingChecksum",
			"renderedWavesChecksum ~= wavesChecksum",
			"waveSetPicker:validIds()",
			"StageSettings.parse",
		}
	do
		expectEqual(
			string.find(gridPluginSource, waveDesignerMarker, 1, true) ~= nil,
			true,
			`plugin bootstrap wires the wave designer: {waveDesignerMarker}`
		)
	end
	for _, draftMarker in
		{
			"local entryDraftKey: string? = nil",
			"local entryDraftDirty = false",
			"local revisionChanged = revision ~= renderedRevision",
			"entryDraftKey ~= selectionKey",
			"enemyButton.Text = `Enemy: {currentDraft.enemyTypeId}`",
			"return resultOk, resultMessage",
		}
	do
		expectEqual(
			string.find(stagewrightWaveDesignerSource, draftMarker, 1, true) ~= nil,
			true,
			`wave entry drafts remain keyed and refresh safely: {draftMarker}`
		)
	end
	local mutateFunctionAt = assert(
		string.find(gridPluginSource, "function mutate(name: string, callback: () -> ()): boolean", 1, true),
		"Stagewright mutate wrapper exists"
	)
	local mutateStoreAt = assert(
		string.find(
			gridPluginSource,
			"local committed, message = ProjectStore.mutate(name, callback)",
			mutateFunctionAt,
			true
		),
		"Stagewright mutate wrapper delegates to ProjectStore"
	)
	local mutateResyncAt = assert(
		string.find(gridPluginSource, "project = ProjectStore.get()", mutateStoreAt, true),
		"Stagewright mutate wrapper resynchronizes its project reference"
	)
	local mutateRejectionAt = assert(
		string.find(gridPluginSource, "if not committed then", mutateStoreAt, true),
		"Stagewright mutate wrapper handles rejected edits"
	)
	expectEqual(
		mutateResyncAt < mutateRejectionAt,
		true,
		"rejected Stagewright edits resynchronize the restored ProjectStore table before returning"
	)
	expectEqual(
		string.find(gridPluginProject, '"WaveDesignerView"', 1, true) ~= nil
			and string.find(gridPluginProject, "Waves/Model.luau", 1, true) ~= nil
			and string.find(gridPluginProject, "StageWaveDefaults.luau", 1, true) ~= nil,
		true,
		"plugin project maps the wave designer modules"
	)
	for _, mapTypeContract in
		{
			"export type MapDefinition = {",
			"backdropImageId: string",
			"mapId: string",
			"maps: { [string]: MapDefinition }",
			"export type RuntimeMapDefinition = {",
			"mapOrder: { string }",
			"maps: { [string]: RuntimeMapDefinition }",
		}
	do
		expectEqual(
			string.find(stageTypesSource, mapTypeContract, 1, true) ~= nil,
			true,
			`Stagewright serializable types preserve the Map registry contract: {mapTypeContract}`
		)
	end
	for _, backdropContract in
		{
			'local MAP_IMAGE_FIELD = "backdropImageId"',
			'local LEGACY_METADATA_KEY = "stagewright.mapBackdrops"',
			'local LEGACY_CONFLICT_KEY = "stagewright.legacyBackdropConflict"',
			"local function stageMapId(stage: any): string?",
			"local function mapRecord(project: any, stage: any): any?",
			"local direct = maps[mapId]",
			"function MapBackdrop.normalizeImageId",
			'return string.match(trimmed, "^rbxassetid://(%d+)$")',
			"function MapBackdrop.readImageId",
			"local map = mapRecord(project, stage)",
			"local configured = MapBackdrop.normalizeImageId(map[MAP_IMAGE_FIELD])",
			"function MapBackdrop.contentId",
			"function MapBackdrop.apply",
			"map[MAP_IMAGE_FIELD] = imageId",
			'if type(project.maps) == "table" then',
			'return false, "The selected Level does not reference an existing Map"',
			"map.metadata[LEGACY_CONFLICT_KEY] = nil",
			"function MapBackdrop.clear",
		}
	do
		expectEqual(
			string.find(stagewrightMapBackdropSource, backdropContract, 1, true) ~= nil,
			true,
			`Stagewright map backdrop preserves contract: {backdropContract}`
		)
	end
	for _, removedBackdropCache in
		{
			"ServerStorage",
			"StagewrightMapBackdrops",
			"ImagePlane",
			"BackdropImage",
			"Instance.new",
			"GetAttribute",
			"SetAttribute",
			"Decal",
			"BasePart",
			"function MapBackdrop.reconcile",
			"function MapBackdrop.reconciled",
		}
	do
		expectEqual(
			string.find(stagewrightMapBackdropSource, removedBackdropCache, 1, true),
			nil,
			`Stagewright map metadata helper does not recreate legacy 3D cache: {removedBackdropCache}`
		)
	end
	for _, forbiddenBackdropCoupling in { "StagePath", "PathTiles", "pathGraphs", "edges" } do
		expectEqual(
			string.find(stagewrightMapBackdropSource, forbiddenBackdropCoupling, 1, true),
			nil,
			`Stagewright map artwork does not encode route data: {forbiddenBackdropCoupling}`
		)
	end
	do
		local executableBackdropSource = string.gsub(
			stagewrightMapBackdropSource,
			"local StageHierarchy = require%(script%.Parent%.Shared%.StageHierarchy%)",
			"local StageHierarchy = ...",
			1
		)
		local backdropChunk, backdropCompileError = luau.load(executableBackdropSource)
		expectEqual(
			backdropChunk ~= nil,
			true,
			`Stagewright map metadata helper loads for behavior tests: {tostring(backdropCompileError)}`
		)
		local MapBackdrop =
			assert(backdropChunk, "MapBackdrop behavior chunk did not compile")(StageHierarchy)
		expectEqual(
			MapBackdrop.normalizeImageId("  rbxassetid://110986082479051  "),
			"110986082479051",
			"Map backdrop normalizes a Roblox content ID without numeric precision loss"
		)
		expectEqual(
			MapBackdrop.normalizeImageId(110986082479051),
			nil,
			"Map backdrop rejects numeric IDs that could lose precision"
		)
		local mapProject = {
			maps = {
				map_main = {
					id = "map_main",
					backdropImageId = "111",
					metadata = { ["stagewright.legacyBackdropConflict"] = true },
				},
				map_bonus = {
					id = "map_bonus",
					backdropImageId = "222",
					metadata = {},
				},
			},
			metadata = {
				["stagewright.mapBackdrops"] = { shared_stage = "999" },
			},
		}
		local mainLevelOne = { mapId = "map_main", stageGroupId = "shared_stage", stageNumber = 1 }
		local mainLevelTwo = { mapId = "map_main", stageGroupId = "shared_stage", stageNumber = 1 }
		local bonusLevel = { mapId = "map_bonus", stageGroupId = "bonus_stage", stageNumber = 1 }
		expectEqual(
			MapBackdrop.readImageId(mapProject, mainLevelOne),
			"111",
			"first-class Map artwork overrides legacy Stage-group metadata"
		)
		local changed, applyError = MapBackdrop.apply(mapProject, mainLevelOne, "110986082479051")
		expectEqual(changed and applyError == nil, true, "valid Map artwork applies successfully")
		expectEqual(
			MapBackdrop.readImageId(mapProject, mainLevelTwo),
			"110986082479051",
			"every Stage and Level in one Map shares the applied artwork"
		)
		expectEqual(
			MapBackdrop.readImageId(mapProject, bonusLevel),
			"222",
			"changing one Map never changes another Map's artwork"
		)
		expectEqual(
			mapProject.maps.map_main.metadata["stagewright.legacyBackdropConflict"],
			nil,
			"choosing Map artwork resolves the legacy backdrop conflict marker"
		)
		local missingChanged, missingError =
			MapBackdrop.apply(mapProject, { mapId = "map_missing", stageGroupId = "missing" }, "333")
		expectEqual(
			missingChanged == false and type(missingError) == "string",
			true,
			"current Map-first projects never fall back to writing artwork for a missing Map"
		)
		local legacyOnlyProject = {
			metadata = { ["stagewright.mapBackdrops"] = { legacy_group = "444" } },
		}
		expectEqual(
			MapBackdrop.readImageId(legacyOnlyProject, { stageGroupId = "legacy_group", stageNumber = 1 }),
			"444",
			"pre-migration projects retain read-only legacy backdrop compatibility"
		)
	end
	for _, directImageContract in
		{
			"backdropImage: () -> string?",
			"mapWorldSize: () -> WorldSize?",
			"transformMapId: string?",
			"if self.transformMapId ~= nextMapId then",
			"local function configuredBackdropImage(self: Controller): string?",
			"local function imageCoverRect(",
			"CanvasTransform.worldToCanvas(transform",
			"local function createImageBackdrop(",
			'Instance.new("ImageLabel")',
			'image.Name = "MapBackdropImage"',
			"image.Image = contentId",
			"image.ScaleType = Enum.ScaleType.Stretch",
			'GetPropertyChangedSignal("IsLoaded")',
			"if observedImage.IsLoaded then",
			"task.delay(BACKDROP_LOAD_TIMEOUT",
			"Loading map artwork...",
			"Map image unavailable - check asset ownership or moderation",
			"mapWorldWidth",
			"mapWorldHeight",
		}
	do
		expectEqual(
			string.find(stagewrightWorldPathSource, directImageContract, 1, true) ~= nil,
			true,
			`Stagewright World Path directly renders Map artwork: {directImageContract}`
		)
	end
	expectEqual(
		string.find(stagewrightWorldPathControllerSource, "backdropImage = config.backdropImage", 1, true)
				~= nil
			and string.find(
				stagewrightWorldPathControllerSource,
				"mapWorldSize = config.mapWorldSize",
				1,
				true
			) ~= nil
			and string.find(gridPluginSource, "MapBackdrop.contentId(project, stage())", 1, true) ~= nil
			and string.find(gridPluginSource, "HierarchyOptions.mapWorldSize(project, stage())", 1, true)
				~= nil,
		true,
		"Stagewright passes the selected Map image into World Path without a generated 3D cache"
	)
	expectEqual(
		string.find(gridPluginSource, "ProjectStore.mutate(name, callback)", 1, true) ~= nil
			and string.find(gridPluginSource, "MapBackdrop.reconciled", 1, true) == nil,
		true,
		"Stagewright map metadata changes use the normal project transaction without cache reconciliation"
	)
	expectEqual(
		string.find(stagewrightWorldPathSource, "local function createWorldBackdrop", 1, true) ~= nil
			and string.find(stagewrightWorldPathSource, "if configuredImage ~= nil then", 1, true) ~= nil
			and string.find(stagewrightWorldPathSource, "hasWorldBackdrop = createWorldBackdrop", 1, true)
				~= nil,
		true,
		"Stagewright uses real Studio scenery only as the no-image fallback"
	)
	expectEqual(
		string.find(gridPluginProject, '"StagePathAssets"', 1, true) ~= nil
			and string.find(gridPluginProject, '"../src/shared/StagePathAssets.luau"', 1, true) ~= nil,
		true,
		"Stagewright plugin maps the shared path asset catalog"
	)
	for moduleName, modulePath in
		{
			HierarchyOptions = "../src/plugins/Stagewright/HierarchyOptions.luau",
			HierarchyBrowserView = "../src/plugins/Stagewright/UI/HierarchyBrowserView.luau",
			MapBackdrop = "../src/plugins/Stagewright/MapBackdrop.luau",
			MapPropertiesView = "../src/plugins/Stagewright/UI/MapPropertiesView.luau",
		}
	do
		expectEqual(
			string.find(gridPluginProject, `"{moduleName}"`, 1, true) ~= nil
				and string.find(gridPluginProject, `"{modulePath}"`, 1, true) ~= nil,
			true,
			`Stagewright plugin maps the Map hierarchy module {moduleName}`
		)
	end
	expectEqual(
		string.find(gridPluginProject, '"GraphToolController"', 1, true) ~= nil
			and string.find(
					gridPluginProject,
					'"../src/plugins/Stagewright/Controllers/GraphToolController.luau"',
					1,
					true
				)
				~= nil,
		true,
		"Stagewright plugin maps the extracted graph-tool controller"
	)
	expectEqual(
		string.find(gridPluginProject, '"MapNavigationController"', 1, true) ~= nil
			and string.find(
					gridPluginProject,
					'"../src/plugins/Stagewright/Controllers/MapNavigationController.luau"',
					1,
					true
				)
				~= nil,
		true,
		"Stagewright plugin maps the extracted map navigation controller"
	)
	expectEqual(
		string.find(stagewrightToolbarSource, "resolvedOffsetX -= padding.PaddingLeft.Offset", 1, true) ~= nil,
		true,
		"Stagewright toolbar icons compensate for padded button coordinates"
	)
	expectEqual(
		string.find(stagewrightThemeSource, "resolveHeaderLayout", 1, true) ~= nil
			and string.find(stagewrightHeaderControllerSource, "styleIconOnlyButton", 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Name = "MapNavigation"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Name = "MapPlayable"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Name = "MapAdmin"', 1, true) ~= nil,
		true,
		"Stagewright responsive shell keeps persistent playable and admin map navigation"
	)
	expectEqual(
		string.find(stagewrightAppShellSource, 'Factory.button(mapPanel, "PLAYABLE"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Factory.button(mapPanel, "ADMIN"', 1, true) ~= nil,
		true,
		"Stagewright MAP panel labels its playable and admin destinations"
	)
	expectEqual(
		string.find(gridPluginSource, "require(script.Controllers.MapNavigationController)", 1, true) ~= nil
			and string.find(
				gridPluginSource,
				"MapNavigationController.bind(shell.mapPlayable, shell.mapAdmin, {",
				1,
				true
			) ~= nil
			and string.find(gridPluginSource, "cancelInteraction = function()", 1, true) ~= nil
			and string.find(gridPluginSource, "focusPlayable = function(): boolean", 1, true) ~= nil
			and string.find(
				gridPluginSource,
				"AuthoringArea.focusPlayable(current.grid.columns, current.grid.rows, current.grid.cellSize)",
				1,
				true
			) ~= nil
			and string.find(gridPluginSource, "focusAdmin = AuthoringArea.focus", 1, true) ~= nil
			and string.find(gridPluginSource, "reportBlocked = flowRuntime.reportBlocked", 1, true) ~= nil
			and string.find(gridPluginSource, "setStatus = setStatus", 1, true) ~= nil
			and string.find(gridPluginSource, "shell.mapPlayable.Activated:Connect", 1, true) == nil
			and string.find(gridPluginSource, "shell.mapAdmin.Activated:Connect", 1, true) == nil,
		true,
		"Stagewright bootstrap delegates MAP behavior to the extracted navigation controller"
	)
	do
		local centerResolverStart = assert(
			string.find(stagewrightAuthoringAreaSource, "local function centerPart", 1, true),
			"Stagewright center resolver exists"
		)
		local centerResolverEnd = assert(
			string.find(
				stagewrightAuthoringAreaSource,
				"local function legacyPlatform",
				centerResolverStart,
				true
			),
			"Stagewright center resolver has a stable boundary"
		)
		local centerResolverSource =
			string.sub(stagewrightAuthoringAreaSource, centerResolverStart, centerResolverEnd - 1)
		expectEqual(
			string.find(centerResolverSource, "local found: BasePart? = nil", 1, true) ~= nil
				and string.find(centerResolverSource, "if found ~= nil then", 1, true) ~= nil
				and string.find(centerResolverSource, "warnedAmbiguousCenter = true", 1, true) ~= nil
				and string.find(centerResolverSource, "return descendant", 1, true) == nil,
			true,
			"Stagewright playable focus fails closed when multiple center anchors exist"
		)
	end
	do
		local layoutCenterStart = assert(
			string.find(stagewrightAuthoringAreaSource, "local function layoutCenter", 1, true),
			"Stagewright layout center resolver exists"
		)
		local layoutCenterEnd = assert(
			string.find(
				stagewrightAuthoringAreaSource,
				"local function legacyPlatform",
				layoutCenterStart,
				true
			),
			"Stagewright layout center resolver has a stable boundary"
		)
		local layoutCenterSource =
			string.sub(stagewrightAuthoringAreaSource, layoutCenterStart, layoutCenterEnd - 1)
		local configuredCenterAt = string.find(
			layoutCenterSource,
			"local configured = templateConfig.towerDefense.platformCenterPosition",
			1,
			true
		)
		local configuredReturnAt =
			string.find(layoutCenterSource, 'return CFrame.new(x, y, z), "ConfiguredCenter"', 1, true)
		local authoredCenterAt =
			string.find(layoutCenterSource, "local center = centerPart(templateConfig)", 1, true)
		expectEqual(
			configuredCenterAt ~= nil
				and configuredReturnAt ~= nil
				and authoredCenterAt ~= nil
				and configuredCenterAt < configuredReturnAt
				and configuredReturnAt < authoredCenterAt,
			true,
			"Stagewright resolves the configured platform center before authored center anchors"
		)
	end
	do
		for _, refreshBehavior in
			{
				"local function freshDesignerPlatformCenter(shared: Instance): ({ number }?, boolean)",
				"cachedDesignerModule == candidate and cachedDesignerSource == source",
				"local snapshot = candidate:Clone()",
				"local success, result = pcall(require, snapshot)",
				"local freshCenter, freshLoaded = freshDesignerPlatformCenter(shared)",
				"towerDefense.platformCenterPosition = freshCenter",
			}
		do
			expectEqual(
				string.find(stagewrightAuthoringAreaSource, refreshBehavior, 1, true) ~= nil,
				true,
				`Stagewright refreshes Rojo-synced map center data without a Studio restart: {refreshBehavior}`
			)
		end
		expectEqual(
			string.find(stagewrightAuthoringAreaSource, "CFrame.new(0, 15.5, 0)", 1, true),
			nil,
			"Stagewright playable navigation does not hardcode the RNG Defender center"
		)
	end
	do
		local slotOriginStart = assert(
			string.find(stagewrightAuthoringAreaSource, "local function playableSlotOrigin", 1, true),
			"Stagewright playable slot origin helper exists"
		)
		local slotOriginEnd = assert(
			string.find(
				stagewrightAuthoringAreaSource,
				"local function setPartProperties",
				slotOriginStart,
				true
			),
			"Stagewright playable slot origin helper has a stable boundary"
		)
		local slotOriginSource =
			string.sub(stagewrightAuthoringAreaSource, slotOriginStart, slotOriginEnd - 1)
		for _, originBehavior in
			{
				"StagePlatformLayout.slotOffset({",
				"slot, templateConfig.towerDefense.platformSlotCount)",
				"CFrame.new(offset.x, offset.y, offset.z)",
				"CFrame.Angles(0, yaw + math.rad(templateConfig.towerDefense.firstPlatformYawDegrees), 0)",
			}
		do
			expectEqual(
				string.find(slotOriginSource, originBehavior, 1, true) ~= nil,
				true,
				`Stagewright centralizes the six-slot transform math: {originBehavior}`
			)
		end
	end
	do
		local focusPlayableStart = assert(
			string.find(
				stagewrightAuthoringAreaSource,
				"function AuthoringArea.focusPlayable(columns: number, rows: number, cellSize: number): boolean",
				1,
				true
			),
			"Stagewright playable focus function exists"
		)
		local focusPlayableEnd = assert(
			string.find(
				stagewrightAuthoringAreaSource,
				"local function legacyGridNpc",
				focusPlayableStart,
				true
			),
			"Stagewright playable focus function has a stable boundary"
		)
		local focusPlayableSource =
			string.sub(stagewrightAuthoringAreaSource, focusPlayableStart, focusPlayableEnd - 1)
		for _, focusBehavior in
			{
				"local centerFrame = layoutCenter(templateConfig)",
				"local origin = playableSlotOrigin(templateConfig, centerFrame, 1)",
				"Selection:Set({})",
				"return focusFrame(origin, Vector3.new(columns * cellSize, 4, rows * cellSize))",
			}
		do
			expectEqual(
				string.find(focusPlayableSource, focusBehavior, 1, true) ~= nil,
				true,
				`Stagewright playable focus frames slot one at the exact level dimensions: {focusBehavior}`
			)
		end
	end
	for _, mapNavigationBehavior in
		{
			"playableButton.Activated:Connect",
			"adminButton.Activated:Connect",
			"focusPlayable: () -> boolean",
			"focusAdmin: () -> boolean",
			"callbacks.cancelInteraction()",
			"callbacks.focusPlayable()",
			"callbacks.focusAdmin()",
			"ProjectStore.isWritable()",
			'callbacks.reportBlocked("Focus authoring area")',
			"callbacks.setStatus(",
			"Focused the first playable grid.",
			"The playable grid could not be resolved.",
			"Focused the Stagewright admin work area.",
			"The admin work area could not be found.",
			"not focused",
		}
	do
		expectEqual(
			string.find(stagewrightMapNavigationControllerSource, mapNavigationBehavior, 1, true) ~= nil,
			true,
			`Stagewright map navigation controller preserves {mapNavigationBehavior}`
		)
	end
	expectEqual(
		string.find(stagewrightAppShellSource, 'Name = "CompactToolsButton"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Name = "CompactInspectorButton"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'Name = "CompactPanelDismiss"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'compactPanel == "Left"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, 'compactPanel == "Right"', 1, true) ~= nil
			and string.find(stagewrightAppShellSource, "isWorkspaceInputAllowed", 1, true) ~= nil
			and string.find(stagewrightAppShellSource, "popupLayer:GetChildren()", 1, true) ~= nil
			and string.find(stagewrightAppShellSource, "PAINT_DESKTOP_SIDEBAR_MIN_WIDTH", 1, true) ~= nil,
		true,
		"Stagewright compact shell keeps authored tools available without canvas click-through or overlap"
	)
	expectEqual(
		string.find(gridPluginSource, "shell:isWorkspaceInputAllowed(position)", 1, true) ~= nil
			and string.find(gridPluginSource, "paintPanState", 1, true) ~= nil
			and string.find(gridPluginSource, "Enum.UserInputType.MouseButton3", 1, true) ~= nil
			and string.find(gridPluginSource, "gridScroll.CanvasPosition = Vector2.new(", 1, true) ~= nil,
		true,
		"Stagewright Paint blocks drawer click-through and supports explicit canvas panning"
	)
	do
		local paintInputChangedStart = assert(
			string.find(gridPluginSource, "UserInputService.InputChanged:Connect(function(input)", 1, true),
			"Stagewright Paint mouse-movement handler exists"
		)
		local paintInputChangedEnd = assert(
			string.find(
				gridPluginSource,
				"UserInputService.InputEnded:Connect(function(input)",
				paintInputChangedStart,
				true
			),
			"Stagewright Paint mouse-movement handler has a stable boundary"
		)
		local paintInputChangedSource =
			string.sub(gridPluginSource, paintInputChangedStart, paintInputChangedEnd - 1)
		for _, idleScopeBehavior in
			{
				"local draggingRoute = routeDragSession:isActive()",
				"local column, row = paintRuntime.cellAt(position)",
				"not draggingRoute",
				"column == nil",
				"row == nil",
				"not shell:isWorkspaceInputAllowed(position)",
			}
		do
			expectEqual(
				string.find(paintInputChangedSource, idleScopeBehavior, 1, true) ~= nil,
				true,
				`Stagewright idle Paint/Route input stays scoped to its canvas: {idleScopeBehavior}`
			)
		end
		expectEqual(
			string.find(paintInputChangedSource, "local preview = latestPaintRoutePreview", 1, true) ~= nil
				and string.find(paintInputChangedSource, "ProjectStore.preview(selectedStageId)", 1, true) == nil
				and string.find(gridPluginSource, "latestPaintRoutePreview = routePreview", 1, true)
					~= nil,
			true,
			"Stagewright Paint/Route mouse movement reuses the latest rendered preview"
		)
		local _, clearHoverCount = string.gsub(paintInputChangedSource, "showHoveredCell%(nil, nil%)", "")
		expectEqual(
			clearHoverCount >= 2,
			true,
			"Stagewright clears route hover both outside the idle canvas and during an active drag"
		)
	end
	expectEqual(
		string.find(gridPluginSource, "cellButton.InputBegan:Connect", 1, true) ~= nil
			and string.find(gridPluginSource, "input:IsModifierKeyDown(Enum.ModifierKey.Shift)", 1, true) ~= nil
			and string.find(gridPluginSource, 'input:GetPropertyChangedSignal("UserInputState")', 1, true) ~= nil
			and string.find(gridPluginSource, "activePaintPointer", 1, true) ~= nil
			and string.find(gridPluginSource, "paintStrokeSession:move(column, row, true)", 1, true) ~= nil
			and string.find(gridPluginSource, "UserInputService:IsKeyDown", 1, true) == nil
			and string.find(
					gridPluginSource,
					'paintStrokeSession:cancel("Rectangle requires Shift through release")',
					1,
					true
				)
				~= nil,
		true,
		"Stagewright Paint owns its Shift-gated gesture lifecycle inside the Studio widget"
	)
	expectEqual(
		string.find(stagewrightPaintCellOverlaySource, '"HoverCellOutline"', 1, true) ~= nil
			and string.find(stagewrightPaintCellOverlaySource, '"SelectedCellOutline"', 1, true) ~= nil
			and string.find(stagewrightPaintCellOverlaySource, "Interactable = false", 1, true) ~= nil
			and string.find(gridPluginSource, "cellButton.BorderColor3 = if", 1, true) == nil,
		true,
		"Stagewright Paint uses input-transparent logical hover and selection outlines"
	)
	expectEqual(
		string.find(stagewrightPaintBrushesSource, 'layer = "Terrain"', 1, true) ~= nil
			and string.find(stagewrightPaintBrushesSource, 'layer = "Build"', 1, true) ~= nil
			and string.find(stagewrightPaintBrushesSource, "function Brushes.eraseId", 1, true) ~= nil
			and string.find(stagewrightPaintAppearanceSource, "PaintAppearance.token", 1, true) ~= nil
			and string.find(stagewrightPaintInspectorSource, "Each cell has one Surface", 1, true) ~= nil
			and string.find(gridPluginSource, "PaintAppearance.resolve(", 1, true) ~= nil
			and string.find(gridPluginSource, "paintLayer", 1, true) ~= nil,
		true,
		"Stagewright Paint visualizes one independent cell layer and explains the resolved cell state"
	)
	expectEqual(
		string.find(stagewrightRouteOverviewSource, "ScrollingEnabled = false", 1, true) ~= nil
			and string.find(
				stagewrightRouteOverviewSource,
				"local minimumZoom = fitZoom(self) or MIN_ZOOM",
				1,
				true
			) ~= nil
			and string.find(stagewrightWorldPathSource, "interactionSurface.InputChanged:Connect", 1, true) ~= nil
			and string.find(stagewrightWorldPathSource, "Enum.ModifierKey.Ctrl", 1, true) ~= nil
			and string.find(stagewrightWorldPathSource, "MIN_WORLD_ZOOM", 1, true) ~= nil
			and string.find(stagewrightWorldPathSource, "UserInputService", 1, true) == nil
			and string.find(gridPluginSource, "graphViewBecameVisible", 1, true) ~= nil
			and string.find(gridPluginSource, 'if activeMode == "Graph" then', 1, true) ~= nil
			and string.find(gridPluginSource, "renderedFlowMode ~= flowRuntime.mode", 1, true) ~= nil,
		true,
		"Stagewright Flow navigation ignores ordinary wheel input and recovers each active view"
	)
	expectEqual(
		string.find(stagewrightAppShellSource, 'Name = "PopupLayer"', 1, true) ~= nil
			and string.find(stagewrightHeaderControllerSource, "config.popupLayer", 1, true) ~= nil
			and string.find(
				stagewrightHeaderControllerSource,
				'createSelector(header, config.popupLayer, "Map", "Map --")',
				1,
				true
			) ~= nil
			and string.find(
				stagewrightHeaderControllerSource,
				'createSelector(header, config.popupLayer, "Stage", "Stage --")',
				1,
				true
			) ~= nil
			and string.find(
				stagewrightHeaderControllerSource,
				'createSelector(header, config.popupLayer, "Level", "Level --")',
				1,
				true
			) ~= nil
			and string.find(
				stagewrightHeaderControllerSource,
				"local selectors = { mapSelector, stageSelector, levelSelector }",
				1,
				true
			) ~= nil
			and string.find(stagewrightHeaderControllerSource, "for _, selector in selectors do", 1, true) ~= nil
			and string.find(stagewrightHeaderControllerSource, "config.mapOptions()", 1, true) ~= nil
			and string.find(stagewrightHeaderControllerSource, "config.stageOptions()", 1, true) ~= nil
			and string.find(stagewrightHeaderControllerSource, "config.levelOptions()", 1, true) ~= nil,
		true,
		"Stagewright header makes Map the first selector and cascades Map, Stage, then Level"
	)
	expectEqual(
		string.find(gridPluginSource, "require(script.HierarchyOptions)", 1, true) ~= nil
			and string.find(gridPluginSource, "mapOptions = function()", 1, true) ~= nil
			and string.find(gridPluginSource, "stageOptions = function()", 1, true) ~= nil
			and string.find(gridPluginSource, "levelOptions = function()", 1, true) ~= nil
			and string.find(gridPluginSource, "HierarchyOptions.build(project, selectedStageId)", 1, true)
				~= nil,
		true,
		"Stagewright bootstrap delegates Map-first selector scoping to one hierarchy model"
	)
	for _, hierarchyContract in
		{
			"mapOptions: { SelectorOption }",
			"stageOptions: { SelectorOption }",
			"levelOptions: { SelectorOption }",
			"maps: { MapItem }",
			"selectedMapId: string?",
			"selectedStageGroupId: string?",
			"for mapNumber, mapId in StageHierarchy.mapIds(maps) do",
			"local stageKey = `{address.mapId}\\0{address.groupId}`",
			"selectedAddress.mapId == mapItem.id",
			"selectedAddress.groupId == stageItem.id",
		}
	do
		expectEqual(
			string.find(stagewrightHierarchyOptionsSource, hierarchyContract, 1, true) ~= nil,
			true,
			`Stagewright hierarchy options preserve Map -> Stage -> Level scoping: {hierarchyContract}`
		)
	end
	do
		local executableHierarchySource = string.gsub(
			stagewrightHierarchyOptionsSource,
			"local StageHierarchy = require%(script%.Parent%.Shared%.StageHierarchy%)",
			"local StageHierarchy = ...",
			1
		)
		local hierarchyChunk, hierarchyCompileError = luau.load(executableHierarchySource)
		expectEqual(
			hierarchyChunk ~= nil,
			true,
			`Stagewright hierarchy options load for behavior tests: {tostring(hierarchyCompileError)}`
		)
		local HierarchyOptions =
			assert(hierarchyChunk, "HierarchyOptions behavior chunk did not compile")(StageHierarchy)
		local optionsProject = {
			maps = {
				map_main = { id = "map_main", name = "Grasslands", displayOrder = 1 },
				map_bonus = { id = "map_bonus", name = "Caverns", displayOrder = 2 },
			},
			stages = {
				main_stage_1_level_1 = {
					id = "main_stage_1_level_1",
					name = "Level 1",
					mapId = "map_main",
					stageGroupId = "main_stage_1",
					stageNumber = 1,
					levelNumber = 1,
					grid = { columns = 10, rows = 8, cellSize = 4 },
				},
				main_stage_1_level_2 = {
					id = "main_stage_1_level_2",
					name = "Level 2",
					mapId = "map_main",
					stageGroupId = "main_stage_1",
					stageNumber = 1,
					levelNumber = 2,
					grid = { columns = 20, rows = 6, cellSize = 4 },
				},
				main_stage_2_level_1 = {
					id = "main_stage_2_level_1",
					name = "Level 1",
					mapId = "map_main",
					stageGroupId = "main_stage_2",
					stageNumber = 2,
					levelNumber = 1,
					grid = { columns = 12, rows = 15, cellSize = 4 },
				},
				bonus_stage_1_level_1 = {
					id = "bonus_stage_1_level_1",
					name = "Level 1",
					mapId = "map_bonus",
					stageGroupId = "bonus_stage_1",
					stageNumber = 1,
					levelNumber = 1,
					grid = { columns = 100, rows = 100, cellSize = 1 },
				},
			},
		}
		local hierarchy = HierarchyOptions.build(optionsProject, "main_stage_1_level_2")
		expectEqual(
			#hierarchy.mapOptions == 2
				and hierarchy.mapOptions[1].selected
				and hierarchy.mapOptions[1].value == "main_stage_1_level_2",
			true,
			"Map selector is primary and preserves the current Level when its Map is selected"
		)
		expectEqual(
			#hierarchy.stageOptions == 2
				and hierarchy.stageOptions[1].selected
				and hierarchy.stageOptions[1].value == "main_stage_1_level_2",
			true,
			"Stage selector lists only Stages owned by the selected Map"
		)
		expectEqual(
			#hierarchy.levelOptions == 2
				and hierarchy.levelOptions[2].selected
				and hierarchy.levelOptions[2].value == "main_stage_1_level_2",
			true,
			"Level selector lists only Levels owned by the selected Stage"
		)
		expectEqual(
			hierarchy.maps[1].id == "map_main"
				and #hierarchy.maps[1].stages == 2
				and hierarchy.maps[2].id == "map_bonus"
				and #hierarchy.maps[2].stages == 1,
			true,
			"hierarchy browser data nests every Stage under exactly one Map"
		)
		local mapWorldSize =
			HierarchyOptions.mapWorldSize(optionsProject, optionsProject.stages.main_stage_1_level_2)
		expectEqual(
			mapWorldSize ~= nil and mapWorldSize.x == 80 and mapWorldSize.y == 60,
			true,
			"one Map backdrop uses stable maximum bounds across its Stages without including another Map"
		)
	end
	for _, browserContract in
		{
			"for _, mapItem in state.hierarchy.maps do",
			"for _, stageItem in mapItem.stages do",
			"for _, levelItem in stageItem.levels do",
			"config.onSelectMap(mapItem.representativeLevelId)",
			"config.onSelectStage(stageItem.representativeLevelId)",
			"config.onSelectLevel(levelId)",
		}
	do
		expectEqual(
			string.find(stagewrightHierarchyBrowserSource, browserContract, 1, true) ~= nil,
			true,
			`Stagewright hierarchy browser nests Map, Stage, and Level: {browserContract}`
		)
	end
	expectEqual(
		string.find(stagewrightMapPropertiesSource, 'textField(form, "MAP NAME", 1)', 1, true) ~= nil
			and string.find(
				stagewrightMapPropertiesSource,
				'textField(form, "BACKDROP IMAGE ASSET ID", 2)',
				1,
				true
			) ~= nil
			and string.find(
				stagewrightMapPropertiesSource,
				"Shared by every Stage and Level on this Map.",
				1,
				true
			) ~= nil
			and string.find(stagewrightMapPropertiesSource, "map.backdropImageId", 1, true) ~= nil,
		true,
		"Stagewright Map Properties owns one shared backdrop for all Stages and Levels on the Map"
	)
	local levelInspectorStart = string.find(gridPluginSource, "local stageInspector =", 1, true)
	local mapPropertiesStart = string.find(
		gridPluginSource,
		"local mapProperties = MapPropertiesView.new",
		levelInspectorStart or 1,
		true
	)
	local levelInspectorSource = if levelInspectorStart ~= nil and mapPropertiesStart ~= nil
		then string.sub(gridPluginSource, levelInspectorStart, mapPropertiesStart - 1)
		else ""
	expectEqual(
		string.find(levelInspectorSource, 'textField(stageForm, "LEVEL NAME", 1)', 1, true) ~= nil
			and string.find(levelInspectorSource, "BACKDROP", 1, true) == nil,
		true,
		"Stagewright Level Properties keeps per-Level settings but no longer owns Map artwork"
	)
	expectEqual(
		string.find(gridPluginSource, "require(script.UI.AppShell)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.HierarchyOptions)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.MapBackdrop)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.GraphToolController)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.PaintRouteDragSession)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.PaintStrokeSession)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.WorldPathController)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.PaintCellOverlay)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.PaintInspector)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.HierarchyBrowserView)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.MapPropertiesView)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.Theme)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Graph.Operations)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.WorkspacePreview)", 1, true) ~= nil,
		true,
		"Stagewright bootstrap composes dedicated controllers, UI, graph, and Workspace preview modules"
	)
	for _, forbiddenDependency in
		{ "ProjectStore", "Workspace", "UserInputService", "GraphOperations", "Instance.new" }
	do
		expectEqual(
			string.find(stagewrightWorldPathControllerSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright world-path controller stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in
		{ "game", "Instance", "ProjectStore", "UserInputService", "Brushes", "PaintAppearance" }
	do
		expectEqual(
			string.find(stagewrightPaintStrokeSessionSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright paint-stroke session stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "game", "Instance", "ProjectStore", "WorldPathView" } do
		expectEqual(
			string.find(stagewrightWorldPathEditSessionSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright world-path edit session stays independent from {forbiddenDependency}`
		)
	end
	for _, retiredPaintState in
		{
			"local painting =",
			"paintTransaction",
			"paintedKeys",
			"finishPaintTransaction",
			"RectangleColumn",
			"RectangleRow",
			"paintRuntime.legend",
			"previousBrushSize",
		}
	do
		expectEqual(
			string.find(gridPluginSource, retiredPaintState, 1, true),
			nil,
			`Stagewright bootstrap retires paint gesture state {retiredPaintState}`
		)
	end
	for _, forbiddenDependency in
		{ "game", "Instance", "ProjectStore", "UserInputService", "GraphOperations", "WorldPathView" }
	do
		expectEqual(
			string.find(stagewrightPaintRouteDragSessionSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright paint-route drag session stays independent from {forbiddenDependency}`
		)
	end
	for _, retiredRouteDragField in
		{
			"routeDraggingNodeId",
			"routeDraggingEdgeId",
			"routeDraggingHandle",
			"routeDragStartScreen",
			"routeDragMoved",
			"routeDragTransaction",
		}
	do
		expectEqual(
			string.find(gridPluginSource, retiredRouteDragField, 1, true),
			nil,
			`Stagewright bootstrap retires route gesture field {retiredRouteDragField}`
		)
	end
	for _, retiredControllerPlumbing in { "viewModule", "flowUi.dragTransaction" } do
		expectEqual(
			string.find(gridPluginSource, retiredControllerPlumbing, 1, true),
			nil,
			`Stagewright bootstrap retires duplicate controller plumbing {retiredControllerPlumbing}`
		)
	end
	for _, transactionFailureContract in
		{
			"local succeeded, result = pcall(ProjectStore.finish",
			"onMoveFailed = function()",
			"onFailed = function(action: string, phase: PaintStrokeSession.FailurePhase)",
		}
	do
		expectEqual(
			string.find(gridPluginSource, transactionFailureContract, 1, true) ~= nil,
			true,
			`Stagewright bootstrap preserves failed transaction handling through {transactionFailureContract}`
		)
	end
	expectEqual(
		string.find(
			gridPluginSource,
			"not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)",
			1,
			true
		) ~= nil,
		true,
		"Stagewright paint and route interactions stop when the primary button is no longer held"
	)
	expectEqual(
		string.find(stagewrightPaintRouteDragSessionSource, "pcall(config.finishEdit", 1, true) ~= nil,
		true,
		"Stagewright paint-route drag session contains a rejected or throwing commit"
	)
	expectEqual(
		string.find(stagewrightPaintStrokeSessionSource, "pcall(config.finishEdit", 1, true) ~= nil,
		true,
		"Stagewright paint-stroke session contains a rejected or throwing commit"
	)
	expectEqual(
		string.find(stagewrightWorkspacePreviewSource, "self.config.onMoveFailed()", 1, true) ~= nil,
		true,
		"Stagewright Workspace preview reports a rejected delayed commit"
	)
	expectEqual(
		string.find(
			stagewrightWorldPathSource
				.. stagewrightWorldPathControllerSource
				.. stagewrightGraphOperationsSource,
			"smoothEdge",
			1,
			true
		),
		nil,
		"Stagewright does not retain the unreachable world-path smoothing surface"
	)
	for _, forbiddenDependency in { "ServerStorage", "Instance.new", "GetAttributeChangedSignal(" } do
		expectEqual(
			string.find(stagewrightProjectStoreSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright project store delegates {forbiddenDependency} access to its storage adapter`
		)
	end
	for _, storageBoundaryCall in
		{
			"ProjectStorage.projectSnapshot()",
			"ProjectStorage.writeProject(",
			"ProjectStorage.refreshRelevantConnections(",
			"ProjectStorage.disconnectRelevantConnections()",
		}
	do
		expectEqual(
			string.find(stagewrightProjectStoreSource, storageBoundaryCall, 1, true) ~= nil,
			true,
			`Stagewright project store delegates through {storageBoundaryCall}`
		)
	end
	expectEqual(
		string.find(stagewrightLoadPolicySource, "StageSchema.checksumEncoded(encoded)", 1, true) ~= nil,
		true,
		"Stagewright validates stored transport bytes without reparsing floating-point values"
	)
	for _, payloadBoundaryCall in { "ProjectStorage.readPayload(", "ProjectStorage.writePayload(" } do
		expectEqual(
			string.find(gridPluginSource, payloadBoundaryCall, 1, true) ~= nil,
			true,
			`Stagewright bootstrap delegates generic payload access through {payloadBoundaryCall}`
		)
	end
	for _, exportReadbackContract in
		{
			"verifyEmbeddedPayload(",
			"expectedEncoded",
			"StagePayload.BUNDLE_FORMAT_ATTRIBUTE",
			"Bundle saved; embedded authoring/runtime verified",
		}
	do
		expectEqual(
			string.find(gridPluginSource, exportReadbackContract, 1, true) ~= nil,
			true,
			`Stagewright plugin verifies export readback through {exportReadbackContract}`
		)
	end
	expectEqual(
		string.find(gridPluginSource, "Export hash matched", 1, true),
		nil,
		"Stagewright plugin does not claim an unread export hash matched"
	)
	for _, importerReadbackContract in
		{
			"payloadFromRoots(roots, StagePayload.RUNTIME_VALUE_NAME)",
			"markedBundleFrom(authoringParent)",
			"outside the marked bundle container",
			"bundleFormat == StagePayload.BUNDLE_FORMAT",
			"embeddedRuntimePayload == canonicalRuntime",
			"Unsupported Stagewright bundle format",
			"embeddedBundleSchemaVersion",
			"Authoring-only Stagewright bundle",
		}
	do
		expectEqual(
			string.find(stagewrightImportSource, importerReadbackContract, 1, true) ~= nil,
			true,
			`Stagewright importer enforces export readback through {importerReadbackContract}`
		)
	end
	for _, bootstrapCall in
		{
			"RouteOverview.new(",
			"WorkspacePreview.new(",
			"ProjectStore.export(",
			"ProjectStore.preview(",
			"ProjectStore.createMap(",
			"ProjectStore.createStageInMap(",
			"ProjectStore.createLevel(",
			"ProjectStore.deleteMap(",
			"ProjectStore.deleteStageGroup(",
			"ProjectStore.deleteLevel(",
			"AuthoringArea.showIslandOutlines(",
		}
	do
		expectEqual(
			string.find(gridPluginSource, bootstrapCall, 1, true) ~= nil,
			true,
			`Stagewright bootstrap wires {bootstrapCall}`
		)
	end
	for _, projectStoreHierarchyContract in
		{
			"function ProjectStore.mapIds(): { string }",
			"function ProjectStore.stageGroupIds(mapId: string): { string }",
			"function ProjectStore.firstLevelId(mapId: string?, groupId: string?): string?",
			"function ProjectStore.createMap(copyFromId: string?): string",
			"function ProjectStore.createStageInMap(mapId: string, copyFromId: string?): string",
			'assert(project.maps[mapId] ~= nil, "Select a valid Map first")',
			"StageHierarchy.nextStageNumber(project.stages, mapId)",
			"function ProjectStore.createLevel(copyFromId: string): string",
			"sourceAddress.mapId",
			"function ProjectStore.deleteMap(mapId: string): (boolean, string)",
			"function ProjectStore.moveMap(mapId: string, offset: number): (boolean, string)",
		}
	do
		expectEqual(
			string.find(stagewrightProjectStoreSource, projectStoreHierarchyContract, 1, true) ~= nil,
			true,
			`Stagewright ProjectStore preserves Map-first ownership: {projectStoreHierarchyContract}`
		)
	end
	for _, hierarchySafetyContract in
		{
			"local function emptiedMapId(deleting: { [string]: boolean }): string?",
			"A Map must keep a Level; select the Map to delete it",
			"A Map must keep a Stage; select the Map to delete it",
			"local function hasSequentialUnlocks(ids: { string }): boolean",
			"Level order is locked because this Stage uses custom unlock requirements",
			"project.stages[id].unlockRequirements = if index == 1",
			'else { { kind = "StageUnlocked", stageId = reorderedIds[index - 1] } }',
			"local startingFollowedOrder = project.startingStageId == ProjectStore.stageIds()[1]",
			"project.startingStageId = ProjectStore.stageIds()[1]",
			'return false, "Level order unchanged"',
			'return false, "Stage order unchanged"',
			'return false, "Map order unchanged"',
		}
	do
		expectEqual(
			string.find(stagewrightProjectStoreSource, hierarchySafetyContract, 1, true) ~= nil,
			true,
			`Stagewright hierarchy mutations preserve progression and Map ownership: {hierarchySafetyContract}`
		)
	end
	do
		local mutateStart = assert(
			string.find(stagewrightProjectStoreSource, "function ProjectStore.mutate", 1, true),
			"ProjectStore mutation helper exists"
		)
		local mutateEnd = assert(
			string.find(stagewrightProjectStoreSource, "function ProjectStore.stageIds", mutateStart, true),
			"ProjectStore stage ordering follows its mutation helper"
		)
		local mutateSource = string.sub(stagewrightProjectStoreSource, mutateStart, mutateEnd - 1)
		local mutationChunk, mutationCompileError = luau.load(
			"return function(ProjectStore, callback)\n"
				.. mutateSource
				.. "\nreturn ProjectStore.mutate('Hierarchy action', callback)\nend"
		)
		expectEqual(
			mutationChunk ~= nil,
			true,
			`ProjectStore mutation behavior compiles independently: {tostring(mutationCompileError)}`
		)
		local runMutation = assert(mutationChunk, "ProjectStore mutation behavior chunk compiles")()
		local requestedCommit = nil
		local fakeStore = {
			begin = function(_name: string): number
				return 7
			end,
			finish = function(_transaction: number, commit: boolean): boolean
				requestedCommit = commit
				return commit
			end,
		}
		local rejected, rejectionMessage = runMutation(fakeStore, function()
			return false, "Custom unlock order cannot be changed"
		end)
		expectEqual(rejected, false, "a rejected hierarchy action does not commit")
		expectEqual(requestedCommit, false, "a rejected hierarchy action explicitly rolls back")
		expectEqual(
			rejectionMessage,
			"Custom unlock order cannot be changed",
			"a rejected hierarchy action preserves its user-facing reason"
		)
		local accepted, acceptedMessage = runMutation(fakeStore, function()
			return true, "Map reordered"
		end)
		expectEqual(accepted, true, "a successful hierarchy action commits")
		expectEqual(requestedCommit, true, "a successful hierarchy action requests commit")
		expectEqual(acceptedMessage, "Map reordered", "a successful hierarchy action preserves feedback")
	end
	do
		local deleteLevelsStart = assert(
			string.find(stagewrightProjectStoreSource, "local function deleteLevels", 1, true),
			"ProjectStore deletion helper exists"
		)
		local emptiedMapStart = assert(
			string.find(stagewrightProjectStoreSource, "local function emptiedMapId", deleteLevelsStart, true),
			"ProjectStore empty-Map guard exists"
		)
		local deleteLevelsSource =
			string.sub(stagewrightProjectStoreSource, deleteLevelsStart, emptiedMapStart - 1)
		expectEqual(
			string.find(deleteLevelsSource, "project.maps", 1, true),
			nil,
			"deleting Levels never sweeps unrelated inactive or orphan Maps"
		)
		expectEqual(
			string.find(stagewrightProjectStoreSource, "activeMapIds", 1, true),
			nil,
			"ProjectStore has no broad inactive-Map cleanup path"
		)
	end
	expectEqual(
		string.find(gridPluginSource, 'stageAction("+ Map"', 1, true) ~= nil
			and string.find(gridPluginSource, 'stageAction("+ Stage"', 1, true) ~= nil
			and string.find(gridPluginSource, 'stageAction("+ Level"', 1, true) ~= nil
			and string.find(
					gridPluginSource,
					"ProjectStore.createStageInMap(address.mapId, nil)",
					1,
					true
				)
				~= nil,
		true,
		"Stagewright hierarchy actions create a Map, a Stage inside the selected Map, or a Level inside the selected Stage"
	)
	expectEqual(
		string.find(gridPluginSource, 'if scope == "Map" then', 1, true) ~= nil
			and string.find(gridPluginSource, "ok, message = ProjectStore.deleteMap(address.mapId)", 1, true) ~= nil
			and string.find(gridPluginSource, 'elseif scope == "Stage" then', 1, true) ~= nil
			and string.find(
				gridPluginSource,
				"ok, message = ProjectStore.deleteStageGroup(address.groupId)",
				1,
				true
			) ~= nil
			and string.find(
				gridPluginSource,
				"ok, message = ProjectStore.deleteLevel(selectedStageId)",
				1,
				true
			) ~= nil
			and string.find(gridPluginSource, "return ok, message", 1, true) ~= nil
			and string.find(gridPluginSource, 'if stagePropertiesScope == "Map" then', 1, true) ~= nil
			and string.find(gridPluginSource, "return ProjectStore.moveMap(address.mapId", 1, true) ~= nil
			and string.find(gridPluginSource, "return ProjectStore.moveStageGroup(address.groupId", 1, true) ~= nil
			and string.find(gridPluginSource, "return ProjectStore.moveLevel(selectedStageId", 1, true) ~= nil
			and string.find(gridPluginSource, "local committed, message = ProjectStore.mutate", 1, true) ~= nil
			and string.find(gridPluginSource, "setStatus(message, true)", 1, true) ~= nil,
		true,
		"Stagewright hierarchy actions roll back rejected no-ops and surface their reason"
	)
	expectEqual(
		string.find(gridPluginSource, "if issue.mapId ~= nil then", 1, true) ~= nil
			and string.find(gridPluginSource, "ProjectStore.firstLevelId(issue.mapId)", 1, true) ~= nil
			and string.find(gridPluginSource, 'stagePropertiesScope = "Map"', 1, true) ~= nil,
		true,
		"Stagewright Map validation issues navigate to Map Properties"
	)
	expectEqual(
		string.find(stagewrightProjectStoreSource, "StageExport.bake(", 1, true) ~= nil,
		true,
		"Stagewright project store delegates bundle baking to StageExport"
	)
	for _, forbiddenDependency in { "ProjectStore", "AuthoringArea", "UI.Theme" } do
		expectEqual(
			string.find(stagewrightWorkspacePreviewSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright Workspace preview stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "GuiObject" } do
		expectEqual(
			string.find(stagewrightGraphSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright graph domain stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new" } do
		expectEqual(
			string.find(stagewrightGraphToolControllerSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright graph-tool controller stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new", "UI.Theme" } do
		expectEqual(
			string.find(stagewrightPaintSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright paint domain stays independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new", "UI.Theme" } do
		expectEqual(
			string.find(stagewrightStageSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright stage settings stay independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "ServerStorage", "StagePayload", "Graph.Operations" } do
		expectEqual(
			string.find(stagewrightUiSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright UI primitives stay independent from {forbiddenDependency}`
		)
	end
	for _, forbiddenDependency in { "ProjectStore", "Workspace", "TextButton", "Instance.new" } do
		expectEqual(
			string.find(stagewrightIssueModelSource, forbiddenDependency, 1, true),
			nil,
			`Stagewright validation model stays independent from {forbiddenDependency}`
		)
	end
	local gridPluginLineCount = 0
	for _ in string.gmatch(gridPluginSource, "[^\r\n]+") do
		gridPluginLineCount += 1
	end
	expectEqual(
		gridPluginLineCount <= 5030,
		true,
		"Stagewright bootstrap does not absorb extracted module code"
	)
	for _, removedLegacySurface in
		{
			"GraphToolMode",
			"graphActionPages",
			"GraphMiniPreviewCanvas",
			"GraphLevelStrip",
			"GraphInspectorDock",
			'"Perspective"',
			'"Snap"',
		}
	do
		expectEqual(
			string.find(gridPluginSource, removedLegacySurface, 1, true),
			nil,
			`Stagewright bootstrap does not recreate dead legacy control {removedLegacySurface}`
		)
	end
	for _, behavior in
		{
			"connectionFromNodeId",
			"connectNodes",
			"outputPort",
			"positionEdgeLine",
			"beginConnection",
			"setObstructions",
			"safeWindowSize",
			"topologySignature",
			"curveProjection",
			"projectOffset",
			"unprojectOffset",
			"beginHandleDrag",
			"HANDLE_DRAG_THRESHOLD",
			"edge.outHandleOffset",
			"edge.inHandleOffset",
			"callbacks.moveHandle",
			'if self.tool == "Select"',
			'if self.tool == "Connect"',
			'if self.tool == "Split"',
			"destinationDistance",
			"suppressNodeActivationId",
		}
	do
		expectEqual(
			string.find(stagewrightRouteOverviewSource, behavior, 1, true) ~= nil,
			true,
			`Stagewright route logic view includes {behavior}`
		)
	end
	for _, behavior in
		{
			"StagePathAssets",
			"ViewportFrame",
			"worldSource",
			"worldOrigin",
			"backdropDirty",
			"backdropDirtyAt",
			"backdropRefreshScheduled",
			"BACKDROP_VISUAL_PROPERTIES",
			"isLegacyBackdropDescendant",
			"CLICK_DRAG_THRESHOLD",
			"Lane centerline",
			"Selected spline",
			"Test segment",
			"Drag cyan handles to shape",
			"setLanes",
			"require(script.Parent.Interaction.HitTest)",
			"require(script.Parent.Interaction.PointerDrag)",
			"HitTest.resolveAll",
			"HitTest.cycleNode",
			"PointerDrag.press",
			"PointerDrag.move",
			"PointerDrag.release",
			"PointerDrag.cancel",
			"seedDragValue",
			"GetRelativeMousePosition",
			"UserInputState",
			"DRAG_RENDER_INTERVAL",
			"liveEdgeSamples",
			"setTool",
			"AddSpawn",
			"SHORT_INSPECTOR_HEIGHT",
			"COLLAPSED_INSPECTOR_HEIGHT",
			"inspectorExpanded",
			"backdropCamera.Parent",
			'area = "Marker"',
			'area = "Label"',
			'if self.tool == "Connect"',
			'if self.tool == "Split"',
			"LEGACY_PATH_FOLDERS",
		}
	do
		expectEqual(
			string.find(stagewrightWorldPathSource, behavior, 1, true) ~= nil,
			true,
			`Stagewright world path view includes {behavior}`
		)
	end
	expectEqual(
		string.find(stagewrightWorldPathSource, "if self.backdropRefreshScheduled then", 1, true) ~= nil
			and string.find(
				stagewrightWorldPathSource,
				"BACKDROP_REFRESH_DELAY - (os.clock() - self.backdropDirtyAt)",
				1,
				true
			) ~= nil
			and string.find(stagewrightWorldPathSource, "BACKDROP_VISUAL_PROPERTIES[propertyName]", 1, true) ~= nil
			and string.find(
					stagewrightWorldPathSource,
					"shouldObserveBackdrop(descendant, source)",
					1,
					true
				)
				~= nil,
		true,
		"Stagewright world backdrop coalesces trailing refreshes and ignores non-visual changes"
	)
	for _, graphToolBehavior in
		{
			"GraphOperations.canConnect",
			"GraphOperations.connect",
			"GraphOperations.splitEdge",
			"sourceNodeId",
			"setSourceNodeId",
			"finishTool",
		}
	do
		expectEqual(
			string.find(stagewrightGraphToolControllerSource, graphToolBehavior, 1, true) ~= nil,
			true,
			`Stagewright graph-tool controller preserves {graphToolBehavior}`
		)
	end
	expectEqual(
		string.find(stagewrightWorkspacePreviewSource, "LocalTransparencyModifier", 1, true) ~= nil
			and string.find(stagewrightWorkspacePreviewSource, "PathPoints", 1, true) ~= nil
			and string.find(stagewrightWorkspacePreviewSource, "PathTiles", 1, true) ~= nil
			and string.find(stagewrightWorkspacePreviewSource, "restoreLegacyPathArtifacts", 1, true)
				~= nil,
		true,
		"Stagewright hides legacy path helpers reversibly while the Studio preview is active"
	)
	do
		local cleanupStart = string.find(
			stagewrightAuthoringAreaSource,
			"local function legacyGridNpc(candidate: Instance?): Model?",
			1,
			true
		)
		local cleanupEnd = if cleanupStart ~= nil
			then string.find(
				stagewrightAuthoringAreaSource,
				"function AuthoringArea.ensure",
				cleanupStart,
				true
			)
			else nil
		local cleanupSource = if cleanupStart ~= nil and cleanupEnd ~= nil
			then string.sub(stagewrightAuthoringAreaSource, cleanupStart, cleanupEnd - 1)
			else ""
		for _, cleanupMarker in
			{
				'candidate.Name ~= "GridNpc"',
				'local requiredParts = { "Root", "Body", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }',
				"#candidate:GetChildren() ~= #requiredParts",
				'not part:IsA("BasePart") or not part.Anchored or part.CanCollide',
				"root.Transparency == 1 and not root.CanQuery and not root.CanTouch",
				'ServerScriptService:FindFirstChild("GridNpcDemo")',
				"candidate.Source",
				'"WALK_SPEED_STUDS_PER_SECOND"',
				'"StagePath.sample"',
				'Workspace:FindFirstChild("FirstPrivateIsland")',
				"function AuthoringArea.removeLegacyArtifacts(existingRecording: boolean?): number",
				"root:FindFirstChild(templateConfig.towerDefense.platformModelName)",
				'"PathPoints"',
				'"PathTiles"',
				"platform:FindFirstChild(name)",
				'"GridOverlay"',
				'base:FindFirstChild("GridOverlay")',
				"add(legacyGridNpc(",
				"add(legacyGridNpcScript())",
				"if existingRecording ~= true then",
				"candidate:Destroy()",
			}
		do
			expectEqual(
				string.find(cleanupSource, cleanupMarker, 1, true) ~= nil,
				true,
				`Stagewright permanent legacy cleanup includes {cleanupMarker}`
			)
		end
		expectEqual(
			string.find(cleanupSource, "root:GetDescendants()", 1, true) == nil
				and string.find(cleanupSource, "ServerScriptService:GetDescendants()", 1, true) == nil,
			true,
			"Stagewright cleanup only inspects direct known legacy locations"
		)
		local recordingGuardPosition =
			string.find(cleanupSource, "if existingRecording ~= true then", 1, true)
		local recordingBeginPosition =
			string.find(cleanupSource, "ChangeHistoryService:TryBeginRecording", 1, true)
		local recordingUnavailablePosition = string.find(cleanupSource, "if recording == nil then", 1, true)
		local destructionPosition = string.find(cleanupSource, "candidate:Destroy()", 1, true)
		expectEqual(
			recordingGuardPosition ~= nil
				and recordingBeginPosition ~= nil
				and recordingUnavailablePosition ~= nil
				and destructionPosition ~= nil
				and recordingGuardPosition < recordingBeginPosition
				and recordingBeginPosition < recordingUnavailablePosition
				and recordingUnavailablePosition < destructionPosition,
			true,
			"Stagewright defers permanent cleanup when Studio cannot create an undo recording"
		)

		local loadedPlanStart =
			string.find(stagewrightProjectStoreSource, "local function applyLoadedPlan", 1, true)
		local loadStart = if loadedPlanStart ~= nil
			then string.find(
				stagewrightProjectStoreSource,
				"function ProjectStore.load",
				loadedPlanStart,
				true
			)
			else nil
		local loadedPlanSource = if loadedPlanStart ~= nil and loadStart ~= nil
			then string.sub(stagewrightProjectStoreSource, loadedPlanStart, loadStart - 1)
			else ""
		local normalizedPosition = string.find(loadedPlanSource, "if not normalizeSuccess", 1, true)
		local loadedCleanupPosition =
			string.find(loadedPlanSource, "AuthoringArea.removeLegacyArtifacts()", 1, true)
		local saveStart = string.find(stagewrightProjectStoreSource, "local function saveUnchecked", 1, true)
		local publicSaveStart = if saveStart ~= nil
			then string.find(stagewrightProjectStoreSource, "function ProjectStore.save", saveStart, true)
			else nil
		local saveSource = if saveStart ~= nil and publicSaveStart ~= nil
			then string.sub(stagewrightProjectStoreSource, saveStart, publicSaveStart - 1)
			else ""
		local storageWritePosition = string.find(saveSource, "ProjectStorage.writeProject", 1, true)
		local savedCleanupPosition =
			string.find(saveSource, "AuthoringArea.removeLegacyArtifacts(existingRecording)", 1, true)
		expectEqual(
			normalizedPosition ~= nil
				and loadedCleanupPosition ~= nil
				and normalizedPosition < loadedCleanupPosition
				and storageWritePosition ~= nil
				and savedCleanupPosition ~= nil
				and storageWritePosition < savedCleanupPosition,
			true,
			"Stagewright removes legacy scene artifacts only after a valid load or successful canonical save"
		)
		local _, existingRecordingSaveCount =
			string.gsub(stagewrightProjectStoreSource, "pcall%(saveUnchecked, true%)", "")
		expectEqual(
			string.find(
				saveSource,
				"local function saveUnchecked(existingRecording: boolean?): string",
				1,
				true
			)
					~= nil
				and existingRecordingSaveCount == 2,
			true,
			"Stagewright transaction and import saves reuse their active undo recording during cleanup"
		)
	end
	expectEqual(
		string.find(
			stagewrightWorkspacePreviewSource,
			"function Controller.destroy(self: Controller)\n\tself.enabled = false\n\tself:cancelInteraction()\n\tself:clear()\n\tself.lastState = nil\nend",
			1,
			true
		) ~= nil,
		true,
		"Stagewright Workspace preview teardown restores legacy helpers even when preview is already disabled"
	)
	for _, graphBehavior in
		{
			"Operations.canConnect",
			"Operations.setHandleOffset",
			"Operations.canDeleteNode",
			"constrainedOpposite",
			"authoredShoulder",
			"cloneValue",
		}
	do
		expectEqual(
			string.find(stagewrightGraphOperationsSource, graphBehavior, 1, true) ~= nil,
			true,
			`Stagewright graph operations preserve functional behavior through {graphBehavior}`
		)
	end
	for _, responsiveBootstrapBehavior in
		{
			"stackedActions",
			"GraphToolController.new",
			"graphTools:activateNode",
			"graphTools:splitEdge",
			"flowUi.activateTool",
			"GraphOperations.setLaneWidth",
			"GraphOperations.setPriority",
			"Shape Stagewright route logic spline",
		}
	do
		expectEqual(
			string.find(gridPluginSource, responsiveBootstrapBehavior, 1, true) ~= nil,
			true,
			`Stagewright bootstrap wires responsive behavior through {responsiveBootstrapBehavior}`
		)
	end
	for _, transformBehavior in
		{
			"require(script.Parent.Interaction.CanvasTransform)",
			"CanvasTransform.worldToCanvas",
			"CanvasTransform.canvasToWorld",
			"CanvasTransform.zoomAt",
			"CanvasTransform.pan",
			"fitToView",
		}
	do
		expectEqual(
			string.find(stagewrightWorldPathSource, transformBehavior, 1, true) ~= nil,
			true,
			`Stagewright world path uses the shared uniform transform for {transformBehavior}`
		)
	end
	for _, retiredTransformField in { "mapTopLeft", "mapScale" } do
		expectEqual(
			string.find(stagewrightWorldPathSource, retiredTransformField, 1, true),
			nil,
			`Stagewright world path retires duplicate transform field {retiredTransformField}`
		)
	end
	for _, retiredPointerPlumbing in
		{
			"lineButton",
			"dragKind",
			"dragId",
			"dragHandle",
			"dragStartScreen",
			"dragMoved",
			"IsMouseButtonPressed",
		}
	do
		expectEqual(
			string.find(stagewrightWorldPathSource, retiredPointerPlumbing, 1, true),
			nil,
			`Stagewright world path retires duplicate pointer plumbing {retiredPointerPlumbing}`
		)
	end
	for _, navigationSafety in
		{
			'current:IsA("LayerCollector") and not current.Enabled',
			"PointerDrag.isActive(self.pointerState)",
			"self.panLastScreen ~= nil",
			"canvasPosition.X < 0",
			"for _, blocker in self.hitBlockers do",
			"self.callbacks.cancelInteraction()",
			"canvas.Position = UDim2.new(",
			"visibleDepth = math.max(worldHeight, worldWidth / aspect)",
			"SHORT_INSPECTOR_HEIGHT",
		}
	do
		expectEqual(
			string.find(stagewrightWorldPathSource, navigationSafety, 1, true) ~= nil,
			true,
			`Stagewright world navigation includes {navigationSafety}`
		)
	end
	expectEqual(
		string.find(stagewrightWorldPathSource, "boundsSize.Z * 1.08", 1, true),
		nil,
		"Stagewright backdrop no longer uses a coordinate system independent from the grid"
	)
	for _, cancellationMarker in
		{
			"cancelActiveEditorInteraction",
			"Enum.KeyCode.Escape",
			"widget.WindowFocusReleased:Connect",
			"UserInputService.WindowFocusReleased:Connect",
			"plugin.Unloading:Connect",
		}
	do
		expectEqual(
			string.find(gridPluginSource, cancellationMarker, 1, true) ~= nil,
			true,
			`Stagewright central cancellation covers {cancellationMarker}`
		)
	end
	expectEqual(
		string.find(
			gridPluginSource .. stagewrightWorkspacePreviewSource .. stagewrightWorldPathSource,
			"RouteCell_",
			1,
			true
		),
		nil,
		"Stagewright no longer floods every route-reserved cell with a cyan preview part"
	)
	local workspacePreviewConstructorStart =
		string.find(stagewrightWorkspacePreviewSource, "function WorkspacePreview.new", 1, true)
	local workspacePreviewConstructorEnd = if workspacePreviewConstructorStart ~= nil
		then string.find(
			stagewrightWorkspacePreviewSource,
			"return WorkspacePreview",
			workspacePreviewConstructorStart,
			true
		)
		else nil
	local workspacePreviewConstructor = if workspacePreviewConstructorStart ~= nil
			and workspacePreviewConstructorEnd ~= nil
		then string.sub(
			stagewrightWorkspacePreviewSource,
			workspacePreviewConstructorStart,
			workspacePreviewConstructorEnd - 1
		)
		else ""
	expectEqual(
		string.find(gridPluginSource, "workspacePreviewEnabled", 1, true) == nil
			and string.find(workspacePreviewConstructor, "enabled = false", 1, true) ~= nil,
		true,
		"Stagewright Workspace preview defaults off in its constructor"
	)
	for _, workspacePreviewWiring in
		{
			"local workspacePreview = WorkspacePreview.new({",
			'toggleAction("In Studio"',
			"workspacePreview:setEnabled(requested)",
			"renderWorkspacePreview()",
			"workspacePreview:cancelInteraction()",
			"workspacePreview:clear()",
			"workspacePreview:destroy()",
		}
	do
		expectEqual(
			string.find(gridPluginSource, workspacePreviewWiring, 1, true) ~= nil,
			true,
			`Stagewright bootstrap wires Workspace preview through {workspacePreviewWiring}`
		)
	end
	expectEqual(
		string.find(stagewrightProjectStoreSource, "if recording ~= nil then\n\t\treturn nil", 1, true) ~= nil
			and string.find(
				stagewrightProjectStoreSource,
				"if transaction ~= activeTransaction then",
				1,
				true
			) ~= nil
			and string.find(stagewrightWorkspacePreviewSource, "moveTransaction: MoveTransaction?", 1, true) ~= nil
			and string.find(gridPluginSource, "dragRecording", 1, true) == nil,
		true,
		"Stagewright recordings reject foreign begins and require the owning transaction to finish"
	)
	for _, ownerlessFinish in
		{ "ProjectStore.finish(true)", "ProjectStore.finish(false)", "ProjectStore.finish(commit)" }
	do
		expectEqual(
			string.find(gridPluginSource, ownerlessFinish, 1, true),
			nil,
			`Stagewright bootstrap does not use ownerless recording finish {ownerlessFinish}`
		)
	end
	do
		local writePayloadStart =
			string.find(stagewrightStorageSource, "function ProjectStorage.writePayload", 1, true)
		local writePayloadEnd = if writePayloadStart ~= nil
			then string.find(
				stagewrightStorageSource,
				"function ProjectStorage.readPayload",
				writePayloadStart,
				true
			)
			else nil
		local writePayloadSource = if writePayloadStart ~= nil and writePayloadEnd ~= nil
			then string.sub(stagewrightStorageSource, writePayloadStart, writePayloadEnd - 1)
			else ""
		local manifestPosition =
			string.find(writePayloadSource, "local manifest = StagePayload.manifest", 1, true)
		local mutationPosition = string.find(writePayloadSource, "local value = ensureStringValue", 1, true)
		expectEqual(
			manifestPosition ~= nil and mutationPosition ~= nil and manifestPosition < mutationPosition,
			true,
			"Stagewright validates payload size before mutating saved Instances"
		)
	end
	expectCompiles(stagewrightAuthoringAreaSource, "Stagewright admin authoring area compiles as Luau")
	local stagewrightCapabilitySource = gridPluginProject
		.. gridPluginSource
		.. stagewrightProjectStoreSource
		.. stagewrightAuthoringAreaSource
		.. stagewrightWorkspacePreviewSource
		.. stagewrightUiSource
		.. stagewrightGraphSource
		.. stagewrightPaintSource
		.. stagewrightStageSource
		.. stagewrightIssueModelSource
		.. templateConfigSource
	for _, capabilityMarker in
		{
			"PromptSaveSelectionAsync",
			"plugin.Unloading",
			"TryBeginRecording",
			"FinishRecording",
			"StagewrightTransientPreview",
			"+ Stage",
			"+ Level",
			"Apply changes",
			"Delete spline",
			"Add Junction",
			"Paint cells",
			"Edit enemy route",
			"Play Trace",
			"In Studio",
			"Export bundle",
			"Focus authoring area",
			"Guides",
			"showIslandOutlines",
			"StagewrightIslandOutlinePreview",
			"Brush 1 x 1",
			"SHIFT TO PAINT",
			"World Path",
			"Route Logic",
			"RouteConflict_",
			"StagewrightPathAsset",
			"Enum.Material.Pebble",
		}
	do
		expectEqual(
			string.find(stagewrightCapabilitySource, capabilityMarker, 1, true) ~= nil,
			true,
			`edit-mode grid plugin includes {capabilityMarker}`
		)
	end
	for _, obsoleteToolbarGlyph in { "⌁", "▦", "✋", "⊕", "⌘", "↖" } do
		expectEqual(
			string.find(gridPluginSource .. stagewrightUiSource, obsoleteToolbarGlyph, 1, true),
			nil,
			`Stagewright toolbar no longer depends on the {obsoleteToolbarGlyph} text glyph`
		)
	end
	expectEqual(
		string.find(gridPluginSource, "UDim2.fromOffset(414, 23)", 1, true),
		nil,
		"Stagewright level settings no longer depend on the clipped fixed-width form"
	)
	for _, removedPluginObject in
		{
			"DEFAULT_STAGE_PROFILES",
			"catmullRomPosition",
			"PATH_GRID_RADIUS",
			"Runtime: any",
		}
	do
		expectEqual(
			string.find(gridPluginSource, removedPluginObject, 1, true),
			nil,
			`edit-mode grid plugin no longer uses separate {removedPluginObject} targeting`
		)
	end
	expectEqual(
		string.find(stagewrightAuthoringAreaSource, "CenterFacingGuide", 1, true),
		nil,
		"edit-mode island guides no longer draw a misleading orientation bar"
	)
end
local runePluginProject = fs.readFile("plugins/rune-config-editor.project.json")
local runePluginSource = fs.readFile("src/plugins/RunewrightPlugin.server.luau")
for _, runePluginObject in
	{
		"RunewrightPlugin",
		"RunewrightPlugin.server.luau",
		"Runewright",
		"RunewrightPanel",
		"Rune altar workbench",
		"plugin:CreateToolbar",
		"CreateDockWidgetPluginGuiAsync",
		"DockWidgetPluginGuiInfo",
		"TryBeginRecording",
		"FinishRecording",
		"Apply to Place",
		"Print Sources",
		"Normalize Weights to 10000",
		"must equal exactly 10000",
		"needs at least one rune",
		"DesignerConfig",
		"RuneCatalog",
		"TemplateConfig",
		"channelModes",
		"copyMilestones",
		"defaultChannelMode",
		"pityMinimumRarity",
		"rareAudioMinimumRarity",
		"baseCost",
		"tickSeconds",
		"minCommonWeight",
		"unlockKind",
		"tiers",
		"bonusPercent",
		"glyph",
		"flavor",
		"Fix first:",
		"Add Rune Card",
		"Remove Card",
		-- Tabbed workbench UX contract: tab navigation, live validation with
		-- per-tab issue tags, visible pill pickers, entry-time range hints,
		-- reload recovery, and confirmed destructive actions.
		"selectTab",
		"optionPills",
		"Refresh.validation",
		"Ready to apply",
		"issue.tab",
		"rangeText",
		"Reload from Place",
		"Confirm remove?",
		"Discard edits?",
		-- Professional control taxonomy: segmented pickers for exclusive
		-- choices, a real toggle switch for mode enablement, hex color entry,
		-- and the live weight-distribution bar on the Rarity tab.
		"segmentedControl",
		"toggleSwitch",
		"parseHexColor",
		"OddsBar",
		-- Glyphs accept a Roblox image asset id (5-16 digits) as well as an
		-- emoji; the card cell previews the actual image via the same rule
		-- RuneLogic.glyphImage applies at runtime.
		"glyphImageId",
		"GlyphPreview",
		-- Tier and milestone editors hold everything the runtime accepts
		-- (RuneModeConfig.MAX_TIERS / MAX_MILESTONES), so loading a place
		-- never silently truncates authored rows.
		"local TIER_ROWS = 8",
		"local MILESTONE_ROWS = 8",
	}
do
	expectEqual(
		string.find(runePluginProject .. runePluginSource, runePluginObject, 1, true) ~= nil,
		true,
		`rune workbench plugin includes {runePluginObject}`
	)
end
-- The workbench edits the open place only; it must never touch live services
-- or publish anything. The blind cycle buttons stay retired: fixed choices
-- render as visible pill pickers instead.
for _, forbiddenPluginCall in
	{ "PolicyService", "DataStoreService", "HttpService", "PublishAsync", "cycleField" }
do
	expectEqual(
		string.find(runePluginSource, forbiddenPluginCall, 1, true),
		nil,
		`rune workbench plugin never references {forbiddenPluginCall}`
	)
end
local runePluginCheck = fs.readFile("scripts/check.ps1")
expectEqual(
	string.find(runePluginCheck, "rune-config-editor.project.json", 1, true) ~= nil,
	true,
	"check.ps1 builds the Runewright plugin package"
)
expectEqual(
	fs.isFile("src/starter/GridNpcDemo.server.luau"),
	false,
	"the unreachable duplicate grid NPC Heartbeat presenter stays retired"
)
local generatedStageCatalog = fs.readFile("src/shared/StageCatalog.generated.luau")
expectEqual(
	string.find(generatedStageCatalog, '"graph_main"', 1, true),
	nil,
	"the retired NPC demo graph is absent from the current runtime catalog"
)
expectEqual(
	string.find(generatedStageCatalog, '"edge_main"', 1, true),
	nil,
	"the retired NPC demo edge is absent from the current runtime catalog"
)
do
	local jsonStartMarker = "[====["
	local jsonEndMarker = "]====]"
	local jsonStartAt = assert(
		string.find(generatedStageCatalog, jsonStartMarker, 1, true),
		"generated RNG Defender catalog JSON starts"
	)
	local jsonEndAt = assert(
		string.find(generatedStageCatalog, jsonEndMarker, jsonStartAt + #jsonStartMarker, true),
		"generated RNG Defender catalog JSON ends"
	)
	local productionCatalog: any =
		serde.decode("json", string.sub(generatedStageCatalog, jsonStartAt + #jsonStartMarker, jsonEndAt - 1))
	for _, stageId in productionCatalog.stageOrder do
		local grid = productionCatalog.stages[stageId].grid
		expectEqual(
			grid.columns == 32 and grid.rows == 27 and grid.cellSize == 4,
			true,
			`RNG Defender production level {stageId} remains 32x27 at 4 studs per cell`
		)
	end
end
expectEqual(
	string.find(compactConnectedUi, '"AnchorPoint":[0.5,1]', 1, true) ~= nil,
	true,
	"connected UI uses a compact bottom navigation dock"
)
expectEqual(
	string.find(compactConnectedUi, '"Text":"TOP"', 1, true),
	nil,
	"secondary actions are not crowded into the main navigation"
)

local screenCopy = fs.readFile("src/client/UI/Screens.luau")
for _, authoredObject in
	{
		'"Name":"InventoryScreen"',
		'"Name":"StoreScreen"',
		'"Name":"RewardsScreen"',
		'"Name":"ProfileScreen"',
		'"Name":"SettingsScreen"',
		'"Name":"ItemSlot12"',
		'"Name":"StoreSlot08"',
		'"Name":"Day7"',
		'"Name":"LeaderRow10"',
		'"Name":"ListRow50"',
	}
do
	expectEqual(
		string.find(compactConnectedUi, authoredObject, 1, true) ~= nil,
		true,
		`connected UI pre-authors {authoredObject}`
	)
end
for _, forbiddenConstructor in { "Instance.new", ":Clone(", ":Destroy(" } do
	expectEqual(
		string.find(screenCopy, forbiddenConstructor, 1, true),
		nil,
		`screen binder does not use {forbiddenConstructor}`
	)
end
for _, developerFacingCopy in { "Project defaults", "Verification is scaffolded", "Discord" } do
	expectEqual(
		string.find(screenCopy, developerFacingCopy, 1, true),
		nil,
		`player UI hides developer wording: {developerFacingCopy}`
	)
end

local audioConfig = fs.readFile("src/shared/TemplateConfig.luau")
for _, audioId in { "12221967", "12222054", "12222253", "12222170", "12222200", "12221976", "12222076" } do
	expectEqual(
		string.find(audioConfig, audioId, 1, true) ~= nil,
		true,
		`audio config includes selected public sound {audioId}`
	)
end

local audioController = fs.readFile("src/client/Controllers/AudioController.luau")
for _, modernAudioObject in
	{ 'Instance.new("AudioPlayer")', 'Instance.new("AudioDeviceOutput")', 'Instance.new("Wire")' }
do
	expectEqual(
		string.find(audioController, modernAudioObject, 1, true) ~= nil,
		true,
		`audio controller uses {modernAudioObject}`
	)
end
for _, legacyAudioObject in { 'Instance.new("Sound")', 'Instance.new("SoundGroup")' } do
	expectEqual(
		string.find(audioController, legacyAudioObject, 1, true),
		nil,
		`audio controller avoids discouraged {legacyAudioObject}`
	)
end
expectEqual(
	string.find(audioController, "player.Asset = ", 1, true) ~= nil,
	true,
	"audio controller assigns the public, documented AudioPlayer.Asset property"
)
expectEqual(
	string.find(audioController, "AudioContent", 1, true),
	nil,
	"audio controller avoids the Hidden AudioPlayer.AudioContent property"
)

local initClient = fs.readFile("src/client/init.client.luau")
for _, silentBackgroundCall in { 'query("InitialState", {}, "")', 'request("AfkRollover", {}, "")' } do
	expectEqual(
		string.find(initClient, silentBackgroundCall, 1, true) ~= nil,
		true,
		`background polling and AFK rollover stay silent: {silentBackgroundCall}`
	)
end
for _, currencyBindingMarker in
	{
		'currencyTray.Visible = primaryId ~= ""',
		'type(rawBalance) == "number"',
		"elseif definition.id == primaryId then nextPrimary",
		'type(definition.iconAssetId) == "string"',
	}
do
	expectEqual(
		string.find(initClient, currencyBindingMarker, 1, true) ~= nil,
		true,
		`currency controller preserves saved primary balances and safe icon fallback: {currencyBindingMarker}`
	)
end

local responsiveController = fs.readFile("src/client/Controllers/ResponsiveController.luau")
for _, requiredMarker in
	{
		"clampNavigation",
		"clampModalsAgainstHud",
		"findSizeConstraint",
		"collectModalRoots",
		"originalMaxSize",
		"updateHudVisibility",
		"modalNeedsHudHidden",
		"safeWidthRaw",
		"applyLeftIconRailLayout",
		"hudRequiresModalClearance",
	}
do
	expectEqual(
		string.find(responsiveController, requiredMarker, 1, true) ~= nil,
		true,
		`responsive controller clamps overflow/overlap on short viewports: {requiredMarker}`
	)
end
expectEqual(
	string.find(responsiveController, "WIDE_SCALE", 1, true) == nil
		and string.find(responsiveController, "return COMPACT_SCALE", 1, true) ~= nil,
	true,
	"responsive controller never auto-enlarges edge-anchored HUD beyond the live viewport"
)

local figmaBridge = fs.readFile("figma/roblox-ui-bridge/code.js")
expectEqual(
	string.find(figmaBridge, "if (!isText)", 1, true),
	nil,
	"Figma bridge does not treat TextButton as a leaf and discard authored icon children"
)
expectEqual(
	string.find(figmaBridge, "for (const child of namedChildren(object))", 1, true) ~= nil,
	true,
	"Figma bridge recursively imports named children for every supported GUI class"
)
expectEqual(
	string.find(figmaBridge, 'entry.cornerRadius = typeof node.cornerRadius === "number"', 1, true) ~= nil,
	true,
	"Figma bridge exports corner styling for TextButtons as well as non-text controls"
)
expectEqual(
	string.find(figmaBridge, 'String(className).startsWith("Image") ? null : solidPaint(node)', 1, true)
		~= nil,
	true,
	"Figma bridge does not export synthetic image-placeholder fills"
)
local figmaPatchApplier = fs.readFile("scripts/figma-ui-bridge.mjs")
expectEqual(
	string.find(figmaPatchApplier, '!String(node.ClassName).startsWith("Image")', 1, true) ~= nil,
	true,
	"Figma patch applier rejects image-placeholder fills from older patches"
)
expectEqual(
	string.find(figmaPatchApplier, "reconcileSourceOnlyLayout", 1, true) ~= nil
		and string.find(figmaPatchApplier, 'layoutNode.ClassName = "UIListLayout"', 1, true) ~= nil,
	true,
	"Figma patch applier keeps Roblox-only constraints and layouts aligned with imported visuals"
)
expectEqual(
	string.find(figmaPatchApplier, "pruneToAuthoritativeEntries", 1, true) ~= nil
		and string.find(figmaPatchApplier, "parent.Children.push(node)", 1, true) ~= nil
		and string.find(figmaPatchApplier, "node.ClassName = entry.className", 1, true) ~= nil,
	true,
	"Figma patch application is an authoritative create/update/delete upsert"
)

-- StoreScreen's header was 60 tall while its own Body label already
-- reserved 92px (Title + wrapped 2-line Body); found via mechanical
-- rendering at phone width, where the description wraps and visibly
-- spills out of the yellow header. Fixed to 100 tall with ProductsGrid and
-- CanvasSize shifted to match; the licensed ShowcaseCanvas duplicate
-- (ZIndex 192) is intentionally left untouched, same as every other
-- restyle pass in this file.
expectEqual(
	string.find(
		compactConnectedUi,
		'"LayoutOrder":1,"Size":{"UDim2":[[1,0],[0,100]]},"Visible":true,"ZIndex":42,',
		1,
		true
	) ~= nil,
	true,
	"real StoreHeader grows to fit its own wrapped 2-line Body label"
)
expectEqual(
	string.find(
		compactConnectedUi,
		'"Position":{"UDim2":[[0,0],[0,112]]},"Size":{"UDim2":[[1,0],[0,1024]]},"ZIndex":41',
		1,
		true
	) ~= nil,
	true,
	"ProductsGrid shifts down to match the taller StoreHeader"
)

-- Tower defense: unit collection, loadout ranking, grid cell roles, and wave scaling.
expectEqual(TowerDefenseLogic.isBuildableCell("."), true, "normal grid cells are buildable for units")
expectEqual(TowerDefenseLogic.isBuildableCell("A"), true, "auto-place grid cells are buildable for units")
expectEqual(
	TowerDefenseLogic.isPortalCell("P") and TowerDefenseLogic.isBlockedCell("P"),
	true,
	"portal grid cells spawn enemies and block unit placement"
)
expectEqual(
	TowerDefenseLogic.isGoalCell("G") and TowerDefenseLogic.isBlockedCell("G"),
	true,
	"goal grid cells end enemy paths and block unit placement"
)
expectEqual(
	TowerDefenseLogic.pickWeightedUnitIndex(TowerDefenseCatalog.units, 0) >= 1,
	true,
	"unit rolls pick a catalog entry at the lower bound"
)
expectEqual(
	TowerDefenseLogic.pickWeightedUnitIndex(TowerDefenseCatalog.units, 0.9999) <= #TowerDefenseCatalog.units,
	true,
	"unit rolls pick a catalog entry at the upper bound"
)
for _, unit in TowerDefenseCatalog.units do
	expectEqual(
		type(unit.backgroundColor) == "table"
			and type(unit.accentColor) == "table"
			and type(unit.iconAssetId) == "string"
			and type(unit.iconGlyph) == "string",
		true,
		`tower unit {unit.id} carries editable slot presentation data`
	)
end
local bestTowerLoadout = TowerDefenseLogic.bestLoadout({
	forest_archer = { count = 1 },
	mushroom_bomber = { count = 1 },
	ancient_treant = { count = 1 },
}, TowerDefenseCatalog.units, 2)
expectEqual(bestTowerLoadout[1], "ancient_treant", "equip best favors the strongest owned unit")
expectEqual(#bestTowerLoadout, 2, "equip best respects loadout slot cap")
do
	local duplicateTowerLoadout = TowerDefenseLogic.bestLoadout({
		forest_archer = { count = 1 },
		mushroom_bomber = { count = 1 },
		ancient_treant = { count = 2 },
	}, TowerDefenseCatalog.units, 3)
	expectEqual(
		duplicateTowerLoadout[1] == "ancient_treant"
			and duplicateTowerLoadout[2] == "ancient_treant"
			and duplicateTowerLoadout[3] == "mushroom_bomber",
		true,
		"equip best fills separate slots with every owned copy in strength order"
	)
end
expectEqual(TowerDefenseLogic.waveScale(1), 1, "first tower defense wave uses base scale")
expectEqual(TowerDefenseLogic.waveScale(5) > 1, true, "later tower defense waves scale up")
expectEqual(
	TowerDefenseLogic.waveScale(5),
	TowerDefenseLogic.waveScale(5, 4),
	"wave scaling defaults to the legacy four-wave loop"
)
expectEqual(TowerDefenseLogic.waveScale(6, 6), 1, "wave scaling adapts to the authored wave-set length")
expectEqual(TowerDefenseLogic.waveScale(7, 6) > 1, true, "authored wave sets scale after a full loop")

-- Wave scheduling: authored waves expand into per-entry spawn streams.
do
	local TowerDefenseWaves = require("../src/shared/TowerDefenseWaves")
	local defaultSet = StageWaveDefaults.defaultWaveSet()
	local firstWave, waveCount = TowerDefenseWaves.waveForIndex(defaultSet, 1)
	expectEqual(waveCount, #defaultSet.waves, "wave lookup reports the authored set length")
	expectEqual(firstWave.entries[1].enemyTypeId, "forest_grunt", "wave one sends the starter grunt")
	local bossSet = StageStarterProject.playtestWaveSets()[StageStarterProject.BOSS_WAVE_SET_ID]
	local requestedBossWave, bossWaveCount = TowerDefenseWaves.waveForIndex(bossSet, 3)
	local requestedBossStreams = TowerDefenseWaves.buildStreams(requestedBossWave, 50, 1)
	expectEqual(
		bossWaveCount == 3
			and requestedBossWave.isBoss == true
			and #requestedBossStreams == 3
			and requestedBossStreams[1].enemyTypeId == "forest_grunt"
			and requestedBossStreams[2].enemyTypeId == "grove_titan"
			and requestedBossStreams[2].nextSpawnAt == 52
			and requestedBossStreams[3].enemyTypeId == "forest_runner"
			and requestedBossStreams[3].nextSpawnAt == 53,
		true,
		"requesting boss wave 3 schedules its exact authored concurrent and delayed streams"
	)
	local loopedWave = TowerDefenseWaves.waveForIndex(defaultSet, #defaultSet.waves + 1)
	expectEqual(
		StageSchema.encodeCanonical(loopedWave :: any),
		StageSchema.encodeCanonical(firstWave :: any),
		"wave numbers past the set length loop back to wave one"
	)
	local legacyAdapter = TowerDefenseWaves.fromCatalogWave(TowerDefenseCatalog.waves[1])
	expectEqual(
		#legacyAdapter.entries == 1
			and legacyAdapter.entries[1].enemyTypeId == TowerDefenseCatalog.waves[1].enemyId
			and legacyAdapter.entries[1].count == TowerDefenseCatalog.waves[1].count
			and legacyAdapter.entries[1].startDelaySeconds == 0,
		true,
		"legacy catalog waves adapt into single-entry authored waves"
	)
	local mixedWave: any = {
		entries = {
			{ enemyTypeId = "forest_grunt", count = 2, spacingSeconds = 0.5, startDelaySeconds = 0 },
			{
				enemyTypeId = "bark_bruiser",
				count = 1,
				spacingSeconds = 0.01,
				startDelaySeconds = 4,
				healthScale = 2,
				rewardScale = 3,
				speedScale = 0.5,
			},
		},
	}
	local streams = TowerDefenseWaves.buildStreams(mixedWave, 100, 1.35)
	expectEqual(#streams, 2, "each wave entry becomes one spawn stream")
	expectEqual(TowerDefenseWaves.remainingSpawns(streams), 3, "stream bookkeeping counts pending spawns")
	expectEqual(streams[1].nextSpawnAt, 100, "immediate entries are due at wave start")
	expectEqual(streams[2].nextSpawnAt, 104, "delayed entries wait out their start delay")
	expectEqual(
		streams[2].spacingSeconds,
		TowerDefenseWaves.MINIMUM_SPACING_SECONDS,
		"spawn spacing clamps to the simulation minimum"
	)
	expectEqual(
		streams[2].healthScale == 2 * 1.35
			and streams[2].rewardScale == 3 * 1.35
			and streams[2].speedScale == 0.5
			and streams[1].healthScale == 1.35,
		true,
		"entry scales multiply with the loop difficulty scale"
	)
	expectEqual(TowerDefenseWaves.dueStreamIndex(streams, 100), 1, "only elapsed streams are due")
	expectEqual(TowerDefenseWaves.dueStreamIndex(streams, 104.5), 1, "earlier streams win due-stream ties")
	streams[1].remaining = 0
	expectEqual(TowerDefenseWaves.dueStreamIndex(streams, 104.5), 2, "exhausted streams are skipped")
	expectEqual(TowerDefenseWaves.dueStreamIndex(streams, 103), nil, "no stream is due before its delay")
	expectEqual(
		TowerDefenseWaves.armorMultiplier({ "Ground", "Armored" }, 0.6),
		0.6,
		"armored enemies reduce incoming tower damage"
	)
	expectEqual(
		TowerDefenseWaves.armorMultiplier({ "Ground" }, 0.6),
		1,
		"unarmored enemies take full tower damage"
	)
	expectEqual(
		TowerDefenseWaves.isBossWave(defaultSet.waves[#defaultSet.waves]),
		true,
		"the seeded default set ends with a boss wave"
	)
	expectEqual(TowerDefenseWaves.isBossWave(firstWave), false, "regular waves are not boss waves")
	expectEqual(
		TowerDefenseWaves.hasTag(StageWaveDefaults.enemyTypes().grove_titan.tags, "Boss"),
		true,
		"the seeded titan carries the Boss tag"
	)
end

-- Stagewright: shared Bezier geometry and deterministic conditional graph traversal.
local straightSamples, straightLength = StagePath.bake(
	{ x = 0, y = 0, z = 0 },
	{ x = 10 / 3, y = 0, z = 0 },
	{ x = 20 / 3, y = 0, z = 0 },
	{ x = 10, y = 0, z = 0 }
)
expectEqual(math.abs(straightLength - 10) < 1e-6, true, "stage path bake preserves straight edge length")
local straightMiddle = StagePath.sample(straightSamples, straightLength, 5)
expectEqual(
	straightMiddle ~= nil and math.abs(straightMiddle.position.x - 5) < 1e-6,
	true,
	"stage path samples by distance"
)
expectEqual(
	straightMiddle ~= nil and straightMiddle.tangent.x > 0.999,
	true,
	"stage path provides stable orientation tangent"
)
do
	local single = StageLanes.offsets(1)
	local double = StageLanes.offsets(2)
	local triple = StageLanes.offsets(3)
	expectEqual(#single == 1 and single[1] == 0, true, "single lane stays on the spline centerline")
	expectEqual(
		#double == 2 and double[1] == -2 and double[2] == 2,
		true,
		"two lanes split evenly across the spline"
	)
	expectEqual(
		#triple == 3 and triple[1] == -4 and triple[2] == 0 and triple[3] == 4,
		true,
		"three lanes remain centered around the spline"
	)
	expectEqual(StageLanes.index(4, 3), 1, "lane assignment cycles deterministically")
	expectEqual(
		StageLanes.sequenceForSpawn(1, 2) == 1
			and StageLanes.sequenceForSpawn(2, 2) == 1
			and StageLanes.sequenceForSpawn(3, 2) == 2,
		true,
		"lane sequence advances independently after distributing across spawns"
	)
	expectEqual(StageLanes.clearanceRadius(triple), 6, "lane clearance covers the full corridor")
	expectEqual(
		StageLanes.resolveWidth({ laneWidth = 7 }, 2.4),
		7,
		"runtime route strips use the edge's authored lane width"
	)
	expectEqual(
		StageLanes.resolveWidth({ laneWidth = 0 / 0 }, 2.4),
		2.4,
		"runtime route strips safely fall back for invalid legacy metadata"
	)
end
do
	local firstPlatformOffset = { x = 183.524, y = 13.344, z = 94.169 }
	local centerFacingLocalDirection = { x = -54, y = 0, z = -32 }
	local alignmentYaw =
		StagePlatformLayout.alignDirectionYaw(firstPlatformOffset, centerFacingLocalDirection)
	expectEqual(
		math.abs(math.deg(alignmentYaw) - 3.4876078885171) < 1e-9,
		true,
		"platform yaw aligns the stage's authored center-facing direction"
	)
	local alignedX = math.cos(alignmentYaw) * centerFacingLocalDirection.x
		+ math.sin(alignmentYaw) * centerFacingLocalDirection.z
	local alignedZ = -math.sin(alignmentYaw) * centerFacingLocalDirection.x
		+ math.cos(alignmentYaw) * centerFacingLocalDirection.z
	local alignedMagnitude = math.sqrt(alignedX * alignedX + alignedZ * alignedZ)
	local centerMagnitude = math.sqrt(
		firstPlatformOffset.x * firstPlatformOffset.x + firstPlatformOffset.z * firstPlatformOffset.z
	)
	local centerAlignment = (alignedX * -firstPlatformOffset.x + alignedZ * -firstPlatformOffset.z)
		/ (alignedMagnitude * centerMagnitude)
	expectEqual(centerAlignment > 0.999999999, true, "aligned stage direction points at the world center")
	local slotOneOffset, slotOneYaw = StagePlatformLayout.slotOffset(firstPlatformOffset, 1, 6)
	local slotFourOffset, slotFourYaw = StagePlatformLayout.slotOffset(firstPlatformOffset, 4, 6)
	expectEqual(
		math.abs(slotOneOffset.x - firstPlatformOffset.x) < 1e-9,
		true,
		"platform slot one preserves authored X"
	)
	expectEqual(
		math.abs(slotOneOffset.z - firstPlatformOffset.z) < 1e-9,
		true,
		"platform slot one preserves authored Z"
	)
	expectEqual(slotOneYaw, 0, "platform slot one preserves authored orientation")
	expectEqual(
		math.abs(slotFourOffset.x + firstPlatformOffset.x) < 1e-9,
		true,
		"opposite platform mirrors X"
	)
	expectEqual(
		math.abs(slotFourOffset.z + firstPlatformOffset.z) < 1e-9,
		true,
		"opposite platform mirrors Z"
	)
	expectEqual(math.abs(slotFourYaw - math.pi) < 1e-9, true, "six platform slots rotate in 60-degree steps")
end

local branchGraph = {
	nodes = {
		spawn = { id = "spawn", kind = "Spawn" },
		upper = { id = "upper", kind = "Goal" },
		fallback = { id = "fallback", kind = "Goal" },
	},
	edges = {
		wave_gate = {
			id = "wave_gate",
			fromNodeId = "spawn",
			toNodeId = "upper",
			priority = 1,
			predicates = { { kind = "WaveRange", minimum = 5, maximum = 10 } },
		},
		fallback = {
			id = "fallback",
			fromNodeId = "spawn",
			toNodeId = "fallback",
			priority = 2,
			predicates = {},
		},
	},
}
local routeContext = {
	wave = 2,
	stageFlags = {},
	enemyTags = {},
	nodeVisits = {},
	unlockedStages = {},
	upgradeLevels = {},
	currencies = {},
}
local selectedEdge = StageGraph.chooseEdge(branchGraph, "spawn", routeContext)
expectEqual(selectedEdge ~= nil and selectedEdge.id, "fallback", "stage graph uses unconditional fallback")
routeContext.wave = 6
selectedEdge = StageGraph.chooseEdge(branchGraph, "spawn", routeContext)
expectEqual(selectedEdge ~= nil and selectedEdge.id, "wave_gate", "stage graph evaluates built-in predicates")
expectEqual(#StageGraph.validate(branchGraph), 0, "valid stage graph passes shared validation")
local fallbackTrace = StageTrace.trace(branchGraph, "spawn", routeContext)
expectEqual(fallbackTrace.reachedGoal, true, "edit-mode route trace reaches a goal")
expectEqual(fallbackTrace.edgeIds[1], "wave_gate", "route trace uses the same deterministic edge evaluator")
local predicateContext = {
	wave = 7,
	stageFlags = { hardMode = true },
	enemyTags = { Flying = true },
	nodeVisits = { spawn = 1 },
	unlockedStages = { stage_two = true },
	upgradeLevels = { range = 4 },
	currencies = { coins = 500 },
}
expectEqual(
	StageGraph.predicatesPass({
		{ kind = "StageFlagEquals", key = "hardMode", value = true },
		{ kind = "EnemyTag", tag = "Flying" },
		{ kind = "VisitCountBelow", nodeId = "spawn", maximum = 3 },
		{ kind = "StageUnlocked", stageId = "stage_two" },
		{ kind = "UpgradeLevelAtLeast", upgradeId = "range", level = 4 },
		{ kind = "CurrencyAtLeast", currencyId = "coins", amount = 250 },
	}, predicateContext),
	true,
	"all built-in route predicates evaluate from authoritative context"
)
local cyclicGraph = serde.decode("json", serde.encode("json", branchGraph))
cyclicGraph.nodes.loop = { id = "loop", kind = "Junction" }
cyclicGraph.edges.wave_gate.toNodeId = "loop"
cyclicGraph.edges.loop = {
	id = "loop",
	fromNodeId = "loop",
	toNodeId = "loop",
	priority = 1,
	predicates = {},
}
local cyclicIssues = StageGraph.validate(cyclicGraph)
expectEqual(#cyclicIssues > 0, true, "unbounded graph cycles are rejected before export")
local cyclicTrace = StageTrace.trace(cyclicGraph, "spawn", routeContext, 12)
expectEqual(cyclicTrace.reachedGoal, false, "route trace safety cap stops an unbounded cycle")
expectEqual(
	string.find(cyclicTrace.stoppedReason, "Maximum node visits", 1, true) ~= nil,
	true,
	"route trace reports the safety cap diagnostic"
)
local finiteJsonOk = pcall(function()
	StageSchema.encodeCanonical({ invalid = 0 / 0 })
end)
expectEqual(finiteJsonOk, false, "Stagewright serialization rejects NaN payloads")
do
	local invalidCellIssues = StageSchema.validateStage({
		id = "invalid_cell_stage",
		mapId = "map_test",
		stageGroupId = "invalid_cell_group",
		stageNumber = 1,
		levelNumber = 1,
		grid = {
			columns = 2,
			rows = 2,
			cellSize = 4,
			defaultCell = {},
			cells = { ["3:1"] = { buildPolicy = "Allowed" } },
		},
		pathGraphs = {},
	})
	expectEqual(invalidCellIssues[1].code, "CellOutOfBounds", "out-of-range stage cells fail validation")
	local inheritedEndpointIssues = StageSchema.validateStage({
		id = "inherited_endpoint_stage",
		mapId = "map_test",
		stageGroupId = "inherited_endpoint_group",
		stageNumber = 1,
		levelNumber = 1,
		grid = {
			columns = 1,
			rows = 1,
			cellSize = 4,
			defaultCell = { buildPolicy = "Blocked" },
			cells = { ["1:1"] = { roles = { EnemySpawn = true } } },
		},
		pathGraphs = {},
	})
	local inheritedEndpointPolicyError = false
	for _, issue in inheritedEndpointIssues do
		if issue.code == "EndpointBuildPolicy" then
			inheritedEndpointPolicyError = true
			break
		end
	end
	expectEqual(
		inheritedEndpointPolicyError,
		false,
		"cell validation resolves inherited tower-placement policy before checking roles"
	)
	local conflictingRoleIssues = StageSchema.validateStage({
		id = "conflicting_role_stage",
		mapId = "map_test",
		stageGroupId = "conflicting_role_group",
		stageNumber = 1,
		levelNumber = 1,
		grid = {
			columns = 1,
			rows = 1,
			cellSize = 4,
			defaultCell = { buildPolicy = "Blocked" },
			cells = {
				["1:1"] = { roles = { EnemySpawn = true, EnemyGoal = true } },
			},
		},
		pathGraphs = {},
	})
	local conflictingPrimaryRoleError = false
	for _, issue in conflictingRoleIssues do
		if issue.code == "ConflictingPrimaryRoles" then
			conflictingPrimaryRoleError = true
			break
		end
	end
	expectEqual(conflictingPrimaryRoleError, true, "a cell cannot stack incompatible primary roles")
	local malformedDefaultCellAccepted, malformedDefaultCellIssues = pcall(function()
		return StageSchema.validateStage({
			id = "malformed_default_cell_stage",
			mapId = "map_test",
			stageGroupId = "malformed_default_cell_group",
			stageNumber = 1,
			levelNumber = 1,
			grid = {
				columns = 1,
				rows = 1,
				cellSize = 4,
				cells = { ["1:1"] = { terrainId = "ground" } },
			},
			pathGraphs = {},
		})
	end)
	expectEqual(malformedDefaultCellAccepted, true, "malformed default cell validation remains diagnostic")
	expectEqual(
		malformedDefaultCellIssues[1].code,
		"InvalidDefaultCell",
		"missing level defaults produce a validation issue"
	)
	local malformedRolesAccepted, malformedRolesIssues = pcall(function()
		return StageSchema.validateStage({
			id = "malformed_roles_stage",
			mapId = "map_test",
			stageGroupId = "malformed_roles_group",
			stageNumber = 1,
			levelNumber = 1,
			grid = {
				columns = 1,
				rows = 1,
				cellSize = 4,
				defaultCell = { buildPolicy = "Allowed" },
				cells = { ["1:1"] = { roles = 7 } },
			},
			pathGraphs = {},
		})
	end)
	expectEqual(malformedRolesAccepted, true, "malformed imported roles remain diagnostic")
	local foundMalformedRolesIssue = false
	for _, issue in malformedRolesIssues do
		if issue.code == "CellRoles" then
			foundMalformedRolesIssue = true
		end
	end
	expectEqual(foundMalformedRolesIssue, true, "malformed imported roles produce a validation issue")
end
local legacyLayered = StageSchema.legacyCells({ ".#PGA?" }, 6)
expectEqual(legacyLayered["2:1"].buildPolicy, "Blocked", "legacy path blocks remain authored manual blocks")
expectEqual(legacyLayered["3:1"].roles.EnemySpawn, true, "legacy portal migrates to spawn role")
expectEqual(legacyLayered["4:1"].roles.EnemyGoal, true, "legacy goal migrates to goal role")
expectEqual(legacyLayered["5:1"].roles.AutoPlace, true, "legacy auto-place migrates independently")
expectEqual(legacyLayered["6:1"].metadata.legacyCode, "?", "unknown legacy cells are preserved as metadata")
local importedLegacy, legacyNotices = StageLegacy.project({
	columns = 4,
	rows = 2,
	cellSize = 2,
	rowValues = { "....", "...G" },
	controlPositions = {
		{ x = -3, y = 0, z = 0 },
		{ x = 0, y = 0, z = 0 },
	},
	stageId = "stage_default",
	graphId = "graph_main",
	stageName = "Legacy Fixture",
	blankFallback = false,
})
local importedLegacyStage = importedLegacy.stages.stage_default
local importedLegacyGraph = importedLegacyStage.pathGraphs.graph_main
expectEqual(
	StageLanes.resolveWidth(importedLegacyGraph.edges.edge_001.metadata),
	StageLanes.DEFAULT_SPACING,
	"legacy routes use the same default width in editor and runtime"
)
expectEqual(
	importedLegacyStage.grid.cells["1:2"].roles.EnemySpawn,
	true,
	"legacy controls infer a missing spawn role at Control_001"
)
expectEqual(
	importedLegacyGraph.nodes.node_spawn.position.x,
	-3,
	"Control_001 becomes the inferred graph spawn without an extra segment"
)
expectEqual(
	importedLegacyGraph.edges.edge_001.toNodeId,
	"node_control_002",
	"legacy controls retain their authored order"
)
expectEqual(
	importedLegacyGraph.edges.edge_001.outHandleOffset.x,
	0.5,
	"legacy Catmull-Rom tangents convert to cubic Bezier handles"
)
local convertedEdge = importedLegacyGraph.edges.edge_001
local convertedFrom = importedLegacyGraph.nodes[convertedEdge.fromNodeId].position
local convertedTo = importedLegacyGraph.nodes[convertedEdge.toNodeId].position
local convertedAlpha = 0.37
local convertedBezier = StagePath.position(convertedFrom, {
	x = convertedFrom.x + convertedEdge.outHandleOffset.x,
	y = convertedFrom.y + convertedEdge.outHandleOffset.y,
	z = convertedFrom.z + convertedEdge.outHandleOffset.z,
}, {
	x = convertedTo.x + convertedEdge.inHandleOffset.x,
	y = convertedTo.y + convertedEdge.inHandleOffset.y,
	z = convertedTo.z + convertedEdge.inHandleOffset.z,
}, convertedTo, convertedAlpha)
local function catmullComponent(p0: number, p1: number, p2: number, p3: number, alpha: number): number
	local alpha2 = alpha * alpha
	local alpha3 = alpha2 * alpha
	return (
		(p1 * 2)
		+ ((p2 - p0) * alpha)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * alpha2)
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * alpha3)
	) * 0.5
end
local legacyGoalPosition = importedLegacyGraph.nodes.node_goal.position
local expectedLegacyX =
	catmullComponent(convertedFrom.x, convertedFrom.x, convertedTo.x, legacyGoalPosition.x, convertedAlpha)
local expectedLegacyZ =
	catmullComponent(convertedFrom.z, convertedFrom.z, convertedTo.z, legacyGoalPosition.z, convertedAlpha)
expectEqual(
	math.abs(convertedBezier.x - expectedLegacyX) < 1e-9
		and math.abs(convertedBezier.z - expectedLegacyZ) < 1e-9,
	true,
	"converted Bezier geometry exactly matches the legacy Catmull-Rom segment"
)
expectEqual(#legacyNotices, 1, "legacy spawn inference produces an explicit diagnostic")
expectEqual(
	StageExport.bake(importedLegacy).bundle ~= nil,
	true,
	"inferred legacy route exports successfully"
)
local schemaOneProject = {
	schemaVersion = 1,
	startingStageId = "legacy",
	stages = {
		legacy = {
			id = "legacy",
			grid = { columns = 2, rows = 2, cellSize = 4, cells = {} },
			pathGraphs = {},
			unknownFutureField = { preserved = true },
		},
	},
}
local migratedStageProject = StageSchema.migrateProject(schemaOneProject)
expectEqual(migratedStageProject.schemaVersion, 5, "Stagewright authoring schemas migrate sequentially")
expectEqual(
	migratedStageProject.stages.legacy.stageNumber == 1
		and migratedStageProject.stages.legacy.levelNumber == 1
		and migratedStageProject.stages.legacy.mapId == StageHierarchy.LEGACY_MAP_ID,
	true,
	"legacy flat stages migrate into stable Map 1 / Stage 1 / Level 1 hierarchy fields"
)
expectEqual(
	migratedStageProject.stages.legacy.unknownFutureField.preserved,
	true,
	"Stagewright migration preserves unknown stage data"
)
expectEqual(
	StageSchema.migrateProject(migratedStageProject).schemaVersion,
	5,
	"Stagewright migration is idempotent"
)
do
	local schemaThreeProject = {
		schemaVersion = 3,
		startingStageId = "level_alpha_1",
		selectedStageId = "level_beta_1",
		unknownRoot = { future = "preserved" },
		metadata = {
			["stagewright.mapBackdrops"] = {
				stage_alpha = "110986082479051",
				stage_beta = "110986082479051",
			},
			unknownMetadata = { future = true },
		},
		stages = {
			level_alpha_1 = {
				schemaVersion = 3,
				id = "level_alpha_1",
				stageGroupId = "stage_alpha",
				stageNumber = 1,
				levelNumber = 1,
				displayOrder = 1,
				unknownLevel = { future = "alpha" },
			},
			level_alpha_2 = {
				schemaVersion = 3,
				id = "level_alpha_2",
				stageGroupId = "stage_alpha",
				stageNumber = 1,
				levelNumber = 2,
				displayOrder = 2,
				unknownLevel = { future = "alpha-two" },
			},
			level_beta_1 = {
				schemaVersion = 3,
				id = "level_beta_1",
				stageGroupId = "stage_beta",
				stageNumber = 2,
				levelNumber = 1,
				displayOrder = 3,
				unknownLevel = { future = "beta" },
			},
		},
	}
	local migratedMapProject = StageSchema.migrateProject(schemaThreeProject)
	local migratedMap = migratedMapProject.maps[StageHierarchy.LEGACY_MAP_ID]
	expectEqual(migratedMapProject.schemaVersion, 5, "schema 3 migrates through Map-first to the wave schema")
	expectEqual(
		migratedMap ~= nil and migratedMap.backdropImageId,
		"110986082479051",
		"matching legacy Stage backdrops promote to one Map backdrop without changing the asset ID"
	)
	expectEqual(
		migratedMapProject.startingStageId == "level_alpha_1"
			and migratedMapProject.selectedStageId == "level_beta_1"
			and migratedMapProject.stages.level_alpha_1.id == "level_alpha_1"
			and migratedMapProject.stages.level_alpha_2.id == "level_alpha_2"
			and migratedMapProject.stages.level_beta_1.id == "level_beta_1",
		true,
		"Map migration preserves every playable Level ID and current selection reference"
	)
	expectEqual(
		migratedMapProject.stages.level_alpha_1.mapId == StageHierarchy.LEGACY_MAP_ID
			and migratedMapProject.stages.level_alpha_2.mapId == StageHierarchy.LEGACY_MAP_ID
			and migratedMapProject.stages.level_beta_1.mapId == StageHierarchy.LEGACY_MAP_ID,
		true,
		"all legacy Stages migrate into exactly one initial Map"
	)
	expectEqual(
		migratedMapProject.unknownRoot.future == "preserved"
			and migratedMapProject.metadata.unknownMetadata.future == true
			and migratedMapProject.stages.level_alpha_2.unknownLevel.future == "alpha-two",
		true,
		"Map migration preserves unknown root, metadata, and Level fields"
	)
	expectEqual(
		migratedMapProject.metadata["stagewright.mapBackdrops"].stage_alpha,
		"110986082479051",
		"Map migration keeps legacy backdrop metadata for lossless compatibility"
	)

	local conflictingLegacy = serde.decode(
		"json",
		StageSchema.encodeCanonical({
			schemaVersion = 3,
			startingStageId = "level_alpha_1",
			metadata = {
				["stagewright.mapBackdrops"] = {
					stage_alpha = "111",
					stage_beta = "222",
				},
			},
			stages = {
				level_alpha_1 = {
					schemaVersion = 3,
					id = "level_alpha_1",
					stageGroupId = "stage_alpha",
					stageNumber = 1,
					levelNumber = 1,
					displayOrder = 1,
				},
				level_beta_1 = {
					schemaVersion = 3,
					id = "level_beta_1",
					stageGroupId = "stage_beta",
					stageNumber = 2,
					levelNumber = 1,
					displayOrder = 2,
				},
			},
		})
	)
	StageSchema.migrateProject(conflictingLegacy)
	local conflictMap = conflictingLegacy.maps[StageHierarchy.LEGACY_MAP_ID]
	expectEqual(
		conflictMap.backdropImageId == ""
			and conflictMap.metadata["stagewright.legacyBackdropConflict"] == true,
		true,
		"conflicting legacy Stage backdrops remain unresolved instead of silently choosing one"
	)
	expectEqual(
		conflictingLegacy.metadata["stagewright.mapBackdrops"].stage_alpha == "111"
			and conflictingLegacy.metadata["stagewright.mapBackdrops"].stage_beta == "222",
		true,
		"conflicting legacy backdrop values remain recoverable"
	)
end
do
	local hierarchyMaps = {
		map_main = { id = "map_main", name = "Map 1", displayOrder = 1 },
		map_bonus = { id = "map_bonus", name = "Map 2", displayOrder = 2 },
	}
	local hierarchyLevels: { [string]: any } = {}
	for stageNumber = 1, 15 do
		local levelId = `main_stage_{stageNumber}_level_1`
		hierarchyLevels[levelId] = {
			id = levelId,
			mapId = "map_main",
			stageGroupId = `main_stage_{stageNumber}`,
			stageNumber = stageNumber,
			levelNumber = 1,
			displayOrder = stageNumber,
		}
	end
	hierarchyLevels.bonus_level = {
		id = "bonus_level",
		mapId = "map_bonus",
		stageGroupId = "bonus_stage",
		stageNumber = 1,
		levelNumber = 1,
		displayOrder = 16,
	}
	expectEqual(
		#StageHierarchy.stageGroupIds(hierarchyLevels, "map_main", hierarchyMaps),
		15,
		"one Map supports at least fifteen independently selectable Stages"
	)
	expectEqual(
		StageHierarchy.nextStageNumber(hierarchyLevels, "map_main"),
		16,
		"new Stage numbering is scoped to its owning Map"
	)
	expectEqual(
		StageHierarchy.nextStageNumber(hierarchyLevels, "map_bonus"),
		2,
		"a second Map keeps an independent Stage sequence"
	)
	expectEqual(
		StageHierarchy.firstLevelId(hierarchyLevels, "map_bonus", nil, hierarchyMaps),
		"bonus_level",
		"Map selection resolves to a representative playable Level"
	)
	local sortedHierarchy = StageHierarchy.sortedIds(hierarchyLevels, hierarchyMaps)
	expectEqual(
		sortedHierarchy[1] == "main_stage_1_level_1" and sortedHierarchy[#sortedHierarchy] == "bonus_level",
		true,
		"hierarchy sorting keeps Maps primary before their Stages and Levels"
	)
end
do
	local authoringProject = serde.decode("json", fs.readFile("stage-data/stagewright-project.json"))
	local authoredProductionStage = authoringProject.stages.stage_default
	local authoredMapId = authoredProductionStage.mapId
	expectEqual(authoredProductionStage.name, "Level 1", "repository names the starting definition Level 1")
	expectEqual(
		type(authoringProject.maps) == "table"
			and authoringProject.maps[authoredMapId] ~= nil
			and authoringProject.maps[authoredMapId].backdropImageId ~= nil,
		true,
		"repository authoring data has a first-class Map registry and Map-owned backdrop field"
	)
	expectEqual(
		authoringProject.metadata["stagewright.approvedStarterRevision"],
		StageStarterProject.REVISION,
		"repository starter data records its approved replacement revision"
	)
	local authoredLevelIds = StageHierarchy.sortedIds(authoringProject.stages)
	expectEqual(#authoredLevelIds, 10, "repository seeds Stage 1 with the first ten levels")
	local expectedPlaytestSets = {
		StageStarterProject.BASICS_WAVE_SET_ID,
		StageStarterProject.MIXED_WAVE_SET_ID,
		StageStarterProject.BOSS_WAVE_SET_ID,
	}
	for levelNumber = 1, 3 do
		expectEqual(
			authoringProject.stages[authoredLevelIds[levelNumber]].waveSetId,
			expectedPlaytestSets[levelNumber],
			`repository assigns the MVP wave set for Level {levelNumber}`
		)
	end
	for levelNumber = 4, 10 do
		expectEqual(
			authoringProject.stages[authoredLevelIds[levelNumber]].waveSetId,
			StageWaveDefaults.DEFAULT_WAVE_SET_ID,
			`Level {levelNumber} remains on the default wave set`
		)
	end
	local basicsSet = authoringProject.waveSets[StageStarterProject.BASICS_WAVE_SET_ID]
	local mixedSet = authoringProject.waveSets[StageStarterProject.MIXED_WAVE_SET_ID]
	local bossSet = authoringProject.waveSets[StageStarterProject.BOSS_WAVE_SET_ID]
	expectEqual(
		#basicsSet.waves == 3
			and basicsSet.waves[1].entries[1].count == 6
			and basicsSet.waves[2].entries[2].enemyTypeId == "forest_runner"
			and basicsSet.waves[2].entries[2].startDelaySeconds == 2.5
			and basicsSet.waves[3].entries[2].enemyTypeId == "bark_bruiser",
		true,
		"Level 1 seeds basic timing and delayed reinforcements"
	)
	expectEqual(
		#mixedSet.waves == 3
			and #mixedSet.waves[3].entries == 3
			and mixedSet.waves[3].entries[1].enemyTypeId == "forest_runner"
			and mixedSet.waves[3].entries[2].enemyTypeId == "bark_bruiser"
			and mixedSet.waves[3].entries[3].enemyTypeId == "sky_wisp",
		true,
		"Level 2 seeds concurrent ground, armored, fast, and flying streams"
	)
	expectEqual(
		#bossSet.waves == 3
			and bossSet.waves[3].isBoss == true
			and bossSet.waves[3].entries[2].enemyTypeId == "grove_titan"
			and bossSet.waves[3].entries[2].count == 1
			and bossSet.waves[3].entries[2].startDelaySeconds == 2,
		true,
		"Level 3 seeds the delayed titan boss and escort streams"
	)
	local copiedStarterLayoutsMatch = true
	local uniqueGraphIds: { [string]: boolean } = {}
	local function topologySignature(level: any): string
		local graphId, graph = next(level.pathGraphs)
		local names: { [string]: string } = {}
		for nodeId, node in graph.nodes do
			names[nodeId] = node.name
		end
		local routes: { string } = {}
		for _, edge in graph.edges do
			table.insert(
				routes,
				`{names[edge.fromNodeId]}->{names[edge.toNodeId]}:{edge.priority}:{#edge.predicates}`
			)
		end
		table.sort(routes)
		uniqueGraphIds[graphId] = true
		return table.concat(routes, "|")
	end
	local authoredTopology = topologySignature(authoredProductionStage)
	for levelNumber, levelId in authoredLevelIds do
		local level = authoringProject.stages[levelId]
		local address = StageHierarchy.address(level)
		if
			StageSchema.encodeCanonical(level.grid)
				~= StageSchema.encodeCanonical(authoredProductionStage.grid)
			or topologySignature(level) ~= authoredTopology
		then
			copiedStarterLayoutsMatch = false
		end
		expectEqual(
			address.mapId == authoredMapId and address.stageNumber == 1 and address.levelNumber == levelNumber,
			true,
			`authored Map 1 / Stage 1 level order includes Level {levelNumber}`
		)
		if levelNumber > 1 then
			expectEqual(
				level.unlockRequirements[1].stageId,
				authoredLevelIds[levelNumber - 1],
				`Level {levelNumber} preserves sequential progression`
			)
		end
	end
	expectEqual(
		copiedStarterLayoutsMatch,
		true,
		"all ten starter levels copy the same editable map and graph"
	)
	local uniqueGraphIdCount = 0
	for _ in uniqueGraphIds do
		uniqueGraphIdCount += 1
	end
	expectEqual(uniqueGraphIdCount, 10, "copied starter levels receive independent graph identities")
	do
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(authoringProject),
			false,
			"approved starter content can never be mistaken for replaceable test data"
		)
		local recognizedLegacy = serde.decode("json", serde.encode("json", authoringProject))
		recognizedLegacy.metadata["stagewright.approvedStarterRevision"] = nil
		for _, legacyStage in recognizedLegacy.stages do
			for _, legacyGraph in legacyStage.pathGraphs do
				local legacyIndex = 1
				for _, legacyNode in legacyGraph.nodes do
					if legacyIndex <= 5 then
						legacyNode.name = `Legacy Control {legacyIndex}`
					end
					legacyIndex += 1
				end
			end
		end
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(recognizedLegacy),
			true,
			"only the exact ten-level random legacy signature authorizes starter replacement"
		)
		recognizedLegacy.stages[authoredLevelIds[10]] = nil
		expectEqual(
			StageStarterProject.isRecognizedLegacyTestProject(recognizedLegacy),
			false,
			"near-matching authored projects remain untouched"
		)
	end
	do
		local duplicateHierarchy = serde.decode("json", serde.encode("json", authoringProject))
		duplicateHierarchy.stages[authoredLevelIds[2]].levelNumber = 1
		local duplicateResult = StageExport.bake(duplicateHierarchy)
		local foundDuplicateLevel = false
		for _, issue in duplicateResult.issues do
			if issue.code == "DuplicateLevelNumber" then
				foundDuplicateLevel = true
				break
			end
		end
		expectEqual(
			duplicateResult.bundle == nil and foundDuplicateLevel,
			true,
			"duplicate level numbers block deterministic export"
		)
	end
	do
		local crossMapStage = serde.decode("json", serde.encode("json", authoringProject))
		crossMapStage.maps.map_second = {
			id = "map_second",
			name = "Map 2",
			displayOrder = 2,
			backdropImageId = "",
			metadata = {},
		}
		crossMapStage.stages[authoredLevelIds[2]].mapId = "map_second"
		local crossMapResult = StageExport.bake(crossMapStage)
		local foundSharedStage = false
		for _, issue in crossMapResult.issues do
			if issue.code == "StageSharedAcrossMaps" then
				foundSharedStage = true
				break
			end
		end
		expectEqual(
			crossMapResult.bundle == nil and foundSharedStage,
			true,
			"one stable Stage group cannot belong to multiple Maps"
		)
	end
	do
		local orphanMapProject = serde.decode("json", serde.encode("json", authoringProject))
		orphanMapProject.maps.map_orphan = {
			id = "map_orphan",
			name = "Orphan Map",
			displayOrder = 2,
			backdropImageId = "",
			metadata = { preservedUnknown = true },
		}
		local orphanMapExport = StageExport.bake(orphanMapProject)
		local orphanIssue: any = nil
		for _, issue in orphanMapExport.issues do
			if issue.code == "OrphanMap" then
				orphanIssue = issue
				break
			end
		end
		expectEqual(
			orphanMapExport.bundle == nil
				and orphanIssue ~= nil
				and orphanIssue.mapId == "map_orphan"
				and string.find(orphanIssue.message, "at least one Level", 1, true) ~= nil,
			true,
			"runtime export rejects an orphan Map with a clear Map-scoped error"
		)
	end
	expectEqual(
		authoredProductionStage.metadata["stagewright.layoutVersion"],
		3,
		"repository records the intentional production layout version"
	)
	expectEqual(
		authoredProductionStage.grid.cells["4:6"].roles.EnemySpawn,
		true,
		"production stage provides a north spawn"
	)
	expectEqual(
		authoredProductionStage.grid.cells["4:22"].roles.EnemySpawn,
		true,
		"production stage provides a south spawn"
	)
	expectEqual(
		authoredProductionStage.grid.cells["31:14"].roles.EnemyGoal,
		true,
		"production goal sits opposite both spawns"
	)
	local authoredGraphId, authoringGraph = next(authoredProductionStage.pathGraphs)
	local edgeByRoute: { [string]: any } = {}
	for _, edge in authoringGraph.edges do
		edgeByRoute[`{authoringGraph.nodes[edge.fromNodeId].name}->{authoringGraph.nodes[edge.toNodeId].name}`] =
			edge
	end
	expectEqual(edgeByRoute["Rejoin->Goal"] ~= nil, true, "merged production route reaches the goal")
	expectEqual(
		edgeByRoute["North Spawn->Merge"] ~= nil and edgeByRoute["South Spawn->Merge"] ~= nil,
		true,
		"north and south spawn splines merge at one stable junction"
	)
	expectEqual(
		edgeByRoute["Merge->Wave Gate"].predicates[1].kind == "WaveRange"
			and edgeByRoute["Merge->Fallback Path"].priority == 2
			and #edgeByRoute["Merge->Fallback Path"].predicates == 0,
		true,
		"production route has a wave-gated branch and unconditional fallback"
	)
	expectEqual(
		edgeByRoute["Wave Gate->Rejoin"] ~= nil and edgeByRoute["Fallback Path->Rejoin"] ~= nil,
		true,
		"conditional and fallback branches rejoin before the goal"
	)
	expectEqual(
		#authoringGraph.laneProfiles.lane_default.offsets,
		2,
		"production route defaults to two enemy lanes"
	)
	do
		local invalidLaneStage = serde.decode("json", serde.encode("json", authoredProductionStage))
		invalidLaneStage.pathGraphs[authoredGraphId].laneProfiles.lane_default.offsets = { -6, -2, 2, 6 }
		local foundLaneCountError = false
		for _, issue in StageSchema.validateStage(invalidLaneStage) do
			if issue.code == "LaneCount" then
				foundLaneCountError = true
			end
		end
		expectEqual(foundLaneCountError, true, "stage validation rejects profiles beyond three lanes")
	end
	local firstExport = StageExport.bake(authoringProject)
	local secondExport = StageExport.bake(authoringProject)
	expectEqual(firstExport.bundle ~= nil, true, "valid Stagewright project bakes a runtime bundle")
	expectEqual(
		firstExport.bundle ~= nil and firstExport.bundle.schemaVersion,
		StageSchema.RUNTIME_VERSION,
		"runtime Map hierarchy exports with the current runtime schema"
	)
	expectEqual(
		firstExport.bundle ~= nil
			and firstExport.bundle.mapOrder[1] == authoredMapId
			and firstExport.bundle.maps[authoredMapId] ~= nil
			and firstExport.bundle.stages[authoringProject.startingStageId].mapId == authoredMapId,
		true,
		"runtime bundle keeps Map order, Map data, and every Level's owning Map ID"
	)
	expectEqual(
		firstExport.bundle ~= nil and #firstExport.bundle.stageOrder,
		10,
		"runtime bundle exports all ten Stage 1 levels"
	)
	expectEqual(
		firstExport.bundle ~= nil and secondExport.bundle ~= nil and firstExport.bundle.checksum,
		secondExport.bundle ~= nil and secondExport.bundle.checksum,
		"unchanged Stagewright exports are checksum deterministic"
	)
	local exportedBundle = assert(firstExport.bundle, "valid Stagewright project has no runtime bundle")
	local normalizedExportProject =
		StageSchema.migrateProject(serde.decode("json", StageSchema.encodeCanonical(authoringProject)))
	local normalizedExport = StageExport.bake(normalizedExportProject)
	local normalizedBundle =
		assert(normalizedExport.bundle, "normalized Stagewright project has no runtime bundle")
	expectEqual(
		StageSchema.encodeCanonical(normalizedBundle),
		StageSchema.encodeCanonical(exportedBundle),
		"canonical authoring readback rebakes the exact embedded runtime payload"
	)
	local canonicalEmbeddedRuntime = StageSchema.encodeCanonical(exportedBundle)
	local tamperedEmbeddedRuntime = serde.decode("json", canonicalEmbeddedRuntime)
	tamperedEmbeddedRuntime.stages.stage_default.name = "Tampered stage"
	expectEqual(
		tamperedEmbeddedRuntime.checksum == exportedBundle.checksum
			and StageSchema.encodeCanonical(tamperedEmbeddedRuntime) ~= canonicalEmbeddedRuntime,
		true,
		"canonical runtime readback rejects modified contents even when the copied checksum matches"
	)
	expectEqual(
		exportedBundle.stages.stage_default.name,
		authoringProject.stages.stage_default.name,
		"runtime verification never mutates the expected export"
	)
	local alternateStartingProject = serde.decode("json", serde.encode("json", authoringProject))
	alternateStartingProject.startingStageId = "stage_1_level_2"
	local alternateStartingExport = StageExport.bake(alternateStartingProject)
	expectEqual(
		alternateStartingExport.bundle ~= nil and alternateStartingExport.bundle.startingStageId,
		"stage_1_level_2",
		"runtime export preserves the authored starting stage"
	)
	local danglingStartingProject = serde.decode("json", serde.encode("json", authoringProject))
	danglingStartingProject.startingStageId = "stage_missing"
	local danglingStartingExport = StageExport.bake(danglingStartingProject)
	expectEqual(danglingStartingExport.bundle, nil, "runtime export rejects a dangling starting stage")
	local foundInvalidStartingStage = false
	for _, issue in danglingStartingExport.issues do
		if issue.code == "InvalidStartingStage" then
			foundInvalidStartingStage = true
			break
		end
	end
	expectEqual(
		foundInvalidStartingStage,
		true,
		"runtime export identifies the dangling starting-stage contract"
	)
	do
		local danglingUnlockProject = serde.decode("json", serde.encode("json", authoringProject))
		local ownerStageId = authoredLevelIds[2]
		danglingUnlockProject.stages[ownerStageId].unlockRequirements = {
			{ kind = "StageUnlocked", stageId = "stage_missing_unlock_target" },
		}
		local danglingUnlockExport = StageExport.bake(danglingUnlockProject)
		local danglingUnlockIssue: any = nil
		for _, issue in danglingUnlockExport.issues do
			if issue.code == "DanglingStageReference" then
				danglingUnlockIssue = issue
				break
			end
		end
		expectEqual(
			danglingUnlockExport.bundle == nil
				and danglingUnlockIssue ~= nil
				and danglingUnlockIssue.mapId == authoredMapId
				and danglingUnlockIssue.stageId == ownerStageId
				and danglingUnlockIssue.objectId == "stage_missing_unlock_target",
			true,
			"runtime export rejects a Level unlock requirement that references a missing Level"
		)
	end
	do
		local danglingRouteProject = serde.decode("json", serde.encode("json", authoringProject))
		local routeEdgeId = edgeByRoute["North Spawn->Merge"].id
		danglingRouteProject.stages.stage_default.pathGraphs[authoredGraphId].edges[routeEdgeId].predicates =
			{
				{ kind = "StageUnlocked", stageId = "stage_missing_route_target" },
			}
		local danglingRouteExport = StageExport.bake(danglingRouteProject)
		local danglingRouteIssue: any = nil
		for _, issue in danglingRouteExport.issues do
			if issue.code == "DanglingStageReference" and issue.graphId == authoredGraphId then
				danglingRouteIssue = issue
				break
			end
		end
		expectEqual(
			danglingRouteExport.bundle == nil
				and danglingRouteIssue ~= nil
				and danglingRouteIssue.mapId == authoredMapId
				and danglingRouteIssue.stageId == "stage_default"
				and danglingRouteIssue.objectId == routeEdgeId
				and string.find(danglingRouteIssue.message, "stage_missing_route_target", 1, true) ~= nil,
			true,
			"runtime export rejects a route predicate that references a missing Level"
		)
	end
	local runtimeStage = firstExport.bundle ~= nil and firstExport.bundle.stages.stage_default or nil
	local runtimeGraph = runtimeStage ~= nil and runtimeStage.pathGraphs[authoredGraphId] or nil
	local autoPlaceCount = 0
	for key, cell in authoredProductionStage.grid.cells do
		if cell.roles ~= nil and cell.roles.AutoPlace == true then
			autoPlaceCount += 1
			expectEqual(
				runtimeStage ~= nil and runtimeStage.routeNoBuildMask[key],
				nil,
				`production auto-place cell {key} stays outside the route corridor`
			)
		end
	end
	expectEqual(autoPlaceCount, 6, "production stage provides six safe auto-place cells")
	local firstRuntimeEdgeId: string? = nil
	if runtimeGraph ~= nil then
		for edgeId in runtimeGraph.edges do
			if firstRuntimeEdgeId == nil or edgeId < firstRuntimeEdgeId then
				firstRuntimeEdgeId = edgeId
			end
		end
	end
	local firstRuntimeEdge = if firstRuntimeEdgeId ~= nil then runtimeGraph.edges[firstRuntimeEdgeId] else nil
	expectEqual(
		firstRuntimeEdge ~= nil and firstRuntimeEdge.length > 0,
		true,
		"runtime export includes baked edge arc length"
	)
	local storedStageChecksum = runtimeStage.checksum
	runtimeStage.checksum = nil
	local recomputedStageChecksum = StageSchema.checksum(runtimeStage)
	runtimeStage.checksum = storedStageChecksum
	expectEqual(
		recomputedStageChecksum,
		storedStageChecksum,
		"runtime stage checksum is derived after projection, baking, and route masking"
	)
	local storedBundleChecksum = firstExport.bundle.checksum
	firstExport.bundle.checksum = nil
	local recomputedBundleChecksum = StageSchema.checksum(firstExport.bundle)
	firstExport.bundle.checksum = storedBundleChecksum
	expectEqual(
		recomputedBundleChecksum,
		storedBundleChecksum,
		"runtime bundle checksum includes projected stage checksums but not itself"
	)
	local routeMaskKey = if runtimeStage ~= nil then next(runtimeStage.routeNoBuildMask) else nil
	expectEqual(
		routeMaskKey ~= nil,
		true,
		"runtime export derives route reservation without rewriting authored cells"
	)
	expectEqual(
		firstRuntimeEdgeId ~= nil and authoringGraph.edges[firstRuntimeEdgeId].samples,
		nil,
		"runtime baking does not mutate the authoring working copy"
	)
	do
		local projectionProject = serde.decode("json", serde.encode("json", authoringProject))
		local projectionStage = projectionProject.stages.stage_default
		local projectionGraph = projectionStage.pathGraphs[authoredGraphId]
		local projectionEdgeId = assert(firstRuntimeEdgeId, "production runtime graph has no edge")
		local projectionEdge = projectionGraph.edges[projectionEdgeId]
		local projectionNode = projectionGraph.nodes[projectionEdge.fromNodeId]
		local projectionLaneProfile = projectionGraph.laneProfiles[projectionEdge.laneProfileId]
		local projectionCellKey =
			assert(next(projectionStage.grid.cells), "production stage has no cell override")
		local projectionCell = projectionStage.grid.cells[projectionCellKey]
		local projectionRole = assert(next(projectionCell.roles), "production cell override has no role")
		projectionStage.editorOnlyField = true
		projectionStage.grid.editorOnlyField = true
		projectionStage.grid.defaultCell.editorOnlyField = true
		projectionCell.editorOnlyField = true
		projectionGraph.editorOnlyField = true
		projectionEdge.editorOnlyField = true
		projectionEdge.outHandleOffset.editorOnlyField = true
		projectionNode.editorOnlyField = true
		projectionNode.tags.editorOnlyField = "editor-only-tag"
		projectionLaneProfile.editorOnlyField = true
		projectionLaneProfile.offsets.editorOnlyField = math.huge
		projectionEdge.predicates.editorOnlyField = { kind = "EditorOnlyPredicate" }
		projectionStage.modifierIds.editorOnlyField = "editor-only-modifier"
		projectionStage.unlockRequirements.editorOnlyField = {
			kind = "StageUnlocked",
			stageId = "stage_default",
		}
		local projectionExport = StageExport.bake(projectionProject)
		local projectedStage = projectionExport.bundle and projectionExport.bundle.stages.stage_default
		local projectedGraph = projectedStage and projectedStage.pathGraphs[authoredGraphId]
		local projectedEdge = projectedGraph and projectedGraph.edges[projectionEdgeId]
		local projectedNode = projectedGraph and projectedGraph.nodes[projectionEdge.fromNodeId]
		local projectedLaneProfile = projectedGraph
			and projectedGraph.laneProfiles[projectionEdge.laneProfileId]
		local projectedCell = projectedStage and projectedStage.grid.cells[projectionCellKey]
		expectEqual(
			projectedStage ~= nil
				and projectedStage.editorOnlyField == nil
				and projectedStage.grid.editorOnlyField == nil
				and projectedStage.grid.defaultCell.editorOnlyField == nil
				and projectedCell ~= nil
				and projectedCell.editorOnlyField == nil
				and projectedGraph.editorOnlyField == nil
				and projectedEdge.editorOnlyField == nil
				and projectedEdge.outHandleOffset.editorOnlyField == nil
				and projectedNode.editorOnlyField == nil
				and projectedNode.tags.editorOnlyField == nil
				and projectedLaneProfile.editorOnlyField == nil
				and projectedLaneProfile.offsets.editorOnlyField == nil
				and projectedEdge.predicates.editorOnlyField == nil
				and projectedStage.modifierIds.editorOnlyField == nil
				and projectedStage.unlockRequirements.editorOnlyField == nil,
			true,
			"runtime projection strips undeclared authoring fields at every DTO boundary"
		)
		expectEqual(
			projectionExport.bundle ~= nil
				and firstExport.bundle ~= nil
				and projectionExport.bundle.checksum == firstExport.bundle.checksum,
			true,
			"unknown authoring fields do not change the runtime bundle checksum"
		)
		expectEqual(
			projectedCell ~= nil
				and projectedCell.roles[projectionRole] == projectionCell.roles[projectionRole]
				and projectedEdge.metadata.pathAssetId == projectionEdge.metadata.pathAssetId,
			true,
			"runtime projection preserves declared role and edge metadata dictionaries"
		)
		expectEqual(
			projectionStage.editorOnlyField
				and projectionEdge.outHandleOffset.editorOnlyField
				and projectionLaneProfile.editorOnlyField
				and projectionNode.tags.editorOnlyField == "editor-only-tag"
				and projectionStage.modifierIds.editorOnlyField == "editor-only-modifier",
			true,
			"runtime projection does not strip unknown fields from the authoring working copy"
		)
		projectionStage.metadata.runtimeMetadataMarker = true
		local metadataProjectionExport = StageExport.bake(projectionProject)
		local metadataProjectedStage = metadataProjectionExport.bundle
			and metadataProjectionExport.bundle.stages.stage_default
		expectEqual(
			metadataProjectedStage ~= nil
				and metadataProjectedStage.metadata.runtimeMetadataMarker
				and projectionExport.bundle ~= nil
				and metadataProjectionExport.bundle.checksum ~= projectionExport.bundle.checksum,
			true,
			"declared runtime metadata survives projection and changes the bundle checksum"
		)
	end
	do
		local invalidUnlockProject = serde.decode("json", serde.encode("json", authoringProject))
		invalidUnlockProject.stages.stage_default.unlockRequirements = {
			{ kind = "WaveRange", minimum = 1 },
		}
		local invalidUnlockExport = StageExport.bake(invalidUnlockProject)
		local foundInvalidUnlockRequirement = false
		for _, issue in invalidUnlockExport.issues do
			if issue.code == "InvalidUnlockRequirement" then
				foundInvalidUnlockRequirement = true
				break
			end
		end
		expectEqual(
			invalidUnlockExport.bundle == nil and foundInvalidUnlockRequirement,
			true,
			"runtime export rejects route-only predicates in stage unlock requirements"
		)
	end
	do
		local staleOutgoingProject = serde.decode("json", serde.encode("json", authoringProject))
		local staleGraph = staleOutgoingProject.stages.stage_default.pathGraphs[authoredGraphId]
		local projectionEdgeId = assert(firstRuntimeEdgeId, "production runtime graph has no edge")
		local sourceNodeId = staleGraph.edges[projectionEdgeId].fromNodeId
		staleGraph.outgoingEdgeIds = {}
		local staleOutgoingExport = StageExport.bake(staleOutgoingProject)
		local rebuiltGraph = staleOutgoingExport.bundle
			and staleOutgoingExport.bundle.stages.stage_default.pathGraphs[authoredGraphId]
		local rebuiltOutgoing = rebuiltGraph and rebuiltGraph.outgoingEdgeIds[sourceNodeId]
		expectEqual(
			rebuiltOutgoing ~= nil and table.find(rebuiltOutgoing, projectionEdgeId) ~= nil,
			true,
			"runtime export validates edge maps and rebuilds stale authoring outgoing caches"
		)
	end
	do
		local traversalConflict = serde.decode("json", serde.encode("json", authoringProject))
		local conflictingCell = traversalConflict.stages.stage_default.grid.cells[routeMaskKey] or {}
		conflictingCell.enemyTraversalPolicy = "Blocked"
		traversalConflict.stages.stage_default.grid.cells[routeMaskKey] = conflictingCell
		local conflictExport = StageExport.bake(traversalConflict)
		expectEqual(conflictExport.bundle, nil, "enemy-blocked route corridors prevent export")
		local foundTraversalConflict = false
		for _, issue in conflictExport.issues do
			if issue.code == "RouteTraversalConflict" and issue.objectId == routeMaskKey then
				foundTraversalConflict = true
				break
			end
		end
		expectEqual(foundTraversalConflict, true, "route conflict validation identifies the authored cell")
		do
			local preview = StageExport.preview(traversalConflict.stages.stage_default)
			local previewGraph = if preview ~= nil then preview.pathGraphs[authoredGraphId] else nil
			local previewEdge = if previewGraph ~= nil then previewGraph.edges[firstRuntimeEdgeId] else nil
			expectEqual(
				preview ~= nil and preview.routeNoBuildMask[routeMaskKey] == true,
				true,
				"invalid working stages still expose the derived route footprint to the editor"
			)
			expectEqual(
				previewEdge ~= nil and #previewEdge.samples > 1,
				true,
				"invalid working stages still bake their visible spline preview"
			)
			expectEqual(
				traversalConflict.stages.stage_default.pathGraphs[authoredGraphId].edges[firstRuntimeEdgeId].samples,
				nil,
				"editor route preview does not mutate authored graph data"
			)
		end
	end
	do
		local coincidentEdge = serde.decode("json", serde.encode("json", authoringProject))
		local coincidentGraph = coincidentEdge.stages.stage_default.pathGraphs[authoredGraphId]
		local zeroEdge = coincidentGraph.edges[firstRuntimeEdgeId]
		local zeroFromPosition = coincidentGraph.nodes[zeroEdge.fromNodeId].position
		coincidentGraph.nodes[zeroEdge.toNodeId].position = {
			x = zeroFromPosition.x,
			y = zeroFromPosition.y,
			z = zeroFromPosition.z,
		}
		zeroEdge.outHandleOffset = { x = 0, y = 0, z = 0 }
		zeroEdge.inHandleOffset = { x = 0, y = 0, z = 0 }
		expectEqual(StageExport.bake(coincidentEdge).bundle, nil, "zero-length Bezier edges prevent export")
	end
end

-- Rune altar: weighted rolls, pity, flat configured cost, and permanent multiplier.
expectEqual(
	RuneLogic.weightTotal(RuneCatalog.rarities),
	10000,
	"rune rarity weights sum to exactly 10000 so disclosed odds total 100%"
)

-- Glyphs: 5-16 digit strings name Roblox image assets; everything else is text.
expectEqual(
	RuneLogic.glyphImage("105300168575798"),
	"rbxassetid://105300168575798",
	"digit glyphs resolve to Roblox image asset content"
)
expectEqual(RuneLogic.glyphImage("🔥"), nil, "emoji glyphs stay display text")
expectEqual(RuneLogic.glyphImage("7"), nil, "short digit glyphs stay display text")
expectEqual(RuneLogic.glyphImage("12345678901234567"), nil, "overlong digit strings stay display text")
expectEqual(RuneLogic.glyphImage("123a5"), nil, "mixed alphanumeric glyphs stay display text")
local oddsSum = 0
for _, rarity in RuneCatalog.rarities do
	oddsSum += RuneLogic.oddsPercent(rarity)
	expectEqual(
		#RuneCatalog.runesForRarity(rarity.id) > 0,
		true,
		`rarity {rarity.id} has at least one authored rune`
	)
end
expectEqual(math.abs(oddsSum - 100) < 1e-9, true, "displayed rune odds add up to exactly 100 percent")
for _, rune in RuneCatalog.runes do
	expectEqual(RuneCatalog.rarity(rune.rarityId) ~= nil, true, `rune {rune.id} maps to a real rarity`)
	expectEqual(rune.bonusPercent > 0, true, `rune {rune.id} grants a positive generation bonus`)
end

local commonIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 0, 40, 4)
expectEqual(commonIndex, 1, "lowest roll lands on the most common rarity")
local boundaryIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0.54, 0, 40, 4)
expectEqual(boundaryIndex, 2, "exact tier boundary promotes to the next rarity")
local mythicIndex = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0.9999, 0, 40, 4)
expectEqual(mythicIndex, #RuneCatalog.rarities, "highest roll lands on the rarest rarity")

local pityIndex, pityTriggered = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 39, 40, 4)
expectEqual(pityTriggered, true, "pity triggers on the guaranteed roll")
expectEqual(pityIndex >= 4, true, "pity roll cannot drop below the guaranteed rarity")
local noPityIndex, noPityTriggered = RuneLogic.pickRarityIndex(RuneCatalog.rarities, 0, 38, 40, 4)
expectEqual(noPityTriggered, false, "pity stays quiet before the threshold")
expectEqual(noPityIndex, 1, "regular rolls still hit common before the pity threshold")

expectEqual(RuneLogic.pickRuneIndex(2, 0), 1, "rune pick lower bound")
expectEqual(RuneLogic.pickRuneIndex(2, 0.99), 2, "rune pick upper bound")
expectEqual(RuneLogic.pickRuneIndex(0, 0.5), 0, "empty rune pools pick nothing")

expectEqual(RuneLogic.rollCost(75, 1.12, 0, 250000), 75, "first roll costs the base price")
expectEqual(RuneLogic.rollCost(75, 1, 500, 75), 75, "configured rune cost stays flat")
expectEqual(RuneLogic.rollCost(75, 1.12, 2, 250000), math.floor(75 * 1.12 * 1.12), "roll cost escalates")
expectEqual(RuneLogic.rollCost(75, 1.12, 500, 250000), 250000, "roll cost clamps at the configured cap")

local ownedSample = {
	ember_rune = { count = 2 },
	celestial_rune = { count = 1 },
	forgotten_rune = { count = 5 },
	corrupt_rune = { count = 0 / 0 },
}
expectEqual(
	RuneLogic.totalBonusPercent(ownedSample, RuneCatalog),
	104,
	"generation bonus sums owned copies and skips unknown or corrupt entries"
)
expectEqual(
	math.floor(RuneLogic.multiplier({ owned = ownedSample }, RuneCatalog) * 100 + 0.5),
	204,
	"rune multiplier converts the summed bonus into an earnings factor"
)
expectEqual(RuneLogic.multiplier(nil, RuneCatalog), 1, "missing rune state keeps a neutral multiplier")
expectEqual(RuneLogic.countOwned(ownedSample), 8, "owned counter keeps unknown saved runes")
expectEqual(
	RuneLogic.countOwnedForRarity(ownedSample, "common", RuneCatalog),
	2,
	"per-rarity counter follows the catalog"
)

local runeMigrated = MigrationCore.migrate({ schemaVersion = 4, coins = 5 }, {
	schemaVersion = 5,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0 },
}, 5)
expectEqual(type(runeMigrated.runes), "table", "older profiles gain the rune state on migration")
expectEqual(runeMigrated.runes.totalRolls, 0, "migrated rune state starts unrolled")
local runePreserved = MigrationCore.migrate({
	schemaVersion = 5,
	coins = 5,
	runes = { owned = { mystery_rune = { count = 3 } }, totalRolls = 7, rollsSincePity = 2 },
}, {
	schemaVersion = 5,
	coins = 0,
	runes = { owned = {}, totalRolls = 0, rollsSincePity = 0 },
}, 5)
expectEqual(
	runePreserved.runes.owned.mystery_rune.count,
	3,
	"unknown saved runes survive migration untouched"
)
expectEqual(runePreserved.runes.totalRolls, 7, "rune roll history survives migration")

local runeServiceSource = fs.readFile("src/server/Services/RuneService.luau")
expectEqual(
	string.find(runeServiceSource, "GetPolicyInfoForPlayerAsync", 1, true) ~= nil,
	true,
	"rune rolls check the paid-random-items policy"
)
expectEqual(
	string.find(runeServiceSource, "ArePaidRandomItemsRestricted", 1, true) ~= nil,
	true,
	"rune rolls respect ArePaidRandomItemsRestricted"
)
expectEqual(
	string.find(runeServiceSource, "OnServerEvent", 1, true),
	nil,
	"rune rolls are server-initiated; no client remote can trigger them"
)
local runeConfigSource = fs.readFile("src/shared/TemplateConfig.luau")
expectEqual(
	string.find(runeConfigSource, "pityMinimumRarity", 1, true) ~= nil,
	true,
	"rune pity guarantee is configurable"
)
expectEqual(
	string.find(runeConfigSource, "mockStartingCoins = 100_000_000_000", 1, true) ~= nil,
	true,
	"Studio mock testing starts with 100B coins"
)
expectEqual(
	string.find(runeConfigSource, '"costGrowth", 1', 1, true) ~= nil,
	true,
	"configured rune price does not grow after each roll"
)
expectEqual(
	string.find(runeConfigSource, '"maxCost", 75', 1, true) ~= nil,
	true,
	"configured rune price cap matches the flat base price"
)
local designerConfigSource = fs.readFile("src/shared/DesignerConfig.luau")
expectEqual(
	string.find(designerConfigSource, "startingAmount = 100_000_000_000", 1, true) ~= nil,
	true,
	"template test currency starts at 100B coins"
)

local runeUi = fs.readFile("src/ui/RuneCircleUI.model.json")
for _, authoredRuneObject in
	{
		'"Name": "RevealCard"',
		'"Name": "RarityBanner"',
		'"Name": "GlassArtwork"',
		'"Name": "RuneHalo"',
		'"Name": "NewTag"',
		'"Name": "PityTag"',
		'"Name": "OddsPanel"',
		'"Name": "OddsArtwork"',
		'"Name": "RarityRow6"',
		'"Name": "TotalChip"',
		'"Name": "RestrictedNote"',
		'"Name": "ModePanel"',
		'"Name": "ModeButton4"',
		'"Name": "MomentumMeter"',
		'"Name": "ModeHint"',
		'"Name": "MilestoneLine"',
		'"Name": "GlyphImage"',
		"rbxassetid://125907024425133",
		"rbxassetid://111977708425543",
	}
do
	expectEqual(
		string.find(runeUi, authoredRuneObject, 1, true) ~= nil,
		true,
		`rune UI pre-authors {authoredRuneObject}`
	)
end
local runeSign = fs.readFile("src/ui/RuneCircleSign.model.json")
for _, authoredSignObject in
	{
		'"Name": "CostLine"',
		'"Name": "StatusLine"',
		'"Name": "AutoChip"',
		'"Name": "RuneBadge"',
		'"Name": "CoinWatermark"',
		"FOREST RUNES",
		"rbxassetid://105300168575798",
	}
do
	expectEqual(
		string.find(runeSign, authoredSignObject, 1, true) ~= nil,
		true,
		`rune sign pre-authors {authoredSignObject}`
	)
end

do
	-- Rune channel modes: momentum tiers, luck-adjusted odds, copy milestones,
	-- and the strongest-temporary-boost rule for surge channeling.
	local sampleTiers = {
		{ atSeconds = 10, value = 1.25 },
		{ atSeconds = 30, value = 1.75 },
		{ atSeconds = 60, value = 2.5 },
	}
	local tierIndexBelow, tierValueBelow = RuneLogic.momentumTier(sampleTiers, 9.9)
	expectEqual(tierIndexBelow, 0, "momentum below the first threshold reaches no tier")
	expectEqual(tierValueBelow, 1, "momentum below the first threshold keeps a neutral value")
	local tierIndexExact, tierValueExact = RuneLogic.momentumTier(sampleTiers, 10)
	expectEqual(tierIndexExact, 1, "momentum reaches a tier exactly at its threshold")
	expectEqual(tierValueExact, 1.25, "tier value follows the reached tier")
	local tierIndexTop, tierValueTop = RuneLogic.momentumTier(sampleTiers, 500)
	expectEqual(tierIndexTop, 3, "long channels reach the top tier")
	expectEqual(tierValueTop, 2.5, "top tier keeps the configured value")
	local tierIndexNaN, tierValueNaN = RuneLogic.momentumTier(sampleTiers, 0 / 0)
	expectEqual(tierIndexNaN, 0, "corrupt momentum reaches no tier")
	expectEqual(tierValueNaN, 1, "corrupt momentum keeps a neutral value")
	local tierIndexEmpty = RuneLogic.momentumTier({}, 100)
	expectEqual(tierIndexEmpty, 0, "empty tier lists never promote")
	expectEqual(RuneLogic.nextTierAt(sampleTiers, 5), 10, "next tier threshold is reported for meters")
	expectEqual(RuneLogic.nextTierAt(sampleTiers, 30), 60, "reached tiers advance the next threshold")
	expectEqual(RuneLogic.nextTierAt(sampleTiers, 60), nil, "the top tier has no next threshold")

	for _, luckFactor in { 1.25, 1.75, 2.5 } do
		local adjusted = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, luckFactor, 500)
		expectEqual(
			RuneLogic.weightTotal(adjusted),
			10000,
			`luck factor {luckFactor} keeps rarity weights summing to exactly 10000`
		)
		local adjustedOdds = 0
		for index, rarity in adjusted do
			adjustedOdds += RuneLogic.oddsPercent(rarity)
			expectEqual(rarity.id, RuneCatalog.rarities[index].id, "luck keeps rarity order and ids")
			if index >= 2 then
				expectEqual(
					rarity.weight >= RuneCatalog.rarities[index].weight,
					true,
					`luck never lowers the {rarity.id} weight`
				)
			end
		end
		expectEqual(
			math.abs(adjustedOdds - 100) < 1e-9,
			true,
			`luck factor {luckFactor} still discloses odds totaling exactly 100 percent`
		)
	end
	local neutralLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 1, 500)
	expectEqual(
		neutralLuck[1].weight,
		RuneCatalog.rarities[1].weight,
		"luck factor 1 leaves weights untouched"
	)
	local weakLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 0.5, 500)
	expectEqual(weakLuck[2].weight, RuneCatalog.rarities[2].weight, "luck below 1 never nerfs odds")
	local nanLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 0 / 0, 500)
	expectEqual(
		nanLuck[#nanLuck].weight,
		RuneCatalog.rarities[#RuneCatalog.rarities].weight,
		"corrupt luck factors leave weights untouched"
	)
	local extremeLuck = RuneLogic.luckAdjustedRarities(RuneCatalog.rarities, 1000, 500)
	expectEqual(RuneLogic.weightTotal(extremeLuck), 10000, "extreme luck keeps the weight invariant")
	expectEqual(extremeLuck[1].weight >= 500, true, "extreme luck respects the common weight floor")
	local luckyCommon = RuneLogic.pickRarityIndex(extremeLuck, 0, 0, 40, 4)
	expectEqual(luckyCommon, 1, "the lowest roll still lands on the first rarity under luck")
	local luckyTop = RuneLogic.pickRarityIndex(extremeLuck, 0.9999, 0, 40, 4)
	expectEqual(luckyTop, #extremeLuck, "the highest roll still lands on the rarest rarity under luck")
	local luckyPity, luckyPityTriggered = RuneLogic.pickRarityIndex(extremeLuck, 0, 39, 40, 4)
	expectEqual(luckyPityTriggered, true, "pity still triggers over luck-adjusted odds")
	expectEqual(luckyPity >= 4, true, "pity still promotes over luck-adjusted odds")

	local sampleMilestones = {
		{ copies = 5, multiplier = 1.25 },
		{ copies = 10, multiplier = 1.5 },
		{ copies = 25, multiplier = 2 },
	}
	expectEqual(
		RuneLogic.milestoneMultiplier(sampleMilestones, 4),
		1,
		"below the first milestone nothing changes"
	)
	expectEqual(
		RuneLogic.milestoneMultiplier(sampleMilestones, 5),
		1.25,
		"reaching a milestone applies its multiplier"
	)
	expectEqual(RuneLogic.milestoneMultiplier(sampleMilestones, 26), 2, "the highest reached milestone wins")
	expectEqual(RuneLogic.milestoneMultiplier(nil, 5), 1, "missing milestones stay neutral")
	expectEqual(
		RuneLogic.milestoneMultiplier(
			{ { copies = 2, multiplier = 0 / 0 }, { copies = 3, multiplier = 0.1 } },
			5
		),
		1,
		"corrupt milestone entries are ignored"
	)
	local upcomingMilestone = RuneLogic.nextMilestone(sampleMilestones, 5)
	expectEqual(
		if upcomingMilestone ~= nil then upcomingMilestone.copies else 0,
		10,
		"the next milestone reports the closest target"
	)
	expectEqual(RuneLogic.nextMilestone(sampleMilestones, 25), nil, "maxed milestones report no next target")
	local milestoneOwned = {
		ember_rune = { count = 5 },
		celestial_rune = { count = 1 },
		forgotten_rune = { count = 25 },
		corrupt_rune = { count = 0 / 0 },
	}
	expectEqual(
		RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog),
		110,
		"without milestones duplicates still stack linearly"
	)
	expectEqual(
		RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog, sampleMilestones),
		112.5,
		"copy milestones scale known runes while unknown and corrupt entries still contribute nothing"
	)
	expectEqual(
		RuneLogic.totalBonusPercent(milestoneOwned, RuneCatalog, sampleMilestones, 50),
		50,
		"an explicit bonus cap clamps the milestone-scaled total"
	)

	local sampleModes = {
		{
			id = "luck",
			name = "Lucky",
			kind = "luck",
			unlock = { kind = "always", value = 0 },
			tiers = sampleTiers,
		},
		{
			id = "surge",
			name = "Surge",
			kind = "surge",
			unlock = { kind = "totalRolls", value = 25 },
			tiers = sampleTiers,
		},
		{
			id = "stage",
			name = "Stage",
			kind = "surge",
			unlock = { kind = "provider", value = 0 },
			tiers = sampleTiers,
		},
	}
	expectEqual(
		RuneLogic.resolveModeId("surge", sampleModes, "luck"),
		"surge",
		"a saved known mode is respected"
	)
	expectEqual(
		RuneLogic.resolveModeId("ghost_mode", sampleModes, "luck"),
		"luck",
		"an unknown saved mode resolves to the default without being overwritten"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(sampleModes[1], { totalRolls = 0, runesOwned = 0 }),
		true,
		"always modes unlock immediately"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(sampleModes[2], { totalRolls = 24, runesOwned = 0 }),
		false,
		"threshold modes stay locked below the requirement"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(sampleModes[2], { totalRolls = 25, runesOwned = 0 }),
		true,
		"threshold modes unlock at the requirement"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(sampleModes[3], { totalRolls = 100, runesOwned = 100 }),
		false,
		"provider modes fail closed without an answer"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(sampleModes[3], { totalRolls = 0, runesOwned = 0 }, true),
		true,
		"provider modes unlock only on an explicit yes"
	)
	expectEqual(
		RuneLogic.isModeUnlocked(
			{ id = "x", unlock = { kind = "mystery" } },
			{ totalRolls = 0, runesOwned = 0 }
		),
		false,
		"unknown unlock kinds fail closed"
	)

	local fallbackModes = {
		{
			id = "luck",
			name = "Lucky",
			kind = "luck",
			unlock = { kind = "always", value = 0 },
			tiers = { { atSeconds = 10, value = 1.25 } },
		},
	}
	local normalizedModes = RuneModeConfig.normalize({
		{ id = "luck", name = "Custom Luck", kind = "luck", tiers = { { atSeconds = 5, value = 1.5 } } },
		{
			id = "surge",
			name = "Surge",
			kind = "surge",
			unlock = { kind = "totalRolls", value = 10 },
			tiers = { { atSeconds = 5, value = 1.2 }, { atSeconds = 15, value = 1.4 } },
		},
	}, fallbackModes)
	expectEqual(#normalizedModes, 2, "valid channel mode overrides pass through")
	expectEqual(normalizedModes[1].unlock.kind, "always", "a missing unlock defaults to always")
	local duplicateModes = RuneModeConfig.normalize({
		{ id = "luck", kind = "luck", tiers = { { atSeconds = 5, value = 1.5 } } },
		{ id = "luck", kind = "surge", tiers = { { atSeconds = 5, value = 1.5 } } },
	}, fallbackModes)
	expectEqual(#duplicateModes, 1, "duplicate mode ids fall back to the authored defaults")
	expectEqual(duplicateModes[1].name, "Lucky", "the wholesale fallback keeps the authored mode")
	local badKindModes = RuneModeConfig.normalize(
		{ { id = "warp", kind = "teleport", tiers = { { atSeconds = 5, value = 1.5 } } } },
		fallbackModes
	)
	expectEqual(badKindModes[1].id, "luck", "unknown mode kinds fall back wholesale")
	local descendingModes = RuneModeConfig.normalize({
		{
			id = "luck",
			kind = "luck",
			tiers = { { atSeconds = 30, value = 1.5 }, { atSeconds = 10, value = 2 } },
		},
	}, fallbackModes)
	expectEqual(descendingModes[1].tiers[1].atSeconds, 10, "descending tier thresholds fall back wholesale")
	local weakTierModes = RuneModeConfig.normalize(
		{ { id = "luck", kind = "luck", tiers = { { atSeconds = 10, value = 0.5 } } } },
		fallbackModes
	)
	expectEqual(weakTierModes[1].tiers[1].value, 1.25, "tier values below 1 fall back wholesale")
	local crowdedModes = {}
	for index = 1, 6 do
		table.insert(crowdedModes, {
			id = `mode{index}`,
			kind = "luck",
			tiers = { { atSeconds = 10, value = 1.25 } },
		})
	end
	expectEqual(
		#RuneModeConfig.normalize(crowdedModes, fallbackModes),
		4,
		"channel modes cap at the four authored buttons"
	)
	expectEqual(
		#RuneModeConfig.normalizeMilestones(
			{ { copies = 5, multiplier = 1.25 }, { copies = 10, multiplier = 1.5 } },
			{}
		),
		2,
		"valid milestone overrides pass through"
	)
	local weakeningMilestones = RuneModeConfig.normalizeMilestones(
		{ { copies = 5, multiplier = 1.5 }, { copies = 10, multiplier = 1.2 } },
		{ { copies = 3, multiplier = 1.1 } }
	)
	expectEqual(weakeningMilestones[1].copies, 3, "weakening milestone curves fall back wholesale")
	expectEqual(
		#RuneModeConfig.normalizeMilestones({}, { { copies = 3, multiplier = 1.1 } }),
		0,
		"an explicit empty list disables milestones"
	)

	local potionBoosts = { { id = "p", expiresAt = 1000, multiplier = 2 } }
	expectEqual(
		Calculations.temporaryMultiplier(potionBoosts, 0, 1.2),
		2,
		"the strongest potion beats a weaker channel surge; they never stack"
	)
	expectEqual(
		Calculations.temporaryMultiplier(potionBoosts, 0, 3),
		3,
		"a stronger channel surge beats the potion; they never stack"
	)
	expectEqual(
		Calculations.temporaryMultiplier(potionBoosts, 0),
		2,
		"temporary multiplier works without a channel value"
	)
	expectEqual(
		Calculations.temporaryMultiplier(potionBoosts, 0, 0 / 0),
		2,
		"corrupt channel values stay neutral"
	)
	expectEqual(
		Calculations.temporaryMultiplier({}, 0, 0.25),
		1,
		"channel surges below 1 never punish earnings"
	)
	expectEqual(
		Calculations.compositeMultiplier(0.5, 0.1, 2, 1.5),
		(1 + 0.5 + 0.1) * 2 * 1.5,
		"composite multiplier composes additive bonuses with temporary and permanent buckets"
	)
	expectEqual(
		Calculations.permanentMultiplier(0.1, true, 2),
		1.1 * 2,
		"offline multiplier keeps premium and runes"
	)
	expectEqual(
		Calculations.permanentMultiplier(0.1, false, 2),
		2,
		"offline multiplier drops premium for free players"
	)
	expectEqual(
		Calculations.earningsMultiplier(3, true, potionBoosts, 0, 0.1, 0.5, 0.1),
		(1 + 0.3 + 0.1) * 2,
		"earnings multiplier still composes social, premium, and the strongest potion"
	)

	local modeMigrated = MigrationCore.migrate({
		schemaVersion = 6,
		coins = 5,
		runes = { owned = { mystery_rune = { count = 3 } }, totalRolls = 7, rollsSincePity = 2 },
	}, {
		schemaVersion = 7,
		coins = 0,
		runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "luck" },
	}, 7)
	expectEqual(modeMigrated.runes.selectedMode, "luck", "older profiles gain the default channel mode")
	expectEqual(
		modeMigrated.runes.owned.mystery_rune.count,
		3,
		"unknown saved runes survive the v7 migration"
	)
	expectEqual(modeMigrated.runes.totalRolls, 7, "roll history survives the v7 migration")
	local modePreserved = MigrationCore.migrate({
		schemaVersion = 7,
		coins = 5,
		runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "surge" },
	}, {
		schemaVersion = 7,
		coins = 0,
		runes = { owned = {}, totalRolls = 0, rollsSincePity = 0, selectedMode = "luck" },
	}, 7)
	expectEqual(modePreserved.runes.selectedMode, "surge", "a saved mode selection survives migration")

	expectEqual(
		string.find(runeServiceSource, "luckAdjustedRarities", 1, true) ~= nil,
		true,
		"rune rolls apply luck-adjusted odds server-side"
	)
	expectEqual(
		string.find(runeServiceSource, "RuneService.setMode", 1, true) ~= nil,
		true,
		"channel mode swaps are validated in RuneService"
	)
	expectEqual(
		string.find(runeServiceSource, "channelEarningsMultiplier", 1, true) ~= nil,
		true,
		"surge channeling exposes a live multiplier"
	)
	expectEqual(
		string.find(runeServiceSource, "Config.runes.tickSeconds", 1, true) ~= nil,
		true,
		"rune tick cadence comes from TemplateConfig"
	)
	expectEqual(
		string.find(runeServiceSource, "TICK_SECONDS", 1, true),
		nil,
		"the hardcoded rune tick constant is gone"
	)
	local runeRemoteSource = fs.readFile("src/server/Services/RemoteService.luau")
	expectEqual(
		string.find(runeRemoteSource, 'SetRuneMode = "runes"', 1, true) ~= nil,
		true,
		"mode swaps are feature-gated behind the runes flag"
	)
	expectEqual(
		string.find(runeRemoteSource, "temporaryMultiplier", 1, true) ~= nil,
		true,
		"snapshots publish the strongest temporary multiplier"
	)
	local economyServiceSource = fs.readFile("src/server/Services/EconomyService.luau")
	expectEqual(
		string.find(economyServiceSource, "setChannelBoostProvider", 1, true) ~= nil,
		true,
		"economy exposes the channel boost provider hook"
	)
	expectEqual(
		string.find(economyServiceSource, "compositeMultiplier", 1, true) ~= nil,
		true,
		"economy composes active earnings through Calculations"
	)
	expectEqual(
		string.find(economyServiceSource, "permanentMultiplier", 1, true) ~= nil,
		true,
		"economy composes offline earnings through Calculations"
	)
	for _, configMarker in
		{
			"defaultChannelMode",
			"channelModes",
			"copyMilestones",
			"tickSeconds",
			"maxTotalBonusPercent",
			"maxOwnedPerRune",
			"revealSeconds",
			"rareAudioMinimumRarity",
			"minCommonWeight",
		}
	do
		expectEqual(
			string.find(runeConfigSource, configMarker, 1, true) ~= nil,
			true,
			`rune channel tunable {configMarker} lives in TemplateConfig`
		)
	end
	local runeClientSource = fs.readFile("src/starter-client/RuneCircle.client.luau")
	expectEqual(
		string.find(runeClientSource, "SetRuneMode", 1, true) ~= nil,
		true,
		"mode buttons send the SetRuneMode intent"
	)
	expectEqual(
		string.find(runeClientSource, "effectiveWeights", 1, true) ~= nil,
		true,
		"the odds panel renders the server-sent effective odds"
	)
	expectEqual(
		string.find(runeClientSource, "RuneLogic.glyphImage", 1, true) ~= nil,
		true,
		"the reveal card resolves image glyphs through the shared RuneLogic rule"
	)
	expectEqual(
		string.find(runeClientSource, "GlyphImage", 1, true) ~= nil,
		true,
		"the reveal card binds the authored GlyphImage slot optionally"
	)
	expectEqual(
		string.find(runeClientSource, "runePromptHasPriority", 1, true) ~= nil
			and string.find(
					runeClientSource,
					"sign.Enabled = panelsVisible or runePromptHasPriority()",
					1,
					true
				)
				~= nil,
		true,
		"the rune billboard yields to the nearer portal prompt instead of stacking world-space cards"
	)
	local incrementalUi = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
	for _, authoredHudObject in { '"RunesValue"', '"ChannelValue"' } do
		expectEqual(
			string.find(incrementalUi, authoredHudObject, 1, true) ~= nil,
			true,
			`incremental HUD pre-authors {authoredHudObject}`
		)
	end
end

local towerDefenseServiceSource = fs.readFile("src/server/Services/TowerDefenseService.luau")
for _, towerDefenseMarker in
	{
		"TowerDefenseService.rollUnit",
		"TowerDefenseService.setLoadout",
		"TowerDefenseService.unlockLoadoutSlot",
		"TowerDefenseService.equipBest",
		"TowerDefenseService.placeUnit",
		"TowerDefenseService.autoPlaceBest",
		"TowerDefenseService.startWave",
		"TowerDefenseService.runWavePlaytest",
		"TowerDefenseService.resetMatch",
		"TowerDefenseService.activateStage",
		"TowerDefenseService.snapshotFor",
		"TowerDefenseService.presentationSnapshot",
		"EconomyService.spendCurrency",
		"TowerDefenseLogic.isBuildableCell",
		"RunService.Heartbeat",
		"StageRuntimeService.chooseEdge",
		"StageRuntimeService.isPlaytesting",
		"maximum travel distance exceeded",
		"Workspace:GetServerTimeNow",
		"buildEnemySpatialIndex",
		"simulationAccumulator",
		"StageCatalog.nextLevelId",
		"StageCatalog.waveSetForStage",
		"TowerDefenseWaves.buildStreams",
		"TowerDefenseWaves.dueStreamIndex",
		"target.armorMultiplier",
		"publishEnemies",
		"publishPlacements",
		"placementRevision",
		"startWaveInternal(player, waveNumber, true)",
	}
do
	expectEqual(
		string.find(towerDefenseServiceSource, towerDefenseMarker, 1, true) ~= nil,
		true,
		`tower defense service includes {towerDefenseMarker}`
	)
end
do
	local autoPlaceAt = assert(
		string.find(towerDefenseServiceSource, "function TowerDefenseService.autoPlaceBest", 1, true),
		"auto-place service exists"
	)
	local nextFunctionAt = assert(
		string.find(towerDefenseServiceSource, "local function enemyDefinitionFor", autoPlaceAt, true),
		"auto-place service has a bounded source section"
	)
	local autoPlaceSource = string.sub(towerDefenseServiceSource, autoPlaceAt, nextFunctionAt - 1)
	expectEqual(
		string.find(autoPlaceSource, "setBestLoadout", 1, true),
		nil,
		"auto-place does not overwrite the player's ordered loadout"
	)
	expectEqual(
		string.find(autoPlaceSource, "local unitId = td.loadout[unitIndex]", 1, true) ~= nil,
		true,
		"auto-place follows the player's unit-slot order"
	)
end
do
	local _, playtestProgressionGuardCount =
		string.gsub(towerDefenseServiceSource, "if profile ~= nil and not match%.isPlaytest then", "")
	expectEqual(
		playtestProgressionGuardCount >= 2
			and string.find(towerDefenseServiceSource, "if not match.isPlaytest then", 1, true) ~= nil,
		true,
		"playtest wave start, loss, and completion stay outside saved profile progression"
	)
	local stageRuntimeServiceSource = fs.readFile("src/server/Services/StageRuntimeService.luau")
	local playtestActivationAt = assert(
		string.find(stageRuntimeServiceSource, "function StageRuntimeService.activateForPlaytest", 1, true),
		"playtest stage activation exists"
	)
	local normalActivationResumeAt = assert(
		string.find(
			stageRuntimeServiceSource,
			"function StageRuntimeService.activeStageId",
			playtestActivationAt,
			true
		),
		"normal active stage lookup follows playtest activation"
	)
	local playtestActivationSource =
		string.sub(stageRuntimeServiceSource, playtestActivationAt, normalActivationResumeAt - 1)
	expectEqual(#playtestActivationSource > 0, true, "playtest stage activation has a testable boundary")
	expectEqual(
		string.find(playtestActivationSource, "selectedStageId", 1, true) == nil
			and string.find(playtestActivationSource, "markDirty", 1, true) == nil,
		true,
		"session-only playtest level activation never selects or saves profile progression"
	)
end
for _, retiredServerPresentation in
	{
		'Instance.new("Part")',
		'Instance.new("BillboardGui")',
		"DebugNameplate",
		"HealthBarFill",
		"setNameplateBar",
		"StudsOffsetWorldSpace",
		"runtimeFolderName",
		"placement.part",
		"match.folder",
	}
do
	expectEqual(
		string.find(towerDefenseServiceSource, retiredServerPresentation, 1, true),
		nil,
		`tower defense service leaves presentation to clients: {retiredServerPresentation}`
	)
end
for _, presentationSnapshotMarker in
	{
		"Players:GetPlayers()",
		"table.sort(players",
		"ownerUserId = player.UserId",
		"slot = slot",
		"id = placement.id",
		"unitId = placement.unitId",
		"column = placement.cell.column",
		"row = placement.cell.row",
		"frame = CFrame.new(placement.position)",
		"return snapshot, placementRevision",
	}
do
	expectEqual(
		string.find(towerDefenseServiceSource, presentationSnapshotMarker, 1, true) ~= nil,
		true,
		`tower presentation snapshot includes {presentationSnapshotMarker}`
	)
end
local sharedTypesSource = fs.readFile("src/shared/Types.luau")
expectCompiles(sharedTypesSource, "shared client snapshot contracts")
local towerPresentationType =
	string.match(sharedTypesSource, "export type TowerDefensePresentationPlacement = (%b{})")
expectEqual(towerPresentationType ~= nil, true, "shared types declare sanitized tower presentation records")
for _, presentationField in { "ownerUserId", "slot", "id", "unitId", "cell", "frame" } do
	expectEqual(
		towerPresentationType ~= nil and string.find(towerPresentationType, presentationField, 1, true) ~= nil,
		true,
		`tower presentation records include sanitized field {presentationField}`
	)
end
for _, privatePresentationField in { "damage", "health", "nextAttackAt", "position", "profile" } do
	expectEqual(
		towerPresentationType and string.find(towerPresentationType, privatePresentationField, 1, true),
		nil,
		`tower presentation records omit server-only field {privatePresentationField}`
	)
end
expectEqual(
	string.find(sharedTypesSource, "towerPlacements: { TowerDefensePresentationPlacement }", 1, true) ~= nil,
	true,
	"initial client snapshots include all-player tower presentation records"
)
expectEqual(
	string.find(sharedTypesSource, "towerPlacementRevision: number?", 1, true) ~= nil,
	true,
	"client snapshots order tower presentation records with a revision"
)
expectEqual(
	string.find(templateConfigSource, "towerVisuals", 1, true) ~= nil
		and string.find(templateConfigSource, 'folderName = "StagewrightClientTowers"', 1, true) ~= nil,
	true,
	"tower presentation styling and folder ownership are configured for clients"
)
expectEqual(
	string.find(templateConfigSource, "runtimeFolderName", 1, true),
	nil,
	"tower configuration retires the unused server presentation folder"
)
local stageRuntimeSource = fs.readFile("src/server/Services/StageRuntimeService.luau")
expectCompiles(fs.readFile("src/shared/StageTypes.luau"), "shared stage DTO contracts")
expectCompiles(fs.readFile("src/shared/StageCell.luau"), "shared layered-cell resolver")
expectCompiles(fs.readFile("src/shared/StageCatalog.luau"), "typed runtime stage catalog")
expectCompiles(stageRuntimeSource, "typed stage runtime service")
expectEqual(
	string.find(stageRuntimeSource, "StageCell.resolve(stage.grid.defaultCell", 1, true) ~= nil,
	true,
	"runtime stage cells inherit every omitted layer from the level default"
)
for _, typedRuntimeMarker in
	{
		"StageTypes.RuntimeStageDefinition",
		"StageTypes.RuntimePathGraph",
	}
do
	expectEqual(
		string.find(stageRuntimeSource, typedRuntimeMarker, 1, true) ~= nil,
		true,
		`runtime stage service consumes the shared DTO contract: {typedRuntimeMarker}`
	)
end
for _, retiredRuntimeOriginDependency in
	{ "Workspace", "defaultPlatformOrigin", "firstPlatformIslandName", "platformOriginName" }
do
	expectEqual(
		string.find(stageRuntimeSource, retiredRuntimeOriginDependency, 1, true),
		nil,
		`runtime stage transforms do not discover Workspace geometry: {retiredRuntimeOriginDependency}`
	)
end
expectEqual(
	string.find(stageRuntimeSource, "UNAVAILABLE_ORIGIN", 1, true) ~= nil
		and string.find(
				stageRuntimeSource,
				"local availabilityProvider: StageAvailabilityProvider = function(_player: Player): boolean\n\treturn false\nend",
				1,
				true
			)
			~= nil,
	true,
	"stage runtime fails closed until its authoritative platform provider is injected"
)
for _, authorityMarker in
	{
		'type(stageId) ~= "string"',
		"#stageId > 80",
		"StageRuntimeService.isUnlocked",
		"ProfileService.get(player)",
		"upgradeLevelProvider(player",
		"profile.currencies",
		"availabilityProvider(player)",
		"activationPublisher(player",
	}
do
	expectEqual(
		string.find(stageRuntimeSource, authorityMarker, 1, true) ~= nil,
		true,
		`stage activation and predicates remain server-authoritative: {authorityMarker}`
	)
end
local stagePlatformSource = fs.readFile("src/server/Services/StagePlatformService.luau")
local stagePlatformCompiles = pcall(function()
	luau.load(stagePlatformSource)
end)
expectEqual(stagePlatformCompiles, true, "six-platform allocator compiles as Luau")
expectEqual(
	string.find(stageRuntimeSource, "StageCatalog.defaultStageId()", 1, true) ~= nil
		and string.find(stagePlatformSource, "StageCatalog.defaultStageId()", 1, true) ~= nil,
	true,
	"runtime stage fallback and platform publication use the exported catalog default"
)
expectEqual(
	string.find(stageRuntimeSource .. stagePlatformSource, "Config.towerDefense.startingStageId", 1, true),
	nil,
	"runtime services do not override the exported starting stage with template configuration"
)
for _, platformMarker in
	{
		"platformSlotCount",
		"centerPartNames",
		"firstPlatformOffsetFromCenter",
		"cachedFirstRelative = configuredRelativeFrame()",
		"CFrame.Angles(0, yaw, 0)",
		"TowerDefensePlatformSlot",
		"StagePlatformService.originForSlot",
		"platformOriginsFolderName",
		"CFrameValue",
		"uniqueCenterAnchor",
		"layoutAttempted",
		"AmbiguousCenter",
		"LayoutSource",
		"OwnerUserId",
		"OwnerDisplayName",
		"ActiveStageId",
		"StagePlatformService.publishActiveStage",
		"StagePlatformService.travelToPlatform",
		"character:PivotTo(origin * CFrame.new(0, travelHeight, 0))",
		"root.AssemblyLinearVelocity = Vector3.zero",
		"root.AssemblyAngularVelocity = Vector3.zero",
		"Players.MaxPlayers",
		"CapacityMatchesSlotCount",
		"Players.PlayerAdded:Connect",
		"publishOwner(existing, player)",
		"StagewrightRuntimeStowed",
		"area.Parent = ServerStorage",
	}
do
	expectEqual(
		string.find(stagePlatformSource, platformMarker, 1, true) ~= nil,
		true,
		`six-platform allocator includes {platformMarker}`
	)
end
expectEqual(
	string.find(stagePlatformSource, "if not RunService:IsStudio() and Players.MaxPlayers ~=", 1, true) ~= nil,
	true,
	"Studio test capacity does not produce a false published-place player warning"
)
do
	local authoringAreaSource = fs.readFile("src/plugins/Stagewright/AuthoringArea.luau")
	local pluginBootstrapSource = fs.readFile("src/plugins/GridPlatformEditPlugin.server.luau")
	expectEqual(
		string.find(authoringAreaSource, "local LAYOUT_VERSION = 4", 1, true) ~= nil
			and string.find(
				authoringAreaSource,
				'existingArea:GetAttribute("StagewrightLayoutVersion") ~= LAYOUT_VERSION',
				1,
				true
			) ~= nil
			and string.find(
					pluginBootstrapSource,
					"local authoringPlatform = AuthoringArea.ensure() or AuthoringArea.findPlatform()",
					1,
					true
				)
				~= nil,
		true,
		"Stagewright startup applies layout v4 and rehomes stale version-3 admin rooms"
	)
end
do
	local configuredCenterFrameStart = assert(
		string.find(stagePlatformSource, "local function configuredCenterFrame(): CFrame?", 1, true),
		"six-platform allocator configured center resolver exists"
	)
	local layoutStart = assert(
		string.find(stagePlatformSource, "local function layout(): (CFrame?, CFrame?)", 1, true),
		"six-platform allocator layout resolver exists"
	)
	local configuredCenterFrameSource =
		string.sub(stagePlatformSource, configuredCenterFrameStart, layoutStart - 1)
	expectEqual(
		string.find(
			configuredCenterFrameSource,
			"local position = Config.towerDefense.platformCenterPosition",
			1,
			true
		)
				~= nil
			and string.find(configuredCenterFrameSource, "return CFrame.new(x, y, z)", 1, true) ~= nil,
		true,
		"six-platform allocator resolves a configured center frame"
	)
	local layoutEnd = assert(
		string.find(stagePlatformSource, "local function claimSlot", layoutStart, true),
		"six-platform allocator layout resolver has a stable boundary"
	)
	local layoutSource = string.sub(stagePlatformSource, layoutStart, layoutEnd - 1)
	local configuredCenterAt =
		string.find(layoutSource, "local configuredCenter = configuredCenterFrame()", 1, true)
	local configuredSourceAt = string.find(layoutSource, 'cachedLayoutSource = "ConfiguredCenter"', 1, true)
	local authoredCenterAt = string.find(
		layoutSource,
		"local center, centerContractValid = uniqueCenterAnchor(Config.towerDefense.centerPartNames)",
		1,
		true
	)
	expectEqual(
		configuredCenterAt ~= nil
			and configuredSourceAt ~= nil
			and authoredCenterAt ~= nil
			and configuredCenterAt < configuredSourceAt
			and configuredSourceAt < authoredCenterAt,
		true,
		"configured platform center takes precedence and publishes the ConfiguredCenter source"
	)
end
for _, multiRouteMarker in
	{
		"StageRuntimeService.spawnNodes",
		"StageLanes.index",
		"laneSequence",
	}
do
	expectEqual(
		string.find(stageRuntimeSource .. towerDefenseServiceSource, multiRouteMarker, 1, true) ~= nil,
		true,
		`server route runtime includes {multiRouteMarker}`
	)
end
expectEqual(
	string.find(stagePlatformSource, "center.CFrame:ToObjectSpace(firstOrigin.CFrame)", 1, true),
	nil,
	"runtime island origins no longer depend on the movable authoring platform"
)
local serverBootstrapSource = fs.readFile("src/server/init.server.luau")
expectEqual(
	string.find(
		templateConfigSource,
		"requirePlatformOnJoin = designerTowerDefense.requirePlatformOnJoin ~= false",
		1,
		true
	)
			~= nil
		and string.find(serverBootstrapSource, "Config.towerDefense.requirePlatformOnJoin", 1, true) ~= nil
		and string.find(serverBootstrapSource, "not StagePlatformService.hasPlatform(player)", 1, true)
			~= nil,
	true,
	"platform-exclusive recipes reject unavailable players while hybrid lobbies may admit them"
)
expectEqual(
	string.find(stagePlatformSource, "if layout() == nil then", 1, true) ~= nil,
	true,
	"unavailable layouts never publish a misleading player platform slot"
)
local stageGridRendererSource = fs.readFile("src/client/Controllers/StageGridRenderer.luau")
local gridRendererCompiles = pcall(function()
	luau.load(stageGridRendererSource)
end)
expectEqual(gridRendererCompiles, true, "six-grid renderer compiles as Luau")
for _, gridRendererMarker in
	{
		"StageCatalog.defaultStageId",
		"platformOriginsFolderName",
		"StagePath.sample",
		"StageCell.resolve(grid.defaultCell, authoredCell)",
		"laneProfile.offsets",
		"StageLanes.resolveWidth(edge.metadata)",
		"routePoint",
		"StagewrightLaneWidth",
		"StagewrightRequestedPathAsset",
		"ActiveStageId",
		"StageCatalog.get(activeStageId)",
		"gridVisuals",
		"LocalTransparencyModifier",
		"Platform_",
		"otherPlatformFade",
		"TowerDefensePlatformSlot",
		"LocalOwner",
		"VisualFade",
		"StagewrightEditorOnly",
		"authoring.areaName",
		"outlines.folderName",
		"hideLegacyEditGridUi",
		'"edit grid"',
		"gridplatformeditor",
		"PlacementPreview",
		"routeNoBuildMask",
		"placementAllowedColor",
		"placementForbiddenColor",
		"placementOccupiedColor",
		"StageGridRenderer.setPlacementMode",
	}
do
	expectEqual(
		string.find(stageGridRendererSource, gridRendererMarker, 1, true) ~= nil,
		true,
		`six-grid renderer includes {gridRendererMarker}`
	)
end
for _, forbiddenGridRendererMarker in { 'Instance.new("SurfaceGui")', 'Instance.new("Frame")', ":Clone(" } do
	expectEqual(
		string.find(stageGridRendererSource, forbiddenGridRendererMarker, 1, true),
		nil,
		`six-grid renderer avoids runtime GUI cloning: {forbiddenGridRendererMarker}`
	)
end
local stageTowerRendererSource = fs.readFile("src/client/Controllers/StageTowerRenderer.luau")
expectCompiles(stageTowerRendererSource, "client tower presentation renderer")
for _, towerRendererMarker in
	{
		"StagewrightClientTowers",
		"towerVisuals",
		'Instance.new("Part")',
		"Enum.PartType.Cylinder",
		"partsByKey",
		"partPool",
		"table.remove(partPool)",
		"table.insert(partPool, part)",
		"recordKey(record.ownerUserId, record.id)",
		"part.CFrame = record.frame",
		"record.cell.column",
		"record.cell.row",
		'SetAttribute("OwnerUserId", record.ownerUserId)',
		'SetAttribute("PlatformSlot", record.slot)',
		'SetAttribute("PlacementId", record.id)',
		'SetAttribute("UnitId", record.unitId)',
		"local enabled = Config.features.towerDefense == true",
		"StageTowerRenderer.localPlacementAtScreen",
		"WorldToViewportPoint",
		"WorldToScreenPoint",
		"DungeonPresentationActive",
		"TowerPlatformPresentationActive",
	}
do
	expectEqual(
		string.find(stageTowerRendererSource, towerRendererMarker, 1, true) ~= nil,
		true,
		`client tower renderer includes {towerRendererMarker}`
	)
end
expectEqual(
	string.find(
		stageTowerRendererSource,
		"local function recordKey(ownerUserId: number, id: string): string",
		1,
		true
	)
			~= nil
		and string.find(stageTowerRendererSource, "`{ownerUserId}:{id}`", 1, true) ~= nil,
	true,
	"tower renderer keys placements by owner and placement id"
)
for _, forbiddenTowerRendererMarker in
	{
		'Instance.new("BillboardGui")',
		'Instance.new("SurfaceGui")',
		'Instance.new("Frame")',
		'Instance.new("TextLabel")',
		'Instance.new("ImageLabel")',
		"GuiObject",
		":Clone(",
	}
do
	expectEqual(
		string.find(stageTowerRendererSource, forbiddenTowerRendererMarker, 1, true),
		nil,
		`client tower renderer avoids dynamic GUI and clones: {forbiddenTowerRendererMarker}`
	)
end
local stageEnemyRendererSource = fs.readFile("src/client/Controllers/StageEnemyRenderer.luau")
expectCompiles(stageEnemyRendererSource, "client enemy rig renderer")
for _, enemyRendererMarker in
	{
		"StagewrightClientEnemies",
		"EnemyRigs",
		"Fallback",
		"modelPools",
		"acquireModel",
		"releaseModel",
		"ScaleTo",
		"PivotTo",
		"StageCatalog.enemyType",
		"HealthBar",
		"UDim2.fromScale",
		"DeathPoof",
		"GetServerTimeNow",
		"StagePath.sample",
		"laneOffset",
	}
do
	expectEqual(
		string.find(stageEnemyRendererSource, enemyRendererMarker, 1, true) ~= nil,
		true,
		`client enemy renderer includes {enemyRendererMarker}`
	)
end
for _, forbiddenEnemyRendererMarker in
	{
		'Instance.new("BillboardGui")',
		'Instance.new("SurfaceGui")',
		'Instance.new("Frame")',
		'Instance.new("TextLabel")',
		'Instance.new("Part")',
		":Destroy(",
	}
do
	expectEqual(
		string.find(stageEnemyRendererSource, forbiddenEnemyRendererMarker, 1, true),
		nil,
		`client enemy renderer clones authored rigs instead of constructing: {forbiddenEnemyRendererMarker}`
	)
end
do
	local enemyRigsModel = serde.decode("json", fs.readFile("src/world/EnemyRigs.model.json"))
	local rigNames: { [string]: any } = {}
	for _, rig in enemyRigsModel.Children do
		rigNames[rig.Name] = rig
	end
	for _, requiredRig in
		{ "Fallback", "forest_grunt", "forest_runner", "bark_bruiser", "sky_wisp", "grove_titan" }
	do
		local rig = rigNames[requiredRig]
		expectEqual(rig ~= nil and rig.ClassName == "Model", true, `enemy rig {requiredRig} is authored`)
		local body: any = nil
		local partCount = 0
		for _, child in rig.Children do
			if child.ClassName == "Part" then
				partCount += 1
				expectEqual(
					child.Properties.Anchored == true and child.Properties.CanCollide == false,
					true,
					`enemy rig {requiredRig} part {child.Name} is anchored and non-colliding`
				)
			end
			if child.Name == "Body" then
				body = child
			end
		end
		expectEqual(partCount <= 4, true, `enemy rig {requiredRig} stays within the four-part budget`)
		expectEqual(body ~= nil, true, `enemy rig {requiredRig} has a Body part`)
		local hasHealthFill = false
		local hasDeathPoof = false
		for _, child in body.Children do
			if child.Name == "HealthBar" and child.ClassName == "BillboardGui" then
				expectEqual(
					child.Properties.Enabled,
					false,
					`enemy rig {requiredRig} health bar starts hidden`
				)
				for _, back in child.Children do
					if back.Name == "Back" then
						for _, fill in back.Children do
							if fill.Name == "Fill" and fill.ClassName == "Frame" then
								hasHealthFill = true
							end
						end
					end
				end
			elseif child.Name == "DeathPoofAttachment" then
				for _, emitter in child.Children do
					if emitter.Name == "DeathPoof" and emitter.ClassName == "ParticleEmitter" then
						expectEqual(
							emitter.Properties.Enabled,
							false,
							`enemy rig {requiredRig} death poof only fires on demand`
						)
						hasDeathPoof = true
					end
				end
			end
		end
		expectEqual(hasHealthFill, true, `enemy rig {requiredRig} authors a Back/Fill health bar`)
		expectEqual(hasDeathPoof, true, `enemy rig {requiredRig} authors a death poof emitter`)
	end
	for enemyTypeId, seededEnemyType in StageWaveDefaults.enemyTypes() do
		expectEqual(
			rigNames[seededEnemyType.modelId] ~= nil,
			true,
			`seeded enemy type {enemyTypeId} has an authored rig`
		)
	end
	for _, projectFile in { "default.project.json", "patches/rng-defender-grid-demo.project.json" } do
		expectEqual(
			string.find(fs.readFile(projectFile), "EnemyRigs.model.json", 1, true) ~= nil,
			true,
			`{projectFile} ships the authored enemy rigs`
		)
	end
end
local stageOwnerControllerSource = fs.readFile("src/client/Controllers/StagePlatformOwnerController.luau")
local stageOwnerControllerCompiles = pcall(function()
	luau.load(stageOwnerControllerSource)
end)
expectEqual(stageOwnerControllerCompiles, true, "platform owner marker controller compiles as Luau")
for _, ownerMarker in
	{
		"OwnerUserId",
		"OwnerDisplayName",
		"GetUserThumbnailAsync",
		"Enum.ThumbnailType.HeadShot",
		"rbxthumb://type=AvatarHeadShot",
		'card:IsA("CanvasGroup")',
		"YOUR PLATFORM",
		"WAITING FOR PLAYER",
		"platformOwnerMarkerHeight",
		"Players:GetPlayers",
		'GetAttributeChangedSignal("TowerDefensePlatformSlot")',
		"owner.DisplayName",
	}
do
	expectEqual(
		string.find(stageOwnerControllerSource, ownerMarker, 1, true) ~= nil,
		true,
		`platform owner display includes {ownerMarker}`
	)
end
for _, forbiddenOwnerMarker in { 'Instance.new("BillboardGui")', 'Instance.new("Frame")', ":Clone(" } do
	expectEqual(
		string.find(stageOwnerControllerSource, forbiddenOwnerMarker, 1, true),
		nil,
		`platform owner display uses authored GUI for {forbiddenOwnerMarker}`
	)
end
local ownerMarkersModel = fs.readFile("src/ui/StagePlatformOwners.model.json")
expectEqual(
	string.find(ownerMarkersModel, '"ClassName": "CanvasGroup"', 1, true) ~= nil,
	true,
	"platform owner cards support authored whole-card fading"
)
expectEqual(
	string.find(ownerMarkersModel, '"MaxDistance": 500', 1, true) == nil
		and string.find(ownerMarkersModel, '"MaxDistance": 160', 1, true) ~= nil,
	true,
	"platform owner cards stop cluttering the HUD from across the full lobby"
)
for slot = 1, 6 do
	expectEqual(
		string.find(ownerMarkersModel, `"Name": "Slot_{string.format("%02d", slot)}"`, 1, true) ~= nil,
		true,
		`platform owner UI authors slot {slot}`
	)
end
expectEqual(
	string.find(gridPatchProject, '"TemplateClient"', 1, true) ~= nil,
	true,
	"shared-place patch delivers the client grid renderer"
)
expectEqual(
	string.find(gridPatchProject, '"StagePlatformOwners"', 1, true) ~= nil,
	true,
	"shared-place patch delivers authored platform owner markers"
)
do
	local playtestHudModel = fs.readFile("src/ui/StagewrightPlaytestHUD.model.json")
	expectEqual(
		string.find(gridPatchProject, '"StagewrightPlaytestHUD"', 1, true) ~= nil
			and string.find(playtestHudModel, '"Enabled": false', 1, true) ~= nil
			and string.find(initClient, "StagewrightPlaytestController.initialize(request)", 1, true) ~= nil
			and string.find(initClient, "StagewrightPlaytestController.apply", 1, true) ~= nil,
		true,
		"RNG Defender receives the disabled-by-default authored Studio playtest HUD and controller"
	)
end
do
	local travelHudModel = fs.readFile("src/ui/TowerDefenseTravelHUD.model.json")
	local travelControllerSource = fs.readFile("src/client/Controllers/TowerDefenseTravelController.luau")
	local defaultProjectSource = fs.readFile("default.project.json")
	expectCompiles(travelControllerSource, "tower-defense platform travel controller compiles as Luau")
	expectEqual(
		string.find(defaultProjectSource, '"TowerDefenseTravelHUD"', 1, true) ~= nil
			and string.find(gridPatchProject, '"TowerDefenseTravelHUD"', 1, true) ~= nil
			and string.find(travelHudModel, '"Name": "TravelButton"', 1, true) ~= nil
			and string.find(travelHudModel, '"Text": "FINDING PLATFORM"', 1, true) ~= nil
			and string.find(initClient, "TowerDefenseTravelController.initialize(request)", 1, true)
				~= nil,
		true,
		"default and RNG Defender builds deliver the pre-authored platform travel control"
	)
	for _, marker in
		{
			"TowerDefensePlatformSlot",
			'request("TravelToTowerPlatform", {})',
			"Config.features.towerDefense ~= true",
			"travelButton.Activated:Connect",
			"DungeonPresentationActive",
			"TowerPlatformPresentationActive",
			"isOnOwnPlayableIsland",
			"platformTravelPromptMargin",
			"origin.Value:PointToObjectSpace(root.Position)",
			"setTowerPlatformPresentationActive(player, isOnIsland == true)",
			"instance.Enabled = isOnIsland == false",
		}
	do
		expectEqual(
			string.find(travelControllerSource, marker, 1, true) ~= nil,
			true,
			`tower-defense platform travel client includes {marker}`
		)
	end
end
do
	local levelHudModel = fs.readFile("src/ui/TowerDefenseLevelHUD.model.json")
	local levelHud = serde.decode("json", levelHudModel)
	local levelControllerSource = fs.readFile("src/client/Controllers/TowerDefenseLevelController.luau")
	local defaultProjectSource = fs.readFile("default.project.json")
	local function directChild(root: any, name: string): any
		for _, child in root.Children or {} do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	expectCompiles(levelControllerSource, "tower-defense level selector controller compiles as Luau")
	expectEqual(
		string.find(defaultProjectSource, '"servePlaceIds": [140239777311760]', 1, true) ~= nil,
		true,
		"bare gallery Rojo serve is restricted to the permanent template place"
	)
	expectEqual(
		string.find(defaultProjectSource, '"TowerDefenseLevelHUD"', 1, true) ~= nil
			and string.find(gridPatchProject, '"TowerDefenseLevelHUD"', 1, true) ~= nil
			and string.find(initClient, "TowerDefenseLevelController.initialize(request)", 1, true) ~= nil
			and string.find(initClient, "TowerDefenseLevelController.apply", 1, true) ~= nil,
		true,
		"default and RNG Defender builds deliver the permanent level selector"
	)
	for index = 1, 10 do
		expectEqual(
			string.find(levelHudModel, `"Name": "Level{string.format("%02d", index)}Button"`, 1, true) ~= nil,
			true,
			`level selector pre-authors level button {index}`
		)
	end
	for _, marker in
		{
			'"Name": "RollButton"',
			'"Name": "AutoPlaceButton"',
			'"Name": "StartWaveButton"',
			'"Name": "ResetButton"',
		}
	do
		expectEqual(
			string.find(levelHudModel, marker, 1, true) ~= nil,
			true,
			`level selector pre-authors gameplay action {marker}`
		)
	end
	expectEqual(
		string.find(levelHudModel, '"ClipsDescendants": true', 1, true) ~= nil
			and string.find(levelHudModel, '"ClassName": "UITextSizeConstraint"', 1, true) ~= nil
			and string.find(levelHudModel, '"TextScaled": true', 1, true) ~= nil,
		true,
		"level selector clips its panel and scales authored labels inside their controls"
	)
	local levelPanel = directChild(levelHud, "Panel")
	local levels = directChild(levelPanel, "Levels")
	local levelsGrid = levels.Children[1]
	local actions = directChild(levelPanel, "Actions")
	local detail = directChild(levelPanel, "Detail")
	expectEqual(
		levelPanel.Properties.AnchorPoint[1] == 1
			and levelPanel.Properties.AnchorPoint[2] == 1
			and levelPanel.Properties.Position.UDim2[1][2] == -24
			and levelPanel.Properties.Position.UDim2[2][2] == -180
			and levelsGrid.Properties.FillDirectionMaxCells == 5
			and levelsGrid.Properties.CellSize.UDim2[1][2] == 80
			and levelsGrid.Properties.CellSize.UDim2[2][2] == 64
			and actions.Properties.Size.UDim2[2][2] == 40
			and detail.Properties.Position.UDim2[2][2] == 238,
		true,
		"level selector uses the compact two-row Figma composition without covering the loadout controls"
	)
	for _, marker in
		{
			'request("ActivateTowerStage", { stageId = option.id })',
			'request("RollUnit", {})',
			'request("AutoPlaceBestUnits", {})',
			'request("StartTowerWave", {})',
			'request("ResetTowerDefense", {})',
			"Config.features.towerDefense ~= true",
			"DungeonPresentationActive",
			"TowerPlatformPresentationActive",
			"screenGui.Enabled = false",
		}
	do
		expectEqual(
			string.find(levelControllerSource, marker, 1, true) ~= nil,
			true,
			`level selector controller uses the existing authoritative action: {marker}`
		)
	end
	expectEqual(
		string.find(levelControllerSource, "applyResponsiveLayout", 1, true) == nil
			and string.find(levelControllerSource, "ViewportSize", 1, true) == nil,
		true,
		"level selector runtime preserves Figma-authored geometry"
	)
	expectEqual(
		string.find(towerDefenseServiceSource, "local levelOptions:", 1, true) ~= nil
			and string.find(towerDefenseServiceSource, "StageRuntimeService.isUnlocked", 1, true) ~= nil
			and string.find(towerDefenseServiceSource, "levelOptions = levelOptions", 1, true) ~= nil,
		true,
		"tower-defense snapshots expose only server-derived level availability"
	)
end
do
	local loadoutHudModel = fs.readFile("src/ui/TowerDefenseLoadoutHUD.model.json")
	local loadoutHud = serde.decode("json", loadoutHudModel)
	local loadoutControllerSource = fs.readFile("src/client/Controllers/TowerDefenseLoadoutController.luau")
	local defaultProjectSource = fs.readFile("default.project.json")
	local function directChild(root: any, name: string): any
		for _, child in root.Children or {} do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	expectCompiles(loadoutControllerSource, "tower-defense loadout controller compiles as Luau")
	expectEqual(
		string.find(defaultProjectSource, '"TowerDefenseLoadoutHUD"', 1, true) ~= nil
			and string.find(gridPatchProject, '"TowerDefenseLoadoutHUD"', 1, true) ~= nil
			and string.find(initClient, "TowerDefenseLoadoutController.initialize(request)", 1, true) ~= nil
			and string.find(initClient, "TowerDefenseLoadoutController.apply", 1, true) ~= nil,
		true,
		"default and RNG Defender builds deliver the dynamic unit loadout"
	)
	for index = 1, 6 do
		expectEqual(
			string.find(loadoutHudModel, `"Name": "UnitSlot{string.format("%02d", index)}"`, 1, true) ~= nil,
			true,
			`loadout HUD pre-authors dynamic slot {index}`
		)
	end
	for _, authoredControl in
		{
			'"Name": "InventoryButton"',
			'"Name": "DiceButton"',
			'"Name": "UpgradeTreeButton"',
			'"Name": "TalentPanel"',
			'"Name": "DynamicWidthConstraint"',
			'"Name": "PlacedBadge"',
			'"Name": "UnitDetailsPanel"',
			'"Name": "DamageValue"',
			'"Name": "RangeValue"',
			'"Name": "TreeCanvas"',
			'"Name": "SlotNode03"',
			'"Name": "SlotNode04"',
			'"Name": "SlotNode05"',
			'"Name": "SlotNode06"',
		}
	do
		expectEqual(
			string.find(loadoutHudModel, authoredControl, 1, true) ~= nil,
			true,
			`loadout HUD authors fixed control {authoredControl}`
		)
	end
	for _, inputContract in
		{
			"TouchTapInWorld",
			"ScreenPointToRay",
			"ViewportPointToRay",
			'request("UnlockTowerLoadoutSlot", {})',
			'send("SetTowerLoadout", { unitIds = nextLoadout })',
			'send("PlaceUnit", { unitId = unitId, column = column, row = row })',
			"DynamicWidthConstraint",
			"currentLoadout()[index]",
			"equippedCount",
			"placementForSlot",
			"StageGridRenderer.setPlacementMode",
			"StageTowerRenderer.localPlacementAtScreen",
			"showUnitDetails",
			"EQUIPPED x{",
			'"PLACED ON GRID"',
			"DungeonPresentationActive",
			"TowerPlatformPresentationActive",
			"StageGridRenderer.setPlacementMode(false, latestState)",
			"screenGui.Enabled = false",
			"templateNavigation.Visible = not dungeonActive",
			"local placementActive = towerPlacementActive()",
			'"GO TO YOUR TOWER TO PLACE UNITS"',
			"and towerPlacementActive()",
			"templateNavigation = navigation",
			'IconCatalog.get("bag")',
			'IconCatalog.get("rollDice")',
			'IconCatalog.get("talentUpgrade")',
			"SLOT_WIDTH = 96",
			"SLOT_GAP = 12",
		}
	do
		expectEqual(
			string.find(loadoutControllerSource, inputContract, 1, true) ~= nil,
			true,
			`loadout controller includes {inputContract}`
		)
	end
	local controlRow = directChild(loadoutHud, "ControlRow")
	local inventoryButton = directChild(controlRow, "InventoryButton")
	local diceButton = directChild(controlRow, "DiceButton")
	local upgradeButton = directChild(controlRow, "UpgradeTreeButton")
	local placementHintModel = directChild(loadoutHud, "PlacementHint")
	expectEqual(
		controlRow.Properties.Size.UDim2[1][2] == 356
			and controlRow.Properties.Size.UDim2[2][2] == 152
			and inventoryButton.Properties.Size.UDim2[1][2] == 96
			and diceButton.Properties.Size.UDim2[1][2] == 124
			and upgradeButton.Properties.Size.UDim2[1][2] == 96
			and placementHintModel.Properties.Size.UDim2[1][1] == 0.92,
		true,
		"loadout controls use the compact icon-driven Figma hierarchy with the primary dice action emphasized"
	)
	expectEqual(
		string.find(loadoutControllerSource, "inventoryButton.Size", 1, true) == nil
			and string.find(loadoutControllerSource, "diceButton.Size", 1, true) == nil
			and string.find(loadoutControllerSource, "upgradeButton.Size", 1, true) == nil,
		true,
		"loadout runtime preserves the Figma-authored action composition"
	)
	for _, forbiddenRuntimeGuiMutation in { "Instance.new", ":Clone(", ":Destroy(" } do
		expectEqual(
			string.find(loadoutControllerSource, forbiddenRuntimeGuiMutation, 1, true),
			nil,
			`loadout controller never performs runtime GUI mutation {forbiddenRuntimeGuiMutation}`
		)
	end
	for _, serverCopyContract in
		{
			"local function loadoutCount",
			"requestedCounts",
			'"Not enough owned copies"',
			"placedCopies >= loadoutCount(player, unitId)",
			'"Every equipped copy of this unit is already placed"',
			'"A placed copy must stay equipped"',
		}
	do
		expectEqual(
			string.find(towerDefenseServiceSource, serverCopyContract, 1, true) ~= nil,
			true,
			`tower server enforces owned/equipped copy contract {serverCopyContract}`
		)
	end
end
do
	local cleanupSource = fs.readFile("src/plugins/Stagewright/LegacyGalleryCleanup.luau")
	local pluginProjectSource = fs.readFile("plugins/grid-platform-editor.project.json")
	local rngDesignerConfig = fs.readFile("patches/rng-defender/DesignerConfig.luau")
	expectCompiles(cleanupSource, "RNG Defender gallery cleanup compiles as Luau")
	expectEqual(
		string.find(pluginProjectSource, '"LegacyGalleryCleanup"', 1, true) ~= nil
			and string.find(
				fs.readFile("src/plugins/GridPlatformEditPlugin.server.luau"),
				"LegacyGalleryCleanup.start()",
				1,
				true
			) ~= nil
			and string.find(rngDesignerConfig, "cleanupLegacyGalleryArtifacts = true", 1, true) ~= nil,
		true,
		"Stagewright starts the explicit RNG Defender cleanup after authoring-area migration"
	)
	for _, marker in
		{
			"identity.placeId == game.PlaceId",
			"config.cleanupLegacyGalleryArtifacts == true",
			'"PlayableStarter"',
			'"PlayableStarterClient"',
			'"GalleryFloor"',
			'"TemplateSpawn"',
			'"ExampleEarningPad"',
			'"BonusEarningPad"',
			"isGalleryGridPlatform(islandPlatform)",
			"Workspace:SetAttribute(CLEANUP_ATTRIBUTE, CLEANUP_VERSION)",
		}
	do
		expectEqual(
			string.find(cleanupSource, marker, 1, true) ~= nil,
			true,
			`gallery cleanup includes guarded marker {marker}`
		)
	end
	expectEqual(
		string.find(cleanupSource, "firstIsland:Destroy()", 1, true),
		nil,
		"gallery cleanup never deletes the Team Create island"
	)
end
expectEqual(
	string.find(stagePlatformSource, "OnServerEvent", 1, true),
	nil,
	"platform allocation has no client-controlled remote"
)
expectEqual(
	string.find(towerDefenseServiceSource, "OnServerEvent", 1, true),
	nil,
	"tower defense service does not listen directly to client remotes"
)
expectEqual(
	string.find(towerDefenseServiceSource, "createEnemyPart", 1, true),
	nil,
	"server simulates scalar route state without enemy visual parts"
)
local remoteServiceSource = fs.readFile("src/server/Services/RemoteService.luau")
for _, towerDefenseRemoteMarker in
	{
		"RollUnit",
		"SetTowerLoadout",
		"UnlockTowerLoadoutSlot",
		"EquipBestUnits",
		"PlaceUnit",
		"AutoPlaceBestUnits",
		"StartTowerWave",
		"RunTowerWavePlaytest",
		"ResetTowerDefense",
		"ActivateTowerStage",
		"TravelToTowerPlatform",
		"TowerEnemies",
		"TowerPlacements",
		"TowerDefenseService.snapshotFor",
		"TowerDefenseService.presentationSnapshot",
		"RemoteService.publishTowerPlacements",
		"FireAllClients",
		"towerPlacementRevision",
		"revision = revision",
	}
do
	expectEqual(
		string.find(remoteServiceSource, towerDefenseRemoteMarker, 1, true) ~= nil,
		true,
		`remote service exposes validated tower defense action {towerDefenseRemoteMarker}`
	)
end
expectEqual(
	string.find(serverBootstrapSource, "publishPlacements = RemoteService.publishTowerPlacements", 1, true)
		~= nil,
	true,
	"tower defense mutations publish the all-player presentation snapshot"
)
for _, clientTowerPresentationMarker in
	{
		"local StageTowerRenderer = require(Controllers.StageTowerRenderer)",
		"StageTowerRenderer.initialize()",
		"acceptTowerPlacements(nextState.towerPlacements, nextState.towerPlacementRevision)",
		'packet.kind == "TowerPlacements"',
		"acceptTowerPlacements(packet.data, packet.revision)",
		"nextRevision < towerPlacementRevision",
		"latestTowerPlacements = nextPlacements",
	}
do
	expectEqual(
		string.find(initClient, clientTowerPresentationMarker, 1, true) ~= nil,
		true,
		`client bootstrap applies tower presentation updates: {clientTowerPresentationMarker}`
	)
end
local unknownRequestBucket =
	string.find(remoteServiceSource, 'limiter:allow(player, "unknown-request"', 1, true)
local knownRequestBucket = string.find(remoteServiceSource, "limiter:allow(player, action", 1, true)
expectEqual(
	unknownRequestBucket ~= nil and knownRequestBucket ~= nil and unknownRequestBucket < knownRequestBucket,
	true,
	"unknown request names are bounded before action-specific rate limiting"
)
local unknownQueryBucket = string.find(remoteServiceSource, 'limiter:allow(player, "query:unknown"', 1, true)
local knownQueryBucket = string.find(remoteServiceSource, "limiter:allow(player, `query:{action}`", 1, true)
expectEqual(
	unknownQueryBucket ~= nil and knownQueryBucket ~= nil and unknownQueryBucket < knownQueryBucket,
	true,
	"unknown query names are bounded before action-specific rate limiting"
)
expectEqual(
	string.find(remoteServiceSource, "TowerDefenseRequest.parseLoadout", 1, true) ~= nil,
	true,
	"tower loadout requests use the shared strict contract"
)
expectEqual(
	string.find(runeConfigSource, "towerDefense = false", 1, true) ~= nil,
	true,
	"tower defense feature is disabled by default template config"
)
expectEqual(
	string.find(runeConfigSource, "unitRollCost = 75", 1, true) ~= nil
		and string.find(runeConfigSource, "startingLoadoutSlots = 2", 1, true) ~= nil
		and string.find(runeConfigSource, "loadoutSlots = 6", 1, true) ~= nil
		and string.find(runeConfigSource, "loadoutSlotUnlockCosts", 1, true) ~= nil
		and string.find(runeConfigSource, "platformTravelPromptMargin = 12", 1, true) ~= nil,
	true,
	"tower defense gameplay loop configures slots and contextual platform travel"
)

do
	local portalClientSource = fs.readFile("src/starter-client/Portal.client.luau")
	local dungeonClientSource = fs.readFile("src/starter-client/Dungeon.client.luau")
	local dungeonHudSource = fs.readFile("src/ui/DungeonHUD.model.json")
	local dungeonWeaponsSource = fs.readFile("src/assets/DungeonWeapons.model.json")
	local dungeonArenaSource = fs.readFile("src/world/DungeonArena.model.json")
	local defaultProjectSource = fs.readFile("default.project.json")
	local rngDefenderProjectSource = fs.readFile("patches/rng-defender-grid-demo.project.json")
	expectEqual(
		string.find(
			dungeonClientSource,
			'local DUNGEON_PRESENTATION_ATTRIBUTE = "DungeonPresentationActive"',
			1,
			true
		)
				~= nil
			and string.find(
					dungeonClientSource,
					"setDungeonPresentationActive(active or Template:GetAttribute",
					1,
					true
				)
				~= nil,
		true,
		"dungeon state publishes the client presentation lock used by contextual lobby HUDs"
	)
	expectEqual(
		string.find(portalClientSource, "portalPromptHasPriority", 1, true) ~= nil
			and string.find(
					portalClientSource,
					"currentSign.Enabled = portalPromptHasPriority()",
					1,
					true
				)
				~= nil,
		true,
		"the portal billboard yields to the nearer rune prompt instead of stacking world-space cards"
	)

	local function authoredDescendant(root: any, name: string): any
		if type(root) ~= "table" then
			return nil
		end
		if root.Name == name then
			return root
		end
		if type(root.Children) == "table" then
			for _, child in root.Children do
				local found = authoredDescendant(child, name)
				if found ~= nil then
					return found
				end
			end
		end
		return nil
	end

	local stateBinding = string.find(dungeonClientSource, "stateRemote.OnClientEvent:Connect", 1, true)
	local attackBinding = string.find(dungeonClientSource, "UserInputService.InputBegan:Connect", 1, true)
	local optionalVisualLookup = string.find(
		dungeonClientSource,
		'local existingHud = playerGui:FindFirstChild("DungeonHUD")',
		1,
		true
	)
	expectEqual(
		stateBinding ~= nil
			and attackBinding ~= nil
			and optionalVisualLookup ~= nil
			and stateBinding < optionalVisualLookup
			and attackBinding < optionalVisualLookup,
		true,
		"dedicated dungeon state and controls bind before its optional authored HUD"
	)
	expectEqual(
		string.find(dungeonClientSource, 'WaitForChild("DungeonHUD"', 1, true) == nil
			and string.find(dungeonClientSource, 'WaitForChild("DungeonArena"', 1, true) == nil
			and string.find(portalClientSource, 'WaitForChild("PortalPad"', 1, true) == nil
			and string.find(portalClientSource, 'WaitForChild("PortalSign"', 1, true) == nil
			and string.find(portalClientSource, 'WaitForChild("Platform"', 1, true) == nil
			and string.find(portalClientSource, 'WaitForChild("Card"', 1, true) == nil,
		true,
		"missing or streamed authored visuals cannot block dungeon controls or portal state"
	)
	expectEqual(
		string.find(portalClientSource, "Workspace.ChildAdded:Connect", 1, true) ~= nil
			and string.find(portalClientSource, "Workspace.ChildRemoved:Connect", 1, true) ~= nil
			and string.find(portalClientSource, "latestPortalState", 1, true) ~= nil
			and string.find(portalClientSource, "latestDungeonState", 1, true) == nil
			and string.find(portalClientSource, "DungeonAttack", 1, true) == nil
			and string.find(portalClientSource, "UserInputService", 1, true) == nil,
		true,
		"portal client recovers streamed lobby visuals without owning dungeon gameplay"
	)
	expectEqual(
		string.find(portalClientSource, "Instance.new", 1, true) == nil
			and string.find(portalClientSource, ":Clone()", 1, true) == nil
			and string.find(portalClientSource, ":Destroy()", 1, true) == nil
			and string.find(dungeonClientSource, "Instance.new", 1, true) == nil
			and string.find(dungeonClientSource, ":Clone()", 1, true) == nil
			and string.find(dungeonClientSource, ":Destroy()", 1, true) == nil,
		true,
		"portal and dungeon clients bind authored visuals without constructing or destroying UI"
	)
	expectEqual(
		string.find(dungeonClientSource, 'packet.kind == "DungeonAttackResult"', 1, true) ~= nil
			and string.find(dungeonClientSource, "weaponByUserId", 1, true) ~= nil
			and string.find(dungeonClientSource, "data.combatActive", 1, true) ~= nil
			and string.find(dungeonClientSource, 'action = "DungeonAttack"', 1, true) ~= nil
			and string.find(dungeonClientSource, 'action = "DungeonDodge"', 1, true) ~= nil,
		true,
		"dedicated dungeon client consumes server state and sends payload-free attack and dodge intent"
	)
	expectEqual(
		string.find(dungeonClientSource, "Enum.KeyCode.ButtonR2", 1, true) ~= nil
			and string.find(dungeonClientSource, "Enum.KeyCode.ButtonB", 1, true) ~= nil
			and string.find(
				dungeonClientSource,
				'childOfClass(controls, "AttackButton", "TextButton")',
				1,
				true
			) ~= nil
			and string.find(
					dungeonClientSource,
					'childOfClass(controls, "DodgeButton", "TextButton")',
					1,
					true
				)
				~= nil,
		true,
		"dungeon combat exposes authored touch controls plus keyboard and gamepad attack/dodge inputs"
	)
	expectEqual(
		string.find(dungeonClientSource, 'FindFirstChildWhichIsA("Tool")', 1, true) ~= nil
			and string.find(dungeonClientSource, "Grip = baseGrip * CFrame.Angles", 1, true) ~= nil
			and string.find(dungeonClientSource, "GuiService.ReducedMotionEnabled", 1, true) ~= nil
			and string.find(dungeonClientSource, "CameraMinZoomDistance", 1, true) ~= nil
			and string.find(dungeonClientSource, "endCameraPresentation", 1, true) ~= nil,
		true,
		"dungeon presentation animates the equipped tool and camera with reduced-motion and restoration paths"
	)
	expectEqual(
		string.find(dungeonClientSource, "LOBBY_GUI_ROOTS", 1, true) ~= nil
			and string.find(dungeonClientSource, "suppressLobbyGuis", 1, true) ~= nil
			and string.find(dungeonClientSource, "TowerDefenseLoadoutHUD = true", 1, true) ~= nil
			and string.find(
					dungeonClientSource,
					'Template:GetAttribute("RuntimeMode") == "dungeon"',
					1,
					true
				)
				~= nil,
		true,
		"dungeon controller suppresses the tower loadout and unrelated lobby UI in every boss run"
	)
	local coreGuiRestoreDefinition =
		string.find(dungeonClientSource, "local function restoreCoreGuiIfApplicable()", 1, true)
	local coreGuiRestoreCall = if coreGuiRestoreDefinition ~= nil
		then string.find(
			dungeonClientSource,
			"restoreCoreGuiIfApplicable()",
			coreGuiRestoreDefinition + 1,
			true
		)
		else nil
	expectEqual(
		string.find(dungeonClientSource, "Enum.CoreGuiType.Backpack", 1, true) ~= nil
			and string.find(dungeonClientSource, "Enum.CoreGuiType.Health", 1, true) ~= nil
			and string.find(dungeonClientSource, "StarterGui:GetCoreGuiEnabled(coreGuiType)", 1, true) ~= nil
			and string.find(dungeonClientSource, "rememberedCoreGuiStates[coreGuiType]", 1, true) ~= nil
			and string.find(
				dungeonClientSource,
				"setCoreGuiEnabledWithRetry(coreGuiType, wasEnabled, revision)",
				1,
				true
			) ~= nil
			and string.find(dungeonClientSource, 'Template:GetAttribute("RuntimeMode") ~= "lobby"', 1, true) ~= nil
			and coreGuiRestoreDefinition ~= nil
			and coreGuiRestoreCall ~= nil,
		true,
		"dungeon mode remembers, suppresses, and lobby-restores Backpack and Health CoreGui"
	)
	expectEqual(
		string.find(dungeonClientSource, "localUserRecord(data.eliminatedByUserId)", 1, true) ~= nil
			and string.find(
				dungeonClientSource,
				"combatActive = nextFightActive and not nextLocalEliminated",
				1,
				true
			) ~= nil
			and string.find(dungeonClientSource, 'setText(controlHint, "SPECTATING - YOU ARE DOWN")', 1, true) ~= nil
			and string.find(dungeonClientSource, "setVisible(controls, false)", 1, true) ~= nil,
		true,
		"an eliminated local player becomes a control-locked spectator instead of rejoining combat"
	)
	expectEqual(
		string.find(dungeonClientSource, "localUserRecord(data.rewardByUserId)", 1, true) ~= nil
			and string.find(dungeonClientSource, "reward.currencyAmount", 1, true) ~= nil
			and string.find(dungeonClientSource, "reward.itemName", 1, true) ~= nil
			and string.find(dungeonClientSource, 'if result == "victory" then', 1, true) ~= nil
			and string.find(dungeonClientSource, "actualRewardText = resultRewardLine(data)", 1, true) ~= nil
			and string.find(dungeonClientSource, 'setText(rewardText, "")', 1, true) ~= nil
			and string.find(dungeonClientSource, "setVisible(rewardText, false)", 1, true) ~= nil,
		true,
		"result UI reads only the local granted reward record and hides rewards on defeat"
	)
	expectEqual(
		string.find(dungeonClientSource, "faceBoss", 1, true) == nil
			and string.find(dungeonClientSource, "character:PivotTo", 1, true) == nil
			and string.find(dungeonClientSource, "CFrame.lookAt", 1, true) == nil
			and string.find(dungeonClientSource, "rootPart.CFrame =", 1, true) == nil
			and string.find(dungeonClientSource, "root.CFrame =", 1, true) == nil,
		true,
		"client presentation never snaps the player's root toward the boss"
	)

	local dungeonHud = serde.decode("json", dungeonHudSource)
	local attackButton = authoredDescendant(dungeonHud, "AttackButton")
	local dodgeButton = authoredDescendant(dungeonHud, "DodgeButton")
	expectEqual(
		dungeonHud.ClassName == "ScreenGui"
			and dungeonHud.Properties.Enabled == false
			and dungeonHud.Properties.ResetOnSpawn == false
			and dungeonHud.Properties.ClipToDeviceSafeArea == true
			and dungeonHud.Properties.ScreenInsets == "CoreUISafeInsets",
		true,
		"dungeon HUD is a disabled-by-default safe-area-aware authored ScreenGui"
	)
	expectEqual(
		attackButton ~= nil
			and attackButton.ClassName == "TextButton"
			and attackButton.Properties.Selectable == true
			and dodgeButton ~= nil
			and dodgeButton.ClassName == "TextButton"
			and dodgeButton.Properties.Selectable == true
			and authoredDescendant(dungeonHud, "BossBar") ~= nil
			and authoredDescendant(dungeonHud, "PlayerPanel") ~= nil
			and authoredDescendant(dungeonHud, "ResultPanel") ~= nil
			and authoredDescendant(dungeonHud, "DangerVignette") ~= nil,
		true,
		"dungeon HUD pre-authors touch combat, boss/player status, danger, and result surfaces"
	)
	local playerPanel = authoredDescendant(dungeonHud, "PlayerPanel")
	local controlsPanel = authoredDescendant(dungeonHud, "Controls")
	local playerPanelBottomInset = -playerPanel.Properties.Position.UDim2[2][2]
	local controlsBottomInset = -controlsPanel.Properties.Position.UDim2[2][2]
	local controlsHeight = controlsPanel.Properties.Size.UDim2[2][2]
	local mobilePanelGap = playerPanelBottomInset - (controlsBottomInset + controlsHeight)
	expectEqual(
		playerPanel.Properties.AnchorPoint[2] == 1
			and controlsPanel.Properties.AnchorPoint[2] == 1
			and playerPanel.Properties.Size.UDim2[2][2] == 110
			and controlsHeight == 92
			and mobilePanelGap >= 18,
		true,
		"bottom-anchored mobile player status clears the authored touch controls by at least 18 pixels"
	)
	do
		local abilityBar = authoredDescendant(dungeonHud, "AbilityBar")
		local hintPanel = authoredDescendant(dungeonHud, "ControlHint")
		local responsiveLayout = nil
		local sizeConstraint = nil
		if abilityBar ~= nil then
			for _, child in abilityBar.Children do
				if child.ClassName == "UIGridLayout" then
					responsiveLayout = child
				elseif child.ClassName == "UISizeConstraint" then
					sizeConstraint = child
				end
			end
		end
		expectEqual(
			abilityBar ~= nil
				and abilityBar.Properties.AnchorPoint[1] == 0.5
				and abilityBar.Properties.AnchorPoint[2] == 1
				and abilityBar.Properties.Position.UDim2[1][1] == 0.5
				and abilityBar.Properties.Position.UDim2[2][1] == 1
				and abilityBar.Properties.Position.UDim2[2][2] == -14
				and abilityBar.Properties.Size.UDim2[1][1] == 0.96
				and abilityBar.Properties.Size.UDim2[2][2] == 116
				and -controlsPanel.Properties.Position.UDim2[2][2] >= 146
				and -hintPanel.Properties.Position.UDim2[2][2] >= 146
				and responsiveLayout ~= nil
				and responsiveLayout.Properties.FillDirectionMaxCells == 4
				and sizeConstraint ~= nil
				and sizeConstraint.Properties.MinSize[1] >= 280
				and sizeConstraint.Properties.MaxSize[1] <= 440,
			true,
			"the responsive ability bar occupies the tower loadout slot without covering combat controls"
		)
	end

	local dungeonWeapons = serde.decode("json", dungeonWeaponsSource)
	local DungeonConfig = require("../src/shared/DungeonConfig")
	local normalizedDungeon = DungeonConfig.normalize(nil)
	local allConfiguredToolsAuthored = dungeonWeapons.ClassName == "Folder"
	for _, weapon in normalizedDungeon.weapons do
		local tool = authoredDescendant(dungeonWeapons, weapon.toolName)
		if
			tool == nil
			or tool.ClassName ~= "Tool"
			or tool.Properties.RequiresHandle ~= true
			or tool.Properties.CanBeDropped ~= false
			or authoredDescendant(tool, "Handle") == nil
		then
			allConfiguredToolsAuthored = false
		end
	end
	expectEqual(
		allConfiguredToolsAuthored,
		true,
		"every server-configured dungeon weapon resolves to an authored non-droppable Tool with a Handle"
	)
	expectEqual(
		string.find(defaultProjectSource, "src/assets/DungeonWeapons.model.json", 1, true) ~= nil
			and string.find(defaultProjectSource, "src/ui/DungeonHUD.model.json", 1, true) ~= nil
			and string.find(defaultProjectSource, '"$path": "src/starter-client"', 1, true) ~= nil
			and string.find(rngDefenderProjectSource, "../src/assets/DungeonWeapons.model.json", 1, true) ~= nil
			and string.find(rngDefenderProjectSource, "../src/ui/DungeonHUD.model.json", 1, true) ~= nil
			and string.find(
					rngDefenderProjectSource,
					"../src/starter-client/Dungeon.client.luau",
					1,
					true
				)
				~= nil,
		true,
		"default and RNG Defender Rojo projects deliver authored dungeon weapons, HUD, and client"
	)
	local dungeonArena = serde.decode("json", dungeonArenaSource)
	local bossCore = authoredDescendant(dungeonArena, "Core")
	local bossVisual = authoredDescendant(dungeonArena, "Visual")
	expectEqual(
		authoredDescendant(dungeonArena, "Boss") ~= nil
			and bossCore ~= nil
			and bossVisual ~= nil
			and authoredDescendant(dungeonArena, "HitHighlight") ~= nil
			and authoredDescendant(dungeonArena, "SlamTelegraph") ~= nil,
		true,
		"dungeon arena pre-authors boss collision, presentation, hit feedback, and slam telegraph parts"
	)
	local visualPartCount = 0
	local visualPartsArePresentationOnly = true
	local function inspectVisualParts(root: any)
		if type(root) ~= "table" then
			return
		end
		if root.ClassName == "Part" or root.ClassName == "MeshPart" then
			visualPartCount += 1
			local properties = root.Properties
			if
				type(properties) ~= "table"
				or properties.CanCollide ~= false
				or properties.CanQuery ~= false
				or properties.CanTouch ~= false
			then
				visualPartsArePresentationOnly = false
			end
		end
		if type(root.Children) == "table" then
			for _, child in root.Children do
				inspectVisualParts(child)
			end
		end
	end
	inspectVisualParts(bossVisual)
	expectEqual(
		bossCore.ClassName == "Part"
			and bossCore.Properties.Anchored == true
			and bossCore.Properties.CanCollide == true
			and bossCore.Properties.CanQuery == true
			and bossCore.Properties.CanTouch == false
			and bossVisual.ClassName == "Model"
			and visualPartCount > 0
			and visualPartsArePresentationOnly,
		true,
		"boss Core owns stable collision and hit queries while every Visual part stays presentation-only"
	)
	-- Keep this assertion-heavy tail in its own register frame. Luau limits each
	-- function to 200 local registers, and adding authored dungeon coverage can
	-- otherwise make unrelated declarations in this test chunk fail to compile.
	local function assertAuthoredDungeonTail()
		do
			local spectatorSpawn = authoredDescendant(dungeonArena, "SpectatorSpawn")
			local spectatorPlatform = authoredDescendant(dungeonArena, "SpectatorPlatform")
			expectEqual(
				spectatorSpawn ~= nil
					and spectatorSpawn.ClassName == "Part"
					and spectatorPlatform ~= nil
					and spectatorPlatform.ClassName == "Part"
					and spectatorPlatform.Properties.Anchored == true
					and spectatorPlatform.Properties.CanCollide == true
					and spectatorPlatform.Properties.CanQuery == true
					and spectatorPlatform.Properties.CanTouch == false
					and spectatorPlatform.Properties.Position[2] < spectatorSpawn.Properties.Position[2],
				true,
				"the authored spectator spawn stands above its stable collidable platform"
			)
		end

		local rateDenied = string.find(
			remoteServiceSource,
			"if not limiter:allow(player, action, rateCapacity, rateRefill) then",
			1,
			true
		)
		local attackRateDrop = if rateDenied ~= nil
			then string.find(
				remoteServiceSource,
				'if action == "DungeonAttack" or action == "DungeonDodge" or action == "UseDungeonAbility" then',
				rateDenied,
				true
			)
			else nil
		local fullSnapshotRejection = if rateDenied ~= nil
			then string.find(
				remoteServiceSource,
				'result(player, false, "Please slow down")',
				rateDenied,
				true
			)
			else nil
		expectEqual(
			rateDenied ~= nil
				and attackRateDrop ~= nil
				and fullSnapshotRejection ~= nil
				and attackRateDrop < fullSnapshotRejection,
			true,
			"rate-limited dungeon combat intent drops before the full snapshot result path"
		)
		expectEqual(
			string.find(remoteServiceSource, "local noPayloadActions", 1, true) ~= nil
				and string.find(remoteServiceSource, "DungeonAttack = true", 1, true) ~= nil
				and string.find(remoteServiceSource, "DungeonDodge = true", 1, true) ~= nil
				and string.find(
						remoteServiceSource,
						"if noPayloadActions[action] and not TowerDefenseRequest.acceptsNoPayload(payload) then",
						1,
						true
					)
					~= nil,
			true,
			"dungeon attack and dodge reuse the strict no-payload request contract"
		)
		expectEqual(
			string.find(remoteServiceSource, "local runtimeFeatures", 1, true) ~= nil
				and string.find(remoteServiceSource, 'then "dungeon"', 1, true) ~= nil
				and string.find(remoteServiceSource, "runtimeFeatures.towerDefense = false", 1, true) ~= nil
				and string.find(remoteServiceSource, "runtimeFeatures.runes = false", 1, true) ~= nil
				and string.find(remoteServiceSource, "features = runtimeFeatures", 1, true) ~= nil
				and string.find(remoteServiceSource, "runtimeMode = runtimeMode", 1, true) ~= nil
				and string.find(remoteServiceSource, "not featureEnabled(requiredFeature)", 1, true)
					~= nil,
			true,
			"reserved dungeon servers identify their mode and hide/reject unstarted lobby runtimes"
		)
		expectEqual(
			string.find(remoteServiceSource, "DungeonService.registerHit(player)", 1, true) ~= nil
				and string.find(
					remoteServiceSource,
					'RemoteService.sendEvent(player, "DungeonAttackResult"',
					1,
					true
				) ~= nil
				and string.find(remoteServiceSource, "DungeonService.registerDodge(player)", 1, true)
					~= nil,
			true,
			"combat remotes delegate intent to dungeon authority and return a lightweight attack result"
		)
		expectEqual(
			string.find(portalClientSource, "padChildAddedConnection", 1, true) ~= nil
				and string.find(portalClientSource, "padChildRemovedConnection", 1, true) ~= nil
				and string.find(portalClientSource, "refreshPortalPadParts", 1, true) ~= nil,
			true,
			"streamed portal descendants can bind after the portal model arrives"
		)
		expectEqual(
			string.find(portalClientSource, "portalNoticeRevision", 1, true) ~= nil
				and string.find(portalClientSource, "task.delay(6", 1, true) ~= nil
				and string.find(portalClientSource, "latestPortalNotice", 1, true) ~= nil
				and string.find(portalClientSource, "restoreAfterPortalNotice", 1, true) ~= nil
				and string.find(portalClientSource, "applyPortalNotice", 1, true) ~= nil,
			true,
			"portal failure notices remain visible on-screen across frequent roster refreshes"
		)
	end
	assertAuthoredDungeonTail()
end

do
	local DungeonConfig = require("../src/shared/DungeonConfig")

	-- DungeonConfig normalization: defaults, numeric clamps, vector validation,
	-- and the all-or-nothing boss list fallback.
	local defaults = DungeonConfig.normalize(nil)
	expectEqual(defaults.partyMax, 4, "dungeon defaults keep the authored party max")
	expectEqual(defaults.countdownSeconds, 5, "dungeon defaults keep the authored countdown")
	expectEqual(defaults.defaultBossId, "forest_warden", "dungeon defaults resolve the authored boss id")
	expectEqual(#defaults.bosses, 2, "dungeon defaults expose the authored boss list")
	expectEqual(defaults.bosses[2].id, "grove_matron", "dungeon defaults include the second selectable boss")
	expectEqual(defaults.bosses[1].baseHealth, 4500, "dungeon default boss keeps its authored health")
	expectEqual(defaults.attackCooldownSeconds, 0.45, "dungeon defaults keep the starter attack cooldown")
	expectEqual(defaults.proximityAutoDps, false, "dungeon defaults make click-to-attack the damage source")
	expectEqual(
		defaults.bosses[1].attackDamagePerHit,
		70,
		"dungeon legacy fallback keeps the starter weapon damage"
	)
	expectEqual(defaults.equipmentSlot, "DungeonWeapon", "dungeon weapons share one saved equipment slot")
	expectEqual(defaults.starterWeaponId, "warden_blade", "dungeon defaults resolve the starter weapon")
	expectEqual(defaults.weapons.warden_blade.damage, 70, "starter weapon damage is server configured")
	expectEqual(defaults.weapons.thorn_spear.rangeStuds, 18, "spear trades damage for reach")
	expectEqual(defaults.weapons.grove_hammer.cooldownSeconds, 0.8, "hammer trades speed for damage")
	expectEqual(defaults.bosses[1].rewardItemId, "grove_hammer", "the forest boss unlocks a saved weapon")
	expectEqual(defaults.bosses[1].rewardItemQuantity, 1, "boss weapon reward is bounded and deterministic")

	-- Nested scope: the ability catalog + wiring assertions declare enough locals to
	-- exceed Luau's 200-per-function register limit if left in the outer block.
	do
		local function abilityDescendant(root: any, name: string): any
			if type(root) ~= "table" then
				return nil
			end
			if root.Name == name then
				return root
			end
			for _, child in if type(root.Children) == "table" then root.Children else {} do
				local found = abilityDescendant(child, name)
				if found ~= nil then
					return found
				end
			end
			return nil
		end

		-- Hotbar ability catalog: four fixed, ordered slots the board always resolves.
		local abilityIds = {}
		for _, ability in defaults.abilities do
			table.insert(abilityIds, ability.id)
		end
		expectEqual(#defaults.abilities, 4, "dungeon defaults expose the four authored hotbar abilities")
		expectEqual(
			table.concat(abilityIds, ","),
			"power_strike,whirlwind,fireball,second_wind",
			"dungeon abilities keep their authored order for keys 1-4"
		)
		expectEqual(defaults.abilities[1].kind, "strike", "power strike is a melee strike")
		expectEqual(defaults.abilities[2].kind, "cleave", "whirlwind is a proximity cleave")
		expectEqual(defaults.abilities[3].kind, "ranged", "fireball is a ranged ability")
		expectEqual(defaults.abilities[4].kind, "heal", "second wind heals the caster")
		expectEqual(defaults.abilities[4].healAmount, 45, "second wind restores its authored health")
		expectEqual(defaults.abilities[1].damageMultiplier, 3, "power strike scales the weapon damage")
		local abilityFieldsValid = true
		for index, ability in defaults.abilities do
			if
				type(ability.name) ~= "string"
				or type(ability.glyph) ~= "string"
				or ability.glyph == ""
				or ability.keyLabel ~= tostring(index)
				or type(ability.cooldownSeconds) ~= "number"
				or ability.cooldownSeconds <= 0
				or type(ability.color) ~= "table"
				or #ability.color ~= 3
			then
				abilityFieldsValid = false
			end
		end
		expectEqual(
			abilityFieldsValid,
			true,
			"every dungeon ability has a name, glyph, key, cooldown, and color"
		)
		local fireball = DungeonConfig.abilityById(defaults, "fireball")
		expectEqual(
			fireball ~= nil and fireball.kind == "ranged",
			true,
			"abilityById resolves an authored ability"
		)
		expectEqual(
			DungeonConfig.abilityById(defaults, "missing_ability"),
			nil,
			"abilityById rejects unknown ids"
		)

		-- Per-ability overrides apply and clamp; malformed fields fall back in place.
		local tunedAbilities = DungeonConfig.normalize({
			abilities = {
				power_strike = { cooldownSeconds = 999, damageMultiplier = 4, kind = "not_a_kind" },
				second_wind = { healAmount = 80 },
			},
		}).abilities
		expectEqual(
			tunedAbilities[1].cooldownSeconds,
			120,
			"an out-of-range ability cooldown clamps to the ceiling"
		)
		expectEqual(tunedAbilities[1].damageMultiplier, 4, "a valid ability override is applied")
		expectEqual(
			tunedAbilities[1].kind,
			"strike",
			"an unknown ability kind falls back to the authored kind"
		)
		expectEqual(tunedAbilities[4].healAmount, 80, "a valid heal override is applied")
		expectEqual(#tunedAbilities, 4, "ability overrides never add or drop hotbar slots")

		-- Server + client wiring for the hotbar abilities.
		local dungeonServiceAbilitySource = fs.readFile("src/server/Services/DungeonService.luau")
		local remoteAbilitySource = fs.readFile("src/server/Services/RemoteService.luau")
		local dungeonClientAbilitySource = fs.readFile("src/starter-client/Dungeon.client.luau")
		local dungeonHudAbilitySource = fs.readFile("src/ui/DungeonHUD.model.json")
		local dungeonWeaponsAbilitySource = fs.readFile("src/assets/DungeonWeapons.model.json")
		expectEqual(
			string.find(dungeonServiceAbilitySource, "function DungeonService.useAbility", 1, true) ~= nil
				and string.find(
					dungeonServiceAbilitySource,
					"DungeonConfig.abilityById(dungeon, abilityId)",
					1,
					true
				) ~= nil
				and string.find(dungeonServiceAbilitySource, "lastAbilityAt", 1, true) ~= nil
				and string.find(
					dungeonServiceAbilitySource,
					"DungeonLogic.applyHit(current.health, damage)",
					1,
					true
				) ~= nil
				and string.find(dungeonServiceAbilitySource, 'return false, "fullHealth", nil', 1, true)
					~= nil,
			true,
			"the server owns ability resolution, per-ability cooldowns, boss damage, and useful healing"
		)
		expectEqual(
			string.find(remoteAbilitySource, 'UseDungeonAbility = "dungeon"', 1, true) ~= nil
				and string.find(remoteAbilitySource, 'action == "UseDungeonAbility"', 1, true) ~= nil
				and string.find(remoteAbilitySource, "DungeonService.useAbility(player, abilityId)", 1, true) ~= nil
				and string.find(remoteAbilitySource, '"DungeonAbilityResult"', 1, true) ~= nil,
			true,
			"the ability request is feature-gated, validated, and answered with a result event"
		)
		expectEqual(
			string.find(dungeonClientAbilitySource, "local function tryAbility", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, 'action = "UseDungeonAbility"', 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "Enum.KeyCode.One", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "Enum.KeyCode.Four", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "Enum.KeyCode.DPadLeft", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "Enum.KeyCode.DPadDown", 1, true) ~= nil
				and string.find(
						dungeonClientAbilitySource,
						'packet.kind == "DungeonAbilityResult"',
						1,
						true
					)
					~= nil,
			true,
			"the dungeon client sends ability intent from keyboard, gamepad, and touch and consumes results"
		)
		expectEqual(
			string.find(dungeonClientAbilitySource, "Instance.new", 1, true) == nil
				and string.find(dungeonClientAbilitySource, ":Clone()", 1, true) == nil
				and string.find(dungeonClientAbilitySource, ":Destroy()", 1, true) == nil,
			true,
			"the ability board binds authored instances without constructing or destroying any"
		)
		for _, slotName in { "AbilityBar", "Ability1", "Ability4", "CooldownCover", "AbilityFlash" } do
			expectEqual(
				string.find(dungeonHudAbilitySource, `"{slotName}"`, 1, true) ~= nil,
				true,
				`the dungeon HUD pre-authors the {slotName} instance`
			)
		end
		local _, burstCount = string.gsub(dungeonWeaponsAbilitySource, "AbilityBurst", "")
		expectEqual(burstCount, 3, "each authored dungeon weapon carries a burst emitter for ability VFX")

		-- Optional real-animation ids: default off, integer, clamped, with a fallback.
		local animDefaultsOff = true
		for _, ability in defaults.abilities do
			if ability.animationId ~= 0 then
				animDefaultsOff = false
			end
		end
		expectEqual(animDefaultsOff, true, "abilities default to the procedural pose with no animation id")
		local tunedAnim = DungeonConfig.normalize({
			abilities = {
				power_strike = { animationId = 123456.9 },
				whirlwind = { animationId = -5 },
			},
		}).abilities
		expectEqual(tunedAnim[1].animationId, 123456, "a configured animation id is floored to an integer")
		expectEqual(tunedAnim[2].animationId, 0, "a negative animation id falls back to off")

		-- Pre-authored Animation vessels (the client cannot construct them) + wiring.
		local defaultProjectSource = fs.readFile("default.project.json")
		local rngDefenderProjectSource = fs.readFile("patches/rng-defender-grid-demo.project.json")
		local figmaWorkspaceSource = fs.readFile("figma/workspaces/rng-defender.json")
		expectEqual(
			string.find(defaultProjectSource, "src/assets/DungeonAnimations.model.json", 1, true) ~= nil
				and string.find(
						rngDefenderProjectSource,
						"../src/assets/DungeonAnimations.model.json",
						1,
						true
					)
					~= nil,
			true,
			"both template and RNG Defender builds mount animation vessels under ReplicatedStorage/Template"
		)
		expectEqual(
			string.find(figmaWorkspaceSource, '"root": "DungeonHUD"', 1, true) ~= nil
				and string.find(figmaWorkspaceSource, '"path": "src/ui/DungeonHUD.model.json"', 1, true) ~= nil
				and string.find(figmaWorkspaceSource, '"root": "RuneCircle"', 1, true) ~= nil
				and string.find(figmaWorkspaceSource, '"root": "EnemyRigs"', 1, true) ~= nil,
			true,
			"the RNG Defender Figma workspace owns HUD, SurfaceGui, and BillboardGui presentation roots"
		)
		local dungeonAnimationsSource = fs.readFile("src/assets/DungeonAnimations.model.json")
		for _, abilityId in { "power_strike", "whirlwind", "fireball", "second_wind" } do
			expectEqual(
				string.find(dungeonAnimationsSource, `"{abilityId}"`, 1, true) ~= nil,
				true,
				`an authored Animation vessel exists for {abilityId}`
			)
		end
		local _, vesselCount = string.gsub(dungeonAnimationsSource, '"ClassName": "Animation"', "")
		expectEqual(vesselCount, 4, "exactly four empty animation vessels are pre-authored")

		-- Layered VFX instances: per-weapon swing trail + boss-core impact emitter.
		local _, trailCount = string.gsub(dungeonWeaponsAbilitySource, '"AbilityTrail"', "")
		expectEqual(trailCount, 3, "each dungeon weapon carries a swing trail")
		expectEqual(
			string.find(dungeonWeaponsAbilitySource, '"TrailAttach0"', 1, true) ~= nil
				and string.find(dungeonWeaponsAbilitySource, '"TrailAttach1"', 1, true) ~= nil,
			true,
			"the swing trail has authored attachment endpoints"
		)
		local authoredWeapons = serde.decode("json", dungeonWeaponsAbilitySource)
		local thornSpear = abilityDescendant(authoredWeapons, "ThornSpear")
		local spearTrailStart = abilityDescendant(thornSpear, "TrailAttach0")
		local spearTrailEnd = abilityDescendant(thornSpear, "TrailAttach1")
		expectEqual(
			spearTrailStart.Properties.Position[2] == -3.4 and spearTrailEnd.Properties.Position[2] == 3.4,
			true,
			"the thorn spear ability trail spans the authored 7.2-stud weapon handle"
		)
		local dungeonArenaAbilitySource = fs.readFile("src/world/DungeonArena.model.json")
		expectEqual(
			string.find(dungeonArenaAbilitySource, '"AbilityImpact"', 1, true) ~= nil,
			true,
			"the boss core pre-authors an ability impact emitter"
		)
		expectEqual(
			string.find(dungeonClientAbilitySource, ":LoadAnimation(", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "local function playAbilityMotion", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "abilityTracks", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "loadAbilityAnimations", 1, true) ~= nil,
			true,
			"the client preloads and plays a real animation track when an id is configured"
		)
		expectEqual(
			string.find(dungeonClientAbilitySource, "emitBossImpact", 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, '"AbilityTrail"', 1, true) ~= nil
				and string.find(dungeonClientAbilitySource, "AbilityImpact", 1, true) ~= nil,
			true,
			"the client drives the swing trail and boss impact VFX"
		)
	end
	local catalogsSource = fs.readFile("src/shared/Catalogs.luau")
	local bladeDefinition = string.find(catalogsSource, "warden_blade = {", 1, true)
	local spearDefinition = string.find(catalogsSource, "thorn_spear = {", 1, true)
	local hammerDefinition = string.find(catalogsSource, "grove_hammer = {", 1, true)
	local bladeSlot = if bladeDefinition ~= nil
		then string.find(catalogsSource, 'equipmentSlot = "DungeonWeapon"', bladeDefinition, true)
		else nil
	local spearSlot = if spearDefinition ~= nil
		then string.find(catalogsSource, 'equipmentSlot = "DungeonWeapon"', spearDefinition, true)
		else nil
	local spearPrice = if spearDefinition ~= nil
		then string.find(catalogsSource, "priceCoins = 25_000", spearDefinition, true)
		else nil
	local hammerSlot = if hammerDefinition ~= nil
		then string.find(catalogsSource, 'equipmentSlot = "DungeonWeapon"', hammerDefinition, true)
		else nil
	expectEqual(
		bladeDefinition ~= nil
			and spearDefinition ~= nil
			and hammerDefinition ~= nil
			and bladeDefinition < spearDefinition
			and spearDefinition < hammerDefinition
			and bladeSlot ~= nil
			and bladeSlot < spearDefinition
			and spearSlot ~= nil
			and spearSlot < hammerDefinition
			and spearPrice ~= nil
			and spearPrice < hammerDefinition
			and hammerSlot ~= nil
			and string.find(catalogsSource, "priceCoins", hammerDefinition, true) == nil,
		true,
		"catalog persists starter, purchased, and boss-reward weapons in one exclusive equipment slot"
	)
	expectEqual(defaults.walkSpeed, 18, "dungeon movement has an explicit server-owned walk speed")
	expectEqual(defaults.dodgeCooldownSeconds, 1.25, "dodge cadence is server configured")
	expectEqual(defaults.camera.fieldOfView, 74, "dungeon camera presentation is configured")
	expectEqual(defaults.telegraphSeconds, 1.1, "dungeon defaults keep the authored slam telegraph window")
	expectEqual(
		defaults.attackRingRadius > defaults.damageRingRadius,
		true,
		"the boss slam out-reaches attack range so attacking is a real risk"
	)

	expectEqual(
		DungeonConfig.normalize({ partyMax = 999 }).partyMax,
		DungeonConfig.AUTHORED_PARTY_SLOTS,
		"party max clamps to the number of authored roster slots"
	)
	expectEqual(defaults.arrivalTimeoutSeconds, 45, "dungeon arrivals allow time for bounded retries")
	expectEqual(
		DungeonConfig.normalize({ arrivalTimeoutSeconds = 999 }).arrivalTimeoutSeconds,
		60,
		"dungeon arrival timeout clamps to the ceiling"
	)
	expectEqual(
		DungeonConfig.normalize({ telegraphSeconds = 100 }).telegraphSeconds,
		10,
		"telegraph window clamps to the ceiling"
	)
	expectEqual(
		DungeonConfig.normalize({ proximityAutoDps = true }).proximityAutoDps,
		true,
		"proximity auto-dps can be re-enabled by a recipe"
	)
	expectEqual(
		DungeonConfig.normalize({ attackCooldownSeconds = 100 }).attackCooldownSeconds,
		5,
		"attack cooldown clamps to the ceiling"
	)
	expectEqual(DungeonConfig.normalize({ partyMax = 0 }).partyMax, 1, "party max clamps to the floor")
	expectEqual(
		DungeonConfig.normalize({ countdownSeconds = 1000 }).countdownSeconds,
		60,
		"countdown seconds clamp to the ceiling"
	)

	local shortVector = DungeonConfig.normalize({ arenaSpawn = { 1, 2 } })
	expectEqual(shortVector.arenaSpawn[2], 503, "a malformed arena spawn falls back to the default vector")
	local goodVector = DungeonConfig.normalize({ arenaSpawn = { 7, 8, 9 } })
	expectEqual(goodVector.arenaSpawn[1], 7, "a valid arena spawn override passes through")
	expectEqual(goodVector.arenaSpawn[3], 9, "a valid arena spawn keeps every component")

	local badBoss = DungeonConfig.normalize({ bosses = { { id = "broken" } } })
	expectEqual(badBoss.bosses[1].id, "forest_warden", "an incomplete boss entry falls back wholesale")

	local customBoss = DungeonConfig.normalize({
		bosses = {
			{
				id = "warden_two",
				name = "Warden II",
				baseHealth = 1000,
				healthPerExtraPlayer = 400,
				partyDpsPerPlayer = 90,
				attackDamage = 12,
				timeLimitSeconds = 45,
				rewardCurrencyId = "gems",
				rewardAmount = 250,
			},
		},
	})
	expectEqual(customBoss.bosses[1].id, "warden_two", "a valid boss override passes through")
	expectEqual(
		customBoss.defaultBossId,
		"warden_two",
		"the default boss id resolves to the first valid boss"
	)
	expectEqual(
		customBoss.bosses[1].attackDamagePerHit,
		70,
		"an omitted attackDamagePerHit defaults to the authored value"
	)

	local badHitBoss = DungeonConfig.normalize({
		bosses = {
			{
				id = "bad_hit",
				name = "Bad Hit",
				baseHealth = 100,
				healthPerExtraPlayer = 0,
				partyDpsPerPlayer = 1,
				attackDamagePerHit = 0,
				attackDamage = 0,
				timeLimitSeconds = 10,
				rewardCurrencyId = "coins",
				rewardAmount = 0,
			},
		},
	})
	expectEqual(
		badHitBoss.bosses[1].id,
		"forest_warden",
		"a present-but-invalid attackDamagePerHit falls back wholesale"
	)

	local duplicateBoss = DungeonConfig.normalize({
		bosses = {
			{
				id = "dupe",
				name = "A",
				baseHealth = 10,
				healthPerExtraPlayer = 0,
				partyDpsPerPlayer = 1,
				attackDamage = 0,
				timeLimitSeconds = 10,
				rewardCurrencyId = "coins",
				rewardAmount = 0,
			},
			{
				id = "dupe",
				name = "B",
				baseHealth = 10,
				healthPerExtraPlayer = 0,
				partyDpsPerPlayer = 1,
				attackDamage = 0,
				timeLimitSeconds = 10,
				rewardCurrencyId = "coins",
				rewardAmount = 0,
			},
		},
	})
	expectEqual(duplicateBoss.bosses[1].id, "forest_warden", "duplicate boss ids fall back wholesale")

	expectEqual(
		DungeonConfig.bossById(defaults, "forest_warden") ~= nil,
		true,
		"bossById finds a configured boss"
	)
	expectEqual(
		DungeonConfig.bossById(defaults, "grove_matron") ~= nil,
		true,
		"the second authored boss is available for selection"
	)
	expectEqual(#defaults.bosses >= 2, true, "boss selection has at least two bosses to choose from")
	expectEqual(DungeonConfig.bossById(defaults, "missing"), nil, "bossById returns nil for an unknown boss")
	expectEqual(
		DungeonConfig.weaponById(defaults, "thorn_spear") ~= nil,
		true,
		"weaponById resolves a server-configured saved weapon"
	)
	expectEqual(DungeonConfig.weaponById(defaults, "missing"), nil, "weaponById rejects unknown items")
	local clampedCamera = DungeonConfig.normalize({ camera = { minZoom = 30, maxZoom = 5 } }).camera
	expectEqual(clampedCamera.maxZoom, 30, "camera max zoom cannot normalize below min zoom")

	expectEqual(#defaults.eventAdminUserIds, 0, "no event-boss admins are configured by default")
	local admins =
		DungeonConfig.normalize({ eventAdminUserIds = { 101, 101, -5, 202, "nope" } }).eventAdminUserIds
	expectEqual(
		#admins == 2 and admins[1] == 101 and admins[2] == 202,
		true,
		"event admin ids dedupe and skip malformed entries without dropping the list"
	)
	expectEqual(
		#DungeonConfig.normalize({ eventAdminUserIds = "nope" }).eventAdminUserIds,
		0,
		"a malformed admin list normalizes to empty"
	)
end

do
	-- Server-authoritative boss resolution: forced event > party pad pick >
	-- personal saved choice > configured default, each validated against the
	-- catalog so a stale or empty id safely falls through.
	local DungeonBossSelection = require("../src/shared/DungeonBossSelection")
	local function known(id: string): boolean
		return id == "forest_warden" or id == "grove_matron"
	end
	expectEqual(
		DungeonBossSelection.resolveBossId(
			"grove_matron",
			"forest_warden",
			"forest_warden",
			"forest_warden",
			known
		),
		"grove_matron",
		"a forced event boss overrides the party and personal picks"
	)
	expectEqual(
		DungeonBossSelection.resolveBossId(nil, "grove_matron", "forest_warden", "forest_warden", known),
		"grove_matron",
		"the party pad pick beats the personal choice"
	)
	expectEqual(
		DungeonBossSelection.resolveBossId(nil, nil, "grove_matron", "forest_warden", known),
		"grove_matron",
		"the personal choice applies when no party pick is set"
	)
	expectEqual(
		DungeonBossSelection.resolveBossId(nil, nil, nil, "forest_warden", known),
		"forest_warden",
		"resolution falls back to the configured default"
	)
	expectEqual(
		DungeonBossSelection.resolveBossId("ghost", "phantom", "", "forest_warden", known),
		"forest_warden",
		"unknown or empty candidates are skipped in favor of the default"
	)

	local record = DungeonBossSelection.normalizeSessionRecord({
		v = 1,
		bossId = "grove_matron",
		launchId = "launch-abc",
	})
	expectEqual(record ~= nil and record.bossId, "grove_matron", "a well-formed session record is accepted")
	expectEqual(
		DungeonBossSelection.normalizeSessionRecord({
			v = 1,
			bossId = "grove_matron",
			launchId = "launch-abc",
			extra = "nope",
		}),
		nil,
		"session records reject unexpected keys"
	)
	expectEqual(
		DungeonBossSelection.normalizeSessionRecord({ v = 1, bossId = "Bad Id!", launchId = "l" }),
		nil,
		"session records reject malformed boss ids"
	)
	expectEqual(DungeonBossSelection.normalizeSessionRecord("nope"), nil, "session records must be tables")

	expectEqual(
		DungeonBossSelection.eventBossIfActive("grove_matron", nil, 1000),
		"grove_matron",
		"an event boss with no expiry stays active"
	)
	expectEqual(
		DungeonBossSelection.eventBossIfActive("grove_matron", 1500, 1000),
		"grove_matron",
		"an event boss before its expiry is active"
	)
	expectEqual(
		DungeonBossSelection.eventBossIfActive("grove_matron", 1000, 1000),
		nil,
		"an event boss at or past its expiry is inactive"
	)
	expectEqual(
		DungeonBossSelection.eventBossIfActive("", nil, 1000),
		nil,
		"an empty event boss id is inactive"
	)
end

do
	-- Lock in the server-authoritative handoff: boss choice travels through the
	-- server-only session store keyed by launch id, while the countdown rune uses
	-- Roblox's reliable one-call reserved-server teleport.
	local dungeonServiceSource = fs.readFile("src/server/Services/DungeonService.luau")
	for _, marker in
		{
			"options.ShouldReserveServer = true",
			"DungeonSessionStore.write(launchId",
			"DungeonSessionStore.read(manifest.launchId)",
			"DungeonSessionStore.write",
			"DungeonSessionStore.read",
			"normalizeSessionRecord",
			"function DungeonService.selectBoss",
		}
	do
		expectEqual(
			string.find(dungeonServiceSource, marker, 1, true) ~= nil,
			true,
			`dungeon boss handoff includes {marker}`
		)
	end
	expectEqual(
		string.find(dungeonServiceSource, "ReservedServerAccessCode", 1, true),
		nil,
		"the rune launch does not use a separately reserved access code"
	)
	local portalServiceSource = fs.readFile("src/server/Services/PortalService.luau")
	for _, marker in
		{ "PortalService.setBossPick", "resolveEffectiveBoss", "DungeonBossSelection.resolveBossId" }
	do
		expectEqual(
			string.find(portalServiceSource, marker, 1, true) ~= nil,
			true,
			`portal boss selection includes {marker}`
		)
	end
	local dungeonRemoteSource = fs.readFile("src/server/Services/RemoteService.luau")
	expectEqual(
		string.find(dungeonRemoteSource, 'SelectDungeonBoss = "dungeon"', 1, true) ~= nil,
		true,
		"the boss selection request is feature-gated on the dungeon system"
	)

	-- Forced admin event boss: allowlist-gated setter, a lobby-only global store
	-- feeding the resolver's event slot, and an admin chat command surface.
	for _, marker in
		{
			"function DungeonService.setEventBoss",
			"dungeon.eventAdminUserIds",
			"DungeonEventStore.set",
		}
	do
		expectEqual(
			string.find(dungeonServiceSource, marker, 1, true) ~= nil,
			true,
			`dungeon event boss admin path includes {marker}`
		)
	end
	expectEqual(
		string.find(portalServiceSource, "activeEventBoss", 1, true) ~= nil
			and string.find(portalServiceSource, "target.eventBossId()", 1, true) ~= nil,
		true,
		"the portal resolves a forced event boss ahead of party and personal picks"
	)
	local dungeonBootstrapSource = fs.readFile("src/server/init.server.luau")
	expectEqual(
		string.find(dungeonBootstrapSource, "DungeonEventStore.start()", 1, true) ~= nil
			and string.find(dungeonBootstrapSource, '"/dungeonevent"', 1, true) ~= nil
			and string.find(dungeonBootstrapSource, "DungeonService.setEventBoss", 1, true) ~= nil,
		true,
		"the lobby starts the event store and installs the allowlisted admin command"
	)
end

do
	-- Roblox-only flows use source-order contracts; pure boss precedence and
	-- session-record normalization are executed immediately above.
	local function ordered(source: string, markers: { string }): boolean
		local cursor = 1
		for _, value in markers do
			local found = string.find(source, value, cursor, true)
			if found == nil then
				return false
			end
			cursor = found + #value
		end
		return true
	end

	local dungeonSource = fs.readFile("src/server/Services/DungeonService.luau")
	local portalSource = fs.readFile("src/server/Services/PortalService.luau")
	local eventStoreSource = fs.readFile("src/server/Util/DungeonEventStore.luau")
	local bootstrapSource = fs.readFile("src/server/init.server.luau")
	local portalClientSource = fs.readFile("src/starter-client/Portal.client.luau")
	local remoteSource = fs.readFile("src/server/Services/RemoteService.luau")
	local portalModelSource = fs.readFile("src/ui/PortalSign.model.json")

	expectEqual(
		ordered(dungeonSource, {
			"local launchId = HttpService:GenerateGUID(false)",
			"DungeonSessionStore.write(launchId",
			"local finalRoster = launchablePlayers(roster)",
			"local ids = DungeonLogic.normalizePartyIds(userIds(finalRoster), dungeon.partyMax)",
			"options.ShouldReserveServer = true",
			"return beginExactTeleport(",
		}),
		true,
		"rune launch stores its boss, revalidates, then atomically reserves and teleports"
	)
	expectEqual(
		string.find(dungeonSource, "TeleportService:ReserveServer", 1, true),
		nil,
		"dungeon launch never performs a separate server reservation"
	)
	expectEqual(
		ordered(dungeonSource, {
			"local function beginExactTeleport(",
			"if player.Parent ~= Players or seen[player] or pendingTeleports[player] ~= nil then",
			"pendingTeleports[player] = {",
			"task.spawn(attemptTeleport, players, game.PlaceId, options, kind, launchId)",
		}),
		true,
		"exact dungeon teleport validates all players before installing pending claims and starting retries"
	)
	expectEqual(
		ordered(dungeonSource, {
			"function DungeonService.selectBoss",
			"if not target.setSavedBossId(player, bossId) then",
			'return false, "profileUnavailable"',
			"target.notePadBossPick(player, bossId)",
			"return true, bossId",
		}),
		true,
		"failed personal persistence prevents both the party pick and success response"
	)
	expectEqual(
		ordered(dungeonSource, {
			"local record = DungeonBossSelection.normalizeSessionRecord",
			"party = waitForReadyParty(party)",
			"lockDungeonRoster(manifest, party)",
			"runFightSafely(party, bossId, core)",
		})
			and string.find(dungeonSource, "result ~= Enum.TeleportResult.Failure", 1, true) ~= nil
			and string.find(dungeonSource, "result ~= Enum.TeleportResult.Flooded", 1, true) ~= nil,
		true,
		"session reads revalidate the party and teleport retries reject permanent failures"
	)
	expectEqual(
		string.find(eventStoreSource, "resolved:RemoveAsync(KEY)", 1, true) ~= nil
			and string.find(eventStoreSource, "local function validUntilTime", 1, true) ~= nil
			and string.find(eventStoreSource, "untilTime ~= nil and not validUntilTime", 1, true) ~= nil
			and ordered(dungeonSource, {
				"function DungeonService.setEventBoss",
				"if not allowed then",
				"if not DungeonEventStore.set(nil, nil) then",
				"The dungeon event store could not be cleared.",
				"Dungeon event boss cleared.",
			}),
		true,
		"event clear uses RemoveAsync, enforces the allowlist, and propagates failure before success"
	)
	expectEqual(ordered(eventStoreSource, {
		"MAX_CACHE_STALE_SECONDS",
		"lastSuccessfulStoreClock",
		"function DungeonEventStore.activeBossId",
		"os.clock() - refreshedAt > MAX_CACHE_STALE_SECONDS",
	}) and string.find(eventStoreSource, "function DungeonEventStore.start(): boolean", 1, true) ~= nil and ordered(
		bootstrapSource,
		{
			"local dungeonEventsEnabled = #Config.dungeon.eventAdminUserIds > 0",
			"if dungeonEventsEnabled then",
			"local eventStoreReady = DungeonEventStore.start()",
			"PortalService.start({",
		}
	), true, "live event cache has bounded readiness and stale fallback before portal launch")
	expectEqual(
		ordered(bootstrapSource, {
			"now - lastAttemptAt < EVENT_COMMAND_COOLDOWN_SECONDS",
			"eventCommandLastAttemptAt[textSource.UserId] = now",
			"local parts = commandParts(message)",
			"if #parts < 2 or #parts > 3 then",
			"or parsed <= 0",
			"DungeonService.setEventBoss(textSource.UserId, bossId, durationMinutes)",
		}) and string.find(bootstrapSource, 'string.gmatch(message, "%S+")', 1, true) ~= nil,
		true,
		"/dungeonevent rate-limits all attempts before parsing and the allowlisted setter"
	)
	expectEqual(
		ordered(portalSource, {
			"local function resetBossPickIfLeaderChanged",
			"if order[1] ~= previousLeader then",
			"pendingBossId = nil",
			"local function removeFromOrder",
			"local previousLeader = order[1]",
			"resetBossPickIfLeaderChanged(previousLeader)",
			"local function refreshOrder",
			"local previousLeader = order[1]",
			"resetBossPickIfLeaderChanged(previousLeader)",
		}),
		true,
		"forget and occupancy refresh clear a party pick only when the effective leader changes"
	)
	expectEqual(
		ordered(portalSource, {
			"local bossId = resolveEffectiveBoss()",
			"launchingBossId = bossId",
			"launchInProgress = true",
			"publishState(true)",
			"target.launch(players, bossId)",
			"launchInProgress = false",
		})
			and string.find(portalSource, "if launching and launchingBossId ~= nil", 1, true) ~= nil
			and ordered(portalClientSource, {
				"pendingPersonalBossId = nextBoss.id",
				'packet.kind == "DungeonBossSelected"',
				"personalBossId = data.bossId",
			})
			and string.find(portalClientSource, "if not launching and not eventActive", 1, true) ~= nil
			and string.find(remoteSource, 'action == "SelectDungeonBoss"', 1, true) ~= nil
			and ordered(portalModelSource, {
				'"ClassName": "BillboardGui"',
				'"Active": true',
				'"Name": "Prev"',
				'"Active": true',
				'"Name": "Next"',
				'"Active": true',
			}),
		true,
		"launching locks party picks while interactive authored controls reconcile dedicated acknowledgements"
	)
end

do
	local DungeonLogic = require("../src/shared/DungeonLogic")

	local manifest = DungeonLogic.normalizePartyManifest({
		kind = "DungeonParty",
		v = 1,
		launchId = "launch-123",
		party = { 101, 202, 303 },
	}, 4)
	expectEqual(manifest ~= nil, true, "a dense unique bounded dungeon manifest is accepted")
	expectEqual(if manifest ~= nil then manifest.party[2] else nil, 202, "manifest party order is retained")
	expectEqual(
		DungeonLogic.normalizePartyManifest({
			kind = "DungeonParty",
			v = 1,
			launchId = "launch-123",
			party = { 101 },
			bossId = "client_choice",
		}, 4),
		nil,
		"manifest rejects extra client-controlled fields"
	)
	expectEqual(
		DungeonLogic.normalizePartyIds({ 101, 101 }, 4),
		nil,
		"manifest rejects duplicate party members"
	)
	expectEqual(
		DungeonLogic.normalizePartyIds({ [1] = 101, [3] = 303 }, 4),
		nil,
		"manifest rejects sparse party arrays"
	)
	expectEqual(
		DungeonLogic.normalizePartyIds({ 101, 202, 303, 404, 505 }, 4),
		nil,
		"manifest rejects parties above the authored limit"
	)
	expectEqual(
		DungeonLogic.normalizePartyManifest({
			kind = "DungeonParty",
			v = 1,
			launchId = "invalid launch id",
			party = { 101 },
		}, 4),
		nil,
		"manifest rejects malformed launch identifiers"
	)

	-- DungeonLogic combat + occupancy math is pure and server-authoritative.
	expectEqual(DungeonLogic.isWithinCylinder(0, 0, 0, 10, 5), true, "the center of a cylinder is inside it")
	expectEqual(DungeonLogic.isWithinCylinder(8, 0, 6, 10, 5), true, "a point on the radius counts as inside")
	expectEqual(
		DungeonLogic.isWithinCylinder(8, 0, 7, 10, 5),
		false,
		"a point beyond the radius is outside the cylinder"
	)
	expectEqual(
		DungeonLogic.isWithinCylinder(0, 6, 0, 10, 5),
		false,
		"a point above the height tolerance is outside the cylinder"
	)
	expectEqual(
		DungeonLogic.canStrike(0, 0, 13, 0, 1, 13, 9, 0.25),
		true,
		"a target on the exact range boundary and in front can be struck"
	)
	expectEqual(
		DungeonLogic.canStrike(0, 0, 13.01, 0, 1, 13, 9, 0.25),
		false,
		"a target beyond weapon range cannot be struck"
	)
	expectEqual(
		DungeonLogic.canStrike(0, 0, 10, 0, -1, 13, 9, 0.25),
		false,
		"a target behind the attacker cannot be struck"
	)
	expectEqual(
		DungeonLogic.canStrike(0, 9.01, 10, 0, 1, 13, 9, 0.25),
		false,
		"a target beyond the weapon vertical tolerance cannot be struck"
	)
	expectEqual(DungeonLogic.phaseForHealth(51, 100, 0.5), 1, "boss remains calm above threshold")
	expectEqual(DungeonLogic.phaseForHealth(50, 100, 0.5), 2, "boss enrages at the threshold")
	local allDeadSince = DungeonLogic.nextAllDeadSince(nil, 0, 10)
	expectEqual(allDeadSince, 10, "party wipe timer starts when every player is down")
	expectEqual(DungeonLogic.isPartyWiped(allDeadSince, 11.9, 2), false, "wipe grace allows a brief recovery")
	expectEqual(DungeonLogic.isPartyWiped(allDeadSince, 12, 2), true, "wipe resolves at the grace boundary")
	expectEqual(
		DungeonLogic.nextAllDeadSince(allDeadSince, 1, 12),
		nil,
		"a living teammate clears wipe progress"
	)

	local boss = {
		id = "b",
		name = "B",
		baseHealth = 1000,
		healthPerExtraPlayer = 500,
		partyDpsPerPlayer = 100,
		attackDamage = 20,
		timeLimitSeconds = 60,
		rewardCurrencyId = "coins",
		rewardAmount = 100,
	}
	expectEqual(DungeonLogic.bossMaxHealth(boss, 1), 1000, "a solo run uses base boss health")
	expectEqual(DungeonLogic.bossMaxHealth(boss, 3), 2000, "boss health scales per extra player")
	expectEqual(DungeonLogic.partyDps(boss, 0), 0, "no attackers deal no damage")
	expectEqual(DungeonLogic.partyDps(boss, 3), 300, "party dps scales with attackers in range")
	expectEqual(DungeonLogic.partyDps(boss, -1), 0, "negative attacker counts never deal damage")

	expectEqual(DungeonLogic.applyDamage(100, 10, 2), 80, "damage applies dps over the elapsed time")
	expectEqual(DungeonLogic.applyDamage(5, 10, 2), 0, "health never drops below zero")
	expectEqual(DungeonLogic.applyDamage(100, 10, -1), 100, "negative delta time never heals or hurts")

	expectEqual(DungeonLogic.applyHit(1000, 90), 910, "a validated hit removes its damage from boss health")
	expectEqual(DungeonLogic.applyHit(50, 90), 0, "a hit never drops boss health below zero")
	expectEqual(DungeonLogic.applyHit(100, -5), 100, "negative hit damage never heals the boss")
	expectEqual(DungeonLogic.isDefeated(0), true, "zero health is a defeat")
	expectEqual(DungeonLogic.isDefeated(1), false, "positive health is not a defeat")
	expectEqual(DungeonLogic.healthFraction(50, 100), 0.5, "half health reports a half bar")
	expectEqual(DungeonLogic.healthFraction(0, 0), 0, "a zero-max boss reports an empty bar")
	expectEqual(DungeonLogic.healthFraction(200, 100), 1, "health fraction clamps to a full bar")

	expectEqual(DungeonLogic.countdownRemaining(10, 4), 6, "countdown reports whole seconds left")
	expectEqual(DungeonLogic.countdownRemaining(10, 3.2), 7, "countdown rounds up to whole seconds")
	expectEqual(DungeonLogic.countdownRemaining(10, 12), 0, "a passed deadline reports zero")

	expectEqual(#DungeonLogic.clampParty({ 1, 2, 3 }, 2), 2, "an oversized roster is capped to party max")
	expectEqual(DungeonLogic.clampParty({ 1, 2, 3 }, 2)[2], 2, "the capped roster keeps arrival order")
	expectEqual(#DungeonLogic.clampParty({ 1, 2 }, 5), 2, "a roster under the cap passes through")
	expectEqual(#DungeonLogic.clampParty({ 1, 2, 3 }, 0), 0, "a zero party max yields an empty party")
end

do
	local dungeonServiceSource = fs.readFile("src/server/Services/DungeonService.luau")
	local portalServiceSource = fs.readFile("src/server/Services/PortalService.luau")
	local inventoryServiceSource = fs.readFile("src/server/Services/InventoryService.luau")
	local mainClientSource = fs.readFile("src/client/init.client.luau")
	local runeClientSource = fs.readFile("src/starter-client/RuneCircle.client.luau")
	local starterClientSource = fs.readFile("src/starter-client/StarterExample.client.luau")
	expectEqual(
		string.find(serverBootstrapSource, "publish = function(players, data)", 1, true) ~= nil
			and string.find(serverBootstrapSource, "for _, player in players do", 1, true) ~= nil
			and string.find(
				serverBootstrapSource,
				'RemoteService.sendEvent(player, "DungeonState", data)',
				1,
				true
			) ~= nil
			and string.find(serverBootstrapSource, 'RemoteService.broadcast("DungeonState"', 1, true) == nil
			and string.find(
					dungeonServiceSource,
					"publish: (players: { Player }, data: any) -> ()",
					1,
					true
				)
				~= nil,
		true,
		"dungeon state is delivered only to the authoritative party instead of every server client"
	)
	local attackAckBranch = string.find(remoteServiceSource, 'elseif action == "DungeonAttack" then', 1, true)
	local dodgeAckBranch = string.find(remoteServiceSource, 'elseif action == "DungeonDodge" then', 1, true)
	local attackAckAction = if attackAckBranch ~= nil
		then string.find(remoteServiceSource, 'action = "attack"', attackAckBranch, true)
		else nil
	local dodgeAckAction = if dodgeAckBranch ~= nil
		then string.find(remoteServiceSource, 'action = "dodge"', dodgeAckBranch, true)
		else nil
	expectEqual(
		attackAckBranch ~= nil
			and dodgeAckBranch ~= nil
			and attackAckAction ~= nil
			and attackAckAction < dodgeAckBranch
			and dodgeAckAction ~= nil
			and string.find(remoteServiceSource, '"DungeonAttackResult"', attackAckBranch, true) ~= nil
			and string.find(remoteServiceSource, '"DungeonAttackResult"', dodgeAckBranch, true) ~= nil,
		true,
		"attack and dodge acknowledgements identify their action on the shared lightweight result event"
	)
	expectEqual(
		string.find(dungeonServiceSource, "TeleportService.TeleportInitFailed:Connect", 1, true) ~= nil
			and string.find(dungeonServiceSource, "pendingTeleports", 1, true) ~= nil
			and string.find(dungeonServiceSource, "retryScheduled", 1, true) ~= nil,
		true,
		"dungeon teleports retry both synchronous and late initialization failures"
	)
	expectEqual(
		string.find(dungeonServiceSource, 'kind = "DungeonParty"', 1, true) ~= nil
			and string.find(dungeonServiceSource, "launchId = launchId", 1, true) ~= nil
			and string.find(dungeonServiceSource, "normalizePartyManifest", 1, true) ~= nil,
		true,
		"dungeon arrivals use a versioned launch-scoped party manifest"
	)
	expectEqual(
		string.find(dungeonServiceSource, "waitForReadyParty", 1, true) ~= nil
			and string.find(dungeonServiceSource, "if not target.ready(player) then", 1, true) ~= nil
			and string.find(dungeonServiceSource, "if target.ready(player) then", 1, true) ~= nil
			and string.find(dungeonServiceSource, "lockDungeonRoster", 1, true) ~= nil,
		true,
		"dungeon fights admit only profile-ready players and recheck rewards"
	)
	local positionPartyCall = string.find(dungeonServiceSource, "if not positionParty(current) then", 1, true)
	local readyPhase = if positionPartyCall ~= nil
		then string.find(dungeonServiceSource, 'current.phase = "ready"', positionPartyCall, true)
		else nil
	local awaitPreparation =
		string.find(dungeonServiceSource, "local function awaitPreparedCharacter", 1, true)
	local awaitRunGuard = if awaitPreparation ~= nil
		then string.find(dungeonServiceSource, "if not isCurrentRun(current) then", awaitPreparation, true)
		else nil
	local prepareCharacter = string.find(dungeonServiceSource, "local function prepareCharacter", 1, true)
	local prepareCharacterYield = if prepareCharacter ~= nil
		then string.find(dungeonServiceSource, 'WaitForChild("HumanoidRootPart", 5)', prepareCharacter, true)
		else nil
	expectEqual(
		string.find(dungeonServiceSource, "local function isCurrentRun(current: Run): boolean", 1, true)
				~= nil
			and string.find(dungeonServiceSource, "run == current and current.active", 1, true) ~= nil
			and awaitPreparation ~= nil
			and awaitRunGuard ~= nil
			and prepareCharacterYield ~= nil
			and string.find(dungeonServiceSource, "isCurrentRun(current)", prepareCharacterYield, true) ~= nil
			and string.find(
				dungeonServiceSource,
				"player.Character ~= character",
				prepareCharacterYield,
				true
			) ~= nil
			and positionPartyCall ~= nil
			and readyPhase ~= nil
			and positionPartyCall < readyPhase,
		true,
		"character preparation revalidates the active run after yields and completes before ready countdown"
	)
	local hitHandler =
		string.find(dungeonServiceSource, "function DungeonService.registerHit(player: Player)", 1, true)
	local dodgeHandler =
		string.find(dungeonServiceSource, "function DungeonService.registerDodge(player: Player)", 1, true)
	local hitEliminatedCheck = if hitHandler ~= nil
		then string.find(dungeonServiceSource, "if current.eliminated[player] then", hitHandler, true)
		else nil
	local dodgeEliminatedCheck = if dodgeHandler ~= nil
		then string.find(dungeonServiceSource, "if current.eliminated[player] then", dodgeHandler, true)
		else nil
	expectEqual(
		string.find(dungeonServiceSource, "player.CharacterRemoving:Connect", 1, true) ~= nil
			and string.find(dungeonServiceSource, "player.CharacterAdded:Connect", 1, true) ~= nil
			and string.find(dungeonServiceSource, "eliminatePlayer(current, player)", 1, true) ~= nil
			and string.find(dungeonServiceSource, "prepareSpectator(current, player, index)", 1, true) ~= nil
			and string.find(dungeonServiceSource, "eliminatedByUserId", 1, true) ~= nil
			and hitHandler ~= nil
			and dodgeHandler ~= nil
			and hitEliminatedCheck ~= nil
			and hitEliminatedCheck < dodgeHandler
			and dodgeEliminatedCheck ~= nil,
		true,
		"death or reset spends one life, respawns at the spectator marker, and blocks later combat intents"
	)
	do
		local prepareSpectatorStart =
			string.find(dungeonServiceSource, "local function prepareSpectator", 1, true)
		local prepareSpectatorEnd =
			string.find(dungeonServiceSource, "local function awaitPreparedCharacter", 1, true)
		local prepareSpectatorSource = if prepareSpectatorStart ~= nil and prepareSpectatorEnd ~= nil
			then string.sub(dungeonServiceSource, prepareSpectatorStart, prepareSpectatorEnd - 1)
			else ""
		expectEqual(
			string.find(
				prepareSpectatorSource,
				"character:PivotTo(spectatorCFrame(current.spectatorSpawn, current.partySpawn, index))",
				1,
				true
			)
					~= nil
				and string.find(prepareSpectatorSource, "root.AssemblyLinearVelocity = Vector3.zero", 1, true) ~= nil
				and string.find(prepareSpectatorSource, "humanoid.WalkSpeed = 0", 1, true) ~= nil,
			true,
			"an eliminated respawn is moved to spectators with horizontal movement and inherited velocity disabled"
		)
	end
	expectEqual(
		string.find(dungeonServiceSource, "TeleportData.bossId", 1, true) == nil
			and string.find(dungeonServiceSource, "runFightSafely(party, dungeon.defaultBossId", 1, true)
				~= nil,
		true,
		"teleport data cannot choose boss or reward authority"
	)
	do
		local function countPlainOccurrences(source: string, needle: string): number
			local count = 0
			local cursor = 1
			while true do
				local startIndex = string.find(source, needle, cursor, true)
				if startIndex == nil then
					break
				end
				count += 1
				cursor = startIndex + #needle
			end
			return count
		end
		local safeFightStart = string.find(dungeonServiceSource, "local function runFightSafely", 1, true)
		local safeFightEnd =
			string.find(dungeonServiceSource, "local function terminalTeleportFailure", 1, true)
		local safeFightSource = if safeFightStart ~= nil and safeFightEnd ~= nil
			then string.sub(dungeonServiceSource, safeFightStart, safeFightEnd - 1)
			else ""
		local failureInvalidation = string.find(safeFightSource, "current.active = false", 1, true)
		local failureDisconnect = string.find(safeFightSource, "connection:Disconnect()", 1, true)
		local failureRunClear = string.find(safeFightSource, "run = nil", 1, true)
		local failureToolClear = string.find(safeFightSource, "clearPartyTools(party)", 1, true)
		local failureInactivePublish = string.find(safeFightSource, "publishInactive(party)", 1, true)
		expectEqual(
			countPlainOccurrences(dungeonServiceSource, "runFight(") == 2
				and countPlainOccurrences(dungeonServiceSource, "runFightSafely(") >= 4
				and string.find(dungeonServiceSource, "local function attemptEncounterCleanup", 1, true) ~= nil
				and string.find(dungeonServiceSource, "local ok, problem = pcall(callback)", 1, true) ~= nil
				and string.find(safeFightSource, "local ok, failure = xpcall(function()", 1, true) ~= nil
				and string.find(
					safeFightSource,
					"outcome, survivors = runFight(party, bossId, core)",
					1,
					true
				) ~= nil
				and string.find(safeFightSource, "return tostring(problem)", 1, true) ~= nil
				and string.find(safeFightSource, 'attemptEncounterCleanup("connection"', 1, true) ~= nil
				and string.find(safeFightSource, 'attemptEncounterCleanup("tool"', 1, true) ~= nil
				and string.find(safeFightSource, 'attemptEncounterCleanup("state"', 1, true) ~= nil
				and failureInvalidation ~= nil
				and failureDisconnect ~= nil
				and failureRunClear ~= nil
				and failureToolClear ~= nil
				and failureInactivePublish ~= nil
				and failureInvalidation < failureRunClear
				and failureRunClear < failureDisconnect
				and failureDisconnect < failureToolClear
				and failureToolClear < failureInactivePublish,
			true,
			"every encounter entry uses the xpcall boundary whose failure finalizer invalidates state and cleans the party"
		)
	end
	expectEqual(
		string.find(dungeonServiceSource, "resolvePartyWeapons", 1, true) ~= nil
			and string.find(
				dungeonServiceSource,
				"target.equippedItemId(player, dungeon.equipmentSlot)",
				1,
				true
			) ~= nil
			and string.find(
				dungeonServiceSource,
				"target.ensureEquipped(player, dungeon.equipmentSlot, dungeon.starterWeaponId)",
				1,
				true
			) ~= nil
			and string.find(dungeonServiceSource, "current.weapons[player]", 1, true) ~= nil,
		true,
		"dungeon runs resolve and cache each server-owned saved weapon loadout"
	)
	expectEqual(
		string.find(dungeonServiceSource, "function DungeonService.registerHit(player: Player)", 1, true)
				~= nil
			and string.find(dungeonServiceSource, "weapon.cooldownSeconds", 1, true) ~= nil
			and string.find(dungeonServiceSource, "DungeonLogic.canStrike", 1, true) ~= nil
			and string.find(dungeonServiceSource, "strikeHasLineOfSight", 1, true) ~= nil
			and string.find(dungeonServiceSource, "Workspace:Raycast", 1, true) ~= nil
			and string.find(
					dungeonServiceSource,
					"DungeonLogic.applyHit(current.health, weapon.damage)",
					1,
					true
				)
				~= nil,
		true,
		"server validates weapon cooldown, range, facing, height, and line of sight before damage"
	)
	expectEqual(
		string.find(dungeonServiceSource, "function DungeonService.registerDodge(player: Player)", 1, true)
				~= nil
			and string.find(dungeonServiceSource, "current.lastDodgeAt[player]", 1, true) ~= nil
			and string.find(dungeonServiceSource, "humanoid.MoveDirection", 1, true) ~= nil
			and string.find(dungeonServiceSource, "dungeon.dodgeSpeed", 1, true) ~= nil
			and string.find(dungeonServiceSource, "root.AssemblyLinearVelocity", 1, true) ~= nil,
		true,
		"dodge cadence and movement direction are resolved and applied by the server"
	)
	local defeatCheck = string.find(dungeonServiceSource, "DungeonLogic.isDefeated(current.health)", 1, true)
	local wipeCheck = string.find(dungeonServiceSource, "DungeonLogic.isPartyWiped", 1, true)
	expectEqual(
		defeatCheck ~= nil
			and wipeCheck ~= nil
			and defeatCheck < wipeCheck
			and string.find(dungeonServiceSource, 'current.resultReason = "partyWipe"', 1, true) ~= nil
			and string.find(dungeonServiceSource, 'current.resultReason = "timeout"', 1, true) ~= nil,
		true,
		"boss defeat wins a tie while timeout and party wipe remain explicit server-owned outcomes"
	)
	expectEqual(
		string.find(dungeonServiceSource, "target.award(player, boss.rewardCurrencyId", 1, true) ~= nil
			and string.find(
				dungeonServiceSource,
				"target.grantItem(player, boss.rewardItemId, boss.rewardItemQuantity)",
				1,
				true
			) ~= nil
			and string.find(dungeonServiceSource, "if target.ready(player) then", 1, true) ~= nil,
		true,
		"victory currency and weapon rewards are granted only through ready server profiles"
	)
	local grantedRewardRecord =
		string.find(dungeonServiceSource, "current.rewardByUserId[tostring(player.UserId)] = {", 1, true)
	local finalResultPublish = if grantedRewardRecord ~= nil
		then string.find(dungeonServiceSource, "publishRun(result)", grantedRewardRecord, true)
		else nil
	expectEqual(
		string.find(dungeonServiceSource, 'if result == "victory" and target ~= nil then', 1, true) ~= nil
			and grantedRewardRecord ~= nil
			and string.find(dungeonServiceSource, "currencyId = actualCurrencyId", grantedRewardRecord, true) ~= nil
			and string.find(
				dungeonServiceSource,
				"currencyAmount = actualCurrencyAmount",
				grantedRewardRecord,
				true
			) ~= nil
			and string.find(dungeonServiceSource, "itemName =", grantedRewardRecord, true) ~= nil
			and string.find(
				dungeonServiceSource,
				"itemQuantity = actualItemQuantity",
				grantedRewardRecord,
				true
			) ~= nil
			and finalResultPublish ~= nil
			and grantedRewardRecord < finalResultPublish,
		true,
		"final victory state publishes each player's actual granted currency and item record after mutation"
	)
	expectEqual(
		string.find(inventoryServiceSource, "function InventoryService.grant", 1, true) ~= nil
			and string.find(inventoryServiceSource, "actualAdded", 1, true) ~= nil
			and string.find(inventoryServiceSource, "clearEquippedSlot", 1, true) ~= nil
			and string.find(inventoryServiceSource, "function InventoryService.equippedItemId", 1, true) ~= nil
			and string.find(inventoryServiceSource, "function InventoryService.ensureEquipped", 1, true) ~= nil
			and string.find(inventoryServiceSource, "ProfileService.markDirty", 1, true) ~= nil,
		true,
		"dungeon weapon grants and exclusive equipment choices persist through InventoryService"
	)
	local launchCall = string.find(portalServiceSource, "if not target.launch(players, bossId) then", 1, true)
	local clearRoster = string.find(portalServiceSource, "table.clear(order)", 1, true)
	expectEqual(
		launchCall ~= nil and clearRoster ~= nil and launchCall < clearRoster,
		true,
		"portal consumes its visible roster only after a launch is accepted"
	)
	expectEqual(
		string.find(serverBootstrapSource, "Config.features.towerDefense and not dungeonMode", 1, true) ~= nil,
		true,
		"reserved dungeon servers do not start lobby tower defense systems"
	)
	local runtimeModePublish =
		string.find(serverBootstrapSource, 'Template:SetAttribute("RuntimeMode"', 1, true)
	local remoteInitialize = string.find(serverBootstrapSource, "RemoteService.initialize()", 1, true)
	expectEqual(
		runtimeModePublish ~= nil
			and remoteInitialize ~= nil
			and runtimeModePublish < remoteInitialize
			and string.find(serverBootstrapSource, "Config.features.runes and not dungeonMode", 1, true) ~= nil
			and string.find(serverBootstrapSource, "InventoryService.ensureEquipped", 1, true) ~= nil
			and string.find(serverBootstrapSource, "grantItem = InventoryService.grant", 1, true) ~= nil,
		true,
		"server publishes runtime mode before remotes, skips lobby systems, and wires saved weapon rewards"
	)
	do
		local optionalLobbyUiWait =
			string.find(mainClientSource, 'playerGui:WaitForChild("TemplateUI")', 1, true)
		local worldRenderersStartBeforeOptionalUi = optionalLobbyUiWait ~= nil
		for _, initializer in
			{
				"StageGridRenderer.initialize()",
				"StagePlatformOwnerController.initialize()",
				"StageEnemyRenderer.initialize()",
				"StageTowerRenderer.initialize()",
			}
		do
			local initializerAt = string.find(mainClientSource, initializer, 1, true)
			worldRenderersStartBeforeOptionalUi = worldRenderersStartBeforeOptionalUi
				and initializerAt ~= nil
				and initializerAt < optionalLobbyUiWait
		end
		expectEqual(
			worldRenderersStartBeforeOptionalUi,
			true,
			"tower-defense world renderers start before the optional template lobby UI wait"
		)
	end
	for clientName, source in
		{
			main = mainClientSource,
			runes = runeClientSource,
			starter = starterClientSource,
		}
	do
		local dungeonGate = string.find(source, 'Template:GetAttribute("RuntimeMode") == "dungeon"', 1, true)
		local firstWorldWait = string.find(source, "Workspace:WaitForChild", 1, true)
		expectEqual(
			dungeonGate ~= nil and (firstWorldWait == nil or dungeonGate < firstWorldWait),
			true,
			`{clientName} lobby client exits dungeon mode before waiting on lobby-only world content`
		)
	end
end

print(`{passed} pure Luau assertions passed`)

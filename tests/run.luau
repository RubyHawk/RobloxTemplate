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
	local keyedUnitIds: any = { "unit_scout" }
	keyedUnitIds.metadata = true
	for _, invalidLoadoutPayload in
		{
			{},
			{ unitIds = "unit_scout" },
			{ unitIds = { "" } },
			{ unitIds = { "unit_scout", "unit_scout" } },
			{ unitIds = { "unit_scout", "unit_guard", "unit_mage" } },
			{ unitIds = { [2] = "unit_scout" } },
			{ unitIds = keyedUnitIds },
			{ unitIds = { "unit_scout" }, selectedByClient = true },
		}
	do
		expectEqual(
			TowerDefenseRequest.parseLoadout(invalidLoadoutPayload, 2),
			nil,
			"tower loadout rejects malformed, oversized, duplicate, or undeclared data"
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
end

do
	local StagePayload = require("../src/shared/StagePayload")
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

	for _, version in { 0, 2 } do
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
	string.find(migrationsSource, "Migrations.CURRENT_VERSION = 7", 1, true) ~= nil,
	true,
	"profile schema version is current"
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
	}
do
	expectEqual(
		string.find(rngPatchDesignerConfig, patchConfigObject, 1, true) ~= nil,
		true,
		`RNG Defender patch config includes {patchConfigObject}`
	)
end
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
	local stagewrightPaintAppearanceSource = fs.readFile("src/plugins/Stagewright/UI/PaintAppearance.luau")
	local stagewrightPaintCellOverlaySource = fs.readFile("src/plugins/Stagewright/UI/PaintCellOverlay.luau")
	local stagewrightPaintInspectorSource = fs.readFile("src/plugins/Stagewright/UI/PaintInspector.luau")
	local stagewrightToolbarSource = fs.readFile("src/plugins/Stagewright/UI/Toolbar.luau")
	local stagewrightGraphOperationsSource = fs.readFile("src/plugins/Stagewright/Graph/Operations.luau")
	local stagePathAssetsSource = fs.readFile("src/shared/StagePathAssets.luau")
	local stagewrightPredicateFieldsSource = fs.readFile("src/plugins/Stagewright/Graph/PredicateFields.luau")
	local stagewrightPaintBrushesSource = fs.readFile("src/plugins/Stagewright/Paint/Brushes.luau")
	local stagewrightStageSettingsSource = fs.readFile("src/plugins/Stagewright/Stage/Settings.luau")
	local stagewrightIssueModelSource = fs.readFile("src/plugins/Stagewright/Validation/IssueModel.luau")
	local stagewrightImportSource = fs.readFile("scripts/stagewright-import.luau")
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
	expectCompiles(stagewrightPaintAppearanceSource, "Stagewright paint appearance compiles as Luau")
	expectCompiles(stagewrightPaintCellOverlaySource, "Stagewright paint cell overlay compiles as Luau")
	expectCompiles(stagewrightPaintInspectorSource, "Stagewright paint inspector compiles as Luau")
	expectCompiles(stagewrightToolbarSource, "Stagewright toolbar compiles as Luau")
	expectCompiles(stagewrightGraphOperationsSource, "Stagewright graph operations compile as Luau")
	expectCompiles(stagePathAssetsSource, "shared Stagewright path asset catalog compiles as Luau")
	expectCompiles(stagewrightPredicateFieldsSource, "Stagewright predicate fields compile as Luau")
	expectCompiles(stagewrightPaintBrushesSource, "Stagewright paint brushes compile as Luau")
	expectCompiles(stagewrightStageSettingsSource, "Stagewright stage settings compile as Luau")
	expectCompiles(stagewrightIssueModelSource, "Stagewright validation issue model compiles as Luau")
	expectCompiles(stagewrightImportSource, "Stagewright repository importer compiles as Luau")
	expectEqual(
		string.find(gridPluginProject, '"StagePathAssets"', 1, true) ~= nil
			and string.find(gridPluginProject, '"../src/shared/StagePathAssets.luau"', 1, true) ~= nil,
		true,
		"Stagewright plugin maps the shared path asset catalog"
	)
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
			and string.find(gridPluginSource, "reportBlocked = flowRuntime.reportBlocked", 1, true) ~= nil
			and string.find(gridPluginSource, "setStatus = setStatus", 1, true) ~= nil
			and string.find(gridPluginSource, "shell.mapPlayable.Activated:Connect", 1, true) == nil
			and string.find(gridPluginSource, "shell.mapAdmin.Activated:Connect", 1, true) == nil,
		true,
		"Stagewright bootstrap delegates MAP behavior to the extracted navigation controller"
	)
	for _, mapNavigationBehavior in
		{
			"playableButton.Activated:Connect",
			"adminButton.Activated:Connect",
			"callbacks.cancelInteraction()",
			"AuthoringArea.focusPlayable()",
			"AuthoringArea.focus()",
			"ProjectStore.isWritable()",
			'callbacks.reportBlocked("Focus authoring area")',
			"callbacks.setStatus(",
			"Focused the playable map.",
			"The playable map could not be found.",
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
				"stageSelector.dropdown.Visible = false",
				1,
				true
			) ~= nil
			and string.find(
				stagewrightHeaderControllerSource,
				"levelSelector.dropdown.Visible = false",
				1,
				true
			) ~= nil
			and string.find(stagewrightHeaderControllerSource, "config.levelOptions()", 1, true) ~= nil,
		true,
		"Stagewright header separates Stage and Level selectors and closes competing popovers"
	)
	expectEqual(
		string.find(gridPluginSource, "seenGroups[address.groupId]", 1, true) ~= nil
			and string.find(gridPluginSource, "levelOptions = function()", 1, true) ~= nil
			and string.find(gridPluginSource, "address.groupId == selectedAddress.groupId", 1, true)
				~= nil,
		true,
		"Stagewright header groups Stages by stable hierarchy ID and scopes Levels to the selection"
	)
	expectEqual(
		string.find(gridPluginSource, "require(script.UI.AppShell)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.GraphToolController)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.PaintRouteDragSession)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.PaintStrokeSession)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.Controllers.WorldPathController)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.PaintCellOverlay)", 1, true) ~= nil
			and string.find(gridPluginSource, "require(script.UI.PaintInspector)", 1, true) ~= nil
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
			"ProjectStore.createStage(",
			"ProjectStore.createLevel(",
			"ProjectStore.deleteStage(",
			"AuthoringArea.showIslandOutlines(",
		}
	do
		expectEqual(
			string.find(gridPluginSource, bootstrapCall, 1, true) ~= nil,
			true,
			`Stagewright bootstrap wires {bootstrapCall}`
		)
	end
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
		gridPluginLineCount <= 5000,
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
	}
do
	expectEqual(
		string.find(responsiveController, requiredMarker, 1, true) ~= nil,
		true,
		`responsive controller clamps overflow/overlap on short viewports: {requiredMarker}`
	)
end

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
local bestTowerLoadout = TowerDefenseLogic.bestLoadout({
	forest_archer = { count = 1 },
	mushroom_bomber = { count = 1 },
	ancient_treant = { count = 1 },
}, TowerDefenseCatalog.units, 2)
expectEqual(bestTowerLoadout[1], "ancient_treant", "equip best favors the strongest owned unit")
expectEqual(#bestTowerLoadout, 2, "equip best respects loadout slot cap")
expectEqual(TowerDefenseLogic.waveScale(1), 1, "first tower defense wave uses base scale")
expectEqual(TowerDefenseLogic.waveScale(5) > 1, true, "later tower defense waves scale up")

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
expectEqual(migratedStageProject.schemaVersion, 3, "Stagewright authoring schemas migrate sequentially")
expectEqual(
	migratedStageProject.stages.legacy.stageNumber == 1
		and migratedStageProject.stages.legacy.levelNumber == 1,
	true,
	"legacy flat stages migrate into stable Stage 1 / Level 1 hierarchy fields"
)
expectEqual(
	migratedStageProject.stages.legacy.unknownFutureField.preserved,
	true,
	"Stagewright migration preserves unknown stage data"
)
expectEqual(
	StageSchema.migrateProject(migratedStageProject).schemaVersion,
	3,
	"Stagewright migration is idempotent"
)
do
	local authoringProject = serde.decode("json", fs.readFile("stage-data/stagewright-project.json"))
	local authoredProductionStage = authoringProject.stages.stage_default
	expectEqual(authoredProductionStage.name, "Level 1", "repository names the starting definition Level 1")
	expectEqual(
		authoringProject.metadata["stagewright.approvedStarterRevision"],
		StageStarterProject.REVISION,
		"repository starter data records its approved replacement revision"
	)
	local authoredLevelIds = StageHierarchy.sortedIds(authoringProject.stages)
	expectEqual(#authoredLevelIds, 10, "repository seeds Stage 1 with the first ten levels")
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
			address.stageNumber == 1 and address.levelNumber == levelNumber,
			true,
			`authored Stage 1 level order includes Level {levelNumber}`
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
	local projectedLaneProfile = projectedGraph and projectedGraph.laneProfiles[projectionEdge.laneProfileId]
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
	local staleOutgoingProject = serde.decode("json", serde.encode("json", authoringProject))
	staleOutgoingProject.stages.stage_default.pathGraphs[authoredGraphId].outgoingEdgeIds = {}
	local staleOutgoingExport = StageExport.bake(staleOutgoingProject)
	local rebuiltGraph = staleOutgoingExport.bundle
		and staleOutgoingExport.bundle.stages.stage_default.pathGraphs[authoredGraphId]
	local rebuiltOutgoing = rebuiltGraph and rebuiltGraph.outgoingEdgeIds[projectionEdge.fromNodeId]
	expectEqual(
		rebuiltOutgoing ~= nil and table.find(rebuiltOutgoing, projectionEdgeId) ~= nil,
		true,
		"runtime export validates edge maps and rebuilds stale authoring outgoing caches"
	)
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
	local incrementalUi = fs.readFile("src/ui/presets/incremental/TemplateUI.model.json")
	for _, authoredHudObject in { '"Name": "RunesValue"', '"Name": "ChannelValue"' } do
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
		"TowerDefenseService.equipBest",
		"TowerDefenseService.placeUnit",
		"TowerDefenseService.autoPlaceBest",
		"TowerDefenseService.startWave",
		"TowerDefenseService.resetMatch",
		"TowerDefenseService.activateStage",
		"TowerDefenseService.snapshotFor",
		"TowerDefenseService.presentationSnapshot",
		"EconomyService.spendCurrency",
		"TowerDefenseLogic.isBuildableCell",
		"RunService.Heartbeat",
		"StageRuntimeService.chooseEdge",
		"maximum travel distance exceeded",
		"Workspace:GetServerTimeNow",
		"buildEnemySpatialIndex",
		"simulationAccumulator",
		"StageCatalog.nextLevelId",
		"publishEnemies",
		"publishPlacements",
		"placementRevision",
	}
do
	expectEqual(
		string.find(towerDefenseServiceSource, towerDefenseMarker, 1, true) ~= nil,
		true,
		`tower defense service includes {towerDefenseMarker}`
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
	string.find(serverBootstrapSource, "not StagePlatformService.hasPlatform(player)", 1, true) ~= nil,
	true,
	"players without an authoritative platform are rejected before profile load"
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
		"EquipBestUnits",
		"PlaceUnit",
		"AutoPlaceBestUnits",
		"StartTowerWave",
		"ResetTowerDefense",
		"ActivateTowerStage",
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
		and string.find(runeConfigSource, "loadoutSlots = 4", 1, true) ~= nil,
	true,
	"tower defense gameplay loop has configured roll cost and loadout slots"
)

print(`{passed} pure Luau assertions passed`)

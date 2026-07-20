# Stagewright architecture and Roblox API check — 2026-07-12

Official Roblox documentation reviewed before replacing the grid editor's persistence, undo, path, and runtime movement boundaries:

- Studio plugins: https://create.roblox.com/docs/studio/plugins
- Plugin API (`CreateDockWidgetPluginGuiAsync`, `CreatePluginAction`, `SetSetting`, `Unloading`): https://create.roblox.com/docs/reference/engine/classes/Plugin
- ChangeHistoryService recordings: https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService
- Selection service: https://create.roblox.com/docs/reference/engine/classes/Selection
- Instance attributes and tags: https://create.roblox.com/docs/studio/properties
- Vector3Curve: https://create.roblox.com/docs/reference/engine/classes/Vector3Curve
- Client/server runtime: https://create.roblox.com/docs/projects/client-server
- Instance streaming: https://create.roblox.com/docs/workspace/streaming
- Network ownership: https://create.roblox.com/docs/physics/network-ownership
- Performance improvement guidance: https://create.roblox.com/docs/performance-optimization/improve

Decisions:

- Project data is stored in the saved DataModel and exported deterministically; `Plugin:SetSetting()` is only for local UI preferences.
- Every interactive plugin mutation uses a `TryBeginRecording()` / `FinishRecording()` transaction. `Plugin.Unloading` finalizes an unfinished recording and removes transient previews.
- Stage routes are directed cubic Bezier graphs with authoring-time arc-length samples. `Vector3Curve` is not used because Stagewright also needs graph connectivity, predicates, lanes, and distance-based traversal.
- The server owns stage activation, branch decisions, combat, rewards, and progress. Clients only interpolate sanitized route state for presentation.
- Runtime stage data does not depend on Workspace descendants being streamed to a client.
- High-frequency server work uses a fixed simulation interval and cached edge samples. Parallel Luau is deferred until profiling demonstrates a remaining pure-computation bottleneck.

## Shared migration source

- The team confirmed the existing shared tower-defense place is `128136881672145` (`https://www.roblox.com/games/128136881672145`).
- Roblox's official place-to-universe endpoint resolved it on 2026-07-12 to universe `10479279603`: `https://apis.roblox.com/universes/v1/places/128136881672145/universe`.
- `7_STAGEWRIGHT_SHARED.cmd` opens this existing place without starting Rojo. This prevents the repository's blank legacy island model from overwriting Team Create-only authored data before the Stagewright bundle is exported and reviewed.
- Deployable runtime QA continues through the permanent `playerTest` experience. The shared place is the migration and collaborative authoring source, not a disposable test target.

## Flow editor API re-check — 2026-07-15

The World Path / Route Logic implementation re-checked the exact Studio APIs used by the interactive preview:

- `LayerCollector.ZIndexBehavior`: https://create.roblox.com/docs/reference/engine/classes/LayerCollector
- `Selection.SelectionChanged`, `Selection:Get()`, and `Selection:Set()`: https://create.roblox.com/docs/reference/engine/classes/Selection

The dock widget uses sibling Z-order so nested route controls remain above their opaque view surfaces. Workspace gravel and node previews expose stable ID attributes; Studio selection changes resolve those IDs back to the selected graph object. This remains edit-mode-only and does not grant runtime authority to Workspace instances.

## World Path interaction API re-check - 2026-07-18

Official Roblox API references reviewed before changing pointer capture, keyboard cancellation, and dock-widget focus behavior:

- `UserInputService.InputBegan`, `InputChanged`, `InputEnded`, and `WindowFocusReleased`: https://create.roblox.com/docs/reference/engine/classes/UserInputService
- `GuiObject.InputBegan`, `InputChanged`, and `InputEnded`: https://create.roblox.com/docs/reference/engine/classes/GuiObject
- `PluginGui.WindowFocusReleased` and `BindToClose`: https://create.roblox.com/docs/reference/engine/classes/PluginGui
- `LayerCollector.Enabled`: https://create.roblox.com/docs/reference/engine/classes/LayerCollector

Decisions:

- An edit begins only from a primary pointer press on a declared hit target and crosses a fixed movement threshold before mutating authored data.
- The initiating input object identifies touch drags; mouse drags use the initiating button plus the global input end event so release outside the canvas is still observed.
- Escape, widget focus loss, widget close, mode/view changes, and plugin unload all roll back an active interaction through one idempotent cancellation path.
- Drawing and hit-testing share one uniform canvas transform so non-square dock widgets do not distort route geometry.

## Paint interaction API re-check - 2026-07-19

Official Roblox API references reviewed before correcting grid painting and cell outlines:

- Studio widget input guidance: https://create.roblox.com/docs/studio/build-studio-widgets#gather-user-input
- `GuiObject.MouseEnter` and input events: https://create.roblox.com/docs/reference/engine/classes/GuiObject
- `InputObject:IsModifierKeyDown()` and `UserInputState`: https://create.roblox.com/docs/reference/engine/classes/InputObject
- `UIStroke.ApplyStrokeMode`, `Thickness`, and `ZIndex`: https://create.roblox.com/docs/reference/engine/classes/UIStroke

Decisions:

- Cells own their exact `GuiObject.InputBegan` hit and read Shift from that mouse `InputObject`; cell painting never queries `UserInputService`, which Roblox documents as unreliable while a Studio dock widget has focus.
- The initiating mouse `InputObject` owns the whole gesture. Its `UserInputState` ends or cancels the undo transaction, while `MouseEnter` extends an armed Pencil or Erase stroke.
- A mutation cannot start without Shift. Releasing Shift commits an armed Pencil or Erase stroke at mouse release, but cancels an armed Rectangle stroke.
- Dedicated logical `UIStroke` frames render complete hover and selection outlines independently of cell borders.
- Surface, tower placement, enemy route access, and optional roles are independent cell properties. The paint canvas renders the active property, while the inspector shows the effective values of every property after level-default inheritance.
- Erase restores only the active property. The explicit Reset Cell action is the only paint action that clears every authored cell property.
- Spawn, goal, and auto-place are mutually exclusive primary roles. Enabling an endpoint also blocks tower placement; enabling auto-place sets tower placement to Allowed. The UI discloses these compatibility changes.

## Flow navigation API re-check - 2026-07-19

Official Roblox API references reviewed before correcting mouse-wheel navigation inside the dock widget:

- Studio widget input guidance: https://create.roblox.com/docs/studio/build-studio-widgets#gather-user-input
- `ScrollingFrame.ScrollingEnabled`, `CanvasPosition`, and `CanvasSize`: https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame
- `ModifierKey.Ctrl`: https://create.roblox.com/docs/reference/engine/enums/ModifierKey

Decisions:

- Route Logic disables native `ScrollingFrame` wheel movement. Its explicit Pan, zoom, Center, and Fit controls remain authoritative.
- World Path accepts wheel zoom only from its active GUI root while Ctrl is held; global `UserInputService` wheel events never navigate a Studio widget.
- Neither World Path nor Route Logic can zoom below its fitted map scale. Entering Graph, changing its subview, changing the selected stage/graph, or reopening the widget fits the active view once so authored content cannot remain stranded off-screen.

## World Path direct-manipulation API re-check - 2026-07-19

Official Roblox references reviewed before replacing the unreliable World Path drag lifecycle:

- Studio widget input guidance: https://create.roblox.com/docs/studio/build-studio-widgets#gather-user-input
- `GuiObject.InputBegan`, `InputChanged`, and `InputEnded`: https://create.roblox.com/docs/reference/engine/classes/GuiObject
- `InputObject.Position`, `UserInputState`, and modifier state: https://create.roblox.com/docs/reference/engine/classes/InputObject
- `PluginGui:GetRelativeMousePosition()` and focus events: https://create.roblox.com/docs/reference/engine/classes/PluginGui
- `DockWidgetPluginGui`: https://create.roblox.com/docs/reference/engine/classes/DockWidgetPluginGui

Decisions:

- A persistent transparent map `GuiObject` owns press, move, and release inside the dock widget. World Path no longer depends on global `UserInputService` pointer events; this supersedes the mouse-release detail recorded in the 2026-07-18 interaction check.
- The initiating `InputObject.UserInputState` owns commit or cancellation. A widget-relative mouse sample keeps the gesture captured when the pointer crosses rebuilt route visuals or leaves the original marker.
- Node and handle drags preserve the initial grab offset, clamp authored positions to the level grid, and expose larger invisible hit targets. Route labels are also valid node drag targets.
- Live drag geometry is sampled directly from the mutable cubic graph. Expensive path baking, conflict-mask derivation, and persistence occur once on release; focus loss or Escape rolls the single edit transaction back.
- Fit frames the authored route nodes and handles with context instead of shrinking them to contain unused grid space. Pan still exposes the complete level grid.

## Flow graph-tool and legacy-overlay re-check - 2026-07-19

Official Roblox references reviewed before correcting Connect/Split input and hiding the imported path helpers:

- Studio widget input guidance: https://create.roblox.com/docs/studio/build-studio-widgets#gather-user-input
- `GuiObject` input events: https://create.roblox.com/docs/reference/engine/classes/GuiObject
- `BasePart.LocalTransparencyModifier`: https://create.roblox.com/docs/reference/engine/classes/BasePart#LocalTransparencyModifier

Decisions:

- Connect and Split are explicit tools in both World Path and Route Logic. Connect arms one non-goal source, retains it after an invalid destination, commits one directed edge on a valid second node, and then returns to Select. Split commits the next clicked spline at its geometric midpoint and selects the inserted junction.
- The extracted graph-tool controller owns these state transitions and graph mutations. Canvas views emit semantic node/edge intents and never mutate graph data directly.
- Node marker hit targets outrank label hit targets. Repeated clicks over the same overlapping node set cycle deterministically, while an eight-pixel movement threshold prevents ordinary selection jitter from moving authored nodes.
- Before the canonical-project boundary, an unsaved or never-imported legacy workspace remains eligible for the migration readers. Its `PathPoints` and `PathTiles` helpers are excluded from the World Path backdrop using reversible, local-only transparency while Graph or Paint is open; closing the widget or leaving those modes restores their prior values.
- A valid checksummed canonical project load, or completion of the first successful canonical save, establishes the safe retirement boundary. Only then does Stagewright remove direct `GamePlatform/PathPoints`, `GamePlatform/PathTiles`, and `GamePlatform/PlatformBase/GridOverlay` legacy children plus fingerprinted `GridNpc` and `GridNpcDemo` demo instances. Cleanup joins an active Stagewright transaction or acquires its own Studio change-history recording; if neither is possible, it defers without deleting anything. The operation is idempotent and does not treat same-named content elsewhere as legacy.
- Legacy helpers are never exported as the active route. Canonical route graphs and baked lane data remain authoritative for `StageRuntimeService` and `TowerDefenseService`, while `TowerEnemies` snapshots and `StageEnemyRenderer` continue to drive real enemy simulation and presentation; retiring the fake walker does not remove gameplay routing or enemies.
- Path assets are stable symbolic metadata backed by one shared catalog. World Path, the 3D Studio preview, exported stage data, and the client development renderer resolve the same color and Roblox material. Unknown imported IDs remain stored, surface an `UnknownPathAsset` warning, and visibly identify the gravel fallback instead of silently changing meaning.
- Authored lane width now drives lane offsets, route clearance/no-build derivation, World Path, the Studio preview, and each runtime lane strip. The previous fixed runtime strip width was removed so the in-game road footprint agrees with the editor.
- Stagewright currently authors deterministic routes on the level plane. The inspector therefore shows a read-only `Route plane` field; it does not offer fictitious terrain-following/fixed-height choices until a persisted height provider can keep export, server routing, and every client synchronized.
- The short inspector stays at 104 pixels so the supported 880-by-560 widget retains a manipulable map. Node labels share exact visual/hit geometry, and the legend hides whenever it could cover an editable marker.

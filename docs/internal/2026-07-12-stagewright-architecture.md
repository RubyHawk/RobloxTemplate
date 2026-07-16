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

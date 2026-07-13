# Stagewright admin authoring-area separation — 2026-07-13

## Decision

The editable `GamePlatform` is no longer the runtime anchor for player slot 1.
Stagewright keeps one canonical authoring platform under
`Workspace.StagewrightAdminArea`, 1,000 studs below `center_grass`, inside an
open-front white room. The plugin preserves the existing model and moves it as
one pivot operation, so `CellMap`, path controls, surface previews, unknown
children, and metadata stay intact.

The six player islands remain runtime surfaces. `StagePlatformService` derives
slot 1 from `center_grass` plus
`TemplateConfig.towerDefense.firstPlatformOffsetFromCenter`, then rotates that
local frame in 60-degree steps. Moving the admin platform can therefore never
move a player's gameplay route, towers, or ownership marker.

## Lifecycle and safety

- The admin room is created only by the Studio plugin while Studio is in Edit
  mode. Local plugins loaded into Play Server or Play Client data models never
  mutate the world.
- The migration uses a ChangeHistoryService recording and remains undoable.
- If `center_grass` is absent, the plugin leaves the legacy platform in place
  rather than guessing a world transform.
- Existing admin rooms at the current layout version are preserved, including
  manual movement of the room or platform.
- The room is persistent authoring state. Only graph handles and curve previews
  inside it carry the transient Stagewright preview tag.
- The **Focus Admin** button and `StagewrightFocusAdminArea` PluginAction select
  the main platform and move the Studio camera to the open side of the room.
- The deeper offset keeps the white room out of sight through water and gaps in
  the production world. During Play, the client also hides every descendant of
  `StagewrightEditorOnly` roots, so the room cannot leak into gameplay.
- **Island Guides** creates a non-archivable, Edit-mode-only footprint at each
  of the six authoritative slot transforms. Cyan edges show the exact grid
  bounds and the orange bar shows orientation.
- Legacy `Edit Grid` controls are hidden if they remain in Team Create data,
  and the Stagewright plugin exits before constructing editor controls in Play
  Server or Play Client data models.

## Runtime result

Every client still renders `Platform_01` through `Platform_06` from the same
generated stage catalog. Ownership and gameplay transforms use the server's six
published CFrames; the admin platform is never treated as a seventh playable
slot and is not used by authoritative route sampling.

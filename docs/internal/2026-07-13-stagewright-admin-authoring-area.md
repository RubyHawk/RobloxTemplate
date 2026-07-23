# Stagewright admin authoring-area separation — 2026-07-13

## 2026-07-23 access correction

Layout version 4 deliberately realigns any version-3 admin room to the
configured editor-only offset. Version 3 preserved manual movement, which could
leave `StagewrightAdminArea` overlapping the production lobby after a Team
Create edit. Stagewright applies this migration before it loads the working
project, so opening the plugin repairs the room without requiring a separate
focus action.

The playable islands remain remote runtime surfaces. Players now receive the
pre-authored `TowerDefenseTravelHUD` whenever tower defense is enabled. Its
**Go to My Tower** button sends a payload-free, rate-limited request; the server
resolves the player's assigned slot and moves the live character seven studs
above that platform origin. The client cannot choose a slot or world CFrame.

## Decision

The editable `GamePlatform` is no longer the runtime anchor for player slot 1.
Stagewright keeps one canonical authoring platform under
`Workspace.StagewrightAdminArea`, 1,000 studs below and 3,000 studs outside the
`center_grass` world footprint, inside an open-front white room. The plugin
preserves the existing model and moves it as
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
- The offset keeps the white room away from transparent water and gaps in the
  production world. Legacy authoring `SurfaceGui` and `BillboardGui` instances
  have `AlwaysOnTop` disabled so they obey normal world occlusion.
- During Play, `StagePlatformService` first publishes all six gameplay origins,
  then moves `StagewrightAdminArea` from `Workspace` to `ServerStorage` for the
  running session. A client-side name/attribute fallback also hides editor-only
  roots, so stale Team Create copies cannot leak into gameplay.
- **Island Guides** creates a non-archivable, Edit-mode-only footprint at each
  of the six authoritative slot transforms. Cyan boundary and interior lines
  show every exact cell. The old orange orientation bar was removed because it
  looked like route geometry; platform alignment remains covered by the shared
  yaw calculation and its pure tests.
- Legacy `Edit Grid` controls are hidden if they remain in Team Create data,
  and the Stagewright plugin exits before constructing editor controls in Play
  Server or Play Client data models.

## Runtime result

Every client still renders `Platform_01` through `Platform_06` from the same
generated stage catalog. Ownership and gameplay transforms use the server's six
published CFrames; the admin platform is never treated as a seventh playable
slot and is not used by authoritative route sampling.

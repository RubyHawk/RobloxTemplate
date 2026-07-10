# Grid Plugin Luau Register Limit Fix - 2026-07-10

## What happened

The locally installed Studio build of the grid editor (saved as
`Stagewright.rbxm` in the local Plugins folder) stopped loading. Studio's
console showed, on every start:

```
user_Stagewright.rbxm.StagewrightPlugin:3265: Out of local registers when
trying to allocate snapToSelection: exceeded limit 200
```

Luau allows at most 200 local registers per function scope, and a script's
top level is one scope. The plugin was written as one flat script whose top
level had crept to just under that cap (the checked-in 2,787-line version
compiled with only ~33 spare locals). Local feature additions pushed it
over, the script stopped compiling entirely, and the toolbar button never
appeared - total plugin death from one added `local`.

Reproduced in this repo: appending 33 used top-level locals to the previous
source produced the identical `Out of local registers ... exceeded limit
200` compile error via `luau.compile` (Lune 0.10.4).

## Fix

`src/plugins/GridPlatformEditPlugin.server.luau` was restructured with no
behavior change:

- All 42 SCREAMING_CASE constants moved into one `C` table.
- All 100 top-level functions moved onto six namespace tables:
  `Scene` (instance/grid lookups), `View` (panel + visual state), `Undo`
  (ChangeHistoryService recordings), `Paint` (viewport/canvas painting),
  `Spline` (path editing), `Actions` (top-level buttons).
- Definition order is unchanged, so call-before-definition hazards cannot
  have been introduced.

Top-level locals went from ~196 effective registers to 54 (+146 measured
headroom), and table entries cost no registers, so the plugin can now grow
indefinitely if new code follows the pattern documented at the top of the
file: add table entries, never new top-level `local` declarations.

## Guardrails

- `tests/run.luau` now compiles the plugin source with `@lune/luau` and
  fails if top-level `local` declarations exceed 80.
- `scripts/check.ps1` builds `plugins/grid-platform-editor.project.json`.
- `scripts/install-grid-plugin.ps1` retires any broken `Stagewright.rbxm`
  (renamed with a `.retired-<timestamp>` suffix, not deleted) so the
  startup error stops while the newer local bytes stay recoverable.

## Lesson recorded

The broken Stagewright build was edited and installed directly on the
local machine without committing the source, so its extra features beyond
the checked-in version could not be recovered here. Plugin changes must go
through this repository (`6_INSTALL_GRID_PLUGIN.cmd` rebuilds and installs
from source) so every version stays recoverable.

## Verification (2026-07-10)

- `luau.compile` on the restructured source: clean.
- Scripted identifier audit: zero bare references to any moved name.
- Selene 0.31.0 (`undefined_variable`/`unused_variable` via an offline
  globals shim; CI still runs the full generated Roblox std): clean.
- StyLua 2.5.2 `--check`: clean.
- Rojo 7.7.0 plugin build: clean.

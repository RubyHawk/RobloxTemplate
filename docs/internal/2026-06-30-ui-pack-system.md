# 2026-06-30: physical reusable UI packs

## What changed

The first UI-pack implementation used one generic slot pool and applied pack colors through `ThemeProvider`. That remained too code-dependent for the intended designer workflow.

The revised system keeps the useful data and persistence work but gives each pack its own complete physical hierarchy under `StarterGui.TemplateUI.Root.PackRoots`:

- `IncrementalPackRoot`
- `CombatPackRoot`

Each root physically owns its `StatRail`, `ProgressRail`, `ActionRail`, finite slots, layout objects, colors, strokes, corners, icons, and responsive positions. `WidgetBinder` selects one root and updates content only. `ThemeProvider` was removed.

## Preserved work

- `PackRegistry` and pure descriptor validation.
- Reactive client Store and client-only combat vitals feed.
- Profile schema v2 and sequential v1-to-v2 multi-currency migration.
- Server-authoritative multi-currency economy methods.
- Studio-only canary DataStore and deterministic DataDelve fixtures.

## Corrections

- Studio mock starting Coins now also synchronize `currencies.coins`.
- The tracked Roblox place is rebuilt with the authored pack roots.
- `servePlaceIds: []` is removed so unpublished local place ID `0` can connect to Rojo.
- Runtime no longer changes pack colors or geometry.

## Boundaries

- Do not create, clone, or destroy GUI instances during Play.
- Do not put visual styling tokens in pack descriptors.
- Keep binding names stable inside every physical root.
- Rebuild the tracked place whenever authored source geometry changes.

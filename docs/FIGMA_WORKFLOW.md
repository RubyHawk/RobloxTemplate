# Figma to Roblox UI handoff

## What connected means

Figma owns visual editing. Roblox owns runnable native instances. The checked-in bridge imports native Rojo models into editable Figma layers, preserves exact Roblox paths as metadata, and exports validated patches back to those models. It is an explicit round trip, not live synchronization.

A screenshot or flattened image is not connected UI. Connected UI remains native `ScreenGui`, `SurfaceGui`, `BillboardGui`, `Frame`, `ImageButton`, `TextLabel`, and layout instances so the existing Luau binders can keep using authored paths.

## RNG Defender

1. Run `PREPARE_FIGMA_UI.cmd`.
2. Import `build/figma/RNGDefender.roblox-ui-workspace.json` with the local Roblox UI Bridge plugin.
3. Edit mapped layers on the current Figma page.
4. Export a `roblox-ui-bridge-v1` patch.
5. Run `FIGMA_UI.cmd`.
6. Connect Rojo to `patches/rng-defender-grid-demo.project.json` and test in the permanent RNG Defender place.

The workspace manifest is `figma/workspaces/rng-defender.json`. It maps every exported root to one exact authored model and rebuilds the RNG Defender safe patch. The Figma Starter plan is sufficient because the plugin no longer creates one page per imported model.

## Preset-only workflow

The original independent-preset workflow remains supported. Import and export only:

- `TemplateUI.model.json`
- `TemplateLoading.model.json`
- `StarterSignUI.model.json`

Run `FIGMA_UI.cmd -Preset <name> -PatchPath <patch>` to apply those changes to one physically independent preset. Never replace another preset's files.

## Required binding names

The primary roots are `CurrencyHUD`, `Navigation`, `Screens`, `MoreButton`, and `MoreMenu`. Connected screens and finite data slots must retain the names already present in the authored model. Decorative Figma layer names may change because the original Roblox path remains attached as plugin metadata.

## World-space UI

`SurfaceGui` and `BillboardGui` use the same editable child GUI objects as a HUD, but their display containers behave differently in Roblox. The bridge visualizes their canvases in Figma and patches their child visuals. Roblox stays authoritative for the target part or attachment, surface face, lighting, distance, occlusion, and input setup.

Sources checked 2026-07-25:

- [Roblox in-game UI containers](https://create.roblox.com/docs/ui/in-experience-containers)
- [SurfaceGui API](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui)
- [BillboardGui API](https://create.roblox.com/docs/reference/engine/classes/BillboardGui)
- [ScreenGui API](https://create.roblox.com/docs/reference/engine/classes/ScreenGui)

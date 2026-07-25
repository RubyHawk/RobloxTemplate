# Edit Roblox UI in Figma

The repository includes a local Figma development plugin that converts authored Rojo UI models into editable Figma layers and exports validated visual patches back to those same models. Runtime Luau remains behavior-only.

The bridge supports all three Roblox display containers:

- `ScreenGui` for on-screen HUD and menus.
- `SurfaceGui` for UI rendered on a face of a 3D part.
- `BillboardGui` for UI placed in 3D that faces the camera.

Their child `Frame`, text, image, button, canvas, and layout objects use the same round-trip mapping. Roblox remains authoritative for container properties such as `Adornee`, `Face`, `PixelsPerStud`, `AlwaysOnTop`, safe-area behavior, and runtime scripts.

## One-time setup

1. Open the Figma desktop app.
2. Open **Plugins -> Development -> Import plugin from manifest**.
3. Select `figma/roblox-ui-bridge/manifest.json` from this repository.

The current editable design target is [Roblox UI Preset Library v2](https://www.figma.com/design/f5CVGUAVDYZ4rZEjgFdkar).

## RNG Defender workspace

1. Double-click `PREPARE_FIGMA_UI.cmd`.
2. In the Figma file, run **Plugins -> Development -> Roblox UI Bridge**.
3. Click **Import Rojo UI models** and choose:
   `build/figma/RNGDefender.roblox-ui-workspace.json`.
4. Edit the generated artboards.
5. Select only the artboards you want to export, or clear the selection to export all mapped artboards on the current page.
6. Click **Export Roblox UI patch**.
7. Run `FIGMA_UI.cmd` and accept the newest downloaded patch.

The RNG Defender bundle contains all 12 authored `StarterGui` roots: the main preset, loading UI, signs, rune UI, stage-owner billboards, tower-defense travel, level, and dynamic loadout HUDs, dungeon HUD, and the Studio-only Stagewright playtest HUD.

`DungeonHUD` includes the four-slot authored ability bar. It shares the same safe-area bottom-center anchor as `TowerDefenseLoadoutHUD`'s dynamic unit bar: lobby/tower-defense play shows the unit bar and its inventory/dice/upgrade controls, while an active boss fight suppresses those surfaces and shows the ability bar instead. Both roots stay separately editable in Figma; the runtime only switches their authored visibility.

The plugin places every artboard on the current Figma page. It does not create a page per model, so the workflow stays within Figma Starter's three-page limit. No Figma upgrade is required for the local import/export bridge.

The exported patch carries the RNG Defender workspace identity even when only one preset artboard is selected. `FIGMA_UI.cmd` therefore applies partial exports to the correct authored model, validates every layer path and class, rebuilds `build/RNGDefenderSafePatch.rbxlx`, and runs the permanent-place delivery guard.

## Surface and billboard sizing

- A `ScreenGui` uses a 1600x900 (16:9) editing canvas. Roblox still lays it out against the live viewport at runtime.
- A fixed-size `SurfaceGui` uses its authored `CanvasSize`.
- A `SurfaceGui` using `PixelsPerStud` derives its Figma canvas from the nearest authored part size and selected face.
- If the part or Adornee is outside the imported model, the bridge uses an 800x600 editing canvas. Roblox sizing remains unchanged until a mapped child is edited.
- A `BillboardGui` with pixel offsets uses those offsets as its artboard size. A studs-only billboard uses a stable nominal pixel scale while preserving its Roblox container size.

## Boundaries

- Figma edits supported visual properties only. Roblox owns behavior, responsive constraints, asset permissions, display-container placement, and live data.
- Existing Roblox image asset IDs are preserved as metadata. Figma shows a visible placeholder for an unavailable Roblox image; placeholder fills are never exported as Roblox backgrounds.
- Renaming mapped Figma layers is safe because the original Roblox path is stored as plugin metadata. Renaming objects in a Rojo model after importing requires a fresh import.
- The bridge rejects missing paths and class mismatches.
- The bridge never creates, clones, or destroys GUI objects at runtime. It updates authored model JSON before Rojo builds the place.

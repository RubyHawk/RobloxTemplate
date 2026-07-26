# Figma to Roblox UI handoff

## What connected means

Figma owns every visual instance in the selected workspace. Roblox owns runnable native instances and nonvisual behavior. The checked-in bridge imports native Rojo models into editable Figma layers, preserves exact Roblox paths as metadata, and exports an authoritative patch back to those models. It is an explicit round trip, not live synchronization.

Workspace import is a path-based create/update/delete sync:

- a matching path updates the existing Roblox visual;
- a new mapped Figma layer creates a native Roblox visual;
- a visual removed from Figma is removed from the authored model;
- duplicate paths stop the import instead of creating overlapping UI;
- nonvisual Luau, audio, parts, attachments, and runtime objects are preserved.

Reapplying the same export is idempotent. It never appends a second copy of the UI.

A screenshot or flattened image is not connected UI. Connected UI remains native `ScreenGui`, `SurfaceGui`, `BillboardGui`, `Frame`, `ImageButton`, `TextLabel`, and layout instances so the existing Luau binders can keep using authored paths.

## RNG Defender

1. Run `PREPARE_FIGMA_UI.cmd`.
2. Import `build/figma/RNGDefender.roblox-ui-workspace.json` with the local Roblox UI Bridge plugin.
3. Edit mapped layers on the current Figma page.
4. Export a `roblox-ui-bridge-v1` patch.
5. Run `FIGMA_UI.cmd`.
6. Connect Rojo to `patches/rng-defender-grid-demo.project.json` and test in the permanent RNG Defender place.

The workspace manifest is `figma/workspaces/rng-defender.json`. It maps all 14 presentation roots to exact authored models: every StarterGui root, both rune-circle `SurfaceGui`s, and all six enemy health-bar `BillboardGui`s. Exporting any selected RNG Defender board exports the entire workspace, then rebuilds the safe patch. An incomplete or older non-authoritative export is rejected before it can delete or mix UI.

## Preset-only workflow

The original independent-preset workflow remains supported. Import and export only:

- `TemplateUI.model.json`
- `TemplateLoading.model.json`
- `StarterSignUI.model.json`

Run `FIGMA_UI.cmd -Preset <name> -PatchPath <patch>` to apply those changes to one physically independent preset. Never replace another preset's files.

## Stable binding names

The primary paths are `CurrencyTray`, `Navigation`, `Screens`, `MoreButton`, and `MoreMenu`. Connected screens and finite data slots retain the names used by their Luau binders.

Imported layers already carry their exact class and path. For a genuinely new Figma layer, use a unique Roblox-safe name. The bridge infers `TextButton` for names ending in `Button`, `Tab`, or `Toggle`, `TextLabel` for other frames with direct text, `ImageLabel` for image-filled layers, and `Frame` otherwise. An explicit class tag such as `Confirm [TextButton]` overrides inference while the Roblox instance name remains `Confirm`.

## World-space UI

`SurfaceGui` and `BillboardGui` use the same editable child GUI objects as a HUD, but their display containers behave differently in Roblox. The bridge visualizes their canvases in Figma and patches their child visuals. Roblox stays authoritative for the target part or attachment, surface face, lighting, distance, occlusion, and input setup.

Sources checked 2026-07-25:

- [Roblox in-game UI containers](https://create.roblox.com/docs/ui/in-experience-containers)
- [SurfaceGui API](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui)
- [BillboardGui API](https://create.roblox.com/docs/reference/engine/classes/BillboardGui)
- [ScreenGui API](https://create.roblox.com/docs/reference/engine/classes/ScreenGui)

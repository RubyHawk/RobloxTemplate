# Edit Roblox UI in Figma

The repository includes a local Figma development plugin that converts authored Rojo UI models into editable Figma layers and exports one authoritative create/update/delete patch back to those same models. Runtime Luau remains behavior-only.

The bridge supports all three Roblox display containers:

- `ScreenGui` for on-screen HUD and menus.
- `SurfaceGui` for UI rendered on a face of a 3D part.
- `BillboardGui` for UI placed in 3D that faces the camera.

Their child frames, text, images, buttons, canvases, effects, and layout objects use the same round-trip mapping. Roblox remains authoritative for behavior, asset permissions, display-container placement, and runtime data.

## One-time Figma setup

1. Open the Figma desktop app.
2. Open **Plugins > Development > Import plugin from manifest**.
3. Select `figma/roblox-ui-bridge/manifest.json` from this repository.
4. Continue using that one local development plugin. After pulling bridge changes, close and reopen it; do not create a duplicate plugin.

The editable production target is [RNG Defender production export](https://www.figma.com/design/Mam5nvta1VxGfxxuplaHYM/Roblox-Template?node-id=3673-2).

## RNG Defender workspace

1. Double-click `PREPARE_FIGMA_UI.cmd` only when the production page needs a fresh repository import.
2. In the Figma file, run **Plugins > Development > Roblox UI Bridge**.
3. Keep gameplay boards on `00 — RNG Defender PRODUCTION EXPORT`.
4. Keep loose concepts on `90 — UI EXPLORATIONS / ARCHIVE (DO NOT EXPORT)`.
5. On the production page, clear the Figma selection.
6. Click **Export authoritative workspace**. The isolated page supplies the complete mapped workspace without manual board selection.
7. In stopped Studio, open **Plugins > Figma UI** and click **Import latest Figma**.
8. On the first import, allow the plugin to access `127.0.0.1`. The local bridge then applies the authoritative upsert, rebuilds the place patch, refreshes the delivery checksum, waits for Rojo, and reports whether all 14 roots match.

`FIGMA_UI.cmd` remains available as a manual fallback. It is not part of the normal edit/test loop.

The RNG Defender bundle contains 14 authored roots: 12 `StarterGui` roots, the world rune-circle surfaces, and the enemy-rig world UI.

`DungeonHUD` includes the authored ability bar. It shares the safe-area bottom-center control region with `TowerDefenseLoadoutHUD`: lobby and tower-defense play show the loadout, dice, inventory, and upgrades; an active dungeon suppresses those surfaces and shows abilities. Both remain separately editable in Figma; runtime code only switches authored visibility.

## One-click Studio delivery

The local **Figma UI** Studio plugin is a delivery companion, not another converter:

- the repository importer remains the sole create/update/delete authority;
- Rojo remains the sole transport into the open place;
- **Import latest Figma** asks a token-authenticated loopback helper to apply the newest authoritative export from Downloads;
- the helper accepts no file path from Studio and binds only to `127.0.0.1`;
- after the repository update, the plugin fetches the new generated manifest and waits for Rojo to sync;
- the Studio plugin compares the stopped place with the generated repository manifest;
- it reports missing roots and instances, class mismatches, sizing or position drift, and mismatched authored corners, strokes, gradients, and other stable visual properties;
- **Select first issue** focuses the closest affected instance, while **Print report** writes the complete result to Output.

`8_RNG_DEFENDER.cmd` installs the current local Studio plugin, creates a new private bridge token, starts the loopback helper, starts Rojo, and opens the existing experience. Keep its terminal open. Stop Play before importing or validating because runtime controllers intentionally change visibility and content.

## Surface and billboard sizing

- A `ScreenGui` uses a 1600x900 (16:9) editing canvas. Roblox still lays it out against the live viewport at runtime.
- A fixed-size `SurfaceGui` uses its authored `CanvasSize`.
- A `SurfaceGui` using `PixelsPerStud` derives its Figma canvas from the nearest authored part size and selected face.
- If the part or Adornee is outside the imported model, the bridge uses an 800x600 editing canvas.
- A `BillboardGui` with pixel offsets uses those offsets as its artboard size. A studs-only billboard uses a stable nominal pixel scale while preserving its Roblox container size.

## Boundaries

- Figma edits supported presentation properties only.
- Existing Roblox image asset IDs are preserved as metadata. Figma preview placeholders never become Roblox backgrounds.
- Renaming mapped Figma layers is safe because the original Roblox path is stored as plugin metadata. Renaming model objects after importing requires a fresh import.
- Duplicate or invalid paths are rejected before they can create overlapping UI.
- The bridge never creates, clones, or destroys GUI objects at runtime. It updates authored model JSON before Rojo builds the place.

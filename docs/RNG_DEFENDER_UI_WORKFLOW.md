# RNG Defender UI: Figma to Studio

This is the production workflow for Roblox place `128136881672145`.

## One-time asset connection

Figma stores image pixels for design previews. Roblox needs uploaded asset IDs before those pixels can render in an `ImageLabel`.

1. Run `8_RNG_DEFENDER.cmd` to open the existing place and start its guarded Rojo server.
2. Run `RNG_DEFENDER_UI_ASSETS.cmd` in a second window.
3. In Studio, open **View > Asset Manager > Images > Bulk Import**.
4. Import the requested files from `assets/icons/gvesster-basic/`.
5. After Roblox processes each image, copy its numeric asset ID.
6. Paste each ID into the waiting asset helper.
7. Stop and restart Play. Reconnect Rojo only if Studio says it is disconnected.

## Apply a Figma revision

1. Run `8_RNG_DEFENDER.cmd`. It installs the current local Studio plugin, starts the secured local import helper, starts Rojo, and opens the existing RNG Defender experience.
2. In Studio, connect **Plugins > Rojo** and keep the command window open.
3. In Figma, reopen the one local development **Roblox UI Bridge** so it uses the current checked-in files.
4. Open `00 — RNG Defender PRODUCTION EXPORT`.
5. Click **Export authoritative workspace**. The bridge downloads the complete mapped workspace; no multi-board selection is required.
6. Stop Play in Studio.
7. Open **Plugins > Figma UI** and click **Import latest Figma**. On the first request, allow access to `127.0.0.1`.
8. The one Studio action:
   - updates matching authored paths;
   - creates new mapped presentation paths;
   - removes mapped presentation paths deleted in Figma;
   - preserves nonvisual Lua and world/runtime objects;
   - generates the source/model checksum manifest;
   - rebuilds `build/RNGDefenderSafePatch.rbxlx`;
   - waits for Rojo to sync the authored hierarchy;
   - verifies all mapped roots and stable visual properties in Studio.
9. Wait for **MATCHED** in the plugin, then start a fresh Play session and test runtime behavior.

Do not manually copy GUI instances into StarterGui. If a visual is missing, fix or map it in Figma and export again.

The repository importer is the only correction and upsert layer. The Studio plugin triggers that importer and validates its result; it does not directly rewrite the place or compete with Rojo.

If the local button cannot be used, close Studio and run `FIGMA_UI.cmd` as the manual fallback, then restart `8_RNG_DEFENDER.cmd`.

## Expected smoke test

1. In the lobby, persistent actions form the middle-left icon cluster without overlapping.
2. Core inventory, roll, and upgrade controls remain available outside dungeons.
3. The active configured currency appears.
4. Enter a tower platform and confirm the level selector remains at the bottom edge.
5. The bottom-center action row appears above the dynamic unit slots.
6. Roll, inventory, upgrades, selection, placement, auto-place, wave start, and reset still call the authoritative runtime actions.
7. Enter the boss room. Tower controls hide and the ability bar owns the gameplay control area.

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

1. Stop Play and close Studio.
2. In Figma, reopen the one local development **Roblox UI Bridge** so it uses the current checked-in files.
3. Open `00 — RNG Defender PRODUCTION EXPORT`.
4. Clear the Figma selection, then click **Export authoritative workspace**.
5. Save the download with a `.figma-patch.json` or `.figma-patch` suffix.
6. Stop `8_RNG_DEFENDER.cmd` if it is still serving.
7. Run `FIGMA_UI.cmd` and choose the newest export. It:
   - updates matching authored paths;
   - creates new mapped presentation paths;
   - removes mapped presentation paths deleted in Figma;
   - preserves nonvisual Lua and world/runtime objects;
   - generates the source/model checksum manifest;
   - rebuilds `build/RNGDefenderSafePatch.rbxlx`;
   - refreshes the local read-only **Figma UI** Studio plugin.
8. Run `8_RNG_DEFENDER.cmd`, connect Rojo, and wait for the sync to finish.
9. Before Play, open **Plugins > Figma UI** and click **Refresh**. A matched report confirms that the authored hierarchy and stable presentation properties arrived.
10. Start a fresh Play session and test runtime behavior.

Do not manually copy GUI instances into StarterGui. If a visual is missing, fix or map it in Figma and export again.

The repository importer is the only correction and upsert layer. The Studio plugin is validation-only, so it cannot compete with Rojo or the authoritative model files.

## Expected smoke test

1. In the lobby, persistent actions form the middle-left icon cluster without overlapping.
2. Core inventory, roll, and upgrade controls remain available outside dungeons.
3. The active configured currency appears.
4. Enter a tower platform and confirm the level selector remains at the bottom edge.
5. The bottom-center action row appears above the dynamic unit slots.
6. Roll, inventory, upgrades, selection, placement, auto-place, wave start, and reset still call the authoritative runtime actions.
7. Enter the boss room. Tower controls hide and the ability bar owns the gameplay control area.

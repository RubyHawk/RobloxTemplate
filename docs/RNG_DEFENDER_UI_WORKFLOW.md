# RNG Defender UI: Figma to Studio

This is the production workflow for Roblox place `128136881672145`.

## One-time asset connection

Figma stores image pixels for design previews. Roblox needs uploaded asset IDs
before those pixels can render in an `ImageLabel`.

1. Run `8_RNG_DEFENDER.cmd` to open the existing place and start its guarded
   Rojo server.
2. Run `RNG_DEFENDER_UI_ASSETS.cmd` in a second window.
3. In Studio, open **View > Asset Manager > Images > Bulk Import**.
4. Import:
   - `assets/icons/gvesster-basic/roll_dice.png`
   - `assets/icons/gvesster-basic/talent_upgrade.png`
5. After Roblox finishes processing each image, copy its numeric asset ID.
6. Paste each ID into the waiting asset helper.
7. Stop and restart Play. Rojo synchronizes the regenerated
   `src/shared/IconAssets.luau`; reconnect Rojo only if Studio says it is
   disconnected.

Inventory already uses the connected `bag` role. The helper reports when both
new tower-defense roles are ready.

## Apply a Figma revision

1. Stop Play in Studio.
2. In Figma, reload the local development plugin so it uses the current
   `figma/roblox-ui-bridge/code.js`.
3. Run **Roblox UI Bridge** on the `Roblox • TemplateUI` page.
4. Select any production RNG Defender board and choose the authoritative
   workspace export. The plugin exports all 14 mapped presentation roots.
5. Save the download with a `.figma-patch.json` or `.figma-patch` suffix.
6. Stop `8_RNG_DEFENDER.cmd` if it is still serving.
7. Run `FIGMA_UI.cmd` and choose the newest export. This performs an
   authoritative upsert:
   - matching Figma paths update;
   - new mapped Figma paths create authored Roblox visuals;
   - visuals removed from Figma are removed from the authored model;
   - nonvisual Lua and world/runtime objects remain intact.
8. Run `8_RNG_DEFENDER.cmd` again, connect Rojo, and start a fresh Play session.

Do not manually copy GUI instances into StarterGui after the import. If a
visual is missing, fix or map it in Figma and export again.

## Expected smoke test

1. In the lobby, the five persistent actions form the middle-left 3+2 icon
   cluster without overlapping.
2. Enter a tower platform. Lobby navigation hides.
3. The level selector stays on the bottom edge and does not jump to the top.
4. The bottom-center action row shows Inventory, a larger raised Roll icon, and
   Upgrades above the dynamic unit slots.
5. Roll, Inventory, Upgrades, unit selection, manual placement, auto-place,
   wave start, and reset still call the existing authoritative runtime actions.
6. Enter the boss room. Tower controls hide and the ability bar owns the
   gameplay control area.

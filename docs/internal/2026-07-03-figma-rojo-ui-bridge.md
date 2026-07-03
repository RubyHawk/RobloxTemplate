# Figma ↔ Rojo visual workflow — 2026-07-03

## Decision

The reusable UI now has an explicit local round trip:

1. `figma/roblox-ui-bridge` imports an authored Rojo `.model.json` as editable Figma artboards.
2. Stable Roblox object paths and original UDim2 scale values are stored as Figma shared plugin metadata.
3. Figma exports a `roblox-ui-bridge-v1` patch containing supported visual and layout properties.
4. `FIGMA_UI.cmd` validates paths and classes, updates only the chosen preset, and rebuilds the playable export with `-NoStudio`.

This is intentionally not described as live or automatic sync. The checked-in Rojo model remains the reviewable source that ships to Roblox, while Figma is the visual editing surface.

## Safety boundaries

- The bridge does not execute or import scripts.
- It cannot create runtime GUI objects.
- It rejects missing object paths, class mismatches, and patches with no entries for the selected model.
- It preserves Roblox image asset IDs as metadata; Figma does not republish or grant access to those assets.
- Each preset has an independent model, so editing Incremental cannot restyle RPG.

## Verification

- Plugin and importer JavaScript syntax checks pass.
- Both preset models expose 1,536 unique named bridge paths.
- The in-memory patch application self-test passes.
- The full repository check passes without opening Roblox Studio.

## Hosted Figma file

- [Roblox UI Preset Library](https://www.figma.com/design/TCKb7NWBeH1wSf6eLDARhn)
- Codex created the file successfully, but the connected Figma Starter plan reached its MCP tool-call quota before canvas population. The local development plugin is therefore the working no-token bridge.

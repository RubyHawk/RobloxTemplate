# Figma UI Studio delivery companion

Date checked: 2026-07-27

Official references:

- Roblox Studio plugins: https://create.roblox.com/docs/studio/plugins
- Roblox Studio widgets: https://create.roblox.com/docs/studio/build-studio-widgets
- Roblox UI overview: https://create.roblox.com/docs/ui
- Roblox ChangeHistoryService undo reference: https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService/Undo
- Figma development plugins: https://help.figma.com/hc/en-us/articles/360042786733-Create-a-plugin-for-development
- Figma plugin management: https://help.figma.com/hc/en-us/articles/360042293714-Manage-plugins-as-a-developer
- Figma plugin manifest: https://developers.figma.com/docs/plugins/manifest/

## Decision

The pipeline has one authority per responsibility:

1. Figma authors presentation on `00 — RNG Defender PRODUCTION EXPORT`.
2. The checked-in bridge exports an authoritative patch.
3. `scripts/figma-ui.ps1` is the only create/update/delete converter for authored Roblox model JSON.
4. Rojo is the only delivery mechanism into the open Roblox place.
5. `FigmaUiBridge.rbxm` is a read-only Studio validator. It does not import, mutate, clone, destroy, save, or publish place UI.

The plugin uses `Plugin:CreateToolbar` and `Plugin:CreateDockWidgetPluginGuiAsync` for a local docked report. Because it is read-only, it does not open a ChangeHistoryService recording. Any future mutation feature must be explicit, undo-safe, and must not become a competing importer.

## Validation contract

`scripts/generate-figma-studio-manifest.mjs` reads the final authored model files after an upsert. It generates a repository-model checksum and expected root/path/class/property data for stable presentation properties, including typography, geometry, and direct effect children. Runtime-bound text and image content are intentionally excluded.

The Studio report is valid only while Play is stopped. Runtime controllers are allowed to change visibility, text, images, and other live state during a session.

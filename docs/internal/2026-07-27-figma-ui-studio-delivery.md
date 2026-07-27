# Figma UI Studio delivery companion

Date checked: 2026-07-27

Official references:

- Roblox Studio plugins: https://create.roblox.com/docs/studio/plugins
- Roblox Studio widgets: https://create.roblox.com/docs/studio/build-studio-widgets
- Roblox UI overview: https://create.roblox.com/docs/ui
- Roblox ChangeHistoryService undo reference: https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService/Undo
- Roblox HTTP requests and localhost plugin access: https://create.roblox.com/docs/cloud-services/http-service
- Roblox HttpService API: https://create.roblox.com/docs/reference/engine/classes/HttpService
- Figma development plugins: https://help.figma.com/hc/en-us/articles/360042786733-Create-a-plugin-for-development
- Figma plugin management: https://help.figma.com/hc/en-us/articles/360042293714-Manage-plugins-as-a-developer
- Figma plugin manifest: https://developers.figma.com/docs/plugins/manifest/

## Decision

The pipeline has one authority per responsibility:

1. Figma authors presentation on `00 — RNG Defender PRODUCTION EXPORT`.
2. The checked-in bridge exports an authoritative patch.
3. `scripts/figma-ui.ps1` is the only create/update/delete converter for authored Roblox model JSON.
4. Rojo is the only delivery mechanism into the open Roblox place.
5. `FigmaUiBridge.rbxm` requests an import from a loopback-only repository helper, then validates the Rojo-synced result. It does not convert a patch, mutate the DataModel, clone or destroy gameplay UI, save, or publish.

The plugin uses `Plugin:CreateToolbar` and `Plugin:CreateDockWidgetPluginGuiAsync` for a local docked report. Roblox documents that Studio plugins can communicate with software on the same computer through `localhost` or `127.0.0.1`; Studio presents a first-use permission prompt. `8_RNG_DEFENDER.cmd` creates a fresh per-launch token, embeds it in the locally built plugin, and starts a helper bound only to the configured loopback address. The helper does not accept client-selected paths: it finds and validates the newest authoritative workspace export itself.

Because the Studio plugin does not mutate the DataModel, it does not open a ChangeHistoryService recording. The existing repository upserter remains the only converter, and Rojo remains the only transport. Any future direct DataModel mutation must be explicit, undo-safe, and must not become a competing importer.

## Validation contract

`scripts/generate-figma-studio-manifest.mjs` reads the final authored model files after an upsert. It generates a repository-model checksum and expected root/path/class/property data for stable presentation properties, including typography, geometry, and direct effect children. Runtime-bound text and image content are intentionally excluded.

The Studio report is valid only while Play is stopped. Runtime controllers are allowed to change visibility, text, images, and other live state during a session.

## One-button boundary

- Figma button: export the complete isolated production workspace.
- Studio button: authenticate to the local helper, apply that export through `scripts/figma-ui.ps1`, fetch the regenerated full manifest, wait for Rojo, and validate.
- Manual fallback: `FIGMA_UI.cmd`.

The helper runs only while the guarded RNG Defender launcher is running. It has no publishing route and cannot target arbitrary files supplied by a Studio request.

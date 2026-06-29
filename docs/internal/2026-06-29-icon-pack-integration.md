# 2026-06-29: licensed icon pack integration

## Decision

The connected UI now has Studio-authored image slots and a single configuration block for the licensed Gvesster Basic icon pack. We selected one consistent high-resolution outlined icon for each of 25 semantic purposes from the archive's 2,044 size/color variants.

Local PNG paths cannot render in a live Roblox experience. Asset IDs remain empty until the experience owner publishes an experience and uploads the selected images. Empty IDs keep readable authored fallbacks instead of showing broken images.

## Official documentation checked on 2026-06-29

- Roblox assets overview: https://create.roblox.com/docs/projects/assets
- Roblox Asset Manager: https://create.roblox.com/docs/projects/assets/manager
- Roblox Studio importer: https://create.roblox.com/docs/studio/importer
- Roblox Open Cloud assets reference: https://create.roblox.com/docs/cloud/reference/features/assets

The documented Studio workflow supports importing multiple images and subjects uploaded assets to moderation. Open Cloud uploads require authenticated creator credentials, which are intentionally not stored in this repository.

## License and provenance

- `Ui Pack Version 5 By Zxgly.rar` is unrelated and remains a visual showroom reference.
- Icon archive: `Free Icon Pack v3.1 (Basic).zip`, supplied locally by the project owner.
- Author: `@gvesster`.
- Repository copy of license: `assets/icons/gvesster-basic/LICENSE.txt`.
- Commercial, client, personal, and non-commercial use are permitted; resale, claiming authorship, and repackaging as another asset pack are forbidden.

## Implementation boundary

- `TemplateConfig.icons` owns all uploaded IDs.
- `IconCatalog` maps semantic UI purposes to source filenames and readable fallbacks.
- `TemplateUI.model.json` owns visual image slots; runtime Luau only binds configured content and live data.
- Inventory item definitions use the same icon catalog.
- No creator credentials, live asset uploads, or experience-specific IDs were added.

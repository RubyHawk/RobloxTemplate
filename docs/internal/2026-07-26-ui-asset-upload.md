# Roblox UI asset upload check — 2026-07-26

Reviewed for the RNG Defender Figma-to-Roblox UI workflow.

Official references:

- [Assets overview](https://create.roblox.com/docs/projects/assets)
- [Asset Manager](https://create.roblox.com/docs/projects/assets/manager)
- [Open Cloud asset usage](https://create.roblox.com/docs/cloud/guides/usage-assets)
- [Assets API feature reference](https://create.roblox.com/docs/cloud/reference/features/assets)
- [Open Cloud API keys](https://create.roblox.com/docs/cloud/auth/api-keys)
- [Open Cloud scopes](https://create.roblox.com/docs/cloud/reference/scopes)

## Repository workflow

Figma image fills are design previews, not Roblox content IDs. Exported Roblox
`ImageLabel` instances receive their images from `IconCatalog`, backed by
`assets/icons/icon-manifest.json`.

For the current tower-defense loadout controls:

- `bag` is already connected for Inventory.
- `rollDice` requires `assets/icons/gvesster-basic/roll_dice.png`.
- `talentUpgrade` requires `assets/icons/gvesster-basic/talent_upgrade.png`.

Run `RNG_DEFENDER_UI_ASSETS.cmd`, bulk-import the two pending PNGs through
Studio's Asset Manager, and paste their numeric asset IDs. The helper updates
the manifest and regenerates `src/shared/IconAssets.luau`; secrets and API keys
are never stored in the repository.

The checked Roblox guidance permits PNG image uploads through Asset Manager.
Open Cloud can automate uploads, but requires an owner-scoped API key with
asset read/write permissions. This repository deliberately keeps the default
workflow interactive so no creator credential is committed or requested by a
build script.

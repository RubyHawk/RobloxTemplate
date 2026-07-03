# Shared icon assets — 2026-07-03

## Sources reviewed

- [Roblox assets overview](https://create.roblox.com/docs/projects/assets)
- [Roblox Asset Manager](https://create.roblox.com/docs/projects/assets/manager)
- [Roblox asset privacy](https://create.roblox.com/docs/projects/assets/privacy)
- `build/icon-pack-extract/Free Icon Pack v3.1 (Basic)/License.txt`

Roblox documents that local project files must be imported into cloud asset management before published experiences can display them. Images, decals, and meshes can be Restricted or Open Use; Restricted assets require creator/group and experience permissions. Asset Manager supports bulk import, and `rbxgameasset://Images/<Name>` can reference an image imported into the current experience by its friendly name.

## Local audit

- `build/` held 4,142 PNGs: screenshots plus duplicate `icon-inspect` and `icon-pack-extract` trees.
- One actual pack extraction contains 2,044 PNG variants and is only 5.63 MB, but checking in every variant would create more than two thousand binary files with no runtime benefit.
- The private repository already tracks a curated 28-PNG selection (25 connected roles plus three provenance files) and the pack license.
- The license allows commercial projects, client work, editing in personal projects, and optional credit. It forbids claiming/reselling the pack. The repository therefore shares the curated project selection, not a repackaged full library.

## Decision

Keep the full archive/extraction ignored as a developer convenience. Track selected source PNGs, SHA-256 hashes, cloud mapping, and upload state in `assets/icons/icon-manifest.json`. Generate `IconAssets.luau` deterministically and fail checks when a PNG changes without a matching manifest update.

Cloud ownership remains deliberately `pending` until the team chooses user or group ownership. The existing public demo IDs continue rendering in the meantime.

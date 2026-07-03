# Shared icon library

`build/` stays ignored. It contains generated files, screenshots, and two duplicate extractions of the 2,044-file licensed icon pack. Committing that whole folder would make reviews noisy and would still not make local PNG paths render in Roblox.

The shared source of truth is instead:

- `assets/icons/gvesster-basic/` — the curated PNGs both developers can edit and commit;
- `assets/icons/icon-manifest.json` — source hash, Roblox content, and upload state for every connected UI role;
- `src/shared/IconAssets.luau` — generated runtime mapping; never edit it by hand;
- `ICON_LIBRARY.cmd` — the non-programmer manager for replacing, disabling, and mapping icons.

## Replace an icon

1. Pull `main` before starting.
2. Double-click `ICON_LIBRARY.cmd`.
3. Choose **Replace an existing UI role** and select any PNG from the local full pack or another licensed source.
4. The manager copies it to the stable shared filename, records its SHA-256 hash, clears the old cloud mapping, and marks it `pending-upload`.
5. Commit the PNG, manifest, and generated Luau together.

Removing an icon means choosing **Disable an icon**. The authored text/Roblox fallback remains visible. Adding a brand-new logical role—not merely replacing artwork—still requires a programmer to add the role to `IconCatalog` and connect it to an authored `ImageLabel`.

## Make it render in Roblox

Roblox experiences cannot render a PNG directly from Git or a Windows path. An authorized developer must upload the selected PNG through **View → Asset Manager → Images**. Roblox moderates imported assets before players can see them.

After upload, open `ICON_LIBRARY.cmd` and choose **Set the Roblox image ID/name**. It accepts:

- a numeric asset ID;
- `rbxassetid://<ID>` for a cloud image shared with the experience;
- `rbxgameasset://Images/<Name>` for an image imported into that specific experience through Asset Manager.

`rbxgameasset` names are convenient in the permanent sandbox, but every future released experience must import the same stable filenames. Group-owned asset IDs with explicit experience permission are usually cleaner when several games will reuse the pack.

## Two-developer workflow

- Keep the full licensed archive local and ignored. The private repository shares only the curated project selection and its license.
- One developer owns each upload batch. Do not both upload the same changed PNG; that creates duplicate cloud assets and ambiguous IDs.
- Commit the source PNG, `icon-manifest.json`, and `IconAssets.luau` in one commit. The other developer pulls that commit before opening Studio.
- Never delete a Roblox cloud asset immediately when removing it from the UI. Old published versions may still reference it. Disable it in the manifest first and retire the cloud asset only after every published place has moved away.
- If two people edit the same manifest role concurrently, keep the source/hash/content from the version that was actually uploaded. Run `3_CHECK.cmd`; a source/hash mismatch fails loudly.
- Moderation and permissions are cloud state and cannot be proven by Git. Test the uploaded image in the shared sandbox before publishing a game.

## Ownership decision still required

`icon-manifest.json` currently leaves `cloudOwner` as `pending`. Before uploading the final replacement set, choose whether assets are owned by one user or a Roblox group/community. A group where both developers have Edit access is recommended. The current demo IDs remain active until this is decided, so the UI does not suddenly go blank.

Official Roblox documentation checked 2026-07-03:

- [Assets overview](https://create.roblox.com/docs/projects/assets)
- [Asset Manager](https://create.roblox.com/docs/projects/assets/manager)
- [Asset privacy and permissions](https://create.roblox.com/docs/projects/assets/privacy)

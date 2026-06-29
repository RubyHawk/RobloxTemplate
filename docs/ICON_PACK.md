# Add the included icons to Roblox

The template is already wired for all 25 selected icons. Roblox cannot display PNG files from your computer, so the experience owner must upload them once.

1. Publish the experience in Roblox Studio.
2. Open **View > Asset Manager**, choose **Images**, then bulk import the PNG files from `assets/icons/gvesster-basic/`. Skip `chat.png`, `gift.png`, and `stats.png`; they are older duplicates.
3. After Roblox finishes moderation, copy each image asset ID into the matching entry under `icons` in `src/shared/TemplateConfig.luau`.
4. Run `3_CHECK.cmd`, then open the map with `START_HERE.cmd`.

You may paste either a number such as `123456789` or a complete `rbxassetid://123456789` value. Empty entries deliberately keep the safe Studio-authored letter or bundled Roblox fallback.

The exact filename-to-key mapping is in `assets/icons/gvesster-basic/README.md`. The connected UI uses the pack in navigation, currency, menus, item cards, daily rewards, profiles, search, offline earnings, Premium, likes, codes, verification, notifications, and leaderboards.

Roblox documentation:

- [Assets overview](https://create.roblox.com/docs/projects/assets)
- [Asset Manager](https://create.roblox.com/docs/projects/assets/manager)
- [Studio 3D Importer and image importing](https://create.roblox.com/docs/studio/importer)

Do not upload the archive's thousands of duplicate size/color variants. The selected high-resolution files produce a more consistent UI and avoid unnecessary moderation work.

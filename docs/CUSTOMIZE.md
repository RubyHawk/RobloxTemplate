# Simple customization

Most values live in [`src/shared/TemplateConfig.luau`](../src/shared/TemplateConfig.luau).

## Change colors

For visual editing, open `StarterGui → TemplateUI → Root` in Studio. The HUD, bottom navigation dock, screen shell, toast, and reusable component templates are ordinary editable GUI objects. Change colors, fonts, sizes, corners, strokes, and positions in Properties, then press Ctrl+S.

The loading screen and playable earning-pad sign are also ordinary editable objects under `StarterGui` as `TemplateLoading` and `StarterSignUI`. Both are disabled while editing so they do not cover the showroom. Select one, temporarily enable it, edit its children in Properties, then disable it again before saving.

Inventory cards, store cards, reward tiles, profile controls, and leaderboard rows are permanent objects under `TemplateUI → Root → Screens`. Expand the screen you want and edit its real objects directly in Studio. Runtime Luau never creates or clones GUI objects.

`src/shared/Theme.luau` contains behavior colors such as hover states. A programmer can change those when creating a full theme branch.

## Change daily rewards

Find `rewards.daily` in `TemplateConfig.luau`. The seven numbers are the Coins awarded for days 1–7.

## Change bonuses

Find `economy` in `TemplateConfig.luau`:

- `friendBonusPerFriend = 0.10` means +10% per friend in the server.
- `friendBonusCap = 0.50` limits it to +50%.
- `premiumBonus = 0.10` means +10% for Roblox Premium.
- Offline caps default to 4 free hours and 12 hours with the pass.

## Add an inventory item

Copy one item inside [`src/shared/Catalogs.luau`](../src/shared/Catalogs.luau), give it a unique permanent ID, and change its name, description, price, and effect.

## Add Roblox IDs later

Keep every ID at `0` or `""` until the corresponding asset exists. Then follow [`PLATFORM_SETUP.md`](PLATFORM_SETUP.md) and fill the `identity`, `products`, `notifications`, and `audio` sections.

For the included UI and inventory art, follow [`ICON_PACK.md`](ICON_PACK.md). All selected icons share the `TemplateConfig.icons` block and automatically replace their readable fallbacks after IDs are configured.

After any change, double-click `3_CHECK.cmd`.

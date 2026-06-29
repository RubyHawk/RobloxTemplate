# Simple customization

Most values live in [`src/shared/TemplateConfig.luau`](../src/shared/TemplateConfig.luau).

## Change colors

For visual editing, open `StarterGui → TemplateUI → Root` in Studio. The HUD, bottom navigation dock, screen shell, toast, and reusable component templates are ordinary editable GUI objects. Change colors, fonts, sizes, corners, strokes, and positions in Properties, then press Ctrl+S.

Inventory and store cards clone `ComponentTemplates → ItemCardTemplate`. Daily rewards clone `RewardTileTemplate`. Edit those templates once instead of restyling every screen in Luau.

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

For inventory art, upload an icon through Roblox and put its asset ID in the matching catalog item's `icon` field. The card automatically hides its text fallback when a real icon is configured.

After any change, double-click `3_CHECK.cmd`.

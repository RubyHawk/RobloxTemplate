# Simple customization

Most values live in [`src/shared/TemplateConfig.luau`](../src/shared/TemplateConfig.luau).

## Change colors

Edit [`src/shared/Theme.luau`](../src/shared/Theme.luau). Colors use RGB values such as `Color3.fromRGB(80, 135, 255)`.

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

After any change, double-click `3_CHECK.cmd`.

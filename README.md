# Roblox Template — Start Here

You do not need to understand Git, Rojo, Wally, or the notification worker to open this project.

## Open the template for the first time

1. Double-click **`1_SETUP.cmd`** and wait for `SETUP COMPLETE`.
2. Double-click **`2_START.cmd`**. Keep the black window open.
3. Roblox Studio opens. Select **Plugins → Rojo → Connect**.
4. Press **Play** in Studio.

You should see a Coins HUD and buttons for the inventory, store, rewards, profile, codes, leaderboards, feedback, community, and settings.

If anything is red or does not open, double-click **`3_CHECK.cmd`**. It explains what is missing in plain language.

## Which branch should I use?

- **`playable-starter`** is the easiest starting point. It includes the complete template plus a blue earning pad that proves the economy works.
- **`template`** contains only the reusable UI and systems. Put improvements that every future map should receive here.
- Ignore **`main`**; it is the untouched original branch.

The GitHub repository opens on `playable-starter` by default, so beginners do not need to switch branches.

## What already works?

- Modern responsive HUD and menu screens
- Mock player saving in Studio, Coins, inventory, potions, daily and offline rewards
- Store foundations, Premium and friend bonuses, profiles, feedback, codes, and leaderboards
- Loading screen, AFK rollover, settings, announcement messages, and empty audio hooks
- Secure server validation and automated checks

Features that need your own Roblox IDs—real purchases, community verification, audio, published DataStores, and notifications—stay visibly disabled until you configure them. Discord and guilds are intentionally scaffolded but off.

## Is it current for 2026?

Yes. The tool versions were rechecked against their latest stable releases on 2026-06-27. The UI uses Roblox’s current token-based styling system, chat uses native cross-server `TextChatService`, and the checklist uses Studio’s Device Emulator for phones.

## Where should I go next?

- [Your first five minutes](docs/FIRST_STEPS.md)
- [What each feature does](docs/FEATURES.md)
- [Common problems and exact fixes](docs/TROUBLESHOOTING.md)
- [Change colors, rewards, IDs, and game values](docs/CUSTOMIZE.md)
- [Technical setup and branch workflow](docs/SETUP.md)

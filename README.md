# Roblox Template — Start Here

You do not need to understand Git, Rojo, Wally, or the notification worker to open this project.

## Open the project

1. Double-click **`START_HERE.cmd`**.
2. Choose **Open Playable Starter** or **Open Template**.
3. Keep the black window open when Roblox Studio starts.
4. In Studio, select **Plugins → Rojo → Connect**, then press **Play**.

You should see a Coins HUD and buttons for the inventory, store, rewards, profile, codes, leaderboards, feedback, community, and settings.

The launcher installs anything missing, switches to the chosen branch, rebuilds the correct place, and replaces any old Rojo session. Its **Repair setup** and **Run project checks** buttons explain problems in plain language.

The numbered CMD files remain available as manual shortcuts, but your non-programmer coworker only needs `START_HERE.cmd`.

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

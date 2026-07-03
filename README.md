# Roblox Template — Start Here

You do not need to understand Git, Rojo, Wally, or the notification worker to open this project.

## Open the project

1. Double-click **`START_HERE.cmd`**.
2. Choose **Open Shared Test Experience**, **Open Template**, or **Design a Game Preset**.
3. Keep the black window open when Roblox Studio starts.
4. In Studio, select **Plugins → Rojo → Connect**.
5. Edit UI objects under **StarterGui**, press **Ctrl+S**, then press **Play**.

You should see a Coins HUD and buttons for the inventory, store, rewards, profile, codes, leaderboards, feedback, community, and settings.

The launcher installs anything missing and replaces any old Rojo session. The shared test option rebuilds your selected preset and opens the same permanent cloud sandbox every time; it never creates another Roblox experience. Its **Repair setup** and **Run project checks** buttons explain problems in plain language.

The numbered CMD files remain available as manual shortcuts. `SANDBOX.cmd` opens the permanent test experience directly, but your non-programmer coworker normally only needs `START_HERE.cmd`.

Use `ICON_LIBRARY.cmd` to swap or disable shared UI icons and record their Roblox image mapping. The selected PNGs and manifest are committed so both developers see the same artwork; the large duplicate extraction under `build/` remains local.

**Design a Game Preset** selects an independent Incremental or RPG UI package, one-to-five server-backed currencies, and shared systems, then loads it into the permanent sandbox. See [`docs/GAME_DESIGNER.md`](docs/GAME_DESIGNER.md).

Figma can now be the visual editor through the checked-in **Roblox UI Bridge**. After its one-time Figma plugin setup, edit the imported layers, export a patch, and double-click **`FIGMA_UI.cmd`** to update and rebuild only the chosen preset. See [`docs/FIGMA_UI.md`](docs/FIGMA_UI.md).

## Which branch should I use?

Use **`main`**. The template workbench, independent UI presets, shared sandbox, and reusable systems all live together. **Template** and **Shared Test Experience** are launcher modes now, not permanent Git branches. Temporary feature branches may still be used while a programmer is actively changing something.

## What already works?

- Modern responsive HUD and menu screens built from Studio-editable templates
- Mock player saving in Studio, Coins, inventory, potions, daily and offline rewards
- Store foundations, Premium and friend bonuses, profiles, feedback, codes, and leaderboards
- Loading screen, AFK rollover, settings, announcement messages, and empty audio hooks
- Secure server validation and automated checks

Features that need your own Roblox IDs—real purchases, community verification, audio, published DataStores, and notifications—stay visibly disabled until you configure them. Discord and guilds are intentionally scaffolded but off.

## Is it current for 2026?

Yes. The tool versions and current official Roblox chat/UI documentation were rechecked on 2026-06-27. Chat uses native `TextChatService`; system announcements use `RBXSystem`, and a regression check rejects legacy chat APIs.

## Where should I go next?

- [Your first five minutes](docs/FIRST_STEPS.md)
- [What each feature does](docs/FEATURES.md)
- [Common problems and exact fixes](docs/TROUBLESHOOTING.md)
- [Change colors, rewards, IDs, and game values](docs/CUSTOMIZE.md)
- [Edit the UI showroom without code](docs/UI_SHOWROOM.md)
- [Edit a preset in Figma](docs/FIGMA_UI.md)
- [Technical setup and branch workflow](docs/SETUP.md)

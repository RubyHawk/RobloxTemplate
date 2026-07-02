# Game Preset Designer

Open `START_HERE.cmd` and choose **Design a Game Preset**, or double-click `5_GAME_DESIGNER.cmd` directly.

The Designer lets a non-programmer choose:

- the independent **Incremental / Simulator** or **Fantasy RPG** UI pack;
- one to five currencies, including names, symbols, starting balances, and colors;
- store, inventory, daily rewards, offline earnings, profiles, leaderboards, codes, feedback, and community verification.

Click **Build and open playable test** to create and open a complete `.rbxlx` test experience. Click **Build drag-and-drop UI package** to create only the `.rbxm` file. Generated files appear under `exports/`.

## Editing safely with UI Plus

The two presets are complete physical copies. They do not contain linked GUI instances:

- `StarterGui > IncrementalPresetUI`
- `StarterGui > RPGPresetUI`

Their loading screens and starter signs are separate too. Enable only the preset you are editing, use UI Plus or normal Studio tools, and save under a distinct filename. Moving an RPG button cannot move the Incremental button because they are different instances backed by different model files.

When editing a generated experience, save or publish that generated place. To make another reusable variation, right-click its `TemplateUI` in Explorer and choose **Save to File**, giving the `.rbxm` a new name. Never overwrite the other preset's package.

## What is genuinely configurable

Each enabled currency has a server-owned saved balance. The profile schema migrates older `coins` data into the selected primary currency. The HUD contains five permanent editable slots and only displays the configured number. Disabled systems are hidden on the client and rejected by server remotes.

Advanced Roblox IDs, reward amounts, product definitions, audio, and platform integrations remain in `src/shared/TemplateConfig.luau`; they are intentionally not guessed by the Designer.

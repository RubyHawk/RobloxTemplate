# Game Preset Designer

Open `START_HERE.cmd` and choose **Design a Game Preset**, or double-click `5_GAME_DESIGNER.cmd` directly.

The Designer automatically lists every complete folder under `src/ui/presets/`, then lets a non-programmer choose:

- an independent UI pack, including the bundled **Incremental / Simulator** and **Fantasy RPG** packs;
- one to five currencies, including live Roblox asset-image previews, fallback symbols, starting balances, and colors;
- store, inventory, daily rewards, offline earnings, profiles, leaderboards, codes, feedback, and community verification.

Click **Build and open shared sandbox** to rebuild the selected configuration and open the existing permanent Roblox test experience. Click **Build drag-and-drop UI package** to create only the `.rbxm` file. Generated backup files still appear under `exports/`.

The sandbox already has one fixed universe and place. Use **File > Publish to Roblox** to update that same place; do not use **Publish As**. Profiles, currencies, inventory, rewards, feedback, public profiles, and leaderboards use Roblox services automatically. Each preset receives a separate DataStore namespace inside the shared universe.

## Editing safely with UI Plus

The two presets are complete physical copies. They do not contain linked GUI instances:

- `StarterGui > IncrementalPresetUI`
- `StarterGui > RPGPresetUI`

Their loading screens and starter signs are separate too. Enable only the preset you are editing, use UI Plus or normal Studio tools, and save under a distinct filename. Moving an RPG button cannot move the Incremental button because they are different instances backed by different model files.

When editing a generated experience, save or publish that generated place. To make another reusable variation, right-click its `TemplateUI` in Explorer and choose **Save to File**, giving the `.rbxm` a new name. Never overwrite the other preset's package.

## What is genuinely configurable

Each enabled currency has a server-owned saved balance. Paste the numeric value from Roblox's **Copy Asset ID** action into its asset field; the preview beside it confirms what Roblox resolves. The generated game renders that ID in the pre-authored HUD ImageLabel and automatically uses the symbol when the field is blank. The profile schema migrates older `coins` data into the selected primary currency. The HUD contains five permanent editable slots and only displays the configured number. Disabled systems are hidden on the client and rejected by server remotes.

Starting balances apply when a profile first sees a currency. Existing balances are never re-granted. In the generated starter, the blue pad proves the primary currency and a teal pad proves the second configured currency; the teal pad hides for one-currency games.

The generated `DesignerConfig.luau` is parsed and shape-checked before Rojo builds, so broken symbols or malformed recipes fail immediately instead of opening a dead place.

Product, audio, notification, experience, and other platform IDs remain in `src/shared/TemplateConfig.luau`; only the safe visual currency asset IDs are configured in the Designer.

## Figma and Studio

Figma is the visual design source; Roblox still needs native `StarterGui` instances to run. Roblox does not provide a first-party Figma-to-Studio GUI sync. Follow [the Figma handoff](FIGMA_WORKFLOW.md): export a finished Figma pack into its own preset folder, verify its required layer names, and then select it in the Game Designer. Runtime binders only connect behavior to those authored instances.

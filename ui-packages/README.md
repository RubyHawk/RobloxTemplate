# Reusable UI packages

`UI_BrightSimulator` is the first visual package. It contains the complete authored `TemplateUI` ScreenGui:

Its **Candy Pop** identity is intentionally different from the original template: purple/cyan panels, gold accents, a top-right currency HUD, and a deep-purple navigation dock.

- Coins and boost HUD
- Bottom navigation and quick menu
- Inventory with 12 permanent slots
- Store with 8 permanent cards
- Seven-day rewards and offline earnings
- Profile and player search
- Settings, feedback, codes, likes, community, and verification
- Ten server leaderboard rows and fifty global rows
- Toast notifications and loading-ready visual hooks

The package includes a safe preview binder, so navigation and sample screens work when it is dragged into an otherwise empty game. When the reusable template core is present, preview mode automatically disables and the real server-authoritative data and actions take over. Object names are the binding contract and must remain unchanged.

Run `4_BUILD_UI_PACK.cmd` to create `exports/UI_BrightSimulator.rbxm` and open its folder.

In another game, delete any older `TemplateUI` copy first, then drag the new RBXM directly under **StarterGui**. Putting it in Workspace will not display it. Press Play to use the standalone preview; install TemplateCore when the game needs real saved data and purchases.

To create a cloud-linked Roblox Package, insert the model under `StarterGui`, right-click its `TemplateUI` root, select **Convert to Package**, choose the permanent owner, and submit. Keep the generated `PackageLink` child.

# Reusable UI packages

`UI_BrightSimulator` is the first visual package. It contains the complete authored `TemplateUI` ScreenGui:

- Coins and boost HUD
- Bottom navigation and quick menu
- Inventory with 12 permanent slots
- Store with 8 permanent cards
- Seven-day rewards and offline earnings
- Profile and player search
- Settings, feedback, codes, likes, community, and verification
- Ten server leaderboard rows and fifty global rows
- Toast notifications and loading-ready visual hooks

The package contains visual instances only. It requires the reusable template core in the destination game for live data and button behavior. Object names are the binding contract and must remain unchanged.

Run `4_BUILD_UI_PACK.cmd` to create `exports/UI_BrightSimulator.rbxm` and open its folder.

To create a cloud-linked Roblox Package, insert the model under `StarterGui`, right-click its `TemplateUI` root, select **Convert to Package**, choose the permanent owner, and submit. Keep the generated `PackageLink` child.

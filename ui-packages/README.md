# Reusable UI packages

The repository now keeps two physically separate authored packages:

- `UI_Incremental` — bright simulator layout with a vertical icon rail.
- `UI_RPG` — fantasy palette, RPG wording, and a bottom action dock.

They do not share GUI instances or model files. Moving, recoloring, or resizing an object in one package cannot modify the other package. Both retain the same binding contract so the shared secure services can connect to either one.

- Coins and boost HUD
- Vertical icon navigation and quick menu
- Inventory with 12 permanent slots
- Store with 8 permanent cards
- Seven-day rewards and offline earnings
- Profile and player search
- Settings, feedback, codes, likes, community, and verification
- Ten server leaderboard rows and fifty global rows
- Toast notifications and loading-ready visual hooks

The package includes a safe preview binder, so navigation and sample screens work when it is dragged into an otherwise empty game. When the reusable template core is present, preview mode automatically disables and the real server-authoritative data and actions take over. Object names are the binding contract and must remain unchanged.

Run `4_BUILD_UI_PACK.cmd` to create `exports/UI_Incremental.rbxm` and `exports/UI_RPG.rbxm` and open their folder. Run `5_GAME_DESIGNER.cmd` to choose a pack, configure one-to-five currencies and shared systems, and build a playable test place.

In another game, delete any older `TemplateUI` copy first, then drag the new RBXM directly under **StarterGui**. Putting it in Workspace will not display it. Press Play to use the standalone preview; install TemplateCore when the game needs real saved data and purchases.

To create a cloud-linked Roblox Package, insert the model under `StarterGui`, right-click its `TemplateUI` root, select **Convert to Package**, choose the permanent owner, and submit. Keep the generated `PackageLink` child.

In Studio edit mode, `ShowcaseCanvas` is intentionally visible so a non-programmer can inspect and edit the design-library examples. Pressing Play hides the showroom and uses the connected HUD/screens. The gameplay versions live under `TemplateUI > Root > Screens`; keep their object names unchanged.

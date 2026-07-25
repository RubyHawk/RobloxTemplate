# Tower placement input review — 2026-07-25

Checked the current Roblox Creator Hub input and camera references before adding manual tower placement:

- [Input Action System](https://create.roblox.com/docs/input/input-action-system)
- [UserInputService](https://create.roblox.com/docs/en-us/reference/engine/classes/UserInputService)
- [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera)

The tower loadout controller follows the repository's existing `UserInputService` approach. Mouse placement ignores processed UI clicks, touch placement uses `TouchTapInWorld` so camera drags do not place units, and gamepad placement casts from the viewport center. Mouse/touch screen coordinates use `Camera:ScreenPointToRay`; the gamepad viewport coordinate uses `Camera:ViewportPointToRay`.

These client checks are interaction feedback only. `TowerDefenseService.placeUnit` remains authoritative for ownership, loadout membership, stage bounds, build policy, path exclusion, occupancy, and deployment cost.

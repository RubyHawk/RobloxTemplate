# World-space UI bridge review

Checked: 2026-07-25

## Decision

The local Figma bridge treats `ScreenGui`, `SurfaceGui`, and `BillboardGui` as display containers. It maps their authored child GUI objects into editable Figma artboards, but it does not patch display-container placement or runtime behavior.

- `ScreenGui` uses the standard 1600x900 (16:9) editing viewport.
- A fixed-size `SurfaceGui` uses `CanvasSize`.
- A `PixelsPerStud` surface derives its editing canvas from the nearest authored part size and the selected face when that part is present in the imported model.
- A `BillboardGui` uses authored pixel offsets, or a stable nominal pixel scale for studs-only sizing.
- Nested containers are discovered through named `Folder`, `Model`, and world-instance paths so their child patch paths remain identical to the Rojo model.
- All imported artboards stay on the current Figma page to avoid the Figma Starter three-page limit.

Roblox remains authoritative for `Adornee`, `Face`, `AlwaysOnTop`, lighting, distance, safe areas, input routing, and scripts. Existing Roblox image IDs remain metadata and synthetic Figma placeholder fills are not exported.

## Platform behavior reviewed

Roblox documents that `SurfaceGui` renders child GUI objects on a part face, while `BillboardGui` renders child GUI objects in 3D facing the camera. Interactive buttons in either world-space container require the GUI to be in the player's `PlayerGui` (normally through `StarterGui`); SurfaceGui interaction also requires the target part's `CanQuery` property.

Sources:

- [In-game UI containers](https://create.roblox.com/docs/ui/in-experience-containers)
- [SurfaceGui API](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui)
- [BillboardGui API](https://create.roblox.com/docs/reference/engine/classes/BillboardGui)
- [ScreenGui API](https://create.roblox.com/docs/reference/engine/classes/ScreenGui)

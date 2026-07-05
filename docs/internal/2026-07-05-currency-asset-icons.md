# Currency asset icons review — 2026-07-05

Official Roblox documentation reviewed before adding currency-image support:

- [Assets](https://create.roblox.com/docs/projects/assets) — Roblox assets use unique IDs; in-experience image properties can use `rbxassetid://`, and `rbxthumb://type=Asset&id=...` can render an asset thumbnail.
- [Thumbnails API](https://create.roblox.com/docs/cloud/reference/features/thumbnails) — `GET https://thumbnails.roblox.com/v1/assets` is the stable, unauthenticated asset-thumbnail endpoint used by the desktop Game Designer preview.

Implementation decision:

- Recipes store only the numeric Roblox asset ID.
- The Game Designer validates the ID as digits and resolves a fixed Roblox thumbnail URL for its preview. It never accepts an arbitrary URL.
- Roblox HUD ImageLabels use `rbxthumb://type=Asset&id=<id>&w=150&h=150`, with the authored text symbol retained as an automatic fallback when no ID is configured.
- The five ImageLabels are authored in every independent StarterGui preset; runtime code only updates their `Image` and `Visible` properties.

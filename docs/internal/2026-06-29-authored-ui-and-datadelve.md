# 2026-06-29: permanent Studio UI and DataDelve boundary

## Official guidance checked on 2026-06-29

- UI and UX design: https://create.roblox.com/docs/production/game-design/ui-ux-design
- Design for Roblox: https://create.roblox.com/docs/production/game-design/design-for-roblox
- Style Editor: https://create.roblox.com/docs/ui/styling/editor
- Position and size UI objects: https://create.roblox.com/docs/building-and-visuals/ui/positioning-and-sizing-guiobjects
- On-screen UI containers and safe insets: https://create.roblox.com/docs/ui/on-screen-containers
- Data stores and Studio access warning: https://create.roblox.com/docs/cloud-services/data-stores

DataDelve primary sources checked:

- https://github.com/pinehappi/DataDelve
- https://create.roblox.com/store/asset/17652185888/DataDelve-Canary

## Applied UI decisions

- All ten connected screens and their children are permanent instances under `StarterGui.TemplateUI.Root.Screens`.
- Inventory has 12 authored slots, the store has 8 authored cards, daily rewards have 7 authored tiles, the server board has 10 authored rows, and the global board has 50 authored rows.
- Runtime UI code only binds actions and updates text, images, attributes, colors, and visibility. It cannot call `Instance.new`, `Clone`, or `Destroy` for GUI work; the repository check enforces this.
- The HUD stays compact while secondary features open in exclusive modal screens.
- The layout uses `CoreUISafeInsets`, minimum touch-friendly controls, scrolling content, consistent close buttons, one primary blue brand color, and semantic gold/green/red accents.
- Icons remain visual-first with text labels for young players and localization clarity.
- Ordinary layout, color, font, corner, stroke, and position changes are editable in Studio without changing Luau.

## DataDelve boundary

DataDelve Canary asset `17652185888` is installed for the local Roblox account. It edits DataStores and is unrelated to GUI construction. Use it only with a separate published test experience; Roblox warns that enabling Studio API access against a live experience can overwrite production data.

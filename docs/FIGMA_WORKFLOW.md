# Figma → Roblox preset handoff

## What “connected” means

Figma owns the visual source. Roblox owns the runnable native instances. A finished Figma design must be exported as actual `ScreenGui`, `Frame`, `ImageButton`, `TextLabel`, and layout instances before the existing Luau binders can connect behavior.

There is currently no first-party Roblox Figma GUI importer. UI Plus edits native instances inside Studio but does not import Figma files. Do not treat a screenshot or one flattened image as a connected UI.

## One pack, one independent copy

1. Keep one Figma page per pack, such as `Incremental` or `RPG`.
2. Preserve the binder names listed below when exporting.
3. Import/export into that pack's own native Roblox hierarchy.
4. Save the three independent files under `src/ui/presets/<pack>/`:
   - `TemplateUI.model.json`
   - `TemplateLoading.model.json`
   - `StarterSignUI.model.json`
5. Run `5_GAME_DESIGNER.cmd`, select the pack, and build the playable starter.

The Game Designer discovers complete preset folders automatically; adding a pack does not require editing its PowerShell UI.

Never replace another pack's files. The builder copies only the selected pack into the playable experience.

## Required binding names

The primary roots are `CurrencyHUD`, `Navigation`, `Screens`, `MoreButton`, and `MoreMenu`. Connected screens and finite data slots must retain the names already present in the authored preset model. Decorative layers can use any names. Interaction code changes values and visibility only; it does not build the visual hierarchy.

## Importer decision

As of 2026-07-02, Roblox documents building UI with native GUI objects and Studio's Style Editor but does not document an official Figma importer. Community importers exist, but they execute third-party plugin code and have different naming/layout support. Review and choose one explicitly before installing it; this repository does not silently install or trust one.

Sources checked 2026-07-02:

- [Roblox UI documentation](https://create.roblox.com/docs/ui)
- [Implement designs in Studio](https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/implement-designs-in-studio)
- [Roblox Studio interface and Style Editor](https://create.roblox.com/docs/studio/ui-overview)

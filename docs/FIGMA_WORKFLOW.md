# Figma → Roblox preset handoff

## What “connected” means

Figma owns the visual source. Roblox owns the runnable native instances. A finished Figma design must be exported as actual `ScreenGui`, `Frame`, `ImageButton`, `TextLabel`, and layout instances before the existing Luau binders can connect behavior.

There is currently no first-party Roblox Figma GUI importer. This repository therefore includes a reviewed local bridge under `figma/roblox-ui-bridge`. It imports native Rojo models into editable Figma layers, preserves Roblox paths as metadata, and exports validated patches back to those models. It is an explicit round trip, not live synchronization. Do not treat a screenshot or one flattened image as a connected UI.

## One pack, one independent copy

1. Use the local plugin to import one preset's model files into separate Figma pages.
2. Edit the generated artboards. Original binder paths remain attached even if a Figma layer is renamed.
3. Export the selected artboards as a `roblox-ui-bridge-v1` patch.
4. Run `FIGMA_UI.cmd`, choose the pack, and drag in the patch. It updates the matching files under `src/ui/presets/<pack>/`:
   - `TemplateUI.model.json`
   - `TemplateLoading.model.json`
   - `StarterSignUI.model.json`
5. The command rebuilds the selected playable starter without opening Studio.

The Game Designer and `FIGMA_UI.cmd` both discover complete preset folders automatically; adding a pack does not require editing any PowerShell UI.

Never replace another pack's files. The builder copies only the selected pack into the playable experience.

## Required binding names

The primary roots are `CurrencyHUD`, `Navigation`, `Screens`, `MoreButton`, and `MoreMenu`. Connected screens and finite data slots must retain the names already present in the authored preset model. Decorative layers can use any names. Interaction code changes values and visibility only; it does not build the visual hierarchy.

## Bridge setup

Follow [`FIGMA_UI.md`](FIGMA_UI.md) once to import the development plugin manifest into Figma. No access token or secret is stored in the repository. The bridge imports no scripts, rejects missing paths and class mismatches, and keeps existing Roblox image asset IDs authoritative.

As of 2026-07-02, Roblox documents building UI with native GUI objects and Studio's Style Editor but does not document an official Figma importer. Community importers exist, but they execute third-party plugin code and have different naming/layout support; the checked-in bridge avoids silently installing one.

Sources checked 2026-07-02:

- [Roblox UI documentation](https://create.roblox.com/docs/ui)
- [Implement designs in Studio](https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/implement-designs-in-studio)
- [Roblox Studio interface and Style Editor](https://create.roblox.com/docs/studio/ui-overview)

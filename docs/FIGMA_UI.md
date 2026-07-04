# Edit a preset in Figma

The repository includes a local Figma development plugin that converts the authored Rojo UI models into editable Figma layers and exports validated visual patches back to those same models. Runtime Luau remains behavior-only.

## One-time setup

1. Open the Figma desktop app.
2. Open **Plugins → Development → Import plugin from manifest**.
3. Select `figma/roblox-ui-bridge/manifest.json` from this repository.

The shared design file is [Roblox UI Preset Library](https://www.figma.com/design/TCKb7NWBeH1wSf6eLDARhn). Figma's Starter-plan MCP quota currently prevents Codex from populating its canvas remotely, so use the local bridge below; it does not require a token or secret.

## Edit and apply

1. In the Figma file, run **Plugins → Development → Roblox UI Bridge**.
2. Click **Import Rojo UI model** and choose one or more files from the chosen preset folder:
   - `TemplateUI.model.json`
   - `TemplateLoading.model.json`
   - `StarterSignUI.model.json`
3. Edit the imported frames, text, colors, outlines, corners, visibility, position, and size in Figma.
4. Select the imported artboards and click **Export selected Roblox patch**.
5. Double-click `START_HERE.cmd` and open the **Figma design** page. The newest `*.figma-patch.json` from your Downloads folder is already selected; confirm the UI pack and click **Apply Figma Design**. Progress streams into the activity panel at the bottom of the app - no extra console window.

The apply step reads which of those three models are present in the patch, validates every layer path and class, updates only the selected preset, and rebuilds its `.rbxlx` and `.rbxm` exports without opening Roblox Studio.

`FIGMA_UI.cmd` remains the console alternative. It now also offers the newest export from Downloads automatically, so pressing Enter twice applies the latest patch to the first preset; it accepts `-Preset` and `-PatchPath` parameters as well.

## Boundaries

- Figma is the visual editor for supported properties. Roblox remains the source for behavior, responsive constraints, asset permissions, and live data.
- Existing Roblox image asset IDs are preserved as metadata. Figma shows image placeholders because it cannot republish Roblox assets or grant experience permissions.
- Renaming mapped Figma layers is safe because the original Roblox path is stored as plugin metadata. Renaming objects in the Rojo model after importing requires a fresh import.
- The bridge never creates, clones, or destroys GUI objects at runtime. It updates the editable `StarterGui` model files before Rojo builds the place.

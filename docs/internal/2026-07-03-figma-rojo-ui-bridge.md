# Figma ↔ Rojo visual workflow — 2026-07-03

## Decision

The reusable UI now has an explicit local round trip:

1. `figma/roblox-ui-bridge` imports an authored Rojo `.model.json` as editable Figma artboards.
2. Stable Roblox object paths and original UDim2 scale values are stored as Figma shared plugin metadata.
3. Figma exports a `roblox-ui-bridge-v1` patch containing supported visual and layout properties.
4. `FIGMA_UI.cmd` validates paths and classes, updates only the chosen preset, and rebuilds the playable export with `-NoStudio`.

This is intentionally not described as live or automatic sync. The checked-in Rojo model remains the reviewable source that ships to Roblox, while Figma is the visual editing surface.

## Safety boundaries

- The bridge does not execute or import scripts.
- It cannot create runtime GUI objects.
- It rejects missing object paths, class mismatches, and patches with no entries for the selected model.
- It preserves Roblox image asset IDs as metadata; Figma does not republish or grant access to those assets.
- Each preset has an independent model, so editing Incremental cannot restyle RPG.

## Verification

- Plugin and importer JavaScript syntax checks pass.
- Both preset models expose 1,536 unique named bridge paths.
- The in-memory patch application self-test passes.
- The full repository check passes without opening Roblox Studio.

## Nested control correction — 2026-07-04

The first local-plugin import treated every class whose name began with `Text` as a leaf. That was wrong for authored `TextButton` controls: simulator-style buttons keep `IconBubble`, icon, label, badge, and other editable layers beneath the button. The importer now recurses through named visual children for every supported GUI class while still adding the generated `$Text` preview layer. Export now also includes a text control's corner radius and outline instead of limiting those properties to non-text controls. Luau regression assertions cover both mistakes.

Existing Figma pages are snapshots and do not repair themselves. Close and rerun the development plugin, delete the incomplete imported page, and import the model again.

Figma renders Roblox `ImageLabel` and `ImageButton` assets as synthetic purple placeholders because it cannot fetch or republish those Roblox assets. Those placeholder fills are now excluded both when exporting new patches and when applying older patches, so they cannot become opaque backgrounds around the real in-experience icons.

## One-window app flow — 2026-07-04

Applying a patch previously required a console round trip: run `FIGMA_UI.cmd`, type a preset number, and drag the downloaded patch into the window. `START_HERE.cmd` is now the app hub for that flow. The launcher discovers game recipes and complete UI packs, pre-selects the newest `*.figma-patch.json` from the Windows Downloads folder (Shell `shell:Downloads` with a `%USERPROFILE%\Downloads` fallback), sanity-checks the `roblox-ui-bridge-v1` format marker before launching, and starts `FIGMA_UI.cmd -Preset <pack> -PatchPath <file>` so the console step runs with no typed input. The shared sandbox button passes `-RecipePath` the same way.

The `.cmd` files forward parameters with `%*` and stay fully usable standalone; `figma-ui.ps1` also offers the newest Downloads export and re-prompts on an invalid preset choice instead of silently applying to the first pack. Validation still happens in `figma-ui.ps1`/`figma-ui-bridge.mjs`, which reject unknown paths and class mismatches before writing; the launcher check is a convenience, not the safety boundary.

Later the same day the launcher became an app shell: sidebar navigation (Play and test, Figma design, Build and tools), a shared WPF resource dictionary (`scripts/app-theme.xaml`) that restyles ComboBox, TextBox, CheckBox, and ScrollBar so no stock light controls sit on the dark background, and an in-app task runner. Non-interactive scripts (`figma-ui.ps1` with parameters, `doctor.ps1 -Full`, `setup.ps1`, `build-ui-pack.ps1`) run hidden with stdout/stderr redirected to `build/app-tasks/*.log` and streamed into the activity panel by a 200 ms `DispatcherTimer`; a Stop button kills the task tree via `taskkill /T`. Long-running Rojo/Studio sessions (`SANDBOX.cmd`, `2_START.cmd`) and the interactive icon console stay in their own windows on purpose, because they must outlive the app and accept input. The Game Designer window merges the same theme, so both GUIs read as one product. The title bars use the DWM immersive dark attribute where available and degrade silently elsewhere.

## Hosted Figma file

- [Roblox UI Preset Library](https://www.figma.com/design/TCKb7NWBeH1wSf6eLDARhn)
- Codex created the file successfully, but the connected Figma Starter plan reached its MCP tool-call quota before canvas population. The local development plugin is therefore the working no-token bridge.

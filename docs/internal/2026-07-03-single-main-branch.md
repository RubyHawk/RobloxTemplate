# Single permanent branch — 2026-07-03

## Decision

The previous `template` and `playable-starter` branches duplicated most commits and repeatedly required merges. Preset folders, generated `DesignerConfig`, the Figma bridge, and the permanent sandbox now provide the separation those branches originally represented.

The repository therefore uses one permanent branch: `main`.

- **Open Template** launches the saved `RobloxTemplateGallery` workbench with mock persistence and all sanitized showroom references.
- **Open Shared Test Experience** generates the selected preset with live persistence and opens the permanent cloud sandbox.
- Incremental, RPG, and future themes remain physically independent under `src/ui/presets/`.
- Short-lived feature branches are still appropriate for active code review. A truly separate released game can receive its own long-lived branch later.

Before deleting old remote branches, preserve their exact tips as annotated archive tags. This keeps every commit and the old saved place snapshots recoverable without asking non-programmers to choose among permanent branches.

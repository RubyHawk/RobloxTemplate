# Two permanent experiences — 2026-07-03

## Decision

The repository now names both permanent Roblox experiences in one committed file, `experiences.config.json`, replacing `sandbox.config.json`:

- `template` — the UI authoring workbench. `scripts/start.ps1` opens it with `RobloxStudioBeta.exe -task EditPlace -placeId <id> -universeId <id>` and serves a generated `build/template/TemplateWorkbench.project.json` (a clone of `default.project.json` with `servePlaceIds` restricted to the template place). It ships with `0/0` placeholder IDs; until the team pastes their real IDs, the script falls back to the local `places/RobloxTemplateGallery.rbxlx` built from `bootstrap.project.json`.
- `playerTest` — the playable sandbox (universe `10434789270`, place `106940880949257`), unchanged behavior from the 2026-07-03 permanent-sandbox record, now reading the new config. Its preset menu lists every recipe under `config-presets/` instead of a hardcoded two-option list.

Neither mode ever creates a Roblox experience. Both serve projects carry `servePlaceIds`, so Rojo refuses to sync into any other place.

## Related hardening in the same change

- `DataStoreRuntime.mode()` now returns `mock` for template builds unconditionally. Previously mock required `RunService:IsStudio()`, so a published template experience would have written live DataStores under the `incremental` namespace. Template mode is now mock on published servers too; only generated `playable` recipes use live persistence.
- The leaderstat column and `Config.leaderboards.metric` follow the recipe's primary currency name (RPG shows `Gold`, not `Coins`). The ordered store keeps the `RobloxTemplate_CoinsLeaderboard_v1_<ns>` name so existing saved rankings stay readable.
- `Config.ui.preset` passes through any validated preset name instead of collapsing to `rpg`/`incremental`.
- `scripts/figma-ui.ps1` discovers complete preset folders (the three authored model files) instead of a hardcoded `ValidateSet`, matching the Game Designer and the documented "add a pack without editing scripts" workflow.
- The committed `places/RobloxTemplateGallery.rbxlx` was removed from version control. It had gone stale (its baked scripts still referenced the removed `useLiveDataStore` switch), and its sharing role moves to the cloud template experience. `start.ps1`/`setup.ps1` rebuild the local fallback from `bootstrap.project.json` when it is missing; the old file remains in Git history. Durable UI truth stays in `src/ui/**/**.model.json`; Studio-to-repository syncback remains a non-goal.

## Sources

- Publish to an existing experience vs Publish As (creates a new experience): https://create.roblox.com/docs/production/publishing/publish-experiences-and-places — link re-verified reachable 2026-07-03; semantics as recorded the same day in [2026-07-03-permanent-sandbox.md](2026-07-03-permanent-sandbox.md), which also documents the `-task EditPlace` Studio invocation reused here.
- Data stores (unchanged store names and namespace scheme): https://create.roblox.com/docs/cloud-services/data-stores — per the 2026-07-02 persistence record.

## Tests

- `tests/run.luau` gained assertions: both launchers read `experiences.config.json`; `start.ps1` uses `-task EditPlace` and `servePlaceIds`; `figma-ui.ps1` has no `ValidateSet` and discovers `src/ui/presets`; `DataStoreRuntime` mock mode no longer depends on `IsStudio`; leaderstat/metric are not hardcoded to `Coins`; `ui.preset` is not collapsed to two packs.
- CI now also lints `ui-packages`, runs the Figma bridge verify/self-test for every preset, smoke-builds every recipe under `config-presets/`, and runs both launchers' `-SmokeTest` config guards on Linux `pwsh`.

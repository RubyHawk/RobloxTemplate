# 2026-06-30: reusable UI pack system

## What changed

Added a config-selected **UI pack** layer so one template can drive different games
(incremental, combat, tycoon, simulator) without rewriting the UI. Packs are frozen
data that map a finite pool of pre-authored HUD slots to player-state paths.

New shared modules: `PackRegistry`, `packs/IncrementalPack`, `packs/CombatPack`,
`PackValidation`, `ProfileMigrationSteps`, `TableMerge`, `SeedProfiles`. New client
modules: `Store`, `WidgetBinder`, `ThemeProvider`, `PackController`, `VitalsFeeder`.
Profile schema bumped to v2 (multi-currency, upgrades, unlocks, progress, tutorial,
selectedPack/selectedTheme).

## Decisions

- **One authored root + a generic slot pool**, not a ScreenGui per pack. Per-pack
  roots would multiply the riskiest activity (editing the 550KB authored model) and
  the brittle substring tests in `tests/run.luau` by N, and re-author safe-area /
  scale plumbing each time. The pool (`StatWidget01..06`, `ProgressBar01..02`,
  `ActionSlot01..04`) generalizes the existing `ItemSlotNN` / `hideFrames` pattern.
- **No `ThemeRole` attributes in the model.** Theming is driven entirely by code
  (resolved theme tokens + per-binding `color`), avoiding a fragile attribute
  encoding in the authored JSON. `ThemeProvider.resolve` deep-merges
  `Theme.packs[themeId]` over the frozen base into a working copy.
- **Keep the custom `ProfileService`**, do not adopt the external ProfileStore Wally
  package. It already does envelope + session lock + autosave + BindToClose +
  migrations, and the repo is intentionally zero-dependency.
- **`coins` stays the canonical primary-currency field**; `currencies[primary]`
  mirrors it (write-through in `EconomyService`). This kept leaderboards, public
  profiles, and existing screens working with no change. A v1→v2 migration step
  seeds `currencies.coins` from `coins`; reconcile preserves unknown keys.
- **Pure helpers for testability.** Lune can only require `script`-free modules, so
  the migration step (`ProfileMigrationSteps`), validator (`PackValidation`), deep
  merge (`TableMerge`), and `Store` are dependency-free and unit-tested directly.

## Platform / API notes

No new Roblox platform API surface was introduced. DataStore usage follows the
existing `ProfileService` pattern; the Studio-only canary store
(`<name>_canary`, gated by `RunService:IsStudio()` + `studio.useCanaryStore`) keeps
seeded fixtures away from production, consistent with the DataDelve guidance and the
[Roblox Data stores documentation](https://create.roblox.com/docs/cloud-services/data-stores).

## Tests performed (local)

`stylua --check src tests`, `rojo build bootstrap.project.json`, and
`lune run tests/run` (113 assertions) pass. `selene` could not run in this
environment (its Rust HTTP client rejects the egress proxy CA when fetching the
Roblox API dump); it runs in CI. Added Lune coverage for the store, deep merge,
v1→v2 migration, reconcile of v2 sections, pack validation, the authored slot pool
substrings, and a no-GuiObject-construction gate over the new client modules.

## Next person must not assume

- Adding a stat icon requires entries in **both** `IconCatalog` and
  `TemplateConfig.icons` or `IconCatalog.get` errors.
- Slot indices in a descriptor must stay within `Config.ui` pool sizes; if a pack
  needs more, grow the authored pool and the pool-size config together.
- Combat health/stamina are **client-local** UI state (`VitalsFeeder`), never server
  profile data.

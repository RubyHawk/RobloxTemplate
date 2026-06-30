# UI packs

A **UI pack** lets one template power many games. A pack is frozen *data* that maps
a finite pool of pre-authored HUD slots to player-state paths, plus a theme,
currencies, enabled screens, and navigation. Different games select a different
pack with no UI rewrite and **no runtime GuiObject creation** — packs only show,
hide, and bind slots that already exist in `StarterGui.TemplateUI`.

The template ships two packs that prove the architecture:

- **`incremental`** (default): coins + gems + multiplier stats, daily-streak
  progress, Shop/Rewards actions.
- **`combat`**: health/stamina vital bars (client-local), gold, an objective bar,
  and ability buttons with cooldowns, on a dark theme.

## Choosing a pack

Set the active pack per game in `src/shared/TemplateConfig.luau`:

```luau
ui = {
    defaultPackId = "incremental", -- or "combat"
    allowPlayerPackSelection = false,
    statWidgetPoolSize = 6,
    actionSlotPoolSize = 4,
    progressBarPoolSize = 2,
},
```

The server resolves the active pack and sends `packId`/`themeId` in the snapshot;
the client looks the descriptor up in `PackRegistry` and binds the HUD.

## The authored slot pool

These instances live under `Root` in `src/ui/TemplateUI.model.json` and are the
only HUD geometry packs may use. Pool sizes are pinned in `Config.ui` so the
model, descriptors, and binder cannot drift.

| Rail | Slots | Authored children a binding may populate |
| --- | --- | --- |
| `StatRail` | `StatWidget01..06` | `Icon`, `Symbol`, `Value`, `Caption`, `Bar` > `Fill`, `Delta` |
| `ProgressRail` | `ProgressBar01..02` | `Caption`, `Value`, `Bar` > `Fill` |
| `ActionRail` | `ActionSlot01..04` | `Icon`, `Label`, `CooldownFill` |

A widget renders a currency, a resource bar, a rate, or progress-to-next purely by
which children its binding fills. Unused slots are hidden. Refine the visuals in
Studio; never add or remove these named instances in code.

## Anatomy of a pack descriptor

`src/shared/packs/IncrementalPack.luau` is the reference. Fields:

- `id`, `displayName`, `themeId` (key into `Theme.packs`).
- `currencies`: `{ id, displayName, icon, primary? }`. Exactly one must be `primary`.
- `hud.stats` / `hud.progress`: `StatBinding`s — `slot`, `path`, `icon?`,
  `caption?`, `format?` (`number`/`raw`/`percent`/`time`/`ratio`), `bar?`
  (`{ max }` or `{ maxPath }`, plus `color?`), `color?` (theme token), `default?`.
- `hud.actions`: `ActionBinding`s — `slot`, `action`, `label`, `icon?`, `screen?`
  (for `OpenScreen`), `value?`, `cooldown?` (for `Ability`).
- `screens`: which screens this pack enables (nav buttons for others are hidden).
- `navigation`: ordered nav items (each `screen` must appear in `screens`).
- `localFeeds?`: `{ health = true }` starts the client-local vitals feed.

### State paths a binding can read

Built by `PackController.buildView` from the snapshot, plus client-local feeds:

- `currencies.<id>` — e.g. `currencies.coins`, `currencies.gems`
- `multiplier` — combined friend × premium × potion multiplier
- `daily.streak`, `progress.rebirths`, `progress.prestige`, `progress.objectives.<id>`
- `stats.totalCoinsEarned`, `friends`
- `local.health`, `local.maxHealth`, `local.stamina`, `local.maxStamina` (combat)

Missing paths fall back to the binding's `default`, so a widget never errors.

## Adding a third pack

1. Create `src/shared/packs/MyPack.luau` returning a `table.freeze`d
   `Types.PackDescriptor`. Keep slot indices within the pool sizes.
2. Register it in `src/shared/PackRegistry.luau` (`packs.mypack = require(...)`).
3. Add a theme override under `Theme.packs.mypackTheme` (optional; only the tokens
   that differ).
4. If you need a new stat icon, add the name to `IconCatalog` **and**
   `TemplateConfig.icons` (both, or `IconCatalog.get` will error).
5. `PackRegistry.validate` runs at startup; the Lune suite covers the validator.
   Run `lune run tests/run` and play-test with `Config.ui.defaultPackId = "mypack"`.

No core service or screen changes are required — that is the point of the layer.

## Multi-currency

The profile stores `currencies` (`{ [id]: number }`). The primary currency mirrors
the legacy top-level `coins` field, so leaderboards and public profiles keep
working. Credit/spend secondary currencies on the server with
`EconomyService.creditCurrency` / `spendCurrency`; the primary currency still goes
through `award`/`awardRaw`/`spend`.

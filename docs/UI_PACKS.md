# Physical UI packs

A UI pack is a complete, editable HUD hierarchy under:

`StarterGui > TemplateUI > Root > PackRoots`

The template ships two real authored packs:

- **IncrementalPackRoot**: bright currency pills, daily progress, and circular Shop/Rewards actions.
- **CombatPackRoot**: dark health/stamina/gold cards, an objective bar, and colorful ability buttons.

These are not generated or styled by code. Every Frame, button, icon slot, stroke, corner, color, size, and position exists in Studio. Runtime code only:

- selects one authored root;
- fills text and image slots;
- changes progress/cooldown fill sizes;
- shows or hides pre-authored finite slots;
- connects the authored buttons to validated actions.

## Choosing a pack

Set the game-wide default in `src/shared/TemplateConfig.luau`:

```luau
ui = {
    defaultPackId = "incremental", -- or "combat"
    allowPlayerPackSelection = false,
    statWidgetPoolSize = 6,
    actionSlotPoolSize = 4,
    progressBarPoolSize = 2,
},
```

The server sends only the selected `packId`. The descriptor identifies the physical root through `authoredRoot`; there is no runtime theme provider.

## Editing without programming

1. Open the place in Studio without pressing Play.
2. Expand `StarterGui > TemplateUI > Root > PackRoots`.
3. Select either `IncrementalPackRoot` or `CombatPackRoot`.
4. Edit its existing Frames, buttons, images, colors, strokes, sizes, and positions in Studio.
5. Keep the binding names unchanged: `StatRail`, `ProgressRail`, `ActionRail`, `StatWidget01..06`, `ProgressBar01..02`, and `ActionSlot01..04`.
6. Press Play. Runtime hides the unselected physical root and binds the configured one.

Both roots are visible in the source model's edit view so designers can compare them. The client hides them immediately during Play before selecting the configured pack.

## Binding contract

Each physical root contains the same finite names so the binder can safely populate it:

| Rail | Authored slots | Runtime may change |
| --- | --- | --- |
| `StatRail` | `StatWidget01..06` | text, image, bar fill, visibility |
| `ProgressRail` | `ProgressBar01..02` | text, bar fill, visibility |
| `ActionRail` | `ActionSlot01..04` | text, image, cooldown fill, visibility, action connection |

The Incremental and Combat instances can have completely different geometry and styling despite sharing these child names.

## Descriptor fields

Descriptors under `src/shared/packs/` are data bindings, not visual definitions:

- `id`, `displayName`, `authoredRoot`.
- `currencies`: server-owned currency definitions.
- `hud.stats` and `hud.progress`: authored slot number, state path, formatting, and optional bar maximum.
- `hud.actions`: authored slot number and validated intent.
- `screens` and `navigation`: which existing connected screens are reachable.
- `localFeeds`: optional client-only presentation feeds such as humanoid health.

Colors and layout do not belong in descriptors. Set them on the physical instances in Studio.

## Adding another pack

1. Author a new full Frame under `PackRoots` with all required named rails and slots.
2. Create `src/shared/packs/MyPack.luau` and set `authoredRoot` to that Frame's exact name.
3. Register the descriptor in `PackRegistry.luau`.
4. Add required semantic icons to `IconCatalog` and `TemplateConfig.icons`.
5. Run `lune run tests/run` and the full repository check.
6. Rebuild and commit the tracked `.rbxlx` place so other people receive the physical instances.

Never create or clone the pack root during Play.

## Multi-currency

Profiles store a `currencies` map. The primary currency mirrors the legacy top-level `coins` field, preserving existing leaderboards and public profiles. Secondary balances use the server-authoritative `EconomyService.creditCurrency` and `spendCurrency` methods.

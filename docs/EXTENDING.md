# Extending the template

## Add a gameplay reward

Keep reward decisions on the server and call the shared economy service with a fixed server-computed base amount:

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local EconomyService = require(ServerScriptService.TemplateServer.Services.EconomyService)

EconomyService.award(player, 25, "game:checkpoint")
```

The service applies current friend, Premium, and strongest-potion multipliers. Use `awardRaw` only for purchases, daily rewards, codes, or migrations that must not be boosted.

## Add an item

Add its definition to `src/shared/Catalogs.luau`. Keep item IDs stable after release. Add a profile migration only if the persisted representation changes.

## Add a screen

Create the complete visual shell and enough finite data slots in `StarterGui.TemplateUI`, then register the existing screen through `ScreenRegistry` and bind its fields. Never create, clone, or destroy GUI objects at runtime. Use Studio-editable styling and verify the mobile acceptance matrix.

## Replace a provider

A released game built from this template can replace `DefaultEconomyRateProvider`, `LikesService`, community verification, notification scheduling, or public profile lookup while preserving the contract in `src/shared/Providers.luau`.

## Add a new UI pack

1. Copy an existing complete pack folder (for example `src/ui/presets/incremental/`) to `src/ui/presets/<name>/`. A pack is complete when it has its own `TemplateUI.model.json`, `TemplateLoading.model.json`, and `StarterSignUI.model.json`. Packs stay physically independent: never link or regenerate one pack from another.
2. Add `config-presets/<name>.json` (copy `incremental.json`), then set its `preset`, `dataNamespace`, one to five currencies, and feature flags.
3. The Game Designer, the sandbox preset menu, `FIGMA_UI.cmd`, and `scripts/check.ps1` discover complete packs automatically; no script edits are needed.
4. Test it through the shared player-test experience. The pack gets its own DataStore namespace; no new Roblox experience is created.

## Release flow

Implement reusable work on `main` through a short-lived feature branch, run `scripts/check.ps1`, and merge. Game-specific tuning belongs in `config-presets/` recipes and `TemplateConfig`, not forked copies of individual services. Create a long-lived branch and a separate Roblox experience only for a genuinely separate released game.

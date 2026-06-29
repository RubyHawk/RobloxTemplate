# Extending the template

## Add a map reward

Keep reward decisions on the server and call the shared economy service with a fixed server-computed base amount:

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local EconomyService = require(ServerScriptService.TemplateServer.Services.EconomyService)

EconomyService.award(player, 25, "map:checkpoint")
```

The service applies current friend, Premium, and strongest-potion multipliers. Use `awardRaw` only for purchases, daily rewards, codes, or migrations that must not be boosted.

## Add an item

Add its definition to `src/shared/Catalogs.luau`. Keep item IDs stable after release. Add a profile migration only if the persisted representation changes.

## Add a screen

Create the complete visual shell and enough finite data slots in `StarterGui.TemplateUI`, then register the existing screen through `ScreenRegistry` and bind its fields. Never create, clone, or destroy GUI objects at runtime. Use Studio-editable styling and verify the mobile acceptance matrix.

## Replace a provider

Map branches can replace `DefaultEconomyRateProvider`, `LikesService`, community verification, notification scheduling, or public profile lookup while preserving the contract in `src/shared/Providers.luau`.

## Release flow

Implement reusable work on `template`, run `scripts/check.ps1`, tag it, then merge the tag/branch into each map branch. Resolve configuration in the map branch; do not fork copies of individual services.

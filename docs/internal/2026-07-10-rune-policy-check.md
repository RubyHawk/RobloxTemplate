# Randomized rune rolls policy review — 2026-07-10

Official Roblox documentation reviewed before adding the rune altar (random rune
cards bought automatically with a configured in-game currency while standing in
the circle):

- [Randomized virtual items policy](https://create.roblox.com/docs/production/monetization/randomized-virtual-items-policy) —
  random items count as **paid** when bought with Robux *or with an in-game
  currency that can be bought with Robux, even indirectly*. Paid random items
  require disclosing every possible outcome with numerical odds shown as
  percentages that sum to exactly 100% before the purchase, and a compliant
  treatment for restricted users (unpaid path, predetermined outcomes, direct
  purchase, removal, or blocking with a clear message).
- [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService) —
  `PolicyService:GetPolicyInfoForPlayerAsync(player)` returns a dictionary with
  `ArePaidRandomItemsRestricted`; the call is async, must be wrapped in `pcall`,
  and its result should be checked before exposing paid random item generators.

Implementation decisions:

- Rune rarity odds are authored as integer weights that must sum to 10,000 so
  the displayed percentages always total exactly 100%. The odds panel and the
  altar sign show them before the first automatic roll (the first roll only
  happens after a charge delay while standing in the circle).
- The template's primary currency becomes Robux-purchasable once
  `Config.products.coinPackSmall/coinPackLarge` IDs are configured. When the
  rune currency is Robux-purchasable, `RuneService` checks
  `ArePaidRandomItemsRestricted` per player, fails closed on errors, and blocks
  rolling with a visible "unavailable" message for restricted players.
- While the product IDs are `0` (repository default) the currency cannot be
  bought with Robux, so rune rolls are not paid random items; the odds stay
  disclosed anyway.
- Rune boosts are permanent additive generation bonuses, not temporary boosts,
  so they do not interact with the "strongest potion wins" rule.

Shared tower-defense world note: the collaborative tower-defense experience
lives at place `128136881672145` (recorded in `experiences.config.json` under
`towerDefense`; universe ID still unknown). Template services keep reading IDs
from configuration only.

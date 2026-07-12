# Randomized Rune Rolls Policy Review - 2026-07-10

Official Roblox documentation reviewed before adding the rune altar, where random rune cards can be bought automatically with configured in-game currency while standing in the circle:

- Paid random items policy guidelines: https://create.roblox.com/docs/production/monetization/paid-random-items
- PolicyService API reference: https://create.roblox.com/docs/reference/engine/classes/PolicyService

Implementation decisions:

- Rune rarity odds are authored as integer weights that must sum to 10,000 so the displayed percentages always total exactly 100%. The odds panel and altar sign show them before the first automatic roll.
- Roblox treats random items as paid when bought with Robux or with in-game currency bought with Robux, including indirect flows like paid gems or tickets.
- The template primary currency becomes Robux-purchasable only once `Config.products.coinPackSmall/coinPackLarge` IDs are configured. While IDs are `0`, repository-default rune rolls are not paid random items, but odds are still disclosed.
- When the rune currency is Robux-purchasable, `RuneService` checks `PolicyService:GetPolicyInfoForPlayerAsync(player)`, reads `ArePaidRandomItemsRestricted`, fails closed on policy lookup errors, and blocks rolling with a visible unavailable state for restricted players.
- Rune boosts are permanent additive generation bonuses, not temporary boosts, so they do not interact with the "strongest potion wins" rule.

Shared tower-defense world note: the collaborative tower-defense experience lives at place `128136881672145` in `experiences.config.json` under `towerDefense`; universe ID is still unknown.

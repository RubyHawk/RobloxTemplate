# Rune channel modes, momentum, and copy milestones — policy check

- Check date: 2026-07-12
- Checked by: template maintainers (automated session)
- Sources reviewed today:
  - https://create.roblox.com/docs/production/monetization/randomized-virtual-items-policy
  - https://create.roblox.com/docs/reference/engine/classes/PolicyService (via the policy page's PolicyService requirements)
  - Prior baseline: `docs/internal/2026-07-10-rune-policy-check.md`

## What changed in the rune altar

1. **Channel modes with momentum.** Standing in the circle builds ephemeral,
   server-tracked momentum. The selected mode decides what momentum does:
   - `luck` (default, always unlocked): momentum tiers multiply the weights of
     every rarity above common, with the increase taken out of the common
     weight (`RuneLogic.luckAdjustedRarities`).
   - `surge` (unlocks at 25 total rolls by default): momentum tiers grant a
     temporary earnings multiplier while channeling.
2. **Copy milestones.** Owning N copies of a rune multiplies that rune's whole
   contribution (default 5 → x1.25, 10 → x1.5, 25 → x2). Deterministic — no new
   randomness was added anywhere.
3. Mode selection persists (profile schema v7) and is swapped through a new
   validated `SetRuneMode` request; rolls remain entirely server-initiated.

## Paid-random-items compliance

The policy applies when random items are bought with Robux directly or with a
paid in-game currency. The template's coin packs still ship with placeholder
product ids (`0`), so rune rolls are not currently "paid" random items; the
fail-closed `PolicyService` gate from the 2026-07-10 check is untouched and
engages automatically the moment a recipe makes coins Robux-purchasable.

The policy requires displayed odds to be the actual numerical odds, to total
exactly 100%, and — quoting today's doc — when odds change, "the odds for the
remaining obtainable outcomes must be updated to reflect up-to-date remaining
odds for that user." Luck momentum changes the effective odds, so:

- `RuneLogic.luckAdjustedRarities` keeps integer weights that sum to exactly
  10000 at every tier (spec-enforced), so displayed odds always total exactly
  100%.
- `RuneService.channelStateFor` sends the exact adjusted weight table the
  server rolls with (`effectiveWeights`) on every enter/tier/mode transition
  and inside every snapshot; the OddsPanel renders those server-sent numbers,
  never a client-side estimate. Base (tier 0) odds show from catalog data the
  moment a player steps in, before the first charged roll.
- `tryRoll` builds the adjusted table from the same inputs, so the disclosed
  odds and the rolled odds cannot diverge.

`ArePaidRandomItemsRestricted` handling is unchanged: restricted players see
the authored `RestrictedNote` unavailable state and the server refuses rolls,
which is one of the sanctioned treatments (feature blocked with a visible
error state).

## Not random items

- The surge earnings boost and copy milestones award no randomized item; surge
  competes in the strongest-temporary-boost bucket with potions (they never
  stack multiplicatively, per the template hard boundary) and is excluded from
  offline earnings.
- Momentum is ephemeral server state: it resets on leaving the circle, death,
  or disconnect, is preserved across mode swaps, and is never persisted nor
  trusted from the client.

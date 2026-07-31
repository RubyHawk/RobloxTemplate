# Stagewright endless waves — 2026-07-31

## What was already true

Authored wave sets have always looped. `TowerDefenseWaves.waveForIndex` is a
1-based modulo lookup and `startWave` increments without a ceiling, so wave 7 of
a six-wave set has always replayed wave 1. There was never a "ran out of waves"
state. What was missing was control over what looping *means*.

Before this change the only growth was one hardcoded formula,
`TowerDefenseLogic.waveScale`, applying `1 + 0.35 * loops` to health and reward.
Speed, spawn count, and spawn spacing never changed, so an endless run got
tankier but never busier, and income tracked difficulty exactly.

## Authoring model

Growth is authored per wave set, not per game, so one level can teach gently
while another compounds:

```
waveSet.endless      : boolean
waveSet.loopScaling  : {
    curve            : "Linear" | "Exponential",
    healthPerLoop, rewardPerLoop, speedPerLoop,
    countPerLoop, spacingPerLoop,
    bossEveryWaves,
}
```

Every rate reads as "more difficulty at higher values". `spacingPerLoop` is the
one inverted axis: it is applied as a divisor so a larger number tightens the
gap between spawns. `Linear` adds `rate * loops`; `Exponential` compounds
`(1 + rate) ^ loops`.

`bossEveryWaves` promotes every Nth wave *number* to a boss wave independently
of how many waves the set contains. It marks the wave — HUD copy and the client
boss health bar — and does not inject a boss enemy; authored `isBoss` flags
still win outright.

`endless` is load-bearing in both directions. `true` loops forever and grows.
`false` genuinely ends the run: clearing the last authored wave sets
`match.runComplete`, the HUD switches to a completed state, and `StartTowerWave`
is refused until the player resets or picks another level. Replaying is an
explicit reset rather than an implicit wrap back to wave one. The Studio
playtest jump still targets an exact wave number, so a completed finite set can
still be re-entered for testing without a reset.

## Compatibility

Schema 5 → 6 seeds `endless = true` and the previous ramp verbatim (Linear,
0.35 health, 0.35 reward, everything else zero), so a migrated project plays
identically until a designer edits it. The migration also repairs missing or
wrongly typed curve fields rather than discarding the set, and is idempotent.

`TemplateConfig.towerDefense.waveLoopScaling` re-exports
`StageWaveDefaults.defaultLoopScaling()` rather than restating the numbers; it
is the fallback for pre-schema-6 bundles and for legacy catalog waves. A test
asserts the config references the seed so the two cannot drift.

`TowerDefenseLogic.waveScale` was deleted rather than left beside the new model.
Two difficulty formulas in one codebase is how they diverge.

## Runtime safety

Count growth is the axis that can hurt the simulation, so it is bounded twice:

- `TowerDefenseWaves.buildStreams` spends a shared per-wave budget capped at
  `MAXIMUM_WAVE_SPAWNS`, which a test pins to `StageSchema.MAX_WAVE_SPAWNS`. A
  runaway curve cannot schedule a wave the scheduler was not sized for.
- Speed growth is clamped to `MAXIMUM_SPEED_MULTIPLIER`. Enemies that outrun the
  fixed 20 Hz step would skip past tower ranges between samples.
- Every loop multiplier is clamped to `MAXIMUM_LOOP_MULTIPLIER`. A deep Studio
  jump on an exponential curve therefore stays finite instead of producing an
  immortal infinite-health enemy or a non-finite reward value.

Hitting the per-player enemy cap is now **backpressure, not failure**.
`spawnEnemy` returns `Spawned | Deferred | Failed`; a full field defers, keeps
the stream's pending spawns, and retries once kills make room. Previously the
cap aborted the wave outright, which endless runs would have hit routinely.
`Failed` — unknown enemy type, no spawn node, unroutable graph — still aborts,
and an abort now clears the field because the fixed-step loop skips matches that
are not running. It also republishes the complete tower-defense snapshot so the
HUD leaves its running state at the same time client rigs are retired.

## Progression

Wave sets loop, so clearing wave 1 was unlocking the next level every run. The
next level now unlocks only after `match.wave >= match.waveCount`, i.e. once
every authored wave has been cleared at least once.

`stats.wins` and `stageProgress.clears` still increment per wave cleared. Those
are stored numbers whose meaning would silently change for every existing save
if redefined as "runs" or "loops", and no migration can repair a number whose
units changed. Renaming or re-scoping them is a deliberate profile-migration
decision, not a side effect of this change.

## Tuning surface

The Wave Designer gains an **Endless Growth** panel: endless toggle, curve
toggle, one field per axis, boss cadence, and a preview that reports the
resolved multipliers for a chosen wave number. The preview calls
`TowerDefenseWaves.scalingFor` — the exact runtime function — so it cannot drift
from what the server does.

Playtest can now jump to any wave up to `TowerDefenseRequest.MAX_PLAYTEST_WAVE`
(1000) instead of stopping at the authored set length, because sampling a deep
wave is the only way to judge a curve. The bound stays enforced server-side and
the action remains Studio-and-playtest-catalog only.

## Starter fixtures

The three MVP sets demonstrate three shapes rather than repeating one:

| Set | Curve | Shape |
| --- | --- | --- |
| `mvp_basics` | Linear | health 0.30, reward 0.20 — income tightens slowly |
| `mvp_mixed` | Linear | adds count 0.15 and spacing 0.10 — the stream thickens |
| `mvp_boss` | Exponential | health 0.22, speed 0.04, boss every 3 waves |

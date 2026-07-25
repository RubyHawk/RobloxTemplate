# Dungeon ability character animation + VFX — Roblox API check 2026-07-25

Official Roblox documentation reviewed before adding real character animations and
layered VFX to the dungeon boss-fight hotbar abilities:

- Using animations (LocalScript playback): https://create.roblox.com/docs/animation/using
- `Animator` (owns playback + replication of `AnimationTrack`s): https://create.roblox.com/docs/reference/engine/classes/Animator
- `AnimationTrack` (`Play`, `Stop`, `AdjustSpeed`, `Priority`, `Looped`): https://create.roblox.com/docs/reference/engine/classes/AnimationTrack
- `Animation` (`AnimationId`): https://create.roblox.com/docs/reference/engine/classes/Animation
- Particle emitters (`Emit`, `NumberSequence` size/transparency curves): https://create.roblox.com/docs/effects/particle-emitters
- `Trail` (`Attachment0`/`Attachment1`, `Enabled`): https://create.roblox.com/docs/reference/engine/classes/Trail
- Custom particle VFX tutorial (layering emitters/trails/beams): https://create.roblox.com/docs/tutorials/use-case-tutorials/vfx/custom-particle-effects

## Confirmed current API

- Play a character animation from a client script by resolving the character's
  `Humanoid`, then its child `Animator` (`humanoid:WaitForChild("Animator")`), then
  `animator:LoadAnimation(animation)` to get an `AnimationTrack`, then `track:Play()`.
  `Animator:LoadAnimation` is the current method; the older `Humanoid:LoadAnimation`
  is legacy. An `Animation` instance requires `AnimationId = "rbxassetid://<id>"`.
- Animations started on the local player's character `Animator` replicate to the
  server and other clients, so this stays a client-presentation concern.
- A `Trail` renders between `Attachment0` and `Attachment1` and is shown/hidden by
  toggling `Enabled`; it is a valid child of a `BasePart`.
- `ParticleEmitter:Emit(count)` fires a one-shot burst regardless of `Enabled`;
  `Size`/`Transparency` `NumberSequence` curves shape the burst. Layered VFX (a
  swing trail + a weapon burst + an impact burst) read better than one emitter.

## Decisions (why this repo does it this way)

- **Animation asset IDs are never fabricated.** Real skeletal animations require
  Studio Animation Editor assets published to Roblox. Per the template's integration
  rules (IDs absent -> visible fallback, never fake success; never hardcode asset
  IDs in services), each ability carries an optional `animationId` in
  `DungeonConfig` that defaults to `0`. A recipe or artist sets real published ids
  through `DesignerConfig.dungeon.abilities[...].animationId`.
- **When `animationId > 0`,** the client plays the real `AnimationTrack`. **When it
  is `0`,** the client falls back to the existing procedural `Motor6D` pose so the
  ability always animates with zero uploaded assets. Reduced motion skips both.
- **The client never constructs instances.** It cannot `Instance.new("Animation")`
  (a dungeon-client invariant enforced by the spec suite), so the `Animation`
  vessels are pre-authored under `ReplicatedStorage/Template/DungeonAnimations`
  (one per ability id, empty `AnimationId`). The client sets each vessel's
  `AnimationId` from config, then `LoadAnimation`s it once per character spawn.
- **VFX are pre-authored and only toggled/emitted at runtime.** A per-weapon
  `AbilityTrail` (with two authored attachments whose refs are assigned at bind
  time, since Rojo `.model.json` does not serialize instance-ref properties) is
  enabled during a swing; a per-weapon `AbilityBurst` emitter and a boss-core
  `AbilityImpact` emitter are recolored to the ability tint and `Emit`ted. Nothing
  is cloned or destroyed.
- **The bottom-center HUD is mode-exclusive.** The Figma-mapped `DungeonHUD`
  authors a responsive four-slot ability bar at the same safe-area anchor as the
  Figma-mapped `TowerDefenseLoadoutHUD`. Dungeon presentation explicitly
  suppresses the tower loadout root, so unit slots and inventory/dice/upgrade
  controls cannot overlap the ability bar during a boss fight.

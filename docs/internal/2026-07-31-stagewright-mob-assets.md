# Stagewright mob assets and animations — 2026-07-31

## Workflow

A mob is a Model under `ReplicatedStorage.Template.EnemyRigs`. Drop a character
asset into that folder and it becomes selectable — there is no registration step
and no separate catalog to keep in sync.

In the Wave Designer's **Enemy Types** panel the model is chosen with the
`< Mob` / `Mob >` picker, which cycles the rigs discovered in the live Studio
tree. The field stays editable so a project can reference a rig that is not in
this Studio session yet. A status line under the picker reports what the runtime
will actually render, including the fallback case, so a typo is visible while
authoring instead of at playtest.

Health, display name, tags, speed, reward, base damage, and render scale are
edited in the same panel and are unchanged by this work.

## Animations

Two sources, in priority order:

1. **Authored override** — `enemyType.animations.walkId` / `.deathId`, set in the
   designer. Accepts a bare numeric asset id or a full `rbxassetid://` URI; both
   normalize to the URI form through `StageSchema.normalizeAssetId`, so the same
   animation pasted two ways is one stored value.
2. **The rig's own declaration** — an `Animations` folder inside the rig model
   holding `Animation` instances named `Walk` and `Death`. This is where a
   designer building the asset naturally puts them, so a well-built character
   needs no authoring at all.

Blank ids mean "use whatever the rig declares", which is why the schema 6 → 7
migration seeds blanks: no existing rig changes how it renders.

**Use rig animations** copies the selected rig's declared ids into the override
fields, which is the quickest way to see what an asset ships with.

## Runtime

`StageEnemyRenderer` binds tracks once per cloned rig and caches them against
the model, so pooled reuse costs no reload. Walk is looped and plays on spawn;
death plays once on retire, alongside the existing poof, before the rig returns
to its pool. Walk uses Roblox's `Movement` animation priority and death uses
`Action`, so an asset's idle track cannot silently win over either state.

Animator resolution prefers what the asset already has — a `Humanoid`, then an
`AnimationController`. One is only created when animations exist and the rig has
no controller, so simple part rigs are never given machinery they do not use.
A declared `Animation` instance is loaded as-is; only an override creates an
instance, and it is parented into the rig rather than built and discarded, which
also keeps the renderer within its "clone authored rigs, do not construct"
contract.

A failed animation load warns once per asset id and leaves the mob rendering
without that track. A `modelId` naming a rig that is not present warns once per
rig name and renders `Fallback`; warnings are deduplicated so a large wave does
not flood Studio output. Missing rigs previously fell back silently.

## Boundaries

`Waves/Model.luau` stays pure — it never reads the Studio tree, and authored
data stores only the rig's **name**. Live discovery lives in
`Waves/RigCatalog.luau`, which the view uses and the model does not. A test
asserts the pure model contains no `RigCatalog` reference, so project data can
never come to depend on a Studio session.

`StageExport.ENEMY_TYPE_FIELDS` had to carry `animations` deliberately; it is an
explicit whitelist, and a field missing from it is silently dropped between
authoring and runtime with no error anywhere. A bake test pins it.

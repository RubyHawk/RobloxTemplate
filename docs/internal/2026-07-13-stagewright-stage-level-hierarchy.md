# Stagewright stage/level hierarchy

Date: 2026-07-13

## Decision

The existing stable `StageDefinition.id` remains the identity of one playable
level so schema-7 profile keys and saved `selectedStageId` values stay valid.
Authoring schema v3 adds three explicit hierarchy fields:

- `stageGroupId`: immutable identity shared by the levels in one stage group.
- `stageNumber`: editable display order for the stage group.
- `levelNumber`: editable order inside that group.

This flat-storage/hierarchical-view design avoids rewriting saved profile keys,
route predicates, transition references, and runtime stage IDs. Schema-v2
projects migrate each former flat stage into its own group as Level 1. The
configured one-level starter project is then seeded once to ten levels; projects
that already contain multiple authored stages are never expanded implicitly.

## Runtime ownership

`StageRuntimeService` remains server-authoritative for activation and unlocks.
It publishes the validated active level ID through the owning slot's replicated
`CFrameValue`. Each client uses that server value to rebuild only the matching
island visual. Definitions are shared immutable catalog data, while progression,
combat, towers, enemies, and active level selection remain per-player state.

Clearing a level unlocks the next catalog entry only for that player's profile.
The stable starting ID remains `stage_default`, so existing schema-7 profiles
continue to resolve to Stage 1 / Level 1 without another profile migration.

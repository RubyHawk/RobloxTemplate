# Stagewright migration and production QA

Stagewright uses four intentionally different surfaces:

- Shared authoring source: place `128136881672145`, universe `10479279603`. This is where Team Create-only legacy cells and route controls must be imported.
- Repository artifact: `stage-data/stagewright-project.json` plus `StageCatalog.generated.luau`. This is the deployable source of truth after export/import.
- Production scenery: the existing Team Create world. Team Create exclusively owns every island, bridge, upgrade area, and other map-scene object; the guarded RNG patch owns no map scenery.
- Runtime sandbox: the permanent `playerTest` experience. Use the `tower-defense` recipe so live QA never mutates the shared authoring place accidentally.

The RNG recipe stores the logical layout center `(0, 15.5, 0)`. The configured slot-1 offset and yaw define the first 32×27 playable grid footprint; slots 2–6 rotate that complete local frame around the center in 60-degree steps. The movable authoring `GamePlatform` and Team Create scenery are deliberately not runtime anchors for this recipe.

There is one canonical admin `GamePlatform`, not six raw copies. `StagePlatformService` assigns six server-authoritative runtime slots, and the exported stage data is transformed independently at those logical origins. Missing or invalid layout configuration must continue to fail closed; assigning a slot without a valid origin would only manufacture a misleading platform.

No workflow below creates a Roblox experience.

## RNG Defender recovery after an incorrect Rojo sync

Do not run bare `rojo serve` from the repository root against RNG Defender. The
root gallery project is now restricted to the permanent template place, while
`8_RNG_DEFENDER.cmd` remains the only supported gameplay delivery launcher.

If the gallery project was previously connected, close Studio, run
`8_RNG_DEFENDER.cmd`, and reopen the existing RNG Defender place. Stagewright
waits for the exact RNG Defender DesignerConfig and then records one undoable
edit that removes the known gallery roots (`PlayableStarter`,
`PlayableStarterClient`, the gallery spawn/floor/earning pads, gallery preview
GUIs, and the gallery loading script). It never deletes
`Workspace.FirstPrivateIsland` or unknown Team Create scenery. The useful
legacy `GamePlatform` is moved to `Workspace.StagewrightAdminArea` first; only
an exact second demo-shaped copy on the island is removed.

After Rojo connects, press Play. The permanent bottom-right **Tower Defense -
Level Select** panel lists Levels 1-10 with server-derived lock state. The
minimal playable loop is **Roll Unit**, **Auto-place Best**, **Start Next
Wave**, and **Reset Run**. The existing top **Go to My Tower** control moves
the player to their assigned grid. Level changes, unit rolls, placements, and
wave starts all continue through the existing server-authoritative remotes.

## 1. Import the shared place safely

1. Close any Rojo session connected to the shared tower-defense place.
2. Optionally use Studio's **File → Download a Copy** before the first migration.
3. Run `7_STAGEWRIGHT_SHARED.cmd`.
4. The launcher installs the local Stagewright plugin and opens the existing shared place without starting Rojo.
5. Open **Plugins → Stagewright**. The plugin moves the existing `FirstPrivateIsland.GamePlatform` intact into the open-front white `Workspace.StagewrightAdminArea`, 1,000 studs below and 3,000 studs outside the map footprint. If the place has no `ServerStorage.StagewrightProject`, Stagewright imports that admin platform once.
6. Confirm before editing:
   - The existing Team Create islands, bridges, upgrade areas, and all other map scenery remain intact. No repository-owned `Workspace.StagewrightPlayableWorld` should appear when the safe patch connects.
   - **Stage → Focus Admin** frames the white authoring room and the main `GamePlatform` remains visible inside it. From the production map, the room is too deep to show through water or island gaps.
   - **Island Guides: On** shows the complete cyan 32×27 cell grid on all six beaches. No unexplained orange orientation line should cross an island. Toggle it off and on without changing authored stage data.
   - Start a Server + Client test and confirm `StagewrightAdminArea` moves to `ServerStorage` for the running session. The white room and its legacy grid cannot appear through the world during Play; Studio restores the editor copy when the test stops.
   - `FirstPrivateIsland` no longer owns the editable `GamePlatform`; the six logical grid origins remain unchanged because they come from the configured center, slot-1 offset, slot-1 yaw, and 60-degree rotations.
   - Every legacy `#` remains an authored `Blocked` cell.
   - `P`, `G`, and `A` appear as independent roles.
   - If `P` is absent but path controls exist, `Control_001` becomes the explicit inferred spawn and the validation panel reports that migration decision.
   - Legacy `PathPoints` appear as a sequential local-space graph.
   - Additional portals/goals appear as `NeedsRepair` nodes and validation errors rather than disappearing.
   - Moving `GamePlatform` does not change stored node coordinates.

Do not connect the `rng-defender-grid-demo` Rojo patch during the first legacy-authoring import. Keep that pass Rojo-free so Team Create-only cells and route controls can be exported before repository-managed gameplay code is synchronized. After review, the safe patch still owns no map scenery: it does not own `FirstPrivateIsland`, any island/bridge/upgrade model, or any other Team Create map root. It synchronizes gameplay code, authored Stagewright data, portal assets, the configured independent UI pack, and the logical layout configuration only. Use the guarded delivery workflow below only after import and repository review are complete.

## 2. Studio interaction checklist

- Confirm the browser starts with **Map 1 → Stage 1 → Level 1** through **Level 10**. All ten begin as independent copies of the same playable grid and graph.
- Select **+ Map**; verify a new Map appears with its own Stage 1 / Level 1 and independent Map Properties.
- Select **+ Stage**; verify a new stage group appears with its own Level 1 and stable group ID.
- Select **+ Level**; verify the selected level is copied into the next number inside the same stage group.
- Import a pathless 16:9 map PNG through Asset Manager, copy its image ID, paste it into **Map Properties → Backdrop image asset ID**, and apply. Confirm the image fills the World Path background while every road still comes from the live spline renderer.
- Switch among Levels and Stages in the same Map and confirm they share that backdrop but retain independent nodes and splines. Switch Maps and confirm each Map has its own backdrop.
- Confirm a Stage appears under exactly one Map and that a Map can contain at least 15 Stages without selector or browser clipping.
- Collapse the World Path inspector and confirm the map reclaims the freed height without changing pointer alignment; expand it and exercise every existing spline and node control.
- Clear the backdrop ID and undo/redo the edit. Confirm the direct UI image disappears while hand-authored Workspace scenery remains untouched.
- Use **Focus Admin** and verify all 3D graph handles appear inside `Workspace.StagewrightAdminArea`, not on a player island.
- Copy a level; verify level, graph, node, and edge IDs change while copied references still work.
- Reorder levels; verify IDs do not change.
- Paint terrain, build policy, traversal policy, and roles across one drag; undo and redo the entire gesture.
- Resize smaller; verify the truncation count and second-click confirmation, then undo.
- Try deleting a referenced stage; verify the inbound-reference diagnostic blocks deletion.
- Add one or two spawn nodes, connect both branches into the same junction, and continue that merged route to a goal.
- Select any edge using a lane profile and switch between **1 Lane**, **2 Lanes**, and **3 Lanes**. Confirm the 3D preview immediately shows the same number of parallel splines.
- Move nodes and gold Bézier handles in 3D; undo and redo each movement.
- Create branches with conditions plus exactly one fallback.
- Exercise every predicate using Graph context fields: wave, flags, tags, currency, upgrades, and unlocked stages.
- Trace a route and confirm green preview edges match the expected branch.
- Author a bounded loop with `VisitCountBelow`; verify an unbounded loop blocks export.
- Reload during a paint or graph movement and confirm the recording finalizes and previews are cleaned up.
- Save, close Studio, reopen, and confirm the payload checksum and previews recover.

### Fast mob-wave playtest loop

For iteration in the existing RNG Defender place, connect the guarded patch with
`8_RNG_DEFENDER.cmd`, edit the selected level in **Waves**, and click
**Prepare Playtest**. The action validates and bakes the current working copy
into `ReplicatedStorage.Template.StagewrightPlaytestRuntime`; it does not replace
the repository export/import workflow.

Press Play after preparing. The Studio-only **Stagewright • Mob Playtest** HUD
shows the prepared source checksum and can run any wave from Levels 1–3, or
reset the current wave immediately. Each run session-selects its level and goes
through the real server spawn scheduler, route graph, lane assignment, enemy
rigs, damage, and client renderer. These runs do not save level selection, wins,
losses, best wave, clears, or unlocks. Stop Play, change Stagewright data,
prepare again, and confirm the next Play session shows the new checksum.

### Endless growth

Authored wave sets loop forever; **Endless Growth** in the Wave Designer is what
each completed loop multiplies. Verify:

1. The panel's preview multipliers for a chosen wave number match what the run
   actually does at that wave. The preview calls the same runtime function.
2. Wave selection in the playtest HUD is not capped at the authored wave count
   for an endless set. Jump past the set length and confirm the label reports the
   loop number, then run that wave and watch the curve applied for real.
3. A `countPerLoop` curve visibly thickens the stream at deep waves, and a
   `spacingPerLoop` curve tightens it, without the wave ever scheduling more than
   the 500-spawn cap.
4. Drive a level to the per-player enemy cap. Spawning must pause and resume as
   towers make room; the wave must not abort and the field must not be wiped.
5. With `bossEveryWaves` set, confirm every Nth wave number reports as a boss
   wave in the HUD even though the authored set is shorter than N.
6. Clearing wave 1 must **not** unlock the next level. The unlock lands only
   after every authored wave in the set has been cleared.
7. The lobby HUD shows a bare wave number (with the loop once past loop 1) for an
   endless set, and `wave/count` only for a set marked not endless.
8. Turn **Endless: OFF** on a set, then clear its last authored wave. The run
   must end: the HUD reports the level complete, Start Wave is disabled, and only
   Reset (or another level) starts play again. Turn it back on and confirm the
   same set loops past its last wave instead.

### Mob assets and animations

1. Drop a character Model into `ReplicatedStorage.Template.EnemyRigs`, then use
   `< Mob` / `Mob >` in **Enemy Types** to select it. The status line must name
   the rig, its part count, and whether it has an animator.
2. Point a mob at a rig name that does not exist and confirm the status line says
   the fallback will render. Run it and confirm the server warns rather than
   silently swapping the rig.
3. On a rig with an `Animations` folder holding `Walk` and `Death`, leave both id
   fields blank and confirm the animations still play. Press **Use rig
   animations** and confirm the declared ids appear in the fields.
4. Paste an animation id as a bare number in one field and as
   `rbxassetid://<id>` in the other; both must store and reload identically.
5. Enter an unusable animation id and confirm the designer refuses the edit with
   a message rather than writing it.
6. Confirm edited health, name, tags, speed, reward, and render scale reach the
   running mob, and that a scaled rig keeps its health bar above the model.

The separate **Your Tower • Platform 01** travel strip is available in every
tower-defense lobby, including Studio sessions without a prepared playtest
snapshot. Select **Go to My Tower** and confirm the server moves the player onto
their assigned playable grid. The strip must show `Platform unavailable`
instead of moving the character if the authoritative six-platform layout cannot
be resolved.

## 3. Export into the repository

1. Resolve every export-blocking validation error.
2. Choose **Validate → Export Bundle** and save the RBXM outside the repository.
3. Import it from the repository root:

   ```powershell
   lune run scripts/stagewright-import.luau "C:\path\to\StagewrightBundle.rbxm"
   ```

   Current bundles contain both authoring and baked runtime payloads. The plugin
   rereads both payloads before opening the save prompt, and this command rebakes
   the authoring data and rejects a saved file whose embedded runtime differs.
   Older authoring-only bundles remain importable and print a legacy notice.

   The same command also accepts the original legacy `GamePlatform` RBXM. It detects the absence of `StagewrightPayload`, imports `CellMap` and `PathPoints`, and prints every inferred endpoint decision.

4. Review changes under `stage-data/` and `src/shared/StageCatalog.generated.luau`.
5. Run `lune run scripts/stagewright-import.luau stage-data/stagewright-project.json --check`.

Import or export cancellation must leave both Studio and repository state unchanged.

## 4. Deliver gameplay to the permanent RNG Defender place

After the Stagewright export/import diff and automated checks pass, run:

```powershell
8_RNG_DEFENDER.cmd
```

This launcher validates universe `10479279603`, place `128136881672145`, and the patch's single `servePlaceIds` entry before opening Studio or serving files. In Studio, connect **Plugins > Rojo**, stop and restart Play, and verify the in-place portal simulation, dungeon arena, combat, HUD, and simulated return. Publish with **File > Publish to Roblox** on this same place; never use **Publish As**.

After connecting, verify that all Team Create island, bridge, upgrade, and other map scenery is unchanged and that Rojo has not added a repository-owned `Workspace.StagewrightPlayableWorld`. Confirm `StagePlatformOrigins.LayoutSource` reports the configured center and that the six derived 32×27 grid footprints line up with the existing first-island play areas. They must not be implemented as clones of `StagewrightAdminArea.GamePlatform`.

Studio cannot execute `TeleportAsync`. After publishing, join RNG Defender through the Roblox client and separately verify the real reserved-server entry, a complete party fight/reward, and the return teleport to the public lobby. The roundtrip is not considered validated until this published-client check passes.

Do not open or publish `build/RNGDefenderSafePatch.rbxlx`. That artifact is only a structural validation build and intentionally omits unknown Team Create world data; it contains no production map scenery.

## 5. Runtime QA in playerTest

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sandbox.ps1 -RecipePath config-presets/tower-defense.json
```

In Studio:

1. Connect Rojo and use **Test → Start** with six players, one for each island platform.
   - Confirm the white admin room, Edit-mode island guides, Stagewright widget, and any legacy `Edit Grid` control are absent from every player client.
   - Confirm every island has a visible ownership card. Occupied cards show the avatar, display name, username, and platform number; the local player's card says `YOUR PLATFORM`.
   - Confirm unoccupied islands say `AVAILABLE`.
   - In each client, confirm that client's grid, route, and ownership card remain fully visible while the other five playable island platforms are faded.
   - Published or real multi-account tests show each account's Roblox display name, username, and headshot. Studio's synthetic multi-client players use negative test IDs, so they show their Studio test name and a `TEST` avatar instead of impersonating a real account.
   - Confirm `ReplicatedStorage.Template.StagePlatformOrigins` reports `SlotCount = 6`, `LayoutAvailable = true`, `ServerMaxPlayers = 6`, and `CapacityMatchesSlotCount = true`.
2. Confirm `Workspace.StagewrightClientGrids` contains `Platform_01` through `Platform_06` in every client. These runtime grids appear only after Play starts and remain on the six islands even though the editor platform lives in the admin room below the map.
3. Confirm each island shows a clearly visible cyan cell grid above the grass plus the same dual-approach route with two distinct orange lanes, two green spawns, one red goal, blue auto-place markers, and no overlapping legacy slot-1 grid.
4. Activate different Stage 1 levels for different players. Confirm each slot's replicated `ActiveStageId` changes only for its owner and every client redraws that one island from the matching level definition.
5. Start waves with different currencies/upgrades/flags and confirm server-selected branches.
6. Attempt malformed, locked, and disabled stage IDs; out-of-range placements; repeated requests; and client-supplied route outcomes. All must fail server-side.
7. Confirm enemies alternate deterministically across every authored spawn. With the production fixture, both outer spawns feed their own branch and merge at `Spawn Merge`.
8. Confirm pooled enemies alternate across the configured 1–3 lanes, keep their lateral lane through each edge profile, orient through elevation, and correct smoothly after network delay.
9. Stream the platform out and back; authoritative wave state must continue and visuals must recover because slot CFrames live in ReplicatedStorage.
10. Rejoin with a schema 6 profile fixture and confirm schema 7 migration preserves unit/loadout/stat data.
11. Clear Level 1 for one player and confirm only that profile unlocks Level 2. Confirm one player's level, towers, enemies, currencies, unlocks, and flags never affect another player.

Before live tower-defense testing, open **File > Game Settings > Places > ... > Configure Place** and set **Maximum Players** to `6`. Roblox then admits at most six players to each server and creates additional servers for further players. Platform-exclusive recipes reject a player before profile loading if no authoritative platform is available, so nobody can remain in gameplay without an island.

RNG Defender is currently an explicit hybrid-lobby exception: `towerDefense.requirePlatformOnJoin = false` allows the rune lobby and reserved dungeon flow to remain available if the logical platform layout is missing or invalid. Tower-defense activation, placement, and wave requests still fail server-side until the configured center can produce all six authoritative slot origins. This fail-closed behavior is intentional and must not be bypassed by synthesizing, sharing, or cloning an admin platform origin.

Use MicroProfiler captures for the agreed device/server baseline. The pure local gate checks:

- 256×256 dense-grid validation under 1 second.
- 1,000-node/1,500-edge validation under 1 second.
- 500-enemy route sampling at 20 Hz under 8 ms per update.
- Six-platform, 3,000-enemy route sampling under 30 ms per 20 Hz update.
- 900 visible-cell incremental mutations under 16 ms.

## 6. Automated acceptance

`3_CHECK.cmd` runs formatting, lint, deterministic parity, Rojo/recipe builds, plugin/runtime artifact inspection, Luau assertions, performance budgets, worker tests, and skill validation.

The final manual sign-off items are this Studio checklist, the six-player playerTest run, StreamingEnabled recovery, and device/server MicroProfiler captures.

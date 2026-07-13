# Stagewright migration and production QA

Stagewright uses three intentionally different surfaces:

- Shared authoring source: place `128136881672145`, universe `10479279603`. This is where Team Create-only legacy cells and route controls must be imported.
- Repository artifact: `stage-data/stagewright-project.json` plus `StageCatalog.generated.luau`. This is the deployable source of truth after export/import.
- Runtime sandbox: the permanent `playerTest` experience. Use the `tower-defense` recipe so live QA never mutates the shared authoring place accidentally.

The production world uses `center_grass` as its center. The configured slot-1 offset defines the first playable island; slots 2–6 rotate that local frame around the center in 60-degree steps. The movable authoring `GamePlatform` is deliberately not a runtime anchor.

No workflow below creates a Roblox experience.

## 1. Import the shared place safely

1. Close any Rojo session connected to the shared tower-defense place.
2. Optionally use Studio's **File → Download a Copy** before the first migration.
3. Run `7_STAGEWRIGHT_SHARED.cmd`.
4. The launcher installs the local Stagewright plugin and opens the existing shared place without starting Rojo.
5. Open **Plugins → Stagewright**. The plugin moves the existing `FirstPrivateIsland.GamePlatform` intact into the open-front white `Workspace.StagewrightAdminArea`, 1,000 studs below and 3,000 studs outside the map footprint. If the place has no `ServerStorage.StagewrightProject`, Stagewright imports that admin platform once.
6. Confirm before editing:
   - **Stage → Focus Admin** frames the white authoring room and the main `GamePlatform` remains visible inside it. From the production map, the room is too deep to show through water or island gaps.
   - **Island Guides: On** shows the complete cyan 32×27 cell grid on all six beaches. No unexplained orange orientation line should cross an island. Toggle it off and on without changing authored stage data.
   - Start a Server + Client test and confirm `StagewrightAdminArea` moves to `ServerStorage` for the running session. The white room and its legacy grid cannot appear through the world during Play; Studio restores the editor copy when the test stops.
   - `FirstPrivateIsland` no longer owns the editable `GamePlatform`; the six island origins remain unchanged because they come from `center_grass` plus configuration.
   - Every legacy `#` remains an authored `Blocked` cell.
   - `P`, `G`, and `A` appear as independent roles.
   - If `P` is absent but path controls exist, `Control_001` becomes the explicit inferred spawn and the validation panel reports that migration decision.
   - Legacy `PathPoints` appear as a sequential local-space graph.
   - Additional portals/goals appear as `NeedsRepair` nodes and validation errors rather than disappearing.
   - Moving `GamePlatform` does not change stored node coordinates.

Do not connect the legacy `rng-defender-grid-demo` Rojo patch during this import. It contains a repository copy of the island and is not the Team Create source of truth.

## 2. Studio interaction checklist

- Create a blank stage; verify the original stage is unchanged.
- Use **Focus Admin** and verify all 3D graph handles appear inside `Workspace.StagewrightAdminArea`, not on a player island.
- Duplicate a stage; verify stage, graph, node, and edge IDs change while copied references still work.
- Reorder stages; verify IDs do not change.
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

## 3. Export into the repository

1. Resolve every export-blocking validation error.
2. Choose **Validate → Export Bundle** and save the RBXM outside the repository.
3. Import it from the repository root:

   ```powershell
   lune run scripts/stagewright-import.luau "C:\path\to\StagewrightBundle.rbxm"
   ```

   The same command also accepts the original legacy `GamePlatform` RBXM. It detects the absence of `StagewrightPayload`, imports `CellMap` and `PathPoints`, and prints every inferred endpoint decision.

4. Review changes under `stage-data/` and `src/shared/StageCatalog.generated.luau`.
5. Run `lune run scripts/stagewright-import.luau stage-data/stagewright-project.json --check`.

Import or export cancellation must leave both Studio and repository state unchanged.

## 4. Runtime QA in playerTest

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
4. Activate stages independently for different players.
5. Start waves with different currencies/upgrades/flags and confirm server-selected branches.
6. Attempt malformed, locked, and disabled stage IDs; out-of-range placements; repeated requests; and client-supplied route outcomes. All must fail server-side.
7. Confirm enemies alternate deterministically across every authored spawn. With the production fixture, both outer spawns feed their own branch and merge at `Spawn Merge`.
8. Confirm pooled enemies alternate across the configured 1–3 lanes, keep their lateral lane through each edge profile, orient through elevation, and correct smoothly after network delay.
9. Stream the platform out and back; authoritative wave state must continue and visuals must recover because slot CFrames live in ReplicatedStorage.
10. Rejoin with a schema 6 profile fixture and confirm schema 7 migration preserves unit/loadout/stat data.
11. Confirm one player's stage, towers, enemies, currencies, unlocks, and flags never affect another player.

Before live testing, open **File > Game Settings > Places > ... > Configure Place** and set **Maximum Players** to `6`. Roblox then admits at most six players to each server and creates additional servers for further players. The server also rejects a player before profile loading if no authoritative platform is available, so nobody can remain in gameplay without an island.

Use MicroProfiler captures for the agreed device/server baseline. The pure local gate checks:

- 256×256 dense-grid validation under 1 second.
- 1,000-node/1,500-edge validation under 1 second.
- 500-enemy route sampling at 20 Hz under 8 ms per update.
- Six-platform, 3,000-enemy route sampling under 30 ms per 20 Hz update.
- 900 visible-cell incremental mutations under 16 ms.

## 5. Automated acceptance

`3_CHECK.cmd` runs formatting, lint, deterministic parity, Rojo/recipe builds, plugin/runtime artifact inspection, Luau assertions, performance budgets, worker tests, and skill validation.

The final manual sign-off items are this Studio checklist, the six-player playerTest run, StreamingEnabled recovery, and device/server MicroProfiler captures.

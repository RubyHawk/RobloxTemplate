# Stage platform ownership and capacity check — 2026-07-13

Stagewright's production world is one complete six-island layout per Roblox server. The place must have **Maximum Players** set to `6`, matching `TemplateConfig.towerDefense.platformSlotCount`. Roblox handles additional concurrency by creating more server instances, each with a fresh six-slot layout.

Team Create exclusively owns the persistent central island, six player islands, bridges, upgrade areas, and every other map-scene object. The guarded RNG patch owns no map scenery and must not add `Workspace.StagewrightPlayableWorld`, a converted `SixIslandWorldLayout`, or replacement island models.

The RNG repository owns only the configured logical center `(0, 15.5, 0)` and the layout math. The measured slot-1 offset and center-facing yaw place the first 32×27 logical grid footprint; rotating that complete frame around the center in 60-degree increments produces slots 2 through 6. These are gameplay transforms over the existing Team Create world, not physical platform copies.

The runtime keeps a second safety boundary: `StagePlatformService` assigns each player one unique server-authoritative slot, publishes sanitized ownership fields on the slot's replicated `CFrameValue`, and releases the slot when the player leaves. Platform-exclusive recipes reject admission before profile loading if no valid platform exists. An explicit hybrid-lobby recipe may set `towerDefense.requirePlatformOnJoin = false`; that admits the player to non-tower-defense systems but does not manufacture a slot, and all tower-defense actions remain unavailable until an authoritative layout exists. Clients only render the published assignment; they never choose or submit a platform.

The missing-layout behavior is intentionally fail-closed. `TowerDefensePlatformSlot` must remain unset when configuration cannot produce a valid layout and no unambiguous compatibility center is available. Reusing one origin, synthesizing a slot, or cloning `StagewrightAdminArea.GamePlatform` would break player isolation and is not an acceptable fallback. The admin model remains the single canonical authoring source; exported level data is transformed independently through `Slot_01` to `Slot_06`.

Six permanent `BillboardGui` cards are authored under `StarterGui.StagePlatformOwners`. Runtime code sets their `Adornee`, text, visibility, and avatar image without creating or cloning GUI instances. Empty islands remain visibly labeled `AVAILABLE`, while the local owner's card says `YOUR PLATFORM`.

Each client renders its inherited grid and route at full opacity and fades all five non-owned platforms. Occupied ownership cards read the server-published `Player.DisplayName`, `Player.Name`, and `Player.UserId`, and load the real `AvatarHeadShot`. Studio's synthetic server-and-client players have negative test IDs and no Roblox account or avatar; the UI labels those honestly as `TEST` rather than displaying an unrelated user's image. Published sessions and real multi-account tests use real names and headshots.

Official Roblox documentation checked on July 13, 2026:

- [Players API](https://create.roblox.com/docs/reference/engine/classes/Players) — `Players.MaxPlayers` is read-only and `Players:GetUserThumbnailAsync()` returns the player thumbnail used by the ownership card.
- [Experience Settings](https://create.roblox.com/docs/studio/experience-settings) — maximum players is a place-specific setting configured through **Places > Configure Place** rather than assigned by a server script.

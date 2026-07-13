# Stage platform ownership and capacity check — 2026-07-13

Stagewright's production world is one complete six-island layout per Roblox server. The place must have **Maximum Players** set to `6`, matching `TemplateConfig.towerDefense.platformSlotCount`. Roblox handles additional concurrency by creating more server instances, each with a fresh six-slot layout.

The runtime keeps a second safety boundary: `StagePlatformService` assigns each player one unique server-authoritative slot, publishes sanitized ownership fields on the slot's replicated `CFrameValue`, releases the slot when the player leaves, and rejects gameplay before profile loading if no valid platform exists. Clients only render the published assignment; they never choose or submit a platform.

Six permanent `BillboardGui` cards are authored under `StarterGui.StagePlatformOwners`. Runtime code sets their `Adornee`, text, visibility, and avatar image without creating or cloning GUI instances. Empty islands remain visibly labeled `AVAILABLE`, while the local owner's card says `YOUR PLATFORM`.

Each client renders its inherited grid and route at full opacity and fades all five non-owned platforms. Occupied ownership cards read the server-published `Player.DisplayName`, `Player.Name`, and `Player.UserId`, and load the real `AvatarHeadShot`. Studio's synthetic server-and-client players have negative test IDs and no Roblox account or avatar; the UI labels those honestly as `TEST` rather than displaying an unrelated user's image. Published sessions and real multi-account tests use real names and headshots.

Official Roblox documentation checked on July 13, 2026:

- [Players API](https://create.roblox.com/docs/reference/engine/classes/Players) — `Players.MaxPlayers` is read-only and `Players:GetUserThumbnailAsync()` returns the player thumbnail used by the ownership card.
- [Experience Settings](https://create.roblox.com/docs/studio/experience-settings) — maximum players is a place-specific setting configured through **Places > Configure Place** rather than assigned by a server script.

# Boss rune teleport regression

**Checked:** 2026-07-23

## Official sources

- TeleportService: https://create.roblox.com/docs/reference/engine/classes/TeleportService
- TeleportOptions: https://create.roblox.com/docs/reference/engine/classes/TeleportOptions
- Teleport between places: https://create.roblox.com/docs/projects/teleport

## Regression and decision

The boss-selection PR replaced the portal rune's working
`TeleportAsync(..., ShouldReserveServer = true)` launch with a separate
`ReserveServerAsync` request followed by an access-code teleport. That made
server reservation a new blocking dependency between the completed countdown
and the actual player teleport.

The rune now uses the original one-call reserved-server launch again. Boss
selection stays server-authoritative: the lobby writes `{v, bossId, launchId}`
to the server-only MemoryStore under its generated `launchId` before teleport,
and the destination reads that record only after validating the same launch id
from its bounded party manifest. Client-visible teleport data contains party
coordination and the opaque launch id, not boss or reward authority.

`TeleportAsync` remains server-only, is wrapped in `pcall`, and late failures
continue through the bounded `TeleportInitFailed` retry path. Roblox teleports
cannot be exercised in Studio; Studio continues to run the selected boss
in-place after the authored countdown.

## Regression coverage

- The source contract requires the session write before
  `ShouldReserveServer = true` and the atomic pending-party claim.
- The contract rejects any separate `ReserveServer`/`ReserveServerAsync` call
  on the rune launch path.
- The RNG Defender patch artifact must contain the restored
  `ShouldReserveServer` marker.

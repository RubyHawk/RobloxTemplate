# Teleport / reserved servers / MemoryStore — platform doc check

**Checked:** 2026-07-21 (rechecked for the RNG Defender delivery/runtime repair)

## Sources
- TeleportService — https://create.roblox.com/docs/reference/engine/classes/TeleportService
- TeleportOptions — https://create.roblox.com/docs/reference/engine/classes/TeleportOptions
- Teleporting between places — https://create.roblox.com/docs/projects/teleport
- DataModel (PrivateServerId / PrivateServerOwnerId) — https://create.roblox.com/docs/reference/engine/classes/DataModel
- MemoryStoreService — https://create.roblox.com/docs/reference/engine/classes/MemoryStoreService

## What is current (2026-07)

- **`TeleportService:ReserveServer(placeId)` is DEPRECATED.** Use
  `ReserveServerAsync(placeId): (accessCode: string, privateServerId: string)`,
  or — preferred — reserve inline through `TeleportOptions`.
- **Preferred party teleport (one call):**
  ```lua
  local options = Instance.new("TeleportOptions")
  options.ShouldReserveServer = true          -- reserve a fresh private server
  options:SetTeleportData({ ... })            -- coordination data only
  local result = TeleportService:TeleportAsync(game.PlaceId, party, options)
  -- result.PrivateServerId, result.ReservedServerAccessCode
  ```
  Passing the whole `party` array in one `TeleportAsync` co-locates them in the
  same reserved server. For later joiners, reuse
  `options.ReservedServerAccessCode = result.ReservedServerAccessCode`.
- **`TeleportToPrivateServer(placeId, accessCode, players, spawnName?, teleportData?, customLoadingScreen?)`**
  is NOT marked deprecated but the `TeleportAsync` + `TeleportOptions` path is the
  documented modern approach; we use `TeleportAsync`.
- **Reserved-server detection (server, at boot):**
  - Public server → `PrivateServerId == ""`, `PrivateServerOwnerId == 0`
  - Reserved server → `PrivateServerId ~= ""`, `PrivateServerOwnerId == 0`  ← dungeon
  - VIP/player-owned → `PrivateServerId ~= ""`, `PrivateServerOwnerId ~= 0`
- **Reading teleport data on arrival:** server `player:GetJoinData().TeleportData`;
  client `TeleportService:GetLocalPlayerTeleportData()`. Roblox documents this
  data as visible to the client and unencrypted. Treat it only as bounded
  coordination data; re-validate its complete shape and never let it choose
  currency, reward amounts, ownership, or other secure state.
- **Custom loading screen:** client `TeleportService:SetTeleportGui(screenGui)`
  before the teleport completes; the GUI is parented to `CoreGui` on the way in.
- **Failure handling:** wrap `TeleportAsync` in `pcall` + bounded retry. A
  successful call can still fail afterward, so every source server must also
  connect `TeleportService.TeleportInitFailed(player, teleportResult,
  errorMessage, placeId, teleportOptions)` and retry only the affected pending
  player with the supplied destination options.
- **Studio:** teleports do not actually run in Studio — guard with
  `RunService:IsStudio()` and simulate (mirrors `AfkService.rollOver`).

## MemoryStore (optional hardening, not in the first slice)
`MemoryStoreService:GetSortedMap(name)` → `SetAsync(key, value, expiration)` /
`GetAsync(key)` / `UpdateAsync`. Keyed by the reserved `PrivateServerId`, it lets
the dungeon server read an authoritative party manifest independent of TeleportData
(defends against access-code guessing / half-joined parties). The current flow
uses strictly validated `TeleportData` only to coordinate expected arrivals.
Boss choice and rewards always come from server-owned configuration; MemoryStore
remains an optional authority hardening step.

## Decisions for this feature
- Same place, dual-mode (lobby vs reserved dungeon) via the detection above.
- One `TeleportAsync` call with `ShouldReserveServer = true` sends the pad party to
  a fresh reserved instance of `game.PlaceId`.
- Server authoritative for occupancy, party, countdown, boss HP, and rewards.

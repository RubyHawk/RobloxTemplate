# Teleport / reserved servers / MemoryStore — platform doc check

**Checked:** 2026-07-22 (rechecked for the authoritative dungeon boss handoff)

## Sources
- TeleportService — https://create.roblox.com/docs/reference/engine/classes/TeleportService
- TeleportOptions — https://create.roblox.com/docs/reference/engine/classes/TeleportOptions
- Teleporting between places — https://create.roblox.com/docs/projects/teleport
- DataModel (PrivateServerId / PrivateServerOwnerId) — https://create.roblox.com/docs/reference/engine/classes/DataModel
- MemoryStoreService — https://create.roblox.com/docs/reference/engine/classes/MemoryStoreService
- MemoryStoreHashMap — https://create.roblox.com/docs/reference/engine/classes/MemoryStoreHashMap
- GlobalDataStore — https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore
- TextChatCommand — https://create.roblox.com/docs/reference/engine/classes/TextChatCommand

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

## MemoryStore boss handoff
`MemoryStoreService:GetHashMap(name)` → `SetAsync(key, value, expiration)` /
`GetAsync(key)`. The lobby explicitly reserves a server, writes the resolved boss
and launch id under the returned `PrivateServerId`, then teleports with the
reserved access code. The destination revalidates the record, launch id, and boss
catalog entry. A missing, expired, malformed, or unavailable record falls back to
the configured default boss. Strictly validated `TeleportData` coordinates only
the expected party and launch identity; it never selects the boss or rewards.

## Global event boss and admin command
- Clearing the global event key uses `GlobalDataStore:RemoveAsync`; `SetAsync`
  remains the write path only when a concrete event record exists.
- The native `TextChatCommand` supplies a server-owned `TextSource.UserId`, but
  the dungeon service still enforces the configured allowlist. The handler also
  validates bounded arguments and applies its own write cooldown.
- An empty event-admin allowlist disables the override and skips the store read,
  so removing every admin cannot leave a persisted event forced without a clear
  path.
- Event-cache startup is bounded. Failed refreshes preserve the last successful
  value briefly, but the forced event is ignored once that cache is 90 seconds
  old, so a store outage cannot keep stale authority indefinitely.

## Decisions for this feature
- Same place, dual-mode (lobby vs reserved dungeon) via the detection above.
- `ReserveServerAsync` obtains the access code and `PrivateServerId`; the lobby
  writes the server-authoritative boss session, then calls `TeleportAsync` with
  `ReservedServerAccessCode`. Teleport retries reuse the same reservation.
- The launch roster is revalidated atomically after reservation/session writes
  and is never silently reduced while retaining a stale full-party manifest.
- Server authoritative for occupancy, party, countdown, boss HP, and rewards.

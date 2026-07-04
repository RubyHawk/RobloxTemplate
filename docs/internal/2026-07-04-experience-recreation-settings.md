# Experience recreation settings — 2026-07-04

## Official documentation checked

- Create and publish experiences and places: <https://create.roblox.com/docs/production/publishing/publish-games-and-places>
- Data stores and Studio API access: <https://create.roblox.com/docs/cloud-services/data-stores>
- Projects and default privacy: <https://create.roblox.com/docs/projects>
- Collaboration permissions: <https://create.roblox.com/docs/projects/collaboration>
- Group ownership and role permissions: <https://create.roblox.com/docs/projects/groups>

Checked on 2026-07-04.

## Permanent experience roles

The team uses two private permanent experiences:

1. `Roblox Template Workbench` is the visual authoring showroom. It always uses mock profiles. Studio API access stays disabled so UI work cannot mutate persistent player data.
2. `Roblox Template Player Test` runs generated playable recipes with real DataStores. Studio API access is enabled only here. Each preset keeps an isolated DataStore namespace.

Both experiences remain private during template development. HTTP requests, third-party sales, place copying, and live external integrations stay disabled. The owner should be the team's Roblox group when both developers need durable access to experiences and uploaded assets; group roles should grant only the required edit, publish, asset, and DataStore permissions.

New experiences start private. Roblox warns that Studio API access reaches the same DataStores as live servers, which is why it is restricted to the dedicated player-test experience.

## Created experience IDs

- Template workbench universe: `10446179596`
- Template workbench start place: `140239777311760`
- Player-test universe: `10446239643`
- Player-test start place: `110706600177579`

The workbench keeps Studio API access disabled. The player-test experience has Studio API access enabled so Studio playtests use its real isolated DataStores.

## Live persistence verification

A Studio playtest reported live mode for universe `10446239643` and profile store `RobloxTemplate_Profile_v1_incremental`. Initial profile and public-profile reads returned the expected not-found response for a brand-new player key.

Stopping the first playtest exposed overlapping `PlayerRemoving` and `BindToClose` release calls: the first call released the session lock, then the second call reported that it no longer owned that same lock. `ProfileService.release` now has a per-player in-flight guard, so the second shutdown path waits for the first instead of issuing a duplicate `UpdateAsync`.

The corrected preset was synced with Rojo 7.7.0 and published as Player Test place version 5. A fresh live Studio start/stop entered LIVE mode for the configured universe and profile store with no session-lock, save, release, or API-access failure.

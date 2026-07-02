# DataDelve Canary

DataDelve Canary is a visual editor for Roblox **DataStores**. It can inspect real saved data; it cannot see the template showroom's in-memory mock data.

## Playable starter: real data

Generated playable starters now select real persistence automatically. There is no hidden code switch to change.

1. Build the selected UI/game preset.
2. Open the generated playable place and publish it as a **separate test experience**.
3. Open **File > Experience Settings > Security**.
4. Enable **Studio Access to API Services**, then save and reopen the published place.
5. Press Play, earn Coins, and stop Play mode so the profile releases and saves.
6. Open **Plugins > DataDelve Canary**.
7. Select `RobloxTemplate_Profile_v1`, then open `player:<your numeric UserId>`.

The value is an envelope. Player data is under `data`; the sibling `lock` is the temporary server session lock and should be `nil` after a clean stop. Do not edit `lock`, `schemaVersion`, receipt keys, or unknown fields.

Other stores are:

| Store | Key format |
| --- | --- |
| `RobloxTemplate_PublicProfiles_v1` | `user:<UserId>` |
| `RobloxTemplate_Feedback_v1` | `user:<UserId>:report:<UnixTime>:<GUID>` |
| `RobloxTemplate_CoinsLeaderboard_v1` | `<UserId>` |

## Template showroom: safe mock data

The large visual template/showroom intentionally stays in memory. Its Output banner starts with `[Template Data] MOCK mode`, and DataDelve will not show changes from that play test. This prevents visual UI work from touching saved player profiles.

In a playable starter, the Output banner says `[Template Data] LIVE`. If setup is incomplete, it now explains whether the place is unpublished or Studio API access is unavailable. The same mode is visible as the `DataStoreMode` attribute on `ReplicatedStorage > Template`.

Roblox Studio accesses the same DataStores as live servers. Use a private test experience, never the production experience, for Studio writes.

Sources checked 2026-07-02:

- [Roblox Data stores documentation](https://create.roblox.com/docs/cloud-services/data-stores)
- [Roblox DataStore best practices](https://create.roblox.com/docs/cloud-services/data-stores/best-practices)
- [DataDelve source and documentation](https://github.com/pinehappi/DataDelve)
- [DataDelve Canary Creator Store listing](https://create.roblox.com/store/asset/17652185888/DataDelve-Canary)

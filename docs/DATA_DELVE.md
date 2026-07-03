# DataDelve Canary

DataDelve Canary is a visual editor for Roblox **DataStores**. It can inspect real saved data; it cannot see the template showroom's in-memory mock data.

## Playable starter: real data

Generated playable starters now select real persistence automatically. There is no hidden code switch to change.

1. Open **Shared Test Experience** and choose the preset.
2. The launcher opens the permanent cloud sandbox; it does not create a new experience.
3. Confirm **File > Experience Settings > Security > Studio Access to API Services** is enabled.
4. Press Play, earn the recipe's primary currency, and stop Play mode so the profile releases and saves.
5. Open **Plugins > DataDelve Canary**.
6. Select `RobloxTemplate_Profile_v1_incremental` or `RobloxTemplate_Profile_v1_rpg`, then open `player:<your numeric UserId>`.

The value is an envelope. Player data is under `data`; the sibling `lock` is the temporary server session lock and should be `nil` after a clean stop. Do not edit `lock`, `schemaVersion`, receipt keys, or unknown fields.

Older sandbox tests may remain in the legacy `RobloxTemplate_Profile_v1` store. They are not deleted, but new preset-isolated tests intentionally start in the suffixed stores so Incremental and RPG cannot overwrite each other.

Other stores are:

| Store | Key format |
| --- | --- |
| `RobloxTemplate_PublicProfiles_v1_<preset>` | `user:<UserId>` |
| `RobloxTemplate_Feedback_v1_<preset>` | `user:<UserId>:report:<UnixTime>:<GUID>` |
| `RobloxTemplate_CoinsLeaderboard_v1_<preset>` | `<UserId>` |

The in-game leaderstat column is named after the recipe's primary currency (for example `Gold` under the RPG recipe). The ordered store name keeps `CoinsLeaderboard` so existing saved rankings stay compatible.

## Template showroom: safe mock data

The large visual template/showroom intentionally stays in memory. Its Output banner starts with `[Template Data] MOCK mode`, and DataDelve will not show changes from that play test. This prevents visual UI work from touching saved player profiles.

In the sandbox, the Output banner says `[Template Data] LIVE`. The exact namespace and profile store are visible as `DataStoreNamespace` and `ProfileStoreName` attributes on `ReplicatedStorage > Template`.

Roblox Studio accesses the same DataStores as live servers. Use a private test experience, never the production experience, for Studio writes.

Sources checked 2026-07-02:

- [Roblox Data stores documentation](https://create.roblox.com/docs/cloud-services/data-stores)
- [Roblox DataStore best practices](https://create.roblox.com/docs/cloud-services/data-stores/best-practices)
- [DataDelve source and documentation](https://github.com/pinehappi/DataDelve)
- [DataDelve Canary Creator Store listing](https://create.roblox.com/store/asset/17652185888/DataDelve-Canary)

# DataDelve Canary

DataDelve Canary is installed in Roblox Studio. It is a visual editor for Roblox **DataStores**; it does not create HUDs, inventory screens, or other GUI objects.

Use it only after publishing a separate private test experience:

1. Open **File > Experience Settings > Security**.
2. Enable **Studio Access to API Services** for the test experience only.
3. Run the game once so the template creates `RobloxTemplate_Profile_v1`.
4. Stop Play mode, open **Plugins > DataDelve Canary**, select that store, and inspect a `Player_<UserId>` profile.

Do not enable Studio API access on the live production experience. Roblox states that Studio accesses the same data as live servers and can overwrite production profiles.

The saved profile contains readable sections for Coins, the `currencies` map, `upgrades`, `unlocks`, `progress`, tutorial flags, `selectedPack`/`selectedTheme`, inventory, boosts, settings, statistics, daily rewards, redemptions, entitlements, social verification, guild reservation, and timestamps. Schema versioning and migrations remain controlled by the template code; do not casually delete unknown fields in DataDelve.

## Predictable canary test data

To inspect deterministic fixtures without touching production, the template can
write seeded profiles to a physically separate store:

1. In `src/shared/TemplateConfig.luau`, set `studio.useCanaryStore = true` and
   `studio.seedCanaryProfiles = true`.
2. Run the game once in Studio (with Studio API access on the **test** experience).
   `ProfileService` now persists to `RobloxTemplate_Profile_v1_canary`, and seeding
   writes `seed:incremental` and `seed:combat` fixtures (see `SeedProfiles.luau`).
3. In DataDelve Canary, open `RobloxTemplate_Profile_v1_canary` and inspect those
   keys; their values are fixed every run, so they are easy to diff.

The production store name is never used while `useCanaryStore` is on. Keep both
flags `false` on the live experience.

Sources:

- [Roblox Data stores documentation](https://create.roblox.com/docs/cloud-services/data-stores)
- [DataDelve source and documentation](https://github.com/pinehappi/DataDelve)
- [DataDelve Canary Creator Store listing](https://create.roblox.com/store/asset/17652185888/DataDelve-Canary)

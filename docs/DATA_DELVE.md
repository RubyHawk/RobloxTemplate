# DataDelve Canary

DataDelve Canary is installed in Roblox Studio. It is a visual editor for Roblox **DataStores**; it does not create HUDs, inventory screens, or other GUI objects.

Use it only after publishing a separate private test experience:

1. Open **File > Experience Settings > Security**.
2. Enable **Studio Access to API Services** for the test experience only.
3. Run the game once so the template creates `RobloxTemplate_Profile_v1`.
4. Stop Play mode, open **Plugins > DataDelve Canary**, select that store, and inspect a `Player_<UserId>` profile.

Do not enable Studio API access on the live production experience. Roblox states that Studio accesses the same data as live servers and can overwrite production profiles.

The saved profile contains readable sections for Coins, inventory, boosts, settings, statistics, daily rewards, redemptions, entitlements, social verification, guild reservation, and timestamps. Schema versioning and migrations remain controlled by the template code; do not casually delete unknown fields in DataDelve.

Sources:

- [Roblox Data stores documentation](https://create.roblox.com/docs/cloud-services/data-stores)
- [DataDelve source and documentation](https://github.com/pinehappi/DataDelve)
- [DataDelve Canary Creator Store listing](https://create.roblox.com/store/asset/17652185888/DataDelve-Canary)

# Persistence and preset boundary audit — 2026-07-02

## Official sources checked

- DataStore behavior and Studio access: <https://create.roblox.com/docs/cloud-services/data-stores>
- DataStore organization and key-prefix guidance: <https://create.roblox.com/docs/cloud-services/data-stores/best-practices>
- Player data and purchase persistence: <https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing>
- `MarketplaceService.ProcessReceipt` guarantees and retries: <https://create.roblox.com/docs/reference/engine/classes/MarketplaceService>
- Ordered store integer and pagination behavior: <https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore>
- Server/client validation and rate limiting: <https://create.roblox.com/docs/scripting/security/client-server-boundary>
- Username lookup caching guidance: <https://create.roblox.com/docs/reference/engine/classes/Players>
- Text filtering for stored user text: <https://create.roblox.com/docs/ui/text-filtering>
- Native Roblox GUI authoring: <https://create.roblox.com/docs/ui>

## Decisions

- Visual template/showroom recipes use mock memory data.
- Every generated playable recipe selects live Roblox persistence, including Studio once the published test experience has Studio API access enabled.
- One centralized runtime module announces the active mode and reports API failures. Services no longer duplicate or silently hide the mode decision.
- Stable keys are centralized and documented. Feedback keys begin with the user prefix to support listing and privacy deletion workflows.
- Profile loading refuses unknown/future data shapes rather than replacing them. Early direct-profile values are wrapped without losing their fields.
- Unclaimed offline earnings are persisted in the profile instead of disappearing on a disconnect or server crash.
- Public profile writes use conflict-safe updates and username lookups are cached.
- Global leaderboard reads use one server cache; writes are changed-only and spread over the refresh window.
- Receipt processing is always installed even when the Store UI is disabled.
- Figma is a design source, not a runtime. A chosen exporter must produce independent native StarterGui instances before the preset is selectable.

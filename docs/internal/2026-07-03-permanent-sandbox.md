# Permanent Roblox sandbox — 2026-07-03

## Official documentation reviewed

- [Roblox projects and places](https://create.roblox.com/docs/projects)
- [Publish experiences and places](https://create.roblox.com/docs/production/publishing/publish-experiences-and-places)
- [Roblox DataStores](https://create.roblox.com/docs/cloud-services/data-stores)

Roblox describes a project/experience as a collection of places and related resources. DataStores are consistent across every place and server in one experience. Therefore, making a new experience for every preset build adds management overhead and would fragment test data, products, analytics, and settings.

## Repository decision

- Reuse universe `10434789270`, place `106940880949257` as the permanent private template sandbox.
- `SANDBOX.cmd` and the main launcher rebuild the selected preset, open that existing cloud place, and serve the generated Rojo project.
- The generated project includes `servePlaceIds: [106940880949257]`, preventing accidental connection to another place.
- Incremental and RPG use separate DataStore names through the `incremental` and `rpg` namespaces. This prevents profiles, public profiles, feedback, and ordered leaderboard values from mixing inside the shared universe.
- A genuinely separate released game should still receive its own experience once. The sandbox is for development and verification only.

## Local launch verification

The current Roblox Studio log recorded the supported local edit invocation as:

```text
RobloxStudioBeta.exe -task EditPlace -placeId 106940880949257 -universeId 10434789270
```

The sandbox launcher uses those same arguments. It does not automate publishing or bypass creator permissions. The user only needs to step in if Roblox asks them to sign in, the account lacks edit access, Studio API access was disabled, or they want to publish the synchronized changes.

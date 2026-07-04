# Technical setup and workflow

Beginners should double-click `START_HERE.cmd` and choose a mode. This page explains what the launcher does. The numbered CMD files remain available as individual setup, start, and check shortcuts.

The project reuses two permanent Roblox experiences configured in `experiences.config.json`; no mode ever creates a new experience:

- **Template experience** (`template` entry): the UI authoring workbench. `2_START.cmd` opens it in Studio with mock data and serves live code sync restricted to that place. While its IDs are still `0`, the launcher falls back to a local place file built once from `bootstrap.project.json` under `places/`.
- **Player-test experience** (`playerTest` entry): `SANDBOX.cmd` builds the selected preset recipe and always opens this one permanent cloud place. Presets keep separate saved data through DataStore namespaces.

## Link your two permanent experiences

1. Open `experiences.config.json`.
2. Fill `template.universeId` and `template.placeId` with your existing template experience IDs. In Studio, File > Experience Settings shows both; the Creator Dashboard URL also contains them.
3. The `playerTest` entry ships filled in. If you fork this template for another team, replace it with your own permanent test experience IDs.
4. Enable Studio Access to API Services on the player-test experience only (File > Experience Settings > Security). DataDelve and live saves need it there. The template experience stays on mock data and needs no API access.

### Seed the template experience (one time)

If your template experience is still an empty baseplate:

1. Run `2_START.cmd` while the template IDs are `0`; it opens the local workbench file.
2. Use File > Publish to Roblox and pick your existing template experience. Never use "Publish As" — that creates a new experience.
3. Paste the IDs into `experiences.config.json` and run `2_START.cmd` again. It now opens the cloud experience directly and restricts Rojo to that place.

## Installed stack

The project pins these current stable releases in `rokit.toml`:

| Tool | Version | Purpose |
| --- | --- | --- |
| Rokit | 1.2.0 | Installs the other exact versions |
| Rojo | 7.7.0 | Syncs files between VS Code and Studio |
| Wally | 0.3.2 | Roblox package manager |
| Selene | 0.31.0 | Finds Luau mistakes |
| StyLua | 2.5.2 | Formats Luau consistently |
| Lune | 0.10.4 | Runs pure Luau tests |

They were compared with their upstream latest releases on 2026-06-27.

## Manual commands

```powershell
./scripts/setup.ps1
./scripts/start.ps1
./scripts/doctor.ps1 -Full
```

`scripts/check.ps1` is the compact pre-commit check; CI runs the same core checks on Linux, including the preset builds and the Figma bridge validation.

## Branch workflow

1. Keep everything permanent on `main`. Template and player test are launcher modes, not branches.
2. Use a short-lived feature branch only while a programmer is actively changing something.
3. Save visual Studio edits (Ctrl+S in the local workbench, File > Publish to Roblox in the cloud template experience) and run `3_CHECK.cmd`.
4. Merge the reviewed feature back into `main`, then remove that temporary branch.
5. Create a long-lived game branch only after a game has genuinely unique gameplay that should release independently.

## Safe defaults

- The template workbench uses in-memory profiles everywhere—including published servers of the template experience—so visual work cannot touch saved data.
- Generated playable configurations use the permanent sandbox and real Roblox DataStores. Preset namespaces keep their saves separate inside that universe.
- HTTP, real purchases, community verification, Discord, guilds, audio assets, and live notifications are disabled initially.
- Secrets never belong in this repository.
- Third-party teleports remain off.

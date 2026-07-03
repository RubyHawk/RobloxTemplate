# Technical setup and workflow

Beginners should double-click `START_HERE.cmd` and choose a mode. This page explains what the launcher does. The numbered CMD files remain available as individual setup, start, and check shortcuts.

The template workbench has one saved editable place under `places/`. Setup creates it once from `bootstrap.project.json`; normal starts reopen it and do not overwrite Studio UI changes. `default.project.json` is used for live code sync.

Playable testing is different: `SANDBOX.cmd` always opens the one permanent cloud place configured in `sandbox.config.json`, then serves the selected preset into it. New presets do not create new experiences.

## Installed stack

The project pins these current stable releases in `rokit.toml`:

| Tool | Version | Purpose |
| --- | --- | --- |
| Rokit | 1.2.0 | Installs the other exact versions |
| Rojo | 7.6.1 | Syncs files between VS Code and Studio |
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

`scripts/check.ps1` is the compact pre-commit/CI-equivalent check.

## Branch workflow

1. Keep the stable template, presets, and sandbox on `main`.
2. Use a short-lived feature branch only while a programmer is actively changing something.
3. Save visual Studio edits with Ctrl+S and run `3_CHECK.cmd`.
4. Merge the reviewed feature back into `main`, then remove that temporary branch.
5. Create a long-lived game branch only after a game has genuinely unique gameplay that should release independently.

## Safe defaults

- The `template` showroom uses in-memory profiles so visual work cannot touch saved data.
- Generated playable configurations use the permanent sandbox and real Roblox DataStores. Preset namespaces keep their saves separate inside that universe.
- HTTP, real purchases, community verification, Discord, guilds, audio assets, and live notifications are disabled initially.
- Secrets never belong in this repository.
- Third-party teleports remain off.

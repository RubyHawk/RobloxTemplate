# Technical setup and workflow

Beginners should double-click `START_HERE.cmd` and choose a version. This page explains what the launcher does. The numbered CMD files remain available as individual setup, start, and check shortcuts.

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

1. Put reusable fixes on `template`.
2. Run `3_CHECK.cmd`.
3. Merge `template` into `playable-starter` and game branches.
4. Put actual map gameplay only on its game branch.

The GitHub default branch is `playable-starter` because it is the easiest demonstration. `template` remains the reusable source of truth.

## Safe defaults

- Studio uses in-memory mock profiles unless explicitly configured otherwise.
- HTTP, real purchases, community verification, Discord, guilds, audio assets, and live notifications are disabled initially.
- Secrets never belong in this repository.
- Third-party teleports remain off.

# Roblox Reusable Template

A server-authoritative, mobile-first Roblox UI and systems kit. The `template` branch is the reusable source of truth; game branches compose its services and screens through configuration.

## Quick start

```powershell
rokit install
wally install
rojo plugin install
rojo serve default.project.json
```

Open Roblox Studio, create or open a blank place, connect the Rojo plugin to `localhost:34872`, and press Play. The template opens a component gallery with mock data when Studio API access is disabled.

## Checks

```powershell
stylua --check src tests
selene src tests
rojo build default.project.json --output RobloxTemplate.rbxlx
lune run tests/run
npm --prefix worker run typecheck
npm --prefix worker test
```

Read [docs/SETUP.md](docs/SETUP.md) before connecting a published experience or real product IDs.

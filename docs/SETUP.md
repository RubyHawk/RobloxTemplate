# Setup

## Already available on this workstation

- Roblox Studio, VS Code, Git, GitHub CLI, Node, Python, Claude Code, Codex, and Rokit.
- VS Code already has Rojo and Roblox/Luau language extensions.

## First run

1. Run `rokit install`, `wally install`, and `npm ci --prefix worker` from the repository root.
2. Run `rojo plugin install` once to install the matching Studio plugin.
3. Run `rojo serve default.project.json` and connect from Studio.
4. Keep **Enable Studio Access to API Services** off while using the built-in mock profile store.
5. Use Studio Test > Device Emulator after every UI change. Check phone portrait and landscape.

## Branch workflow

- Merge reusable fixes into `template` first.
- Tag tested template releases.
- Merge `template` into `playable-starter` and game branches; do not copy individual source folders by hand.
- Override map behavior in `TemplateConfig` or a provider instead of editing reusable services.

## Security defaults

- Third-party teleports and HTTP requests stay off until required.
- Product, pass, group, notification, audio, backend, and universe IDs use disabled placeholders.
- Never store Open Cloud or backend keys in Git. Configure Roblox secrets and hosting environment variables.

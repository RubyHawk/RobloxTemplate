---
name: roblox-template
description: Build, extend, review, or debug the reusable Roblox Luau template, including UI/HUD components, profile data, economy, inventory, rewards, leaderboards, chat, monetization adapters, mobile compatibility, Rojo tooling, and map-branch integration. Use for changes under src/, tests/, worker/, Roblox project files, or template configuration.
---

# Roblox Template

## Workflow

1. Before changing Roblox chat, policy, monetization, notifications, privacy, platform APIs, or other fast-moving engine behavior, read the newest official Roblox documentation for that exact topic. Record the check date and links in `docs/internal/`. Never rely only on remembered API behavior.
2. Read `references/architecture.md` before changing a service boundary, profile field, provider, remote, or UI component contract.
3. Inspect `src/shared/TemplateConfig.luau` and the nearest existing module before adding a new setting or pattern.
4. Keep gameplay-specific behavior behind configuration or a provider. Keep reusable services independent of a map.
5. Treat the server as authoritative. Validate and rate-limit every client request before reading or mutating state.
6. Add a profile migration whenever persisted shape changes. Preserve old and unknown values where safe.
7. Keep all visual UI as permanent Studio-authored instances under `StarterGui`. Pre-author finite inventory, shop, reward, and leaderboard slots; runtime code may populate and show/hide them, but must not create, clone, or destroy GuiObjects.
8. Bind connected screens through `ScreenRegistry`, use Studio-editable properties and current Roblox styling tools, and support safe insets, touch, gamepad, reduced motion, and UI scale. `UIFactory` is formatting-only and must not construct instances.
9. Keep integrations disabled when IDs, secrets, consent, or hosting are absent. Provide a visible unavailable state rather than fake success.
10. Add or update tests, then run the commands in `AGENTS.md`.
11. Treat each UI preset as an independent product: separate `TemplateUI`, loading, and sign models with the same binding contract. Never share GUI instances between presets or overwrite an existing preset from a bootstrap script.
12. Use the Game Designer recipe boundary for preset selection, feature flags, and one-to-five currencies. Keep balances server-authoritative, migrate profile data explicitly, and reject disabled feature remotes on the server.
13. Keep the visual `template` showroom on mock memory data. Every generated `playable` recipe uses real Roblox persistence and must emit a clear startup diagnostic when the place is unpublished or Studio API access is unavailable.
14. Treat Figma as visual source material, not a Roblox runtime. Require a reviewed exporter to produce independent native StarterGui instances, preserve binder names, and never claim automatic Figma synchronization when no importer is configured.

## Hard boundaries

- Never trust client-provided prices, rewards, ownership, elapsed time, ranks, or player targets.
- Never commit credentials or enable Studio access to production DataStores.
- Use native `TextChatService` channels for player chat.
- Do not set or depend on deprecated chat migration properties. Keep rotating announcements in the native `RBXSystem` channel and validate that legacy chat tokens do not return.
- Do not put Discord URLs or handles in the experience UI.
- Do not add paid random items without odds disclosure and `PolicyService` restrictions.
- Do not make temporary boosts multiply each other; the strongest applicable potion wins unless configuration explicitly changes the policy.

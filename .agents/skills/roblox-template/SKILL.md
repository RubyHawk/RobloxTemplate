---
name: roblox-template
description: Build, extend, review, or debug the reusable Roblox Luau template, including UI/HUD components, profile data, economy, inventory, rewards, leaderboards, chat, monetization adapters, mobile compatibility, Rojo tooling, and map-branch integration. Use for changes under src/, tests/, worker/, Roblox project files, or template configuration.
---

# Roblox Template

## Workflow

1. Read `references/architecture.md` before changing a service boundary, profile field, provider, remote, or UI component contract.
2. Inspect `src/shared/TemplateConfig.luau` and the nearest existing module before adding a new setting or pattern.
3. Keep gameplay-specific behavior behind configuration or a provider. Keep reusable services independent of a map.
4. Treat the server as authoritative. Validate and rate-limit every client request before reading or mutating state.
5. Add a profile migration whenever persisted shape changes. Preserve old and unknown values where safe.
6. Build UI through `UIFactory` and `ScreenRegistry`, use theme tokens, and support safe insets, touch, gamepad, reduced motion, and UI scale.
7. Keep integrations disabled when IDs, secrets, consent, or hosting are absent. Provide a visible unavailable state rather than fake success.
8. Add or update tests, then run the commands in `AGENTS.md`.

## Hard boundaries

- Never trust client-provided prices, rewards, ownership, elapsed time, ranks, or player targets.
- Never commit credentials or enable Studio access to production DataStores.
- Use native `TextChatService` channels for player chat.
- Do not put Discord URLs or handles in the experience UI.
- Do not add paid random items without odds disclosure and `PolicyService` restrictions.
- Do not make temporary boosts multiply each other; the strongest applicable potion wins unless configuration explicitly changes the policy.

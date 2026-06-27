# 2026-06-27: native chat and editable UI showroom

## Documentation checked

- Roblox in-experience text chat: https://create.roblox.com/docs/chat/in-experience-text-chat
- Roblox `TextChatService` API: https://create.roblox.com/docs/reference/engine/classes/TextChatService
- Roblox cross-server chat: https://create.roblox.com/docs/chat/cross-server-chat
- Roblox `ScreenGui.ScreenInsets`: https://create.roblox.com/docs/reference/engine/classes/ScreenGui#ScreenInsets
- Rojo sync details: https://rojo.space/docs/v7/sync-details/

Checked on 2026-06-27. Recheck the official documentation before the next chat, policy, platform, or monetization change.

## Chat decision

The project uses native `TextChatService` and default text channels. The `Chat` singleton can still appear in Explorer with a warning; that is not proof that project code uses the legacy system. Do not set `TextChatService.ChatVersion`; the current API marks that migration property deprecated. Rotating system announcements display in `RBXSystem`, not the player-chat `RBXGeneral` channel. Tests reject known legacy chat tokens.

## UI decision

The connected HUD and screen shells are Studio-authored GUI instances. Runtime code only binds behavior and creates player-specific content by cloning authored component templates. The template branch holds a large reference showroom; playable starter branches keep one coherent connected design.

## Imported packs

- `Ui Pack Version 5 By Zxgly.rar`: no license file was present. A script-free sanitized copy is kept as an internal visual reference; do not redistribute or publish it as an asset pack until rights are confirmed.
- `Notification System V2.rbxm`: all supplied scripts were removed because its remote path trusted client-chosen notification content and presentation.
- `Free Icon Pack v3.1 (Basic).zip`: selected source icons and its license are retained under `assets/icons/gvesster-basic/`. The license permits use and editing but forbids reselling or redistributing the icons as an asset pack.

## Persistence decision

Branch places live under `places/`. Setup creates a place from `bootstrap.project.json` only when one does not exist. Normal start opens the existing place and never rebuilds over Studio visual edits. Live code sync uses `default.project.json`, whose StarterGui boundary preserves unknown authored UI instances.

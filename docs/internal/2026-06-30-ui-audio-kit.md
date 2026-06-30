# UI audio kit review — 2026-06-30

## Sources checked

- Roblox Creator Store model: <https://create.roblox.com/store/asset/7209483381/Sound-Kit-v160-142-SOUNDS>
- Current Roblox audio-object guidance: <https://create.roblox.com/docs/audio/objects>
- Current Roblox audio-asset and permission guidance: <https://create.roblox.com/docs/audio/assets>
- Current `AudioPlayer` API: <https://create.roblox.com/docs/reference/engine/classes/AudioPlayer>
- Current asset privacy guidance: <https://create.roblox.com/docs/projects/assets/privacy>

## Findings and decision

The supplied Creator Store item is a script-free model containing 143 `Sound` instances even though its title says 142. The dedicated `UiSounds` folder contains `Click1`, `Notification1`, and `Notification2`, but those audio IDs currently require authentication and are not dependable defaults for an unrelated experience. Several other sounds in the pack have the same limitation.

The template therefore uses only the pack's still-public Roblox-owned audio assets. This keeps the requested kit as the source while avoiding silent failures caused by private audio permissions:

| Template cue | Pack sound | Asset ID |
| --- | --- | ---: |
| Click | `button.wav` | `12221967` |
| Cash/pickup | `Kerplunk.wav` | `12222054` |
| Reward/success | `victory.wav` | `12222253` |
| Inventory | `switch.wav` | `12222170` |
| Lootbox/open hook | `swoosh.wav` | `12222200` |
| Spin/tick hook | `clickfast.wav` | `12221976` |
| Announcement | `Pageturn1` | `12222076` |

Roblox's current docs discourage starting new systems with `Sound` and `SoundGroup`. The client mixer now uses non-directional `AudioPlayer` objects wired to a local `AudioDeviceOutput`. UI structures remain authored StarterGui instances; runtime audio code only binds interaction feedback.

Music remains intentionally empty until an owned or clearly licensed track is selected. Map branches can replace every sound centrally through `TemplateConfig.audio`.

The lootbox/open hook and spin/tick hook load with the mixer but have no caller yet — this template ships no lootbox or spin-wheel screen. A map branch that adds one can call `AudioController.play("lootboxOpen")` / `AudioController.play("spin")` directly.

## Follow-up correctness review — 2026-06-30

A second pass against the live engine reference caught two defects in the initial integration:

- **Wrong `AudioPlayer` property.** The mixer set `AudioPlayer.AudioContent` (via `Content.fromUri`) instead of `AudioPlayer.Asset`. The current class reference (<https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AudioPlayer.yaml>, checked 2026-06-30) tags `AudioContent` as `Hidden` ("not meant to be used, and may have unresolved issues") and `AssetId` as `Hidden`/`Deprecated`. `Asset` (type `ContentId`) is the only non-hidden, non-deprecated property, matches every code sample in the [Add 2D audio](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/audio/add-2D-audio.md) and [Audio objects](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/audio/objects.md) guides, and takes a plain `rbxassetid://` string like the legacy `Sound.SoundId`. `AudioController.luau` now sets `player.Asset` directly.
- **Non-Roblox-owned hook asset.** `lootboxOpen` pointed at `910988901` ("Deploy1"), owned by a third-party creator (`SuperEvilAzmil`, verified via `economy.roblox.com/v2/assets/910988901/details`), not Roblox. That contradicts the "still-public Roblox-owned audio assets" rule above and reintroduces the private-audio-permission risk this document exists to avoid. Replaced with `12222200` (`swoosh.wav`), confirmed Roblox-owned (`"Creator":{"Id":1,"Name":"Roblox"}`) and public domain via the same endpoint, and a closer thematic fit for a reveal/open cue.

Two UI-wiring defects were also fixed in `src/client/init.client.luau` and `src/client/UI/Screens.luau`:

- The shared `query()` helper unconditionally played `"click"` on every call, including the automatic `InitialState` polling loop on join (up to once per second for 30s). It now takes an optional `audioCue` and the polling loop and the automatic AFK rollover request pass `""` (silent) instead of triggering phantom click sounds for actions the player didn't take.
- The Feedback screen's category-cycle button was missing the click cue that the otherwise-identical Inventory category button received.

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
| Lootbox/open hook | `Deploy1` | `910988901` |
| Spin/tick hook | `clickfast.wav` | `12221976` |
| Announcement | `Pageturn1` | `12222076` |

Roblox's current docs discourage starting new systems with `Sound` and `SoundGroup`. The client mixer now uses non-directional `AudioPlayer` objects wired to a local `AudioDeviceOutput`. UI structures remain authored StarterGui instances; runtime audio code only binds interaction feedback.

Music remains intentionally empty until an owned or clearly licensed track is selected. Map branches can replace every sound centrally through `TemplateConfig.audio`.

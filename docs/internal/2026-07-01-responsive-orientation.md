# Responsive UI / screen orientation review — 2026-07-01

## Sources checked

- `Camera.ViewportSize`: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Camera.yaml>
- `PlayerGui.CurrentScreenOrientation` / `PlayerGui.ScreenOrientation`: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/PlayerGui.yaml>
- `StarterGui.ScreenOrientation`: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StarterGui.yaml>
- `GuiService.ViewportDisplaySize` and `Enum.DisplaySize`: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/GuiService.yaml>, <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/DisplaySize.yaml>
- `Enum.ScreenOrientation` values: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/ScreenOrientation.yaml>

## Findings

A user-supplied guide recommended `Camera.ViewportSize` as the primary responsive signal, `PlayerGui.CurrentScreenOrientation` for landscape-flip detection, and setting `StarterGui.ScreenOrientation` for rotation support. All of the referenced properties and enum values (`LandscapeLeft`, `LandscapeRight`, `LandscapeSensor`, `Portrait`, `Sensor`) checked out against the current class/enum reference. Two things the guide didn't call out:

- `StarterGui.ScreenOrientation` **already defaults to `Sensor`** — this repo never overrides it, so portrait/landscape rotation is already permitted today. Set it explicitly anyway so the intent survives an engine default change and isn't just an accident of never having touched the property.
- `GuiService.ViewportDisplaySize` only distinguishes `Small` (tablet/mobile/handheld), `Medium` (laptop/monitor), `Large` (TV or bigger) — it cannot tell a phone from a tablet. `Camera.ViewportSize` (actual pixel/offset dimensions) has to be the real signal for that distinction, exactly as the guide itself argued.

The guide's example script targets a different, hypothetical game (`Workspace.CurrencyPlatform`, a `BillboardGui` named `UpgradeBubble`, panels named `CurrencyPanel`/`UpgradePanel`) that doesn't exist in this template. Adapted the *approach* (viewport-size-driven, orientation as a supporting signal, never gameplay-authoritative) to this template's real structure instead of porting the example verbatim:

- The authored screens (`InventoryScreen`, `StoreScreen`, etc.) and `Navigation` already carry `UISizeConstraint` Min/MaxSize pairs (screens: 300×300 to 560×620; nav: 74×320 to 92×450) — the template already guards against screens ballooning on a tablet/desktop-sized viewport or collapsing on a small phone. No need to duplicate that.
- `AudioController`-style controllers already exist under `src/client/Controllers/`; `ResponsiveController` follows the same pattern rather than inventing a new module shape.
- The existing per-player `uiScale` setting (`Settings` screen, 0.8–1.2, saved server-side) already drives `Root.InterfaceScale.Scale`. The new automatic device-based factor multiplies with that value rather than fighting or replacing a player's explicit preference.
- Did not build the guide's 7-way profile taxonomy (`PhonePortrait`/`PhoneLandscape`/`TabletPortrait`/`TabletLandscape`/`DesktopNarrow`/`DesktopWide`/`ConsoleLarge`) — nothing in this template's screens currently branches into that many distinct layouts (no side-panel/dashboard mode exists), so it would be unused abstraction. Exposed just what's actually consumed: orientation, raw viewport size, and an input-capability flag, as attributes on `Root`.
- Orientation/viewport data stays a client-only display concern, per the guide's own correct point — nothing server-authoritative (currency, rewards, purchases) reads any of it.

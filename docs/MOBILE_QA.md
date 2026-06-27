# Mobile acceptance matrix

For every UI or HUD change, inspect the component gallery in Studio's Device Emulator.

| Target | Orientation | Required checks |
| --- | --- | --- |
| Small phone | Portrait | Safe insets, no clipped modal, 44px touch targets, scrolling |
| Small phone | Landscape | HUD does not cover controls, modal fits vertically |
| Tablet | Both | Grid uses available width without oversized text |
| Desktop | Landscape | Keyboard/gamepad selection, hover and back navigation |

Also verify UI scale 80% and 120%, reduced motion, long names/numbers, empty/loading/error states, virtual keyboard focus, and a simulated slow server response.

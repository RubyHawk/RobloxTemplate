# 2026-06-28: coherent gallery preview modes

## Problem

The first showroom build enabled the connected HUD, full visual pack, and notification preview simultaneously. Although every item was visible, the result was visually chaotic and did not represent a usable game interface.

## Decision

Only one content layer is visible at a time: Connected UI, UI Pack, or Notification. A Studio-authored `GalleryMenu` provides the mode buttons and description. `GalleryBackdrop` gives isolated visual previews a consistent labelled canvas. The imported showroom ScreenGuis are disabled by default and remain ordinary editable objects under StarterGui.

The playable starter does not bootstrap the gallery controls or imported showroom layers, so players only receive the connected interface.

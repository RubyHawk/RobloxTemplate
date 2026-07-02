# UI showroom: edit without code

Open the `template` version from `START_HERE.cmd`, connect Rojo, and expand **StarterGui** in Explorer.

The gallery shows one preview mode at a time. In Play mode, use the **UI Library** bar:

- **Connected UI** shows the real working HUD and systems.
- **UI Pack** shows the editable Giga Simulator component sheet.
- **Notification** shows the notification reference by itself.

In Studio edit mode, `TemplateUI > Root > ShowcaseCanvas` is intentionally visible. Pressing Play hides that design-library canvas and uses the connected HUD/screens.

## What is there

- **TemplateUI > Root > ShowcaseCanvas** is the editable Giga Simulator design library arranged in a coherent grid.
- **TemplateUI > Root > Screens** contains the gameplay-bound inventory, shop, rewards, profile, settings, feedback, codes, boards, community, and global list.
- **TemplateLoading** is the editable loading screen. It stays disabled in edit mode; temporarily set `Enabled` to true to restyle it, then turn it off before saving.
- **StarterSignUI** is the editable playable-starter world sign. Its client binder only attaches the authored billboard to the earning pad.
- **ZxglyV5Showroom** remains as the raw imported source reference.
- **NotificationV2Showroom** is a script-free notification reference.
- **GalleryMenu** and **GalleryBackdrop** keep previews separated and labelled.

The imported scripts were removed. The supplied notification system allowed a client to choose arbitrary notification text, color, and duration; the template keeps its server-validated notification path instead.

## Connected starter design

`TemplateUI` uses the bright **Giga Simulator** style: compact floating windows, thick dark outlines, floating circular icon navigation, wide illustrated shop offers, a two-column inventory, real cartoon pack artwork, a white currency pill, and a seven-day reward strip. Color is never the only cue; every action has readable text.

## What to edit

Inside `TemplateUI > Root`:

- use **ShowcaseCanvas** to compare and remix the design-library examples;
- edit **CurrencyHUD**, **Navigation**, **ScreenTemplate**, and **Toast** directly;
- edit the gameplay-bound versions under **Screens** when a change must appear in Play mode;
- toggle one connected screen's `Visible` property while editing, then turn it off again before saving;
- keep connected object names unchanged because runtime behavior binds to those names.

Dynamic data uses pre-authored capacity: 12 inventory slots, 8 store cards, 7 reward tiles, 10 server rows, and 50 global rows. Runtime code only replaces text/images and toggles visibility. No GUI objects are created, cloned, or destroyed during Play.

The loading screen and starter sign follow the same rule: their complete visual trees are under `StarterGui`; their scripts only update progress, visibility, and the billboard's `Adornee`.

## Save safely

Press **Ctrl+S** in Studio. The branch place is stored in `places/` and is not rebuilt every time the launcher opens it. Commit the changed place with the rest of the branch when the design is ready.

Rojo ignores unknown objects under StarterGui, so visual edits survive code sync. Keep the Rojo window open for code updates.

## Making starter themes

Keep the huge workbench on `template`. A finished starter branch should contain one coherent connected theme, not every raw imported showroom. Future theme branches can use names such as `playable-starter-bright`, `playable-starter-dark`, or `playable-starter-pastel`.

The starter uses public image IDs from the user-supplied Zxgly pack for its initial cash, reward, pet, calendar, potion, multiplier, and equipment art. The 25 selected Gvesster PNG files remain available as replacement source art. Roblox cannot display local disk paths in a live experience, so follow [`ICON_PACK.md`](ICON_PACK.md) when uploading a branded replacement set. Follow both packs' licenses.

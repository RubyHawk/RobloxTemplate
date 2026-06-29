# UI showroom: edit without code

Open the `template` version from `START_HERE.cmd`, connect Rojo, and expand **StarterGui** in Explorer.

The gallery now shows one preview mode at a time. In Play mode, use the tidy **UI Library** bar:

- **Connected UI** shows the real working HUD and systems.
- **UI Pack** shows the full visual component sheet by itself.
- **Notification** shows the notification reference by itself.

The UI Pack and Notification ScreenGuis are disabled by default, so they no longer pile on top of the connected HUD. Outside Play mode, select the ScreenGui you want in Explorer and toggle its `Enabled` property to preview it while editing.

## What is there

- **TemplateUI** is connected to the real inventory, store, rewards, profile, codes, boards, feedback, community, settings, toast, and HUD logic.
- **ZxglyV5Showroom** is a script-free visual reference with its screens arranged in rows and columns.
- **NotificationV2Showroom** is a script-free notification reference.
- **GalleryMenu** and **GalleryBackdrop** keep previews separated and clearly labelled.

The imported scripts were removed. In particular, the supplied notification system allowed a client to choose arbitrary notification text, color, and duration. The template keeps its server-validated notification path instead.

## Connected starter design

`TemplateUI` targets a mainstream kid-friendly Roblox experience: a compact coin card, five icon-and-label actions in a bottom dock, visual item cards, and a seven-day reward strip. Color is never the only cue; every action has readable text. The connected starter is intentionally calmer than the visual reference packs.

## What to edit

Inside `TemplateUI → Root`:

- edit **CurrencyHUD**, **Navigation**, **ScreenTemplate**, and **Toast** directly;
- edit **ComponentTemplates → ButtonTemplate, TextBoxTemplate, LabelTemplate, RowTemplate, ItemCardTemplate, RewardTileTemplate** once to restyle every live screen;
- keep object names unchanged because the runtime binds behavior by those names.

The lists inside inventory, shop, profiles, and leaderboards must be created at runtime because their data changes per player. They are not visually hardcoded: they clone the Studio-authored component templates.

## Save safely

Press **Ctrl+S** in Studio. The branch place is stored in `places/` and is no longer rebuilt every time the launcher opens it. Commit the changed place with the rest of the branch when the design is ready.

Rojo deliberately ignores unknown objects under StarterGui, so visual edits survive code sync. Keep the Rojo window open for code updates.

## Making starter themes

Keep the huge workbench on `template`. A finished starter branch should contain one coherent connected theme, not every showroom screen. Future theme branches should use names such as `playable-starter-bright`, `playable-starter-dark`, or `playable-starter-pastel`, each with its own saved place file.

The connected UI is wired for all 25 selected Gvesster icons. Roblox cannot display local disk paths in a live experience, so follow [`ICON_PACK.md`](ICON_PACK.md) once to upload the files and paste their IDs into `TemplateConfig.icons`. Follow the included icon license.

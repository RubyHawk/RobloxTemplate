# Your first five minutes

## 1. Open the launcher

Double-click `START_HERE.cmd` in the project folder.

Choose **Open Playable Starter** or **Open Template**. The launcher switches versions, installs anything required on the first run, opens that branch's saved place, starts Rojo, and opens Roblox Studio.

Success looks like this:

```text
Branch:  template
Project: RobloxTemplateGallery
```

## 2. Keep the black window open

The black window runs the live code connection. Closing it stops live syncing but does not delete anything.

It shows both the Git branch and project name. `template` should show `RobloxTemplateGallery`; `playable-starter` should show `RobloxPlayableStarter`.

## 3. Connect Studio

Inside Roblox Studio:

1. Open the **Plugins** tab at the top.
2. Click the **Rojo** button.
3. Click **Connect** next to `localhost:34872`.
4. Expand **StarterGui** in Explorer to see and edit the real GUI objects.
5. Press **Ctrl+S** after visual changes.
6. Press **Play** from the Home or Test tab.

Expected result: the loading screen disappears, the Coins HUD appears in the upper-left, and the menu bar appears along the bottom.

On the `template` branch, `ZxglyV5Showroom` and `NotificationV2Showroom` are script-free visual reference galleries. `TemplateUI` is the connected UI used by the actual systems.

## 4. Try the template

- Open **SHOP** and buy a potion with the mock Coins.
- Open **BAG** and use it; the HUD multiplier changes.
- Open **GIFT** and claim the daily reward.
- Open **SETTINGS** and change UI scale or reduced motion.
- On `playable-starter`, walk to the blue pad and use its prompt to earn Coins.

Studio deliberately uses mock data, so these tests cannot damage a future live game’s saves.

## 5. Check a phone

In Studio, open **Test → Device Emulator**, select a phone, test portrait and landscape, and press Play again. Touch simulation turns on automatically for a mobile device.

## When you finish

Stop Play mode in Studio, then press `Ctrl+C` in the black Rojo window. Your source files remain in the project folder.

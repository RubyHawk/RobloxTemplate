# Your first five minutes

## 1. Open the launcher

Double-click `START_HERE.cmd` in the project folder.

Choose **Open Shared Test Experience** or **Open Template**. The shared option lists every recipe under `config-presets/`, rebuilds the chosen preset, opens the existing player-test experience, and starts Rojo. It does not create a new Roblox experience.

Choose **Design a Game Preset** when you want a clean Incremental/RPG package with configurable currencies and systems instead of the general workbench.

Success looks like this:

```text
Mode:    Template workbench (mock data only)
Project: RobloxTemplateGallery
```

## 2. Keep the black window open

The black window runs the live code connection. Closing it stops live syncing but does not delete anything.

It shows the mode and project name, then the live Rojo log. The launcher window separately shows the project and Git branch; normal work should show `main`.

## 3. Connect Studio

Inside Roblox Studio:

1. Open the **Plugins** tab at the top.
2. Click the **Rojo** button.
3. Click **Connect** next to `localhost:34872`.
4. Expand **StarterGui** in Explorer. `TemplateUI` contains the HUD and screens, `TemplateLoading` contains the loading screen, and `StarterSignUI` contains the playable earning-pad sign. Temporarily enable/show the object you are editing, then hide it again before saving.
5. Press **Ctrl+S** after visual changes.
6. Press **Play** from the Home or Test tab.

Expected result: the loading screen disappears, the Coins HUD appears in the upper-left, and the menu bar appears along the bottom.

In **Open Template**, use the **UI Library** bar in Play mode to switch between the connected UI, the script-free Zxgly pack, and the notification preview. Only one appears at a time.

## 4. Try the template

- Open **SHOP** and buy a potion with the mock Coins.
- Open **BAG** and use it; the HUD multiplier changes.
- Open **REWARDS** and claim the daily reward.
- Open **SETTINGS** and change UI scale or reduced motion.
- In **Shared Test Experience**, the blue pad earns the primary currency. A generated game with two or more currencies also shows a teal pad for the second currency.

The `template` showroom deliberately uses mock data. The shared sandbox uses real saved data. Incremental and RPG use different DataStore namespaces so switching presets cannot mix their profiles.

DataDelve Canary is already installed, but it is only for inspecting saved profiles in a separate published test experience. Follow [`DATA_DELVE.md`](DATA_DELVE.md) before enabling Studio API access.

## 5. Check a phone

In Studio, open **Test → Device Emulator**, select a phone, test portrait and landscape, and press Play again. Touch simulation turns on automatically for a mobile device.

## When you finish

Stop Play mode in Studio, then press `Ctrl+C` in the black Rojo window. Your source files remain in the project folder.

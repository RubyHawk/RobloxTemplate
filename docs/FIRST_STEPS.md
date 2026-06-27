# Your first five minutes

## 1. Run setup once

Double-click `1_SETUP.cmd` in the project folder.

It installs the exact project tools, installs the official Rojo plugin into Studio, prepares the optional notification-worker packages when Node.js is available, and builds `build/RobloxTemplate.rbxlx`.

Success looks like this:

```text
SETUP COMPLETE
Next: close this window and double-click 2_START.cmd.
```

## 2. Start the project

Double-click `2_START.cmd`. It opens the generated place in Roblox Studio and starts the live code connection.

Keep its black command window open while working. Closing that window stops live syncing but does not delete anything.

## 3. Connect Studio

Inside Roblox Studio:

1. Open the **Plugins** tab at the top.
2. Click the **Rojo** button.
3. Click **Connect** next to `localhost:34872`.
4. Press **Play** from the Home or Test tab.

Expected result: the loading screen disappears, the Coins HUD appears in the upper-left, and the menu bar appears along the bottom.

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

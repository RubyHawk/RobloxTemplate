# Troubleshooting

Start by double-clicking `3_CHECK.cmd`. Fix the first red `[FAIL]` line, then run it again.

## “Windows protected your PC”

The `.cmd` files are plain text in this repository. Select **More info → Run anyway**, or open the file in Notepad first to inspect it.

## Setup says Rokit or a tool is missing

Close the window and run `1_SETUP.cmd` again. Setup installs pinned tools only inside Rokit’s normal user directory.

## Studio did not open

Install Roblox Studio from the official Creator Hub, then rerun `2_START.cmd`:

https://create.roblox.com/docs/studio/setup

## The wrong mode opened

Close the old Studio window and open `START_HERE.cmd` again:

- **Template** opens the permanent template experience configured in `experiences.config.json`. While its IDs are still `0`, it opens a locally built `RobloxTemplateGallery.rbxlx` instead.
- **Shared Test Experience** always opens the permanent player-test place from `experiences.config.json`, then serves the selected preset configuration into it.

The launcher closes an older Rojo server on port `34872`; otherwise Studio could reconnect to the previous mode.

## My Studio UI edits disappeared

In the cloud template experience, keep changes with File > Publish to Roblox before closing Studio. In the local fallback workbench, use the place under `places/` (not an old file under `build/`) and save with Ctrl+S; the launcher reopens the saved place and does not rebuild over it. Durable preset UI lives in the `src/ui/presets/` model files edited through Figma patches — the local place file is disposable.

## There is no Rojo button in Studio

Close Studio, run `1_SETUP.cmd`, and reopen it. Setup uses the official Creator Store Rojo plugin when asset `13916111004` is already installed; otherwise it installs the pinned `RojoManagedPlugin.rbxm` into your Roblox Plugins folder. Keep exactly one copy. If both appear in **Manage Plugins**, remove either the Creator Store copy or the local managed copy before reopening Studio—two copies create duplicate widgets, connections, and sync work.

## Rojo says it cannot connect

Keep the `SANDBOX.cmd` or `2_START.cmd` window open. It should say `Rojo server listening` and show port `34872`. Then reopen **Plugins → Rojo** in Studio and click **Connect**.

If it says the port is already in use, close any older `2_START.cmd` windows and run it once more.

## The HUD does not appear after pressing Play

1. Confirm Rojo says **Connected** before pressing Play.
2. Stop and press Play again.
3. Open **View → Output** in Studio and look for a red error.
4. Run `3_CHECK.cmd` outside Studio.

## Purchases, audio, Discord, or notifications say disabled

That is intentional. These features require assets, IDs, secrets, consent, or hosting owned by you. Follow `docs/PLATFORM_SETUP.md` when configuring the permanent sandbox or a released game.

## DataDelve is empty or my profile will not load

Look in **View > Output** for the line beginning `[Template Data]`.

- `MOCK mode` means you opened the visual template/showroom. It never writes to DataDelve.
- `LIVE mode selected, but this file is unpublished` means you opened a local export instead of **Shared Test Experience**.
- `StudioAccessToApisNotAllowed` or `403` means enable **File > Experience Settings > Security > Studio Access to API Services**, save, and reopen the exact published test experience.

In DataDelve, select `RobloxTemplate_Profile_v1_incremental` or `RobloxTemplate_Profile_v1_rpg` and key `player:<numeric UserId>`. It is not `Player_<UserId>`. See `docs/DATA_DELVE.md` for the complete store list.

## My friend is on an old branch

The permanent work now lives on `main`. Run:

```powershell
git fetch origin
git switch main
```

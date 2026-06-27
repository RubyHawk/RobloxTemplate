# Troubleshooting

Start by double-clicking `3_CHECK.cmd`. Fix the first red `[FAIL]` line, then run it again.

## “Windows protected your PC”

The `.cmd` files are plain text in this repository. Select **More info → Run anyway**, or open the file in Notepad first to inspect it.

## Setup says Rokit or a tool is missing

Close the window and run `1_SETUP.cmd` again. Setup installs pinned tools only inside Rokit’s normal user directory.

## Studio did not open

Install Roblox Studio from the official Creator Hub, then rerun `2_START.cmd`:

https://create.roblox.com/docs/studio/setup

## The wrong branch or map opened

Close the old Studio window and open `START_HERE.cmd` again. The launcher switches to your selection and prints the branch and saved place it is opening:

- `template` opens `RobloxTemplateGallery.rbxlx`.
- `playable-starter` opens `RobloxPlayableStarter.rbxlx`.

If you have uncommitted edits on a different branch, the launcher refuses to switch so nothing is lost. Ask the programmer to commit them, then choose the version again.

The launcher also closes an older Rojo server on port `34872`; otherwise Studio could reconnect to the previous branch.

## My Studio UI edits disappeared

Use the place under `places/`, not an old file under `build/`. Save with Ctrl+S before closing Studio. The launcher now reopens the saved branch place and does not rebuild over it.

## There is no Rojo button in Studio

Close Studio, run `1_SETUP.cmd`, and reopen it. Setup installs `RojoManagedPlugin.rbxm` into your Roblox Plugins folder.

## Rojo says it cannot connect

Keep the `2_START.cmd` window open. It should say `Rojo server listening` and show port `34872`. Then reopen **Plugins → Rojo** in Studio and click **Connect**.

If it says the port is already in use, close any older `2_START.cmd` windows and run it once more.

## The HUD does not appear after pressing Play

1. Confirm Rojo says **Connected** before pressing Play.
2. Stop and press Play again.
3. Open **View → Output** in Studio and look for a red error.
4. Run `3_CHECK.cmd` outside Studio.

## Purchases, audio, Discord, or notifications say disabled

That is intentional. These features require assets, IDs, secrets, consent, or hosting owned by you. Follow `docs/PLATFORM_SETUP.md` only after creating a private test experience.

## My friend cannot see the branches

Open the repository’s branch list on GitHub, or run:

```powershell
git fetch origin
git switch playable-starter
```

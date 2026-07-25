@echo off
cd /d "%~dp0"
title Roblox Template - Prepare RNG Defender UI for Figma
node "%~dp0scripts\figma-ui-bridge.mjs" bundle --workspace "%~dp0figma\workspaces\rng-defender.json" --out "%~dp0build\figma\RNGDefender.roblox-ui-workspace.json"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo Ready: build\figma\RNGDefender.roblox-ui-workspace.json
  echo Import that single file with the Roblox UI Bridge plugin in Figma.
) else (
  echo The Figma workspace was not prepared. Read the message above.
)
pause
exit /b %RESULT%

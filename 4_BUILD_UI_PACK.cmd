@echo off
cd /d "%~dp0"
title Build Roblox UI Package
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-ui-pack.ps1"
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo The UI package could not be built. Run 1_SETUP.cmd, then try again.
  pause
)

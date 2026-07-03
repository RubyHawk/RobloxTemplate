@echo off
cd /d "%~dp0"
title Roblox Template Launcher
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\launcher.ps1"
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo The launcher could not open. Run 1_SETUP.cmd, then try again.
  pause
)

@echo off
cd /d "%~dp0"
title Roblox Template App
start "" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\launcher.ps1"
exit /b 0

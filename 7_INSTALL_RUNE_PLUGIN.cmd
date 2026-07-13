@echo off
cd /d "%~dp0"
title Roblox Template - Install Runewright
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-rune-plugin.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Runewright install stopped because something needs attention above.
pause
exit /b %RESULT%

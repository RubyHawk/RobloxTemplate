@echo off
cd /d "%~dp0"
title Roblox Shared Icon Library
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\icon-library.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo The icon manager stopped because something needs attention above.
pause
exit /b %RESULT%

@echo off
cd /d "%~dp0"
title RNG Defender UI Asset Setup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rng-defender-ui-assets.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo UI asset setup stopped because something needs attention above.
pause
exit /b %RESULT%

@echo off
setlocal
cd /d "%~dp0"
title RNG Defender - Gameplay Delivery
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rng-defender.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo RNG Defender delivery stopped because something needs attention above.
pause
exit /b %RESULT%

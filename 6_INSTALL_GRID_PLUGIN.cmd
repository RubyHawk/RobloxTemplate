@echo off
cd /d "%~dp0"
title Roblox Template - Install Grid Plugin
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-grid-plugin.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Grid plugin install stopped because something needs attention above.
pause
exit /b %RESULT%

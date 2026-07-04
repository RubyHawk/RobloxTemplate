@echo off
cd /d "%~dp0"
title Roblox Template - Shared Sandbox
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\sandbox.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo The sandbox stopped because something needs attention above.
pause
exit /b %RESULT%

@echo off
cd /d "%~dp0"
title Roblox Template - Start
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Start stopped because something needs attention above.
pause
exit /b %RESULT%

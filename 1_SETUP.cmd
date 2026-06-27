@echo off
cd /d "%~dp0"
title Roblox Template - Setup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Setup did not finish. Read the red message above.
pause
exit /b %RESULT%

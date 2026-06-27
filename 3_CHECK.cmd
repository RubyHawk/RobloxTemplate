@echo off
cd /d "%~dp0"
title Roblox Template - Check Everything
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\doctor.ps1" -Full
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%

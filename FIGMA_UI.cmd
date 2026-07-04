@echo off
cd /d "%~dp0"
title Roblox Template - Apply Figma Design
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\figma-ui.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo The Figma design was not applied. Read the message above.
pause
exit /b %RESULT%

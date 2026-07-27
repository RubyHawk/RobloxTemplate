@echo off
setlocal
cd /d "%~dp0"
title RNG Defender - Gameplay Delivery
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" set "POWERSHELL_EXE=powershell.exe"
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rng-defender.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo RNG Defender delivery stopped because something needs attention above.
pause
exit /b %RESULT%

@echo off
cd /d "%~dp0"
title Roblox Template App
start "" wscript.exe "%~dp0scripts\launch-workshop.vbs"
exit /b 0

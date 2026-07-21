@echo off
REM Serves the RNG Defender / Tower Defense place (placeId 128136881672145).
REM This is the project that has the dungeon feature ON and includes the portal
REM pad + arena + dungeon UI. Do NOT use START_HERE (that opens the template UI
REM workbench) or default.project.json (the gallery) for this place.
cd /d "%~dp0"
title RNG Defender - Serve (place 128136881672145, dungeon ON)
echo Open your Tower Defense place (128136881672145) in Studio, then click
echo    Plugins ^> Rojo ^> Connect
echo This project only connects to place 128136881672145 and merges with your
echo Team Create map (it never deletes map/mapwater/pier/islands).
echo.
rojo serve patches\rng-defender-grid-demo.project.json
pause

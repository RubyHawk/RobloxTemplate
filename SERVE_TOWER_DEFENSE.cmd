@echo off
setlocal
REM Compatibility name from the original dungeon delivery. Delegate to the
REM guarded launcher so both shortcuts install the matching plugin, open only
REM place 128136881672145, validate its universe, and safely manage Rojo.
cd /d "%~dp0"
call "%~dp08_RNG_DEFENDER.cmd" %*
exit /b %ERRORLEVEL%

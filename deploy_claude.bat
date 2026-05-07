@echo off
set "ARGS=%*"
set "ARGS=%ARGS:--config=-ConfigFile%"
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %ARGS%

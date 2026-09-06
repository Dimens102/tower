@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-Tower-Control.ps1"
exit /b %errorlevel%

@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Tower-Control.ps1"
exit /b %errorlevel%

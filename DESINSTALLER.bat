@echo off
chcp 65001 >nul
title Desinstallation - Interface style Mac
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Demande des droits administrateur...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install\desinstaller.ps1"
echo.
pause

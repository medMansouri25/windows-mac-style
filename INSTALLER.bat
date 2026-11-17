@echo off
chcp 65001 >nul
title Installation - Interface style Mac pour Windows 11
cd /d "%~dp0"

:: Demander les droits administrateur (fenetre Windows "Voulez-vous autoriser...")
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Demande des droits administrateur...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install\installer.ps1"
echo.
pause

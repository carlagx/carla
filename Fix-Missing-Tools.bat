@echo off
cls
color 0A

echo.
echo ============================================================================
echo CARLA - Fix Missing Tools (Run as Administrator)
echo ============================================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator!
    echo.
    echo Solution: Right-click this file ^> "Run as Administrator"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Missing-Tools.ps1"

pause

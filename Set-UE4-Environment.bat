@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================================
echo Set UE4_ROOT Environment Variable
echo ============================================================================
echo.

REM Check for Admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator!
    echo.
    echo Solution: Right-click on this file ^> "Run as Administrator"
    pause
    exit /b 1
)

echo [INFO] Checking for Unreal Engine 4.26...
echo.

REM Preferred: the CARLA engine fork (required for the Carla plugin),
REM then common Epic Launcher paths as fallback
set "UE4_PATHS[0]=C:\UE4carla"
set "UE4_PATHS[1]=C:\Program Files\Epic Games\UE_4.26"
set "UE4_PATHS[2]=C:\Program Files (x86)\Epic Games\UE_4.26"

set UE4_FOUND=0

for /l %%i in (0,1,2) do (
    if exist "!UE4_PATHS[%%i]!" (
        set UE4_ROOT=!UE4_PATHS[%%i]!
        set UE4_FOUND=1
        goto found_ue4
    )
)

:found_ue4
if !UE4_FOUND! equ 1 (
    echo [OK] Found UE4 at: !UE4_ROOT!
    echo.
    echo [INFO] Setting UE4_ROOT environment variable...
    setx UE4_ROOT "!UE4_ROOT!"

    if %errorlevel% equ 0 (
        echo [OK] UE4_ROOT has been set successfully!
        echo.
        echo [IMPORTANT] You must RESTART the computer for the changes to take effect!
        echo.
    ) else (
        echo [ERROR] Failed to set UE4_ROOT
    )
) else (
    echo [ERROR] UE4 4.26 installation not found!
    echo.
    echo Please install Unreal Engine 4.26.2:
    echo 1. Download Epic Games Launcher: https://www.epicgames.com/download
    echo 2. Open Epic Games Launcher
    echo 3. Go to "Unreal Engine" -> "Library"
    echo 4. Click "+" -> "Engine Versions"
    echo 5. Install version 4.26.2
    echo 6. Run this script again
    echo.
)

echo.
pause

@echo off
setlocal enabledelayedexpansion
cls
color 0A

REM ============================================================================
REM CARLA Setup Verification
REM ============================================================================

echo.
echo ============================================================================
echo CARLA (carlagx/ue4-min) - Setup Verification
echo ============================================================================
echo.

set ALL_OK=1

REM ============================================================================
echo [1] Verification of Installed Tools
echo ============================================================================
echo.

REM Git
echo [CHECK] Git...
where git >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('git --version') do echo   [OK] %%i
) else (
    echo   [FAILED] Git not found - ERROR
    set ALL_OK=0
)

REM Python
echo [CHECK] Python 3 ^(64-Bit^)...
where python >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('python --version') do echo   [OK] %%i
    for /f "tokens=*" %%i in ('python -c "import struct; print(struct.calcsize(chr(80))*8)"') do echo   [OK] %%i-Bit
) else (
    echo   [FAILED] Python not found - ERROR
    set ALL_OK=0
)

REM CMake
echo [CHECK] CMake...
where cmake >nul 2>&1
if %errorlevel% neq 0 (
    echo   [FAILED] CMake not found - ERROR
    set ALL_OK=0
    goto cmake_done
)
for /f "tokens=1,2,3" %%i in ('cmake --version') do (
    echo   [OK] CMake %%k installed
    goto cmake_done
)
:cmake_done

REM Make
echo [CHECK] Make 3.81 ^(CRITICAL!^)...
where make >nul 2>&1
if %errorlevel% neq 0 (
    echo   [FAILED] Make not found - ERROR
    set ALL_OK=0
    goto make_done
)
for /f "tokens=*" %%i in ('make --version 2^>^&1') do (
    echo   %%i
    if "%%i"=="GNU Make 3.81" echo   [OK] Correct version 3.81
    goto make_done
)
:make_done

REM 7-Zip
echo [CHECK] 7-Zip...
where 7z >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] 7-Zip installed
) else (
    echo   [FAILED] 7-Zip not found - ERROR
    set ALL_OK=0
)

REM Visual Studio
echo [CHECK] Visual Studio 2022 Community Edition...
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\" (
    echo   [OK] Visual Studio 2022 Community Edition installed
) else (
    echo   [FAILED] Visual Studio 2022 not found - ERROR
    set ALL_OK=0
)

REM Unreal Engine (CARLA fork required, see CARLA_BUILD_GUIDE.md section 1)
echo [CHECK] Unreal Engine (CARLA fork)...
if defined UE4_ROOT (
    if exist "!UE4_ROOT!\Engine\Binaries\Win64\UE4Editor.exe" (
        echo   [OK] UE4_ROOT = !UE4_ROOT! ^(engine built^)
    ) else (
        if exist "!UE4_ROOT!" (
            echo   [WARNING] UE4_ROOT exists but engine not built yet: !UE4_ROOT!
        ) else (
            echo   [FAILED] UE4_ROOT is set but path does not exist - ERROR
            set ALL_OK=0
        )
    )
) else (
    echo   [FAILED] UE4_ROOT environment variable not set - ERROR
    echo            Run Set-UE4-Environment.bat as Administrator.
    set ALL_OK=0
)
if /i "!UE4_ROOT!"=="C:\Program Files\Epic Games\UE_4.26" (
    echo   [WARNING] UE4_ROOT points to the stock Epic Launcher build.
    echo             The Carla plugin needs the CARLA engine fork ^(C:\UE4carla^).
)

echo.

REM ============================================================================
echo [2] PATH Environment Variable
echo ============================================================================
echo.

echo [CHECK] Important paths in PATH...
set PATHS_OK=1

echo %PATH% | find /i "Git\cmd" >nul
if %errorlevel% equ 0 (
    echo   [OK] Git in PATH
) else (
    echo   [WARNING] Git may not be in PATH
    set PATHS_OK=0
)

echo %PATH% | find /i "CMake\bin" >nul
if %errorlevel% equ 0 (
    echo   [OK] CMake in PATH
) else (
    echo   [WARNING] CMake may not be in PATH
    set PATHS_OK=0
)

echo %PATH% | find /i "Python" >nul
if %errorlevel% equ 0 (
    echo   [OK] Python in PATH
) else (
    echo   [WARNING] Python may not be in PATH
    set PATHS_OK=0
)

if !PATHS_OK! equ 0 (
    echo.
    echo [INFO] Solution: Restart computer!
)

echo.

REM ============================================================================
echo [3] Disk Space
echo ============================================================================
echo.

echo [CHECK] Free disk space on C:...
for /f "tokens=2" %%i in ('wmic logicaldisk get freespace ^| find "."') do (
    set /a FREE_GB=%%i/1073741824
    if !FREE_GB! gtr 150 (
        echo   [OK] !FREE_GB! GB free ^(sufficient^)
    ) else (
        echo   [WARNING] Only !FREE_GB! GB free - CARLA requires min. 150 GB
        set ALL_OK=0
    )
)

echo.

REM ============================================================================
echo [4] Firewall and Network
echo ============================================================================
echo.

echo [CHECK] Ports 2000 and 2001...
netstat -aon | find ":2000 " >nul
if %errorlevel% equ 0 (
    echo   [WARNING] Port 2000 is already in use
) else (
    echo   [OK] Port 2000 is free
)

netstat -aon | find ":2001 " >nul
if %errorlevel% equ 0 (
    echo   [WARNING] Port 2001 is already in use
) else (
    echo   [OK] Port 2001 is free
)

echo.

REM ============================================================================
echo [5] CARLA Repository
echo ============================================================================
echo.

cd /d "%~dp0"

echo [CHECK] Git Repository...
if exist ".git" (
    echo   [OK] CARLA Repository detected
    for /f "tokens=*" %%i in ('git branch --show-current') do (
        echo   [INFO] Current branch: %%i
        if "%%i"=="ue4-min" (
            echo   [OK] Correct branch ^(ue4-min^)
        ) else (
            echo   [WARNING] Branch is not ue4-min
        )
    )
) else (
    echo   [FAILED] No .git directory - not a Git repository
    set ALL_OK=0
)

echo.

REM ============================================================================
echo [5b] CARLA Content Assets
echo ============================================================================
echo.

echo [CHECK] Unreal\CarlaUE4\Content\Carla...
if exist "Unreal\CarlaUE4\Content\Carla\Maps" (
    echo   [OK] Content assets installed ^(Maps folder present^)
) else (
    echo   [FAILED] Content assets missing - the editor/package WILL crash without them.
    echo            Download the version listed in Util\ContentVersions.txt, e.g.:
    echo            curl -L -o content.tar.gz https://carla-assets.s3.us-east-005.backblazeb2.com/^<version^>.tar.gz
    echo            and extract into Unreal\CarlaUE4\Content\Carla\
    set ALL_OK=0
)

echo.

REM ============================================================================
echo [6] Python venv and wheel tooling
echo ============================================================================
echo.

echo [CHECK] carla_venv...
if exist "carla_venv\Scripts\python.exe" (
    echo   [OK] carla_venv exists
    "carla_venv\Scripts\python.exe" -c "import build" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [OK] Python 'build' package installed
    ) else (
        echo   [FAILED] Python 'build' package missing - run:
        echo            carla_venv\Scripts\python -m pip install build wheel
        set ALL_OK=0
    )
    "carla_venv\Scripts\python.exe" -c "import carla" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [OK] carla module importable ^(PythonAPI already built^)
    ) else (
        echo   [INFO] carla module not built yet ^(run Build-CARLA.bat option 1^)
    )
) else (
    echo   [FAILED] carla_venv not found - create it:
    echo            python -m venv carla_venv
    set ALL_OK=0
)

echo.

REM ============================================================================
echo Summary
echo ============================================================================
echo.

if !ALL_OK! equ 1 (
    color 0A
    echo [SUCCESS] All critical components are installed and configured!
    echo.
    echo [INFO] You can now proceed:
    echo   1. Run: Build-CARLA.bat
    echo   2. Option 1 builds the Python API, option 2 the UE4 editor
    echo   3. Option 3 creates the standalone server package
) else (
    color 0C
    echo [ERROR] There are still problems with the installation!
    echo.
    echo [INFO] Please fix the errors marked with [FAILED]:
    echo   - Check CARLA_BUILD_GUIDE.md Troubleshooting section
    echo   - Run Install-CARLA-Tools.bat again
    echo   - Restart the computer
)

echo.
pause

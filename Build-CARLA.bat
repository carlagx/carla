@echo off
setlocal enabledelayedexpansion
title CARLA Build (carlagx/ue4-min)

REM ============================================================================
REM CARLA Build Menu - carlagx fork, branch ue4-min
REM ============================================================================
REM Loads the MSVC x64 environment itself, so it can be started from any
REM normal cmd/Explorer double-click. No administrator rights required.
REM See CARLA_BUILD_GUIDE.md for details and troubleshooting.
REM ============================================================================

cd /d "%~dp0"
echo.
echo ============================================================================
echo CARLA Build - %cd%
echo ============================================================================
echo.

REM --- Load MSVC x64 environment (required for cl.exe, this was root cause #2)
if not defined VSCMD_ARG_TGT_ARCH (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    if not exist "!VCVARS!" (
        echo [ERROR] vcvars64.bat not found: !VCVARS!
        echo         Install Visual Studio 2022 Community with C++ workload.
        pause
        exit /b 1
    )
    echo [INFO] Loading MSVC x64 environment...
    call "!VCVARS!" >nul
)
where cl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] cl.exe not available even after vcvars64 - check the VS installation.
    pause
    exit /b 1
)
echo [OK] MSVC x64 environment active

REM --- Prefer Windows-native tools (tar=bsdtar) over Git's GNU tools
set "PATH=C:\Windows\System32;%PATH%"

REM --- .NET 4.6.2 reference assemblies for UBT/AutomationTool (root cause #12)
if exist "C:\tools\netfx462\build\.NETFramework\v4.6.2\mscorlib.dll" (
    set "TargetFrameworkRootPath=C:\tools\netfx462\build"
)

REM --- Activate Python venv
if exist "carla_venv\Scripts\activate.bat" (
    call carla_venv\Scripts\activate.bat
    echo [OK] Python venv activated
) else (
    echo [ERROR] carla_venv not found. Create it first:
    echo         python -m venv carla_venv
    echo         carla_venv\Scripts\activate.bat
    echo         python -m pip install build wheel
    pause
    exit /b 1
)

REM --- Ensure the 'build' package is available (root cause #8)
python -c "import build" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Installing missing Python packages 'build' and 'wheel'...
    python -m pip install build wheel
)

REM --- Basic checks
set TOOLS_OK=1
for %%t in (git cmake make) do (
    where %%t >nul 2>&1 || (echo [FAILED] %%t not found & set TOOLS_OK=0)
)
if not defined UE4_ROOT (
    echo [WARNING] UE4_ROOT not set - editor/package builds will fail.
    echo           Run Set-UE4-Environment.bat as Administrator.
)
if !TOOLS_OK! equ 0 (
    echo [ERROR] Missing tools - run Install-CARLA-Tools.bat as Administrator.
    pause
    exit /b 1
)
echo [OK] Tools available
echo.

:menu
echo.
echo ============================================================================
echo Menu
echo ============================================================================
echo.
echo 1^) Build Python API          (make PythonAPI - LibCarla + wheel, ~30-60 min)
echo 2^) Build + launch UE4 editor (make launch - long, opens the editor)
echo 3^) Create server package     (make package - standalone CarlaUE4.exe in Dist\)
echo 4^) Download assets           (Update.bat - tens of GB, optional for ue4-min)
echo 5^) Test Python API           (import carla)
echo 6^) Clean build files         (make clean)
echo 7^) Exit
echo.

set CHOICE=
set /p CHOICE="Choose an option (1-7): "

if "%CHOICE%"=="1" goto build_python
if "%CHOICE%"=="2" goto build_launch
if "%CHOICE%"=="3" goto build_package
if "%CHOICE%"=="4" goto download_assets
if "%CHOICE%"=="5" goto test_python
if "%CHOICE%"=="6" goto clean
if "%CHOICE%"=="7" goto end
goto menu

:build_python
echo.
echo [INFO] Building Python API (started %date% %time%)...
make PythonAPI
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed - see CARLA_BUILD_GUIDE.md section 5 for symptoms.
) else (
    echo.
    echo [OK] Python API built. Wheel: PythonAPI\carla\dist\
)
pause
goto menu

:build_launch
echo.
echo [INFO] Building CarlaUE4Editor and launching the editor...
echo [INFO] Note: this opens the Unreal editor. The standalone server
echo        comes from option 3 (make package).
make launch
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed - see CARLA_BUILD_GUIDE.md section 5.
)
pause
goto menu

:build_package
echo.
echo [INFO] Creating standalone server package (long build)...
make package
if errorlevel 1 (
    echo.
    echo [ERROR] Packaging failed - see CARLA_BUILD_GUIDE.md section 5.
) else (
    echo.
    echo [OK] Package created under Dist\ - run CarlaUE4.exe from
    echo      Dist\CARLA_*\WindowsNoEditor\
)
pause
goto menu

:download_assets
echo.
echo [INFO] Downloading content assets via Update.bat (tens of GB)...
if exist "Update.bat" (
    call Update.bat
) else (
    echo [ERROR] Update.bat not found.
)
pause
goto menu

:test_python
echo.
python -c "import carla; print('OK  carla imported from:', carla.__file__)" || echo [FAILED] import carla - build the Python API first (option 1)
pause
goto menu

:clean
echo.
set CONFIRM=
set /p CONFIRM="Delete all build outputs? Next build takes much longer. (y/n): "
if /i not "%CONFIRM%"=="y" goto menu
make clean
pause
goto menu

:end
endlocal
exit /b 0

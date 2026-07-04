@echo off
setlocal enabledelayedexpansion

REM Color for output
color 0A
cls

echo.
echo ============================================================================
echo CARLA 0.9.16 - Automatic Tool Installation for Windows
echo ============================================================================
echo.

REM Check for Admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator!
    echo.
    echo Solution: Right-click on the BAT file ^> "Run as Administrator"
    pause
    exit /b 1
)

echo [INFO] Administrator rights detected
echo.

REM Check for Winget or Chocolatey
where winget >nul 2>&1
set WINGET_AVAILABLE=0
if %errorlevel% equ 0 (
    set WINGET_AVAILABLE=1
    echo [INFO] Winget detected - will be used for installation
)

where choco >nul 2>&1
set CHOCO_AVAILABLE=0
if %errorlevel% equ 0 (
    set CHOCO_AVAILABLE=1
    if !WINGET_AVAILABLE! equ 0 (
        echo [INFO] Chocolatey detected - will be used for installation
    )
)

if !WINGET_AVAILABLE! equ 0 if !CHOCO_AVAILABLE! equ 0 (
    echo [WARNING] Neither Winget nor Chocolatey found
    echo [INFO] Will try to install Chocolatey...
    echo.
    call :InstallChocolatey
)

echo.
echo ============================================================================
echo Phase 1: Check for Existing Installations
echo ============================================================================
echo.

REM Check Git
echo [CHECK] Git...
where git >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%i in ('git --version') do set GIT_VERSION=%%i
    echo [OK] Git !GIT_VERSION! is installed
) else (
    echo [INSTALL] Installing Git...
    call :InstallGit
)
echo.

REM Check Python
echo [CHECK] Python 3 ^(64-Bit^)...
where python >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
    python -c "import struct; arch=struct.calcsize('P'); print(arch*8)" >nul 2>&1
    if %errorlevel% equ 0 (
        for /f "tokens=*" %%i in ('python -c "import struct; print(struct.calcsize(chr(80))*8)"') do set PYTHON_BITS=%%i
        echo [OK] Python !PYTHON_VERSION! ^(!PYTHON_BITS!-Bit^) is installed
    ) else (
        echo [WARNING] Python 32-Bit detected - will be replaced with 64-Bit
        call :InstallPython
    )
) else (
    echo [INSTALL] Installing Python 3.x ^(64-Bit^)...
    call :InstallPython
)
echo.

REM Check CMake
echo [CHECK] CMake...
where cmake >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%i in ('cmake --version') do set CMAKE_VERSION=%%i
    echo [OK] CMake !CMAKE_VERSION! is installed
) else (
    echo [INSTALL] Installing CMake...
    call :InstallCMake
)
echo.

REM Check Visual Studio 2022
echo [CHECK] Visual Studio 2022 Community Edition...
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\" (
    echo [OK] Visual Studio 2022 Community Edition is installed
) else (
    echo [INSTALL] Installing Visual Studio 2022 Community Edition...
    call :InstallVisualStudio
)
echo.

REM Check Make
echo [CHECK] Make 3.81...
where make >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('make --version 2^>^&1') do (
        set MAKE_VERSION=%%i
        goto make_check_done
    )
    :make_check_done
    echo [OK] Make is installed - please verify manually that version is 3.81
    echo       Output: !MAKE_VERSION!
) else (
    echo [INSTALL] Installing Make 3.81...
    call :InstallMake
)
echo.

REM Check 7-Zip
echo [CHECK] 7-Zip...
where 7z >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] 7-Zip is installed
) else (
    echo [INSTALL] Installing 7-Zip...
    call :Install7Zip
)
echo.

echo ============================================================================
echo Phase 1b: Create Python Virtual Environment (venv)
echo ============================================================================
echo.

call :CreateVirtualEnvironment

echo.
echo ============================================================================
echo Phase 2: Update PATH Environment Variable
echo ============================================================================
echo.

call :UpdatePATH

echo.
echo ============================================================================
echo Phase 3: Set Environment Variables
echo ============================================================================
echo.

call :SetEnvironmentVariables

echo.
echo ============================================================================
echo Phase 4: Verification
echo ============================================================================
echo.

REM Verify all tools
call :VerifyInstallation

echo.
echo ============================================================================
echo INSTALLATION COMPLETED
echo ============================================================================
echo.
echo [IMPORTANT] Next steps:
echo.
echo 1. RESTART COMPUTER (required for PATH and environment variables!)
echo.
echo 2. After restart:
echo    - Install Epic Games Launcher
echo    - Install Unreal Engine 4.26.2
echo    - See CARLA_BUILD_GUIDE.md for details
echo.
echo 3. Prepare CARLA Repository:
echo    cd C:\Users\wkuzn\carla
echo    git checkout 0.9.16
echo    .\Update.bat
echo.
echo 4. Activate Python Virtual Environment:
echo    cd C:\Users\wkuzn\carla
echo    .\carla_venv\Scripts\activate.bat
echo.
echo 5. Compile CARLA:
echo    make launch
echo.
echo Detailed instructions: CARLA_BUILD_GUIDE.md
echo.
pause
exit /b 0

REM ============================================================================
REM FUNCTIONS
REM ============================================================================

:InstallChocolatey
echo [INFO] Installing Chocolatey...
powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
set CHOCO_AVAILABLE=1
goto :eof

:InstallGit
if !WINGET_AVAILABLE! equ 1 (
    winget install -e --id Git.Git --silent --accept-source-agreements
) else if !CHOCO_AVAILABLE! equ 1 (
    choco install git -y
) else (
    echo [ERROR] No package manager available - please install Git manually
    echo From: https://git-scm.com/download/win
)
goto :eof

:InstallPython
if !WINGET_AVAILABLE! equ 1 (
    winget install -e --id Python.Python.3.11 --silent --accept-source-agreements
) else if !CHOCO_AVAILABLE! equ 1 (
    choco install python -y
) else (
    echo [ERROR] No package manager available - please install Python manually
    echo From: https://www.python.org/downloads/
)
goto :eof

:InstallCMake
if !WINGET_AVAILABLE! equ 1 (
    winget install -e --id Kitware.CMake --silent --accept-source-agreements
) else if !CHOCO_AVAILABLE! equ 1 (
    choco install cmake -y
) else (
    echo [ERROR] No package manager available - please install CMake manually
    echo From: https://cmake.org/download/
)
goto :eof

:InstallVisualStudio
echo.
echo [INFO] Visual Studio 2022 Community Edition will be downloaded...
echo [INFO] Size: ^~5-7 GB
echo [INFO] This may take 10-20 minutes...
echo.

REM Download Visual Studio 2022 Community Installer
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Write-Host '[INFO] Starting download...'; (New-Object System.Net.WebClient).DownloadFile('https://aka.ms/vs/17/release/vs_community.exe', '%TEMP%\vs_community.exe'); Write-Host '[OK] Download completed'}"

if %errorlevel% equ 0 (
    echo.
    echo [INFO] Installation started - this takes 30-45 minutes...
    echo [INFO] This will install:
    echo   - Desktop development with C++
    echo   - MSVC v143 C++ x64/x86 Build Tools
    echo   - CMake Tools for Windows
    echo   - Windows 11 SDK
    echo.
    echo [IMPORTANT] The installation window will open!
    echo.
    timeout /t 3

    "%TEMP%\vs_community.exe" ^
        --add Microsoft.VisualStudio.Workload.NativeDesktop ^
        --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
        --add Microsoft.VisualStudio.Component.Windows11SDK.22000 ^
        --add Microsoft.VisualStudio.Component.CMake.Win32 ^
        --includeRecommended ^
        --quiet ^
        --norestart

    if %errorlevel% equ 0 (
        echo.
        echo [OK] Visual Studio 2022 Community Edition installed successfully!
        del "%TEMP%\vs_community.exe"
    ) else (
        echo.
        echo [WARNING] VS 2022 installation had errors
        echo [INFO] Please check manually or restart
    )
) else (
    echo.
    echo [ERROR] Visual Studio download failed
    echo [INFO] Please install manually:
    echo https://visualstudio.microsoft.com/downloads/
    echo.
    echo [IMPORTANT] When installing, select:
    echo   - Desktop development with C++
    echo   - Windows SDK 11
)
goto :eof

:InstallMake
echo.
echo [INFO] Installing Make 3.81...

REM Make can be installed via GNUWin32 or Chocolatey
if !CHOCO_AVAILABLE! equ 1 (
    choco install make -y
) else (
    echo [ERROR] No package manager available
    echo [INFO] Please install manually:
    echo https://gnuwin32.sourceforge.io/packages/make.htm
    echo Make sure version 3.81 is installed!
)
goto :eof

:Install7Zip
if !WINGET_AVAILABLE! equ 1 (
    winget install -e --id 7zip.7zip --silent --accept-source-agreements
) else if !CHOCO_AVAILABLE! equ 1 (
    choco install 7zip -y
) else (
    echo [ERROR] No package manager available - please install 7-Zip manually
    echo From: https://www.7-zip.org/
)
goto :eof

:CreateVirtualEnvironment
echo [INFO] Creating Python Virtual Environment...
echo.

where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found - venv could not be created
    goto :eof
)

cd /d "%~dp0"

if exist "carla_venv" (
    echo [OK] venv already exists at: %cd%\carla_venv
) else (
    echo [INFO] Creating venv in directory: %cd%\carla_venv
    python -m venv carla_venv

    if %errorlevel% equ 0 (
        echo [OK] Virtual Environment created successfully!
        echo.
        echo [INFO] venv path: %cd%\carla_venv
        echo [INFO] Activation: %cd%\carla_venv\Scripts\activate.bat
        echo.

        REM Upgrade pip
        echo [INFO] Updating pip...
        call carla_venv\Scripts\activate.bat
        python -m pip install --upgrade pip setuptools wheel
        call carla_venv\Scripts\deactivate.bat

        echo [OK] pip updated
    ) else (
        echo [ERROR] Virtual Environment could not be created
    )
)

cd /d "%~dp0"
goto :eof

:UpdatePATH
echo [INFO] Updating PATH environment variable...

REM Add common paths to PATH
setx PATH "%PATH%;C:\Program Files\Git\cmd"
setx PATH "%PATH%;C:\Program Files\CMake\bin"
setx PATH "%PATH%;C:\Program Files\Python311"
setx PATH "%PATH%;C:\Program Files\Python311\Scripts"
setx PATH "%PATH%;C:\Program Files\7-Zip"
setx PATH "%PATH%;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64"
setx PATH "%PATH%;C:\Program Files (x86)\GnuWin32\bin"

echo [OK] PATH updated

goto :eof

:SetEnvironmentVariables
echo [INFO] Setting environment variables...

REM Check if UE4 is installed
if exist "C:\Program Files\Epic Games\UE_4.26" (
    setx UE4_ROOT "C:\Program Files\Epic Games\UE_4.26"
    echo [OK] UE4_ROOT = C:\Program Files\Epic Games\UE_4.26
) else (
    echo [WARNING] UE4 not yet installed
    echo [INFO] UE4_ROOT will be set after UE4 installation
    echo [INFO] See CARLA_BUILD_GUIDE.md Phase 3
)

goto :eof

:VerifyInstallation
echo [VERIFY] Verifying all installations...
echo.

set VERIFIED=1

where git >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Git
) else (
    echo [FAILED] Git - ERROR
    set VERIFIED=0
)

where python >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Python 3
) else (
    echo [FAILED] Python 3 - ERROR
    set VERIFIED=0
)

where cmake >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] CMake
) else (
    echo [FAILED] CMake - ERROR
    set VERIFIED=0
)

where make >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Make
) else (
    echo [FAILED] Make - ERROR
    set VERIFIED=0
)

where 7z >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] 7-Zip
) else (
    echo [FAILED] 7-Zip - ERROR
    set VERIFIED=0
)

if exist "C:\Program Files\Microsoft Visual Studio\2022\Community" (
    echo [OK] Visual Studio 2022
) else (
    echo [FAILED] Visual Studio 2022 - ERROR
    set VERIFIED=0
)

if exist "carla_venv" (
    echo [OK] Python Virtual Environment (venv)
) else (
    echo [FAILED] venv - ERROR
    set VERIFIED=0
)

echo.
if !VERIFIED! equ 1 (
    echo [OK] All tools installed successfully!
) else (
    echo [WARNING] Some tools could not be verified
    echo [INFO] Please check manually and restart if necessary
)

goto :eof

REM End of script

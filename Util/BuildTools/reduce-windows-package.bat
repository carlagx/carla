@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM  reduce-windows-package.bat
REM  Trimmt LOSE, unnoetige Dateien aus einem bereits gebauten/entpackten
REM  Windows-CARLA-Paket (Ordner "WindowsNoEditor") - schnell, ohne Rebuild.
REM
REM  Entfernt (nur lose Dateien, NICHT den gecookten .pak-Content):
REM    - ueberzaehlige HDMaps\*.pcd  (behaelt nur die Towns in KEEP_PCD)   ~1 GB
REM    - Debug-Symbole *.pdb / *.sym / *.debug
REM    - PythonAPI\examples\nvidia   (cosmos-Demodaten)                    ~140 MB
REM    - Co-Simulation\              (SUMO/PTV-Vissim/Chrono)              ~25 MB
REM    - statische Link-Libs in CarlaDependencies (*.lib / *.a)           ~40 MB
REM    - PythonAPI\util\opendrive\TownBig.xodr                            ~15 MB
REM
REM  Aufruf:
REM    reduce-windows-package.bat "C:\Pfad\zu\WindowsNoEditor"        (fragt nach)
REM    reduce-windows-package.bat "C:\Pfad\zu\WindowsNoEditor" /y     (ohne Nachfrage)
REM    (ohne Pfad -> aktuelles Verzeichnis)
REM
REM  HINWEIS: Content-Reduktionen (Maps/Gebaeude/Fahrzeuge/Fussgaenger) sind in
REM  den .pak gecookt und koennen hier NICHT entfernt werden. Dafuer die Windows-
REM  Version aus dem reduzierten Branch bauen. Siehe reduce-package-size.report.md.
REM ============================================================================

REM --- Welche Town-HD-Punktwolken BEHALTEN (Leerzeichen-getrennt, ohne .pcd) ---
set "KEEP_PCD=Town01 Town04"

REM --- optional: komplette PythonAPI\examples loeschen (1=ja, 0=nur nvidia) ---
set "REMOVE_ALL_EXAMPLES=0"

REM --- Paket-Wurzel bestimmen ---
set "ROOT=%~1"
if "%ROOT%"=="" set "ROOT=%CD%"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
if not exist "%ROOT%\CarlaUE4" (
  echo [FEHLER] "%ROOT%" sieht nicht nach einem CARLA-Paket aus ^(kein CarlaUE4-Ordner^).
  echo Uebergib den Pfad zum entpackten WindowsNoEditor-Ordner.
  exit /b 1
)

set "ASSUME_YES=0"
if /I "%~2"=="/y" set "ASSUME_YES=1"

echo Ziel-Paket : %ROOT%
echo Behalte pcd: %KEEP_PCD%
echo.

REM --- Groesse vorher (PowerShell, sprachunabhaengig) ---
for /f %%A in ('powershell -NoProfile -Command "[long]((Get-ChildItem -LiteralPath '%ROOT%' -Recurse -File -ErrorAction SilentlyContinue ^| Measure-Object Length -Sum).Sum)" 2^>nul') do set "BEFORE=%%A"

if "%ASSUME_YES%"=="0" (
  set /p "ANS=Loeschen jetzt durchfuehren? [y/N] "
  if /I not "!ANS!"=="y" ( echo Abgebrochen. & exit /b 0 )
)

echo.
echo === Entferne ueberzaehlige Dateien ===

REM 1) HDMaps: jede .pcd loeschen, deren Town nicht in KEEP_PCD steht
if exist "%ROOT%\HDMaps" (
  for %%F in ("%ROOT%\HDMaps\*.pcd") do (
    set "KEEP=0"
    for %%K in (%KEEP_PCD%) do if /I "%%~nF"=="%%K" set "KEEP=1"
    if "!KEEP!"=="0" (
      echo   [del ] HDMaps\%%~nxF
      del /q "%%~F"
    ) else (
      echo   [keep] HDMaps\%%~nxF
    )
  )
)

REM 2) Debug-Symbole
for /r "%ROOT%\CarlaUE4\Binaries" %%F in (*.pdb *.sym *.debug) do (
  echo   [del ] %%~nxF
  del /q "%%~F"
)

REM 3) PythonAPI\examples
if "%REMOVE_ALL_EXAMPLES%"=="1" (
  if exist "%ROOT%\PythonAPI\examples" (
    echo   [rmdir] PythonAPI\examples
    rmdir /s /q "%ROOT%\PythonAPI\examples"
  )
) else (
  if exist "%ROOT%\PythonAPI\examples\nvidia" (
    echo   [rmdir] PythonAPI\examples\nvidia
    rmdir /s /q "%ROOT%\PythonAPI\examples\nvidia"
  )
)

REM 4) Co-Simulation
if exist "%ROOT%\Co-Simulation" (
  echo   [rmdir] Co-Simulation
  rmdir /s /q "%ROOT%\Co-Simulation"
)

REM 5) statische Link-Libs (zur Laufzeit nie geladen)
if exist "%ROOT%\CarlaUE4\Plugins\Carla\CarlaDependencies" (
  for /r "%ROOT%\CarlaUE4\Plugins\Carla\CarlaDependencies" %%F in (*.lib *.a) do (
    echo   [del ] %%~nxF
    del /q "%%~F"
  )
)

REM 6) Beispiel-OpenDRIVE
if exist "%ROOT%\PythonAPI\util\opendrive\TownBig.xodr" (
  echo   [del ] TownBig.xodr
  del /q "%ROOT%\PythonAPI\util\opendrive\TownBig.xodr"
)

REM --- Groesse nachher + Bilanz ---
for /f %%A in ('powershell -NoProfile -Command "[long]((Get-ChildItem -LiteralPath '%ROOT%' -Recurse -File -ErrorAction SilentlyContinue ^| Measure-Object Length -Sum).Sum)" 2^>nul') do set "AFTER=%%A"

echo.
echo === Fertig ===
if defined BEFORE if defined AFTER (
  for /f %%A in ('powershell -NoProfile -Command "[math]::Round(((%BEFORE%-%AFTER%)/1MB),1)"') do set "FREED=%%A"
  for /f %%A in ('powershell -NoProfile -Command "[math]::Round((%AFTER%/1GB),2)"') do set "NOWGB=%%A"
  echo   Freigegeben: !FREED! MB
  echo   Neue Groesse: !NOWGB! GB
)
endlocal

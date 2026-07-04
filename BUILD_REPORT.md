# CARLA Windows Build — Problem Report

**Repo:** https://github.com/carlagx/carla.git, branch `ue4-min`
**Machine:** Windows 11 Pro, VS 2022 Community (MSVC 14.44), CMake 4.3.3, Python 3.14, 24 GB RAM
**Period:** 2026-07-02 → 2026-07-04
**Outcome:** PythonAPI built and verified (`import carla` works), CarlaUE4Editor built
against the CARLA engine fork and starts cleanly (map loads, 0 errors).
`make package` verified separately — see the final status note at the bottom.

The build had **never** worked on this machine. The investigation found 13 independent
root causes; each one alone was fatal. They are listed in the order they were found.
All fixes are either committed to the repo scripts or documented in
[CARLA_BUILD_GUIDE.md](CARLA_BUILD_GUIDE.md).

## Root causes and fixes

| # | Problem | Symptom | Fix | Where |
|---|---------|---------|-----|-------|
| 1 | Entire `LibCarla/` source tree deleted from the working tree (moved to `oldLibCarla/`) | 580 files shown as `D` in `git status`; nothing to build | `git restore LibCarla` | one-time |
| 2 | Build started from plain PowerShell without the MSVC environment | `[ERROR] Can't find Visual Studio compiler (cl.exe)` in `setup.log` | Always build via `vcvars64.bat` / x64 Native Tools Prompt; `Build-CARLA.bat` now loads it itself | `Build-CARLA.bat` |
| 3 | CMake 4.3.3 removed compatibility with `cmake_minimum_required < 3.5`; zlib/xerces/proj/sumo declare ancient minimums | `Compatibility with CMake < 3.5 has been removed` during configure | `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` added to every affected cmake call | `Util/InstallersWin/install_{zlib,recast,rpclib,gtest,fastDDS,xercesc,proj}.bat`, `Util/BuildTools/BuildOSM2ODR.bat` |
| 4 | Boost toolset hardcoded `msvc-14.3`, installed MSVC is 14.44 | b2: `Did not find command for MSVC toolset`; **zero** Boost libs built, install dir contained only headers | Toolset changed to `msvc-14.4` | `Util/BuildTools/Windows.mk:78`, `Util/BuildTools/Setup.bat:74`, `Util/InstallersWin/install_boost.bat:59` |
| 5 | Windows policy `NoDefaultCurrentDirectoryInExePath=1` is set on this machine — cmd does not resolve executables from the current directory | `Der Befehl "b2" ist entweder falsch geschrieben…` although `b2.exe` was right there; same for `bootstrap.bat`, `get_dependencies.bat`, and any `.\`-less call | `.\` prefix on all cwd-relative invocations | `install_boost.bat` (b2, bootstrap), `BuildCarlaUE4.bat:150` (get_dependencies) |
| 6 | No Boost.Python configuration; the venv Python (no `include/`/`libs/`) is first on PATH | Risk of b2 picking the wrong interpreter → no `libboost_python314` | `install_boost.bat` now writes `user-config.jam` pointing at the **base** Python (`sys.base_prefix`) and passes `--user-config` | `Util/InstallersWin/install_boost.bat` |
| 7 | Boost auto-link tag mismatch: headers request `vc143`-named libs, b2 with `msvc-14.4` produces `vc144` names | `LNK1104: libboost_filesystem-vc143-mt-x64-1_90.lib` when linking the Python extension | `add_definitions(-DBOOST_ALL_NO_LIB)` in the generated `Build/CMakeLists.txt.in` (libs are linked explicitly by `setup.py`) | `Util/BuildTools/Setup.bat` (CMakeLists.txt.in generation) |
| 8 | Python `build` package not installed in the venv (a false "installed" impression came from the repo's `Build/` folder shadowing the module name on case-insensitive NTFS) | `python -m build` → `No module named build`; BuildPythonAPI claimed success anyway | `pip install build wheel` in `carla_venv`; `Build-CARLA.bat` now auto-installs it | one-time + `Build-CARLA.bat` |
| 9 | .NET Framework SDK (NetFxSDK) missing | `UnrealBuildTool: ERROR: Could not find NetFxSDK install dir` → editor build abort | .NET Framework 4.8.1 Developer Pack installed (winget `Microsoft.DotNet.Framework.DeveloperPack_4`) | one-time |
| 10 | osm2odr source download broken in Git-Bash environments: GNU `tar` (no zip support) shadows Windows bsdtar; additionally `%errorlevel%` inside parenthesized batch blocks hid the failure | `tar: This does not look like a tar archive`, then a bogus "successfully installed" | Source fetched manually once; `BuildOSM2ODR.bat` now uses `!errorlevel!` (delayed expansion) and the wrapper prepends `C:\Windows\System32` to PATH | `Util/BuildTools/BuildOSM2ODR.bat` |
| 11 | **Stock Epic Launcher UE 4.26 lacks the CARLA engine patches** (`Renderer/Public/GBufferView.h`, publicly exposed `SplineMeshSceneProxy.h` / `HLSLMaterialTranslator.h`, FoliageEdMode, …) | `fatal error C1083` on those headers when compiling the Carla plugin | Cloned and built the official engine fork `CarlaUnreal/UnrealEngine` branch `carla` at `C:\UE4carla`; `UE4_ROOT` re-pointed (setx, user level) | one-time; documented in the guide |
| 12 | The engine fork's UnrealBuildTool targets .NET Framework **4.6.2**, but only the 4.8.1 targeting pack is installed; no admin rights available overnight | `GenerateProjectFiles ERROR: UnrealBuildTool failed to compile` (MSB3644) | NuGet package `Microsoft.NETFramework.ReferenceAssemblies.net462` extracted to `C:\tools\netfx462`, `TargetFrameworkRootPath` set in the build wrappers — no admin needed | `C:\tools\netfx462`, `Build-CARLA.bat` |
| 13 | **CARLA content assets never downloaded** — `Unreal/CarlaUE4/Content/Carla` was empty (0 MB) | Editor starts, then deterministic `EXCEPTION_ACCESS_VIOLATION reading 0x38` in `UE4Editor-Carla.dll` ~40 s in (asset loads in class constructors return null) | Asset pack `20250912_2171890` (20.5 GB, per `Util/ContentVersions.txt`) downloaded and extracted to `Content/Carla` | one-time; check added to `Verify-Setup.bat` |
| 14 | `RunUAT.bat` (engine) runs `AutomationToolLauncher.exe` from its own directory — blocked by the same `NoDefaultCurrentDirectoryInExePath` policy as #5 | `make package`: Shipping build succeeds (713/713), then `Der Befehl "AutomationToolLauncher.exe" … konnte nicht gefunden werden` → BUILD FAILED | `.\` prefix on line 54 of `C:\UE4carla\Engine\Build\BatchFiles\RunUAT.bat` — **engine-local edit, must be re-applied if the engine is re-cloned** | `C:\UE4carla` (not in this repo) |

Two UE5-vs-UE4 traps found along the way (documented, no repo change needed):
- `GitDependencies.exe --prompt=false` is a UE5 flag; UE4's binary prints usage and
  exits **0**, silently downloading nothing. Call it without arguments.
- The engine's `Setup.bat` ends with a prerequisites installer that triggers a UAC
  prompt — for unattended runs call `Engine\Binaries\DotNET\GitDependencies.exe`
  directly (prerequisites were already present here).

## Verified results

- `make setup` / `make LibCarla` / `make PythonAPI` — all green; wheel
  `carla-0.9.16-cp314-cp314-win_amd64.whl` installed; `import carla` works.
- Engine fork built (4,236 actions), `C:\UE4carla\Engine\Binaries\Win64\UE4Editor.exe`.
- `make CarlaUE4Editor` — `CarlaUE4.exe` (editor target) built without errors.
- Editor launch — Carla plugin initializes, map loads (`Map check complete: 0 Error(s)`),
  no crash after the content install; first launch spends a long time building
  derived data (textures/shaders), which is expected and cached.
- `make package` — started 2026-07-04; **see the line below, updated when finished.**

**make package status:** _in progress at the time of writing — the result will be
confirmed in the session summary / this line updated._

## Housekeeping

- The Epic Launcher UE 4.26 (`C:\Program Files\Epic Games\UE_4.26`) is no longer used;
  uninstall it via the launcher to reclaim ~40 GB.
- `oldLibCarla/` (repo root) holds the previously moved-away sources; delete after review.
- `Build\content.tar.gz` is removed automatically after extraction.

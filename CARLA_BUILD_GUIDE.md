# CARLA (carlagx fork, branch `ue4-min`) — Windows Build Guide

> Verified working on 2026-07-02 on this machine.
> Fork: https://github.com/carlagx/carla.git — branch **`ue4-min`**
> Reference: [Official CARLA Windows build docs](https://carla.readthedocs.io/en/latest/build_windows/)
>
> **Just want to run the simulator?** You don't need any of this — see
> [INSTALL_WINDOWS.md](INSTALL_WINDOWS.md) (extract the package, install the
> wheel, start `CarlaUE4.exe`).

---

## 1. Environment (verified combination)

| Component | Version | Notes |
|-----------|---------|-------|
| Windows | 11 Pro | |
| Visual Studio | 2022 Community, MSVC **14.44** (toolset `msvc-14.4`) | "Desktop development with C++" workload |
| CMake | 4.3.3 | Works — repo scripts pass `CMAKE_POLICY_VERSION_MINIMUM=3.5` for old deps |
| Python | 3.14 (64-bit) + venv `carla_venv` | venv lives in the repo root |
| Boost | 1.90.0 | Pinned by `Util/BuildTools/Setup.bat` |
| GNU Make | **3.81** (`C:\tools\make381`) | Do NOT use make 4.x |
| 7-Zip | any recent | Used to extract archives |
| .NET Framework | 4.8.1 Developer Pack (NetFxSDK) | Required by UnrealBuildTool/Swarm |
| Unreal Engine | **CARLA engine fork** at `C:\UE4carla` | `UE4_ROOT=C:\UE4carla` — see below |

**Important — the engine must be the CARLA fork, not the Epic Launcher build.**
The Carla plugin uses engine-side patches (`Renderer/Public/GBufferView.h` for
GBuffer sensors, publicly exposed `SplineMeshSceneProxy.h`/`HLSLMaterialTranslator.h`,
FoliageEdMode, …) that only exist in
https://github.com/CarlaUnreal/UnrealEngine (branch **`carla`**, UE 4.26 based).
Access requires a GitHub account linked to Epic Games. Built once via:

```
git clone --depth 1 -b carla https://github.com/CarlaUnreal/UnrealEngine.git C:\UE4carla
cd C:\UE4carla
Engine\Binaries\DotNET\GitDependencies.exe     REM instead of Setup.bat: avoids the UAC prereq installer
GenerateProjectFiles.bat
Engine\Build\BatchFiles\Build.bat ShaderCompileWorker Win64 Development -WaitMutex
Engine\Build\BatchFiles\Build.bat UE4Editor Win64 Development -WaitMutex
setx UE4_ROOT C:\UE4carla
```

If `GenerateProjectFiles.bat` fails with *"UnrealBuildTool failed to compile"*
(MSB3644, missing .NET 4.6.2 reference assemblies), download the NuGet package
`Microsoft.NETFramework.ReferenceAssemblies.net462`, extract it, and set
`TargetFrameworkRootPath=<extracted>\build` in the environment before running
the engine scripts — no admin rights needed.

Helper scripts in the repo root:
- `Install-CARLA-Tools.bat` — one-time tool installation (run as Administrator)
- `Set-UE4-Environment.bat` — sets `UE4_ROOT` (run as Administrator)
- `Fix-Missing-Tools.bat` — repairs corrupted PATH entries (run as Administrator)
- `Verify-Setup.bat` — checks that everything above is in place
- `Build-CARLA.bat` — build menu (loads the MSVC environment itself)

---

## 2. One-time preparation

1. Install tools: run `Install-CARLA-Tools.bat` as Administrator, then reboot.
2. Install Unreal Engine 4.26.2 via the Epic Games Launcher, then run
   `Set-UE4-Environment.bat` as Administrator and reboot.
3. Create/verify the Python venv and install the wheel build tooling:
   ```
   python -m venv carla_venv
   carla_venv\Scripts\activate.bat
   python -m pip install build wheel
   ```
   (`python -m build` is required by `BuildPythonAPI.bat` — without the `build`
   package the wheel step fails with "No module named build".)
4. **Download the content assets** (required — the editor/server crashes without
   them, see root cause #13 in [BUILD_REPORT.md](BUILD_REPORT.md)). Look up the
   version for this release in `Util\ContentVersions.txt` (0.9.16 →
   `20250912_2171890`, ~20.5 GB) and run:
   ```
   curl -L --retry 5 -o %TEMP%\content.tar.gz https://carla-assets.s3.us-east-005.backblazeb2.com/20250912_2171890.tar.gz
   cd Unreal\CarlaUE4\Content\Carla
   C:\Windows\System32\tar.exe -xzf %TEMP%\content.tar.gz
   del %TEMP%\content.tar.gz
   ```
   (`Update.bat` is the upstream way to do the same.)
5. Run `Verify-Setup.bat` — everything should be `[OK]`.

---

## 3. Building

**Always build from an MSVC x64 environment.** Either:
- open the **"x64 Native Tools Command Prompt for VS 2022"** from the Start menu, or
- use `Build-CARLA.bat` (it calls `vcvars64.bat` for you).

Then:

```
cd C:\Users\wkuzn\carla
carla_venv\Scripts\activate.bat

make PythonAPI     REM deps + LibCarla + osm2odr + carla wheel (~30-60 min first time)
make launch        REM builds CarlaUE4Editor and opens the UE4 editor
make package       REM creates the standalone server package under Dist\
```

Notes:
- `make launch` builds and starts the **Unreal editor** — the standalone
  `CarlaUE4.exe` server only exists after `make package` (under
  `Dist\CARLA_*\WindowsNoEditor\`).
- **You do not need to open the editor to produce a server package.**
  `make package` cooks the content and produces the standalone build directly.
  Expect several hours on the first run (asset cooking); later runs reuse the
  Derived Data Cache and are much faster.
- The build wrappers must have `TargetFrameworkRootPath=C:\tools\netfx462\build`
  in the environment (AutomationTool/UBT target .NET 4.6.2 — root cause #12).
  `Build-CARLA.bat` sets this automatically.
- Assets: `Update.bat` downloads the content library (tens of GB). The
  `ue4-min` fork is intentionally minimal — only run it if you need the full
  asset set.
- Verify the Python API from the venv:
  ```
  python -c "import carla; print(carla.__version__ if hasattr(carla,'__version__') else carla.__file__)"
  ```

---

## 4. Why the build used to fail here (all fixed)

These root causes were identified and fixed on 2026-07-02. The fixes live in
the repo scripts, so a fresh `make` run just works — this list is for
understanding and for re-diagnosing similar issues.

| # | Root cause | Fix (where) |
|---|-----------|-------------|
| 1 | The whole `LibCarla/` source tree had been moved to `oldLibCarla/` — nothing to build | `git restore LibCarla` |
| 2 | `Setup.bat` was run from a plain PowerShell — no `cl.exe` in PATH | Always build via vcvars64 / Native Tools Prompt (`Build-CARLA.bat` does this) |
| 3 | CMake 4.x removed compatibility with `cmake_minimum_required < 3.5` — zlib, xerces, proj, sumo/osm2odr failed to configure | `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` added in `Util/InstallersWin/install_{zlib,recast,rpclib,gtest,fastDDS,xercesc,proj}.bat` and `Util/BuildTools/BuildOSM2ODR.bat` |
| 4 | Boost toolset was hardcoded `msvc-14.3`, but installed MSVC is 14.44 → b2 built **zero** libraries | `msvc-14.4` in `Windows.mk`, `Setup.bat`, `install_boost.bat` |
| 5 | Windows policy `NoDefaultCurrentDirectoryInExePath=1` is set on this machine → `b2`/`bootstrap.bat` not found in their own directory | `.\b2` / `call .\bootstrap.bat` in `install_boost.bat` |
| 6 | No Python config for Boost.Python; the venv Python (no `libs/` dir) confused b2 | `install_boost.bat` now writes `user-config.jam` pointing at the **base** Python 3.14 (`sys.base_prefix`) |
| 7 | Boost auto-link requested `*-vc143-*.lib` while b2 produced `*-vc144-*.lib` → LNK1104 in the PythonAPI link | `add_definitions(-DBOOST_ALL_NO_LIB)` in the `CMakeLists.txt.in` generation in `Setup.bat` (libs are linked explicitly by `setup.py`) |
| 8 | `python -m build` failed: `build` package not installed (a false "OK" came from the repo's `Build/` folder shadowing the module name on case-insensitive NTFS) | `pip install build wheel` in the venv |

Additional environment quirks worth knowing:
- **GNU tools vs. Windows tools**: if you build from a Git-Bash-derived
  environment, Git's GNU `tar` (no zip support) can shadow Windows' bsdtar.
  Build from a plain Native Tools Prompt, or prepend `C:\Windows\System32` to
  PATH.
- A stale, half-populated dependency install dir (e.g. `Build\boost-…-install`
  with headers but no `lib\`) makes the installer skip via its
  "already exists" check. Delete the install dir to force a rebuild.

---

## 5. Troubleshooting quick reference

| Symptom | Cause / action |
|---------|----------------|
| `Can't find Visual Studio compiler (cl.exe)` | Not in an MSVC x64 environment — see section 3 |
| `Compatibility with CMake < 3.5 has been removed` | A dependency installer lost the policy flag — see cause #3 |
| b2 warning `Did not find command for MSVC toolset` | Toolset/MSVC mismatch — see cause #4 |
| `Der Befehl "b2" ist entweder falsch geschrieben…` | `NoDefaultCurrentDirectoryInExePath` — see cause #5 |
| `LNK1104: libboost_…-vc143-….lib` | Auto-link vs. b2 naming — see cause #7 |
| `No module named build` | see cause #8 |
| `tar: This does not look like a tar archive` | GNU tar shadowing bsdtar — see quirks above |
| Boost install exists but `lib\` is empty | Stale install dir — delete `Build\boost-1.90.0-install` and rerun |

---

## 6. Resolved on 2026-07-03 (second wave, editor build)

| # | Root cause | Fix |
|---|-----------|-----|
| 9 | .NET Framework SDK (NetFxSDK) missing → UnrealBuildTool aborted | .NET 4.8.1 Developer Pack installed via winget |
| 10 | `call get_dependencies.bat` in `BuildCarlaUE4.bat` blocked by `NoDefaultCurrentDirectoryInExePath` | `.\` prefix (line 150) |
| 11 | Stock Epic Launcher UE 4.26 lacks CARLA engine patches (`GBufferView.h`, …) → fatal C1083 | Built the CARLA engine fork at `C:\UE4carla`, `UE4_ROOT` updated |
| 12 | Engine's UBT (targets .NET 4.6.2) failed to compile: only 4.8.1 targeting pack installed | NuGet reference assemblies + `TargetFrameworkRootPath` (see section 1) |

## 7. Leftovers / housekeeping

- The Epic Games Launcher UE 4.26 install (`C:\Program Files\Epic Games\UE_4.26`)
  is no longer used by CARLA and can be uninstalled to reclaim ~40 GB.
- `oldLibCarla/` in the repo root contains the previously moved-away sources.
  It is untracked and can be deleted once you are confident nothing unique is
  in it.

# Prompt: Build a fully portable CARLA development kit for **Windows** (zip)

> Copy everything below into an AI coding agent (or follow it manually) on a
> Windows machine where CARLA already builds per the official guide:
> https://carla.readthedocs.io/en/latest/build_windows/
> Result: one zip that, after extraction on ANY Windows 10/11 x64 machine
> (no admin rights, nothing installed), immediately supports:
> `make help / launch / PythonAPI / LibCarla / package / clean / rebuild`.

---

## PROMPT (Windows)

Create a fully portable, self-contained CARLA development kit as a single zip.

### 0. Preconditions on the build machine (verify, do not skip)

- CARLA builds successfully: `make PythonAPI`, `make launch`, `make package`
  all green per the official Windows guide (VS 2022 C++ workload, CMake,
  GNU Make 3.81, Python 3.x, 7-Zip).
- The Unreal Engine used is the **CARLA engine fork** (built from source at
  e.g. `C:\UE4carla`, `UE4_ROOT` points there). A launcher-installed engine
  cannot be made portable.
- Decide the content variant:
  - **WITH content**: run `Update.bat` first so `Unreal\CarlaUE4\Content\Carla`
    is fully populated (the version listed in `Util\ContentVersions.txt`).
  - **WITHOUT content**: skip it; the kit README must then tell the target
    user to run `Update.bat` (needs internet, ~20 GB) before first launch —
    the editor **crashes** with an access violation if content is missing.

### 1. Kit layout (single root folder, extracted as-is)

```
CarlaKit\
  CarlaKit-env.bat          portable environment (see step 3)
  FirstRun.bat              one-time venv creation + offline wheel install
  Start-VSCode.bat          optional: portable VSCode wired to the workspace
  Start-Simulator.bat       run a packaged CarlaUE4.exe if present
  README.md                 usage + capability matrix
  UE4carla\                 engine fork, PREBUILT (Binaries, Intermediate kept)
  carla\                    the CARLA repo incl. Build\ (all *-install dirs!)
  toolchain\
    MSVC\<version>\         copy of VC\Tools\MSVC\<version>
    WindowsKits\10\         copy of Windows SDK: Include, Lib, bin, References
    DIA SDK\                copy from the VS folder
    NETFXSDK\<version>\     copy from Program Files (x86)\Windows Kits\NETFXSDK
  tools\
    python\Python3xx\       copy of a full CPython install (not a venv!)
    PortableGit\            official PortableGit release, extracted
    cmake\                  CMake zip distribution (bin, share)
    make381\                GNU make 3.81 binaries
    7zip\                   7z.exe + 7z.dll
    netfx462\               NuGet Microsoft.NETFramework.ReferenceAssemblies.net462, extracted
    vscode\                 optional: VSCode zip distribution + empty data\ dir (portable mode)
  wheels\                   offline wheels: the built carla wheel + pygame(-ce),
                            numpy, pip, setuptools, wheel, build (pip download --only-binary :all:)
```

Copy rules:
- Engine: exclude `.git`, `Samples`, `Templates`, `FeaturePacks`. **Keep**
  `Engine\Intermediate` (import libs needed to link project modules) and
  `Engine\DerivedDataCache` (fast first cook/editor start).
- Repo: exclude `carla_venv` (venvs are NOT relocatable — recreated by
  FirstRun.bat), old package zips under `Build\UE4Carla\*.zip`, and
  `Unreal\CarlaUE4\Saved\{Logs,Crashes}`. Keep everything else in `Build\`
  (the `*-install` dirs are the prebuilt C++ deps: boost, rpclib, xerces,
  proj, sqlite, zlib, libpng, gtest, recast, eigen, osm2odr).

### 2. Portability fixes to apply in the repo before packaging

1. `Package.bat`: support `CARLA_PACKAGE_NO_BUILD=true` → skip the two
   `Build.bat` calls and pass `-nobuild` instead of `-build` to
   `RunUAT BuildCookRun` (packaging with existing binaries, no compiler).
2. `BuildOSM2ODR.bat`: skip entirely when
   `PythonAPI\carla\dependencies\lib\osm2odr.lib` exists (source tree is not
   shipped); `FORCE_OSM2ODR=true` overrides.
3. Engine `RunUAT.bat` line ~54: `%UATExecutable%` → `.\%UATExecutable%`
   (machines with `NoDefaultCurrentDirectoryInExePath=1` fail otherwise).
   Same `.\` rule for any script that calls a neighbour exe/bat without path
   (`b2`, `bootstrap.bat`, `get_dependencies.bat`).
4. All dependency installers must already contain
   `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (CMake ≥ 4 on the target).

### 3. `CarlaKit-env.bat` — the heart of the kit

Must set, relative to `%~dp0` (no absolute paths, no registry access):
- `VCToolsInstallDir` (discover the version dir with a `for /d` loop),
  `WindowsSdkDir` + `WindowsSDKVersion`, and hand-built `INCLUDE` / `LIB`
  exactly like `vcvars64.bat` would (MSVC include + ucrt/shared/um/winrt;
  MSVC lib\x64 + ucrt\x64 + um\x64).
- `VSCMD_ARG_TGT_ARCH=x64` (so wrapper scripts skip their vcvars call).
- `PATH`: MSVC `bin\Hostx64\x64`, SDK `bin\<ver>\x64`, then
  `C:\Windows\System32` (native bsdtar must beat Git's tar!), then venv
  Scripts, bundled python, PortableGit\cmd, cmake\bin, make381, 7zip.
- `UE4_ROOT=%KIT_ROOT%UE4carla`
- `TargetFrameworkRootPath=%KIT_ROOT%tools\netfx462\build` (UBT/UAT are
  compiled by MSBuild against .NET 4.6.2 — the targeting pack is never
  installed on a fresh machine; the NuGet reference assemblies fix MSB3644
  without admin).
- `GENERATOR=NMake Makefiles` — GNU make forwards this into all build
  scripts; the CMake *Visual Studio* generator needs an installed VS
  (COM discovery) and must not be the default inside the kit.

### 4. Optional but recommended: UBT portable-toolchain patch

Stock UnrealBuildTool finds MSVC **only** via installed Visual Studio
(COM/registry), so `make launch`/full `make package`/`make rebuild` would
need VS on the target. Patch the engine's
`Engine\Source\Programs\UnrealBuildTool\Platform\Windows\UEBuildWindows.cs`
(pattern identical to the existing `LLVM_PATH` handling) to also accept:

| Env var | Insert into |
|---------|-------------|
| `UE_PORTABLE_MSVC_DIR` | `FindToolChainInstallations` (VS2017/2019 branch) via `FindVisualStudioToolChains(dir, false, ToolChainInstallations)` |
| `UE_PORTABLE_WINSDK_DIR` | `EnumerateSdkRootDirs` (add as first root) |
| `UE_PORTABLE_DIA_DIR` | `FindDiaSdkDirs` (add first, validated by `IsValidDiaSdkDir`) |
| `UE_PORTABLE_NETFXSDK_DIR` | `TryGetNetFxSdkInstallDir` (check `Include\um\mscoree.h`) |

Rebuild UBT once on the build machine
(`MSBuild UnrealBuildTool.csproj -p:Configuration=Development`), set the four
variables in `CarlaKit-env.bat`, and **verify** by deleting
`Engine\Intermediate\Build\Win64\BlankProgram` and building the
`BlankProgram` target with the variables pointing into the kit — the UBT log
must print `Using portable MSVC toolchain root at <kit>\toolchain\MSVC`.
Without the variables set, behavior is 100% stock (VS users unaffected).

### 5. `FirstRun.bat` (run once on the target)

1. `tools\python\Python3xx\python.exe -m venv carla\carla_venv`
   (recreate if present — venvs hardcode machine paths).
2. `pip install --no-index --find-links=wheels pip setuptools wheel build pygame-ce numpy`
   then the carla wheel from `wheels\`. (`pygame` classic has no wheels for
   new Python versions; `pygame-ce` does.)
3. Verify `python -c "import carla"`.

### 6. Create the zip (avoid a full staging copy)

Use several `7z a` calls into the same archive from different working
directories so archive paths come out right without copying 100+ GB:

```
cd C:\CarlaKit  && 7z a -tzip -mx=1 -mmt=on E:\CarlaKit.zip *
cd C:\          && 7z a -tzip -mx=1 -mmt=on E:\CarlaKit.zip UE4carla -x!UE4carla\.git -x!UE4carla\Samples -x!UE4carla\Templates -x!UE4carla\FeaturePacks
cd C:\Users\me  && 7z a -tzip -mx=1 -mmt=on E:\CarlaKit.zip carla -x!carla\carla_venv -x!carla\Build\UE4Carla\*.zip -x!carla\Unreal\CarlaUE4\Saved\Logs -x!carla\Unreal\CarlaUE4\Saved\Crashes
```

Run these from **cmd/batch**, not from an MSYS/Git-Bash shell (its path
mangling corrupts `-x!dir\sub` arguments). Note: 7z *updates* an existing
zip via a temp file next to it — budget 2× the final size on the target
drive during creation. WITHOUT-content variant: add
`-x!carla\Unreal\CarlaUE4\Content\Carla`.

### 7. Acceptance checklist on a target machine (no admin, no VS)

Extract to a short path (e.g. `D:\CarlaKit`), run `FirstRun.bat`, open cmd,
`call CarlaKit-env.bat`, `cd carla`, then verify **all** of:

| Command | Expectation |
|---------|-------------|
| `make help` | prints the target list |
| `make LibCarla` | rebuilds via portable MSVC + NMake generator |
| `make PythonAPI` | wheel builds; `python -c "import carla"` works |
| `make launch` | with UBT patch: builds + starts editor; without: use `make launch-only` |
| `make package` | with UBT patch: full; without: `set CARLA_PACKAGE_NO_BUILD=true` first |
| `make clean` → `make rebuild` | full cycle (requires the UBT patch) |
| packaged `CarlaUE4.exe` + client connect | server version string returned |

### 8. Known pitfalls (each one cost real debugging time)

- `NoDefaultCurrentDirectoryInExePath=1` breaks every pathless neighbour-exe
  call in batch files (`b2`, `bootstrap.bat`, `get_dependencies.bat`,
  `AutomationToolLauncher.exe`) → always `.\` prefix.
- venvs are not relocatable → never ship one, always FirstRun.
- MSBuild targeting .NET 4.6.2 fails on fresh machines (MSB3644) →
  `TargetFrameworkRootPath` + NuGet reference assemblies, no admin needed.
- CMake VS generator + vswhere/COM cannot see a copied toolchain → NMake
  generator inside the kit.
- GNU tar (from Git) shadows Windows bsdtar and cannot read zip →
  System32 first in PATH.
- Keep the kit path short: UE4 + MAX_PATH is a real risk on deep trees.
- exFAT is fine for the zip file itself; extract the kit onto NTFS.
```

---

**Deliverable**: `CarlaKit.zip` (+ optional `CarlaKit-UBTPatch-optional.zip`
overlay if you ship the UBT patch separately), verified against the
checklist in step 7.

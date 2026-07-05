# Prompt: Build a fully portable CARLA development kit for **Linux** (tar)

> Copy everything below into an AI coding agent (or follow it manually) on a
> Linux machine where CARLA already builds per the official guide:
> https://carla.readthedocs.io/en/latest/build_linux/
> Result: one tar archive that, after extraction on ANY x86-64 Linux with a
> GPU (no root, nothing installed), immediately supports:
> `make help / launch / PythonAPI / LibCarla / package / clean / rebuild`.

---

## PROMPT (Linux)

Create a fully portable, self-contained CARLA development kit as a single
tar archive. Use **tar** (not zip) — symlinks and execute permissions inside
the engine and toolchain must survive.

### 0. Preconditions on the build machine (verify, do not skip)

- CARLA builds successfully per the official Linux guide: `make PythonAPI`,
  `make launch`, `make package` all green.
- Unreal Engine is the **CARLA engine fork** built from source (e.g.
  `~/UE4carla`, `UE4_ROOT` set).
- Build machine distro should be at least as old as the oldest intended
  target (glibc compatibility: binaries built on newer glibc do not run on
  older). Building on Ubuntu LTS n-1 is a safe default.
- Decide the content variant:
  - **WITH content**: run `./Update.sh` first so
    `Unreal/CarlaUE4/Content/Carla` is fully populated.
  - **WITHOUT content**: exclude that folder; kit README must say to run
    `./Update.sh` on the target before first launch (editor crashes on
    missing content).

### 1. Kit layout

```
CarlaKit/
  carlakit-env.sh           portable environment (source it; see step 3)
  first-run.sh              one-time venv creation + offline wheel install
  start-vscode.sh           optional: portable VSCode wired to the workspace
  start-simulator.sh        run a packaged CarlaUE4.sh if present
  README.md
  UE4carla/                 engine fork, PREBUILT (keep Intermediate + DDC)
  carla/                    the CARLA repo incl. Build/ (all *-install dirs)
  toolchain/
    micromamba/             micromamba binary + a prefix with the compilers
  tools/
    python/                 python-build-standalone (indygreg) full CPython
    cmake/                  cmake-<ver>-linux-x86_64 tarball, extracted
    ninja/, make/           static/portable binaries
    vscode/                 optional: VSCode .tar.gz + empty data/ (portable mode)
  wheels/                   offline wheels: built carla wheel + pygame(-ce),
                            numpy, pip, setuptools, wheel, build
```

### 2. The two toolchain layers (this is the key Linux insight)

**Engine side (UBT) — already portable by design.** Linux UE4.26 compiles
with its own bundled clang toolchain
(`Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/v17_clang-10.0.1-centos7`
or via the official `LINUX_MULTIARCH_ROOT` environment variable). Ship that
directory inside `UE4carla` (it is there after `Setup.sh`) and set
`LINUX_MULTIARCH_ROOT` in `carlakit-env.sh`. **No UBT patch is needed on
Linux** — this is a supported mechanism.

**LibCarla/PythonAPI side — bundle a relocatable compiler.** The repo
scripts expect `clang++`/`clang` (pinned major version, see `Setup.sh`) plus
cmake/make/ninja. System compilers are not portable; instead create a
micromamba prefix inside the kit:

```
./micromamba create -p ./toolchain/prefix -c conda-forge \
    clang=<version-carla-expects> clangxx lld cmake make ninja
```

conda-forge compiler packages are built relocatable (RPATH-patched), require
no root, and work from any path. Alternative: a portable LLVM release
tarball (llvm.org) + static cmake/ninja — also fine; micromamba is simply
one command.

### 3. `carlakit-env.sh`

```bash
export KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UE4_ROOT="$KIT_ROOT/UE4carla"
export LINUX_MULTIARCH_ROOT="$UE4_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/"
export PATH="$KIT_ROOT/toolchain/prefix/bin:$KIT_ROOT/tools/cmake/bin:$KIT_ROOT/tools/python/bin:$KIT_ROOT/carla/carla_venv/bin:$PATH"
export CC="$KIT_ROOT/toolchain/prefix/bin/clang"
export CXX="$KIT_ROOT/toolchain/prefix/bin/clang++"
# make forwards this into the build scripts if they honor $(GENERATOR);
# Ninja avoids any system generator dependency
export GENERATOR="Ninja"
```

No absolute machine paths anywhere — everything derives from `KIT_ROOT`.

### 4. Portability fixes in the repo before packaging

1. `Util/BuildTools/Package.sh`: add a `CARLA_PACKAGE_NO_BUILD=true` mode
   that skips the `Build.sh` compile steps and passes `-nobuild` instead of
   `-build` to `RunUAT.sh BuildCookRun` (packaging with existing binaries).
2. `Util/BuildTools/BuildOSM2ODR.sh`: skip when
   `PythonAPI/carla/dependencies/lib/libosm2odr.a` exists and the source
   tree is absent (`FORCE_OSM2ODR=true` overrides).
3. Check every `Setup.sh` dependency installer for hardcoded `/usr` compiler
   paths; they must respect `$CC`/`$CXX`.
4. If the target may have CMake ≥ 4: dependency installers need
   `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (old third-party CMakeLists).

### 5. `first-run.sh` (run once on the target)

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
rm -rf carla/carla_venv
tools/python/bin/python3 -m venv carla/carla_venv
carla/carla_venv/bin/pip install --no-index --find-links=wheels \
    pip setuptools wheel build pygame-ce numpy
carla/carla_venv/bin/pip install --no-index --find-links=wheels wheels/carla-*.whl
carla/carla_venv/bin/python -c "import carla; print('import carla OK')"
```

venvs hardcode interpreter paths — always recreate on the target, never ship.

### 6. What to include / exclude

- Engine: exclude `.git`, `Samples`, `Templates`, `FeaturePacks`.
  **Keep** `Engine/Intermediate`, `Engine/DerivedDataCache`,
  `Engine/Binaries` and the bundled clang SDK dir.
- Repo: exclude `carla_venv`, `Build/UE4Carla/*.tar.gz` (old packages),
  `Unreal/CarlaUE4/Saved/Logs`, `Saved/Crashes`.
  Keep all `Build/*-install` dirs (prebuilt boost, rpclib, xerces, proj,
  sqlite, zlib, libpng, gtest, recast, eigen, osm2odr) and, for fast
  repackaging, `Unreal/CarlaUE4/Saved/Cooked`.
- WITHOUT-content variant: additionally exclude
  `carla/Unreal/CarlaUE4/Content/Carla`.

### 7. Create the tar

```bash
cd /
tar -c \
  --exclude='UE4carla/.git' --exclude='UE4carla/Samples' \
  --exclude='UE4carla/Templates' --exclude='UE4carla/FeaturePacks' \
  -C /path/above/kit CarlaKit \
  -C /path/above/engine UE4carla \
  -C /home/me carla \
  --exclude='carla/carla_venv' \
  --exclude='carla/Unreal/CarlaUE4/Saved/Logs' \
  -I 'zstd -T0 -3' -f /mnt/external/CarlaKit-linux.tar.zst
```

(Adjust `-C` juggling or stage with symlinks + `--dereference`; the point:
one archive, no 100 GB staging copy, zstd multithreaded.) The tar itself may
live on any filesystem; **extract onto ext4/xfs**, not FAT/exFAT/NTFS —
symlinks and the execute bits must survive.

### 8. Acceptance checklist on a target machine (no root)

Extract, `./first-run.sh`, `source carlakit-env.sh`, `cd carla`, verify:

| Command | Expectation |
|---------|-------------|
| `make help` | prints the target list |
| `make LibCarla` | rebuilds with the kit clang (check `which clang++`) |
| `make PythonAPI` | wheel builds; `python -c "import carla"` works |
| `make launch` | UBT uses `LINUX_MULTIARCH_ROOT` clang; editor starts (needs Vulkan-capable GPU + X11/Wayland) |
| `make package` | full build+cook+archive; or `CARLA_PACKAGE_NO_BUILD=true make package` for cook-only |
| `make clean` → `make rebuild` | full cycle with kit toolchain only |
| packaged `CarlaUE4.sh` + client connect | server version string returned |

### 9. Known pitfalls

- **glibc**: kit binaries run only on distros with glibc ≥ build machine's.
  Build on old LTS. `patchelf`/AppImage tricks are NOT needed if you respect
  this one rule.
- Runtime libs the kit cannot bring: GPU/Vulkan drivers, X11/Wayland client
  libs, libasound — present on every desktop distro; document them.
- venv not relocatable → first-run.sh, never ship the venv.
- `Setup.sh` re-downloading deps on the target: make sure every installer
  short-circuits when its `Build/*-install` dir exists (same idempotency the
  Windows installers have).
- Keep the kit path free of spaces; some engine scripts break on them.
- If the repo's `make` targets hardcode `Visual Studio`-style generators
  anywhere (they should not on Linux), Ninja from the kit is the safe
  default.
```

---

**Deliverable**: `CarlaKit-linux.tar.zst` (WITH-content) or
`CarlaKit-linux-nocontent.tar.zst`, verified against the checklist in
step 8.

# 🚗 CARLA 0.9.16 Complete Build Guide for Ubuntu 22.04 LTS

**Complete guide to building CARLA from source on Ubuntu 22.04 with the critical Xerces-C pthread-linking fix.**

---

## Table of Contents

1. [Prerequisites & System Requirements](#prerequisites--system-requirements)
2. [The Xerces-C pthread-Linking Bug](#the-xerces-c-pthread-linking-bug)
3. [Installation Steps](#installation-steps)
4. [Building CARLA](#building-carla)
5. [Quick Setup with Automated Script](#quick-setup-with-automated-script)
6. [Testing Your Installation](#testing-your-installation)
7. [Useful Resources](#useful-resources)

---

## Prerequisites & System Requirements

### System Requirements

- **OS:** Ubuntu 22.04 LTS (or similar with glibc ≥ 2.34)
- **RAM:** Minimum 16 GB, recommended 32 GB
- **Disk Space:** Minimum 150 GB (CARLA: ~80 GB, UE4 build objects: ~50 GB, Content: ~20 GB)
- **GPU:** NVIDIA GPU with CUDA support (optional for server mode, required for rendering)
- **Network:** Good internet connection (Download ~50 GB)

### Required Tools

```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install build essentials
sudo apt-get install -y \
  build-essential \
  g++-12 \
  cmake \
  ninja-build \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  git \
  git-lfs \
  wget \
  curl \
  aria2 \
  libvulkan1 \
  libpng-dev \
  libtiff5-dev \
  libjpeg-dev \
  autoconf
```

### Verify Installation

```bash
# Check Python version (3.10+ recommended)
python3 --version

# Check available tools
which git cmake make ninja python3
```

### Download Unreal Engine 4.26

CARLA 0.9.16 requires a custom-built Unreal Engine 4.26 from NVIDIA's fork.

**Important:** This step takes several hours and requires ~100 GB of disk space.

```bash
# Create directory for UE4
mkdir -p ~/UnrealEngine_4.26_src
cd ~/UnrealEngine_4.26_src

# Clone NVIDIA's UE4 fork (contains CARLA-specific patches)
git clone --branch carla --depth 1 \
  https://github.com/CarlaUnreal/UnrealEngine.git .

# Build UE4 (this will take 2-4 hours)
# Follow the official CARLA build instructions for your platform
# See: https://carla.readthedocs.io/en/latest/build_linux/
```

**Official Reference:**
- CARLA UE4 Build Instructions: https://carla.readthedocs.io/en/latest/build_linux/
- UnrealEngine Repository: https://github.com/CarlaUnreal/UnrealEngine

After building, set:
```bash
export UE4_ROOT=~/UnrealEngine_4.26_src/Engine
```

---

## The Xerces-C pthread-Linking Bug

### Problem Description

On **Ubuntu 22.04 with glibc ≥ 2.34**, the pthread symbols were merged into `libc` and `libpthread.so` became an empty stub, so executables that relied on implicit pthread linkage now need an explicit `-pthread`/`-lpthread`.

When CARLA's build system compiles Xerces-C 3.2.3, it also builds the test/sample/doc executable targets, which link statically without passing a `-pthread` flag. This causes **linker errors**:

```
undefined reference to `pthread_create'
undefined reference to `pthread_join'
... (similar pthread symbol errors)
```

### Root Cause Analysis

Inspecting Xerces-C 3.2.3's build, the cause is:
- The top-level `CMakeLists.txt` unconditionally adds helper targets via `add_subdirectory(tests)`, `add_subdirectory(samples)` and `add_subdirectory(doc)`.
- A plain `ninja` invocation builds the default `all` target, which compiles **and links** those helper executables.
- On glibc ≥ 2.34 those executables fail to link the pthread symbols, aborting the build — even though the only artifact CARLA needs, the static library `libxerces-c.a`, builds fine.
- This only bites the **server build**, which links against UE's bundled `libc++`/`libc++abi` (those static libs reference pthread). The client build (system gcc/libstdc++) links the full test/sample set without trouble.

### Solution: Link pthread Explicitly

The fix addresses the root cause: pass `-pthread` to the compiler/linker so the test and sample executables resolve the pthread symbols. This keeps the upstream `CMakeLists.txt` untouched and leaves all targets (including the tests) building normally.

Add `-pthread` to the `CMAKE_CXX_FLAGS` of **both** Xerces-C cmake invocations in `Util/BuildTools/Setup.sh` (client and server build).

> **Note:** Two alternatives were evaluated and rejected:
> - **Commenting out the `tests`/`samples`/`doc` subdirectories** (used by older versions of this guide) works, but patches upstream sources and disables the tests.
> - **Building only the `xerces-c` target** (`ninja xerces-c` + `-DCMAKE_SKIP_INSTALL_ALL_DEPENDENCY=ON`) does **not** work on 3.2.3: the static library and the sample binaries share CMake component `runtime`, so `ninja install` aborts trying to install sample binaries that were never built.

### Implementation

Edit the two Xerces-C cmake blocks in `Util/BuildTools/Setup.sh` (one for the client build, one for the server build) and add `-pthread` to each `-DCMAKE_CXX_FLAGS="..."`:

```bash
# Client build
-DCMAKE_CXX_FLAGS="-std=c++14 -fPIC -w -pthread"

# Server build (UE libc++)
-DCMAKE_CXX_FLAGS="-std=c++14 -stdlib=libc++ -fPIC -w -pthread ${UNREAL_HOSTED_CFLAGS} -I${LLVM_INCLUDE} -L${LLVM_LIBPATH}"
```

The `ninja` / `ninja install` commands stay unchanged.

**Verification:**
```bash
# Both Xerces blocks should now pass -pthread
grep -c "fPIC -w -pthread" Util/BuildTools/Setup.sh   # Should return: 2
```

---

## Installation Steps

### Step 1: Clone CARLA Repository

```bash
# Create workspace directory
mkdir -p ~/carla_workspace
cd ~/carla_workspace

# Clone CARLA from official repository
git clone --branch ue4-dev \
  https://github.com/carla-simulator/carla.git carla

cd carla

# (Optional) Create a feature branch for your changes
git checkout -b ubuntu22-build
```

**Official Repository:** https://github.com/carla-simulator/carla

### Step 2: Apply Xerces Fix (if not using automated script)

```bash
# Edit Setup.sh with your preferred editor
nano Util/BuildTools/Setup.sh

# Add -pthread to CMAKE_CXX_FLAGS in both Xerces-C cmake blocks (see above)

# Save and verify (should return: 2)
grep -c "fPIC -w -pthread" Util/BuildTools/Setup.sh
```

### Step 3: Set Environment Variables

```bash
# Set UE4 root (must match your actual UE4 installation)
export UE4_ROOT=~/UnrealEngine_4.26_src/Engine

# Verify it's correct
ls -d $UE4_ROOT/Engine  # Should show "Engine" directory
```

### Step 4: Run Setup.sh

```bash
# Navigate to CARLA directory
cd ~/carla_workspace/carla

# Run setup (this applies the Xerces fix if present)
./Setup.sh

# This step:
# - Downloads build dependencies
# - Applies patches (including Xerces fix)
# - Generates project files for UE4
# Typical duration: 10-20 minutes
```

### Step 5: Download Content Assets

```bash
# Download maps, models, and other content (~20 GB)
./Update.sh

# Alternative: Skip download for faster testing
# ./Update.sh --skip-download

# Typical duration: 30-60 minutes (depends on internet speed)
```

---

## Building CARLA

### Method 1: Automated Build Script (Recommended)

We provide a production-ready script that handles all steps automatically:

```bash
# Setup
mkdir -p ~/carla_build_scripts
cd ~/carla_build_scripts

# Download script and config
wget https://your-repo-url/build_carla.sh
wget https://your-repo-url/carla_build.conf
chmod +x build_carla.sh

# Edit configuration
nano carla_build.conf

# Run preflight checks
./build_carla.sh --preflight-only

# Start build
./build_carla.sh
```

**Script Features:**
- Automatic Git clone if repository doesn't exist
- Automatic Xerces-C pthread-fix detection and application
- Reuse-mode for existing repositories
- Step-by-step logging
- Robust error handling
- Progress tracking

### Method 2: Manual Build

```bash
# Navigate to CARLA directory
cd ~/carla_workspace/carla

# Build PythonAPI (C++ bindings + Python wheel)
make PythonAPI

# Expected output:
# - carla/dist/carla-0.9.16-cp310-cp310-linux_x86_64.whl
# - Typical duration: 20-30 minutes

# Build Launch (CarlaUE4.sh - the server binary)
make launch

# Typical duration: 20-30 minutes
# Expected output: ./CarlaUE4.sh binary

# Build Package (distribution tarball)
make package

# Typical output: Dist/CARLA_0.9.16.tar.gz
# Typical duration: 10-15 minutes
```

### Build Troubleshooting

**Issue: "make PythonAPI" fails with pthread errors**
```bash
# Verify the Xerces fix was applied (should return: 2)
grep -c "fPIC -w -pthread" Util/BuildTools/Setup.sh

# If not, apply it manually and re-run Setup.sh
./Setup.sh
make PythonAPI
```

**Issue: "Setup.sh" fails**
```bash
# Check UE4_ROOT
echo $UE4_ROOT
ls -d $UE4_ROOT/Engine  # Must exist

# Re-run with verbose output
./Setup.sh 2>&1 | tee setup.log
cat setup.log | grep -i "error\|warning"
```

**Issue: Out of disk space**
```bash
# Check available space
df -h

# You need:
# - CARLA source: ~5 GB
# - UE4 build objects: ~50 GB
# - Content: ~20 GB
# - Build artifacts: ~20 GB
# = ~95 GB minimum, ~150 GB recommended
```

---

## Quick Setup with Automated Script

### Complete Setup in 4 Commands

```bash
# 1. Create workspace
mkdir -p ~/carla_build_scripts && cd ~/carla_build_scripts

# 2. Get the scripts (replace with your actual URLs)
# Download build_carla.sh and carla_build.conf
cp /path/to/build_carla.sh .
cp /path/to/carla_build.conf .
chmod +x build_carla.sh

# 3. Edit configuration
# At minimum, set UE4_ROOT and CLONE_BASE_DIR
nano carla_build.conf

# 4. Run build
./build_carla.sh
```

### Configuration Checklist

Before running the script, verify in `carla_build.conf`:

```bash
# ✓ UE4 installation path exists
UE4_ROOT="/home/user/UnrealEngine_4.26_src/Engine"
ls -d $UE4_ROOT/Engine  # Must show "Engine"

# ✓ Clone directory has space
CLONE_BASE_DIR="/home/user/carla_workspace"
df -h $CLONE_BASE_DIR  # Need >100 GB free

# ✓ Python version
python3 --version  # Should be 3.10+

# ✓ Build steps (optional customization)
BUILD_STEPS=("PythonAPI" "launch" "package")
# Remove steps to skip (e.g., just PythonAPI: ("PythonAPI"))
```

### Expected Output

Successful build shows:
```
╔════════════════════════════════════════════════════════════════════╗
║  ✅ CARLA-Build erfolgreich abgeschlossen!                          ║
╚════════════════════════════════════════════════════════════════════╝

  📁 Repo        : /home/user/carla_workspace/carla
  🌳 Branch      : ue4-ubuntu22
  ⏱️  Gesamtdauer : 1h 45m 32s
  📦 Pakete      :
    • CARLA_0.9.16.tar.gz
```

---

## Testing Your Installation

### 1. Install Python Wheel

```bash
# Install the PythonAPI wheel
pip install ~/carla_workspace/carla/PythonAPI/carla/dist/carla-*.whl

# Verify installation
python3 -c "import carla; print(f'CARLA {carla.__version__} installed successfully')"
```

### 2. Start CARLA Server

```bash
# Start the server (requires GPU or --off-screen mode)
cd ~/carla_workspace/carla
./CarlaUE4.sh

# With GPU but no display (X11 not available):
./CarlaUE4.sh -RenderOffScreen

# Output should show:
# Starting CARLA
# Waiting for clients on 127.0.0.1:2000
```

### 3. Run Python Client (in another terminal)

```bash
# Keep the server running, open a new terminal

# Example: Simple client that connects and spawns a vehicle
python3 << 'EOF'
import carla
import time

# Connect to CARLA server
client = carla.Client('localhost', 2000)
client.set_timeout(10.0)

# Get world
world = client.get_world()
print(f"Connected to CARLA {world.client.get_server_version()}")

# Get blueprint library
blueprints = world.get_blueprint_library()

# Spawn a vehicle
vehicle_bp = blueprints.filter("vehicle.tesla.model3")[0]
transform = world.get_map().get_spawn_points()[0]
vehicle = world.spawn_actor(vehicle_bp, transform)
print(f"Spawned {vehicle.type_id}")

# Clean up
vehicle.destroy()
EOF
```

### 4. Run Official Examples

```bash
cd ~/carla_workspace/carla

# Manual control (keyboard control with pygame)
python3 PythonAPI/examples/manual_control.py

# Dynamic weather example
python3 PythonAPI/examples/weather.py

# Spawn NPCs example
python3 PythonAPI/examples/spawn_npc.py
```

### 5. Verify Core Functionality

```python
# Test script: core_test.py
import carla

client = carla.Client('localhost', 2000)
world = client.get_world()

# Test 1: Can we get the map?
print(f"Map: {world.get_map().name}")

# Test 2: Can we get weather?
weather = world.get_weather()
print(f"Weather: {weather.sun_altitude_angle}°")

# Test 3: Can we spawn an actor?
bp = world.get_blueprint_library().find('vehicle.tesla.model3')
transform = world.get_map().get_spawn_points()[0]
vehicle = world.spawn_actor(bp, transform)
print(f"Vehicle: {vehicle.type_id}")
vehicle.destroy()

print("✓ All core tests passed!")
```

---

## Useful Resources

### Official Documentation

| Resource | URL |
|----------|-----|
| **CARLA Official Website** | https://carla.org |
| **CARLA Build Documentation** | https://carla.readthedocs.io/en/latest/build_linux/ |
| **CARLA Python API Docs** | https://carla.readthedocs.io/en/latest/python_api/ |
| **CARLA GitHub Repository** | https://github.com/carla-simulator/carla |
| **CARLA Releases** | https://github.com/carla-simulator/carla/releases |

### UnrealEngine Requirements

| Resource | URL |
|----------|-----|
| **CARLA UE4 Fork** | https://github.com/CarlaUnreal/UnrealEngine |
| **UE4 Documentation** | https://docs.unrealengine.com/4.26 |
| **Linux Build Guide (UE4)** | https://docs.unrealengine.com/4.26/en-US/SharingAndReleasing/Linux/BeginnerLinuxDeveloper/SettingUpAnUnrealProject/ |

### Ubuntu 22.04 Specific

| Resource | URL |
|----------|-----|
| **glibc Release Notes** | https://www.gnu.org/software/libc/manual/ |
| **Ubuntu 22.04 Release Notes** | https://wiki.ubuntu.com/JammyJellyfish/ReleaseNotes |
| **Ubuntu Toolchain Updates** | https://wiki.ubuntu.com/ToolchainTransitionPlan |

### NVIDIA CUDA & Drivers

| Resource | URL |
|----------|-----|
| **CUDA Toolkit Download** | https://developer.nvidia.com/cuda-downloads |
| **NVIDIA Driver Download** | https://www.nvidia.com/Download/driverDetails.aspx |
| **CUDA Installation Guide Linux** | https://docs.nvidia.com/cuda/cuda-installation-guide-linux/ |

### Community & Support

| Resource | URL |
|----------|-----|
| **CARLA Discussions** | https://github.com/carla-simulator/carla/discussions |
| **CARLA Issues** | https://github.com/carla-simulator/carla/issues |
| **CARLA Discord** | https://discord.gg/carla |
| **Stack Overflow (carla tag)** | https://stackoverflow.com/questions/tagged/carla |

### Related Projects

| Project | URL | Use Case |
|---------|-----|----------|
| **SUMO** | https://sumo.dlr.de/ | Traffic simulation, vehicle behavior |
| **OpenDRIVE** | https://www.asam.net/standards/detail/opendrive | Road format standard |
| **OpenScenario** | https://www.asam.net/standards/detail/openscenario | Scenario definition |
| **CARLA Leaderboard** | https://leaderboard.carla.org/ | Autonomous driving benchmarks |

---

## Quick Reference: Common Commands

```bash
# Environment setup
export UE4_ROOT=~/UnrealEngine_4.26_src/Engine
cd ~/carla_workspace/carla

# Initial setup
./Setup.sh                          # Download & prepare dependencies
./Update.sh                         # Download content

# Build steps
make PythonAPI                      # Build Python bindings
make launch                         # Build server binary
make package                        # Create distribution package

# Running CARLA
./CarlaUE4.sh                       # Start server with GPU
./CarlaUE4.sh -RenderOffScreen      # Start server without display

# Python client
python3 -m pip install PythonAPI/carla/dist/carla-*.whl
python3 PythonAPI/examples/manual_control.py

# Debugging
./Setup.sh 2>&1 | tee setup.log     # Capture setup output
make PythonAPI 2>&1 | tee build.log # Capture build output
grep -i error build.log             # Find errors in logs
```

---

## Verification Checklist

Before reporting build issues, verify:

- [ ] Ubuntu 22.04 LTS (`lsb_release -a`)
- [ ] glibc ≥ 2.34 (`ldd --version`)
- [ ] Python 3.10+ (`python3 --version`)
- [ ] UE4 4.26 built and installed (`ls -d $UE4_ROOT/Engine`)
- [ ] >100 GB free disk space (`df -h`)
- [ ] Git LFS installed (`git lfs install`)
- [ ] CARLA repo cloned (`git clone --branch ue4-dev ...`)
- [ ] Xerces fix applied (`grep -c "fPIC -w -pthread" Setup.sh` → 2)
- [ ] Setup.sh completed without errors
- [ ] Content downloaded (`./Update.sh`)
- [ ] PythonAPI built (`make PythonAPI`)
- [ ] Python wheel installed (`pip install carla-*.whl`)
- [ ] Server starts (`./CarlaUE4.sh`)
- [ ] Python client connects

---

## Summary

| Step | Time | Key Point |
|------|------|-----------|
| **Prerequisites** | 30 min | Install build tools, verify glibc ≥ 2.34 |
| **UE4 Download & Build** | 4-6 hours | Largest time consumer, do this first |
| **CARLA Clone** | 10 min | Use `ue4-dev` branch |
| **Apply Xerces Fix** | 2 min | Critical for Ubuntu 22.04 |
| **Setup.sh** | 15 min | Downloads dependencies |
| **Update.sh** | 30-60 min | Downloads content (~20 GB) |
| **make PythonAPI** | 20-30 min | Python bindings |
| **make launch** | 20-30 min | Server binary |
| **make package** | 10-15 min | Optional distribution |
| **Test Installation** | 10 min | Verify with Python client |
| **Total Time** | **7-8 hours** | Most spent on UE4 build |

---

## Getting Help

If you encounter issues:

1. **Check the logs** — Each build step has detailed output
2. **Verify prerequisites** — Use the checklist above
3. **Apply Xerces fix** — This is the most common Ubuntu 22.04 issue
4. **Search issues** — https://github.com/carla-simulator/carla/issues
5. **Post to discussions** — https://github.com/carla-simulator/carla/discussions

**Include in bug reports:**
```bash
# System info
uname -a
lsb_release -a
gcc --version
python3 --version
ldd --version

# Error logs
cat build.log | tail -50
```

---

**Good luck building CARLA! 🚗💨**

Last updated: June 2026
CARLA Version: 0.9.16
OS: Ubuntu 22.04 LTS

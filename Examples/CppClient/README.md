C++ Client Example
==================

This example creates an application using CARLA's C++ API to connect and control
the simulator from C++.

Compile and run
---------------

Use the Makefile provided (Linux only), to compile and run the example. Note
that it expects to have a simulator running at port 2000.

```
make run
```

Manual control
--------------

`manual_control.cpp` is the C++ counterpart of
`PythonAPI/examples/manual_control.py`: drive a vehicle (or walker) with the
keyboard, switch between camera, depth, segmentation, lidar, DVS and optical
flow views, and use the same HUD and key bindings. It uses SDL2 and SDL2_ttf
in place of pygame:

```
sudo apt install libsdl2-dev libsdl2-ttf-dev
make run.manual_control ARGS="--res 1280x720 --sync"
```

The client must be built against the LibCarla of the server's CARLA version;
a newer LibCarla misreads the sensor data of an older server (and crashes).
For a 0.9.16 server, build against a checkout of the `0.9.16` tag:

```
git worktree add --detach ../../../carla-0.9.16 0.9.16
make manual_control CARLA_SRC=../../../carla-0.9.16   # -> bin-carla-0.9.16/
```

At start it reads `carla.conf` (the config of `carla-start.sh`): `--config FILE`,
else `$CARLA_CONF`, else the first `carla.conf` in the working directory or
above the binary. It takes `CARLA_HOST`, `CARLA_PORT`, `VEHICLE` and
`CPP_MANUAL_ARGS` from it; command line options override these. Without a
config the vehicle defaults to `vehicle.audi.a2`.

It accepts the same options as the Python script (`--host`, `--port`,
`--autopilot`, `--res`, `--filter`, `--generation`, `--rolename`, `--gamma`,
`--sync`). Press `H` in the window for the key bindings. Images recorded with
`R` are written to `_out/` as BMP files.

### GTK variant

`manual_control_gtk.cpp` is the same client with GTK3 + Cairo + Pango instead
of SDL2: same features, key bindings, options and `carla.conf` handling, but
it needs no SDL2 or SDL2_ttf, only GTK3 (`libgtk-3-dev` to build; the runtime
libraries come with Ubuntu desktops) and it takes its fonts from fontconfig.
Build and run it like the SDL version:

```
make run.manual_control_gtk CARLA_SRC=../../../carla-0.9.16
```

Differences to the SDL version:

- Images recorded with `R` are written to `_out/` as PNG files.
- It reads `CPP_GTK_ARGS` (not `CPP_MANUAL_ARGS`) from `carla.conf`, so extra
  options for one variant do not break the other.
- `--screenshot FILE.png [--screenshot-delay SECONDS]` saves the first complete
  frame (camera picture and HUD) as a PNG and keeps running.
- GTK would switch the program to the user's locale, and a German `LC_NUMERIC`
  makes LibCarla misread the OpenDRIVE map and crash. The program therefore
  stays in the `C` locale, and it drops `GTK_PATH` and similar variables that a
  terminal started from the VS Code snap points into `/snap/code`.

How it works
------------

In order to link our application against LibCarla, we need to compile LibCarla
with the same compiler and configuration we are using with our application. To
do so, we generate a CMake tool-chain file specifying the compiler and flags we
want

```cmake
# Example ToolChain.cmake
set(CMAKE_C_COMPILER /usr/bin/clang-8)
set(CMAKE_CXX_COMPILER /usr/bin/clang++-8)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++14 -O3 -DNDEBUG" CACHE STRING "" FORCE)
```

We pass this file to CMake when compiling LibCarla.client

```sh
cd /path/to/carla-root-folder

make setup

cd /path/to/build-folder

cmake \
    -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Client \
    -DLIBCARLA_BUILD_RELEASE=ON \
    -DLIBCARLA_BUILD_DEBUG=OFF \
    -DLIBCARLA_BUILD_TEST=OFF \
    -DCMAKE_TOOLCHAIN_FILE=/path/to/ToolChain.cmake \
    -DCMAKE_INSTALL_PREFIX=/path/to/install-folder \
    /path/to/carla-root-folder

ninja
ninja install
```

This will generate the following structure at the provided install path

```
libcarla-install
├── include
│   ├── carla
│   ├── cephes
│   ├── pugixml
|   ├── ...
│   └── system
│       ├── boost
│       ├── recast
│       └── rpc
└── lib
    ├── libcarla_client.a
    ├── librpc.a
    ├── libboost_filesystem.a
    └── ...
```

Our application needs to be linked at minimum against `libcarla_client.a`,
`librpc.a`, `libRecast.a`, and `libDetour*.a`. If we make use of IO
functionality and/or image processing we would need to link against
`boost_filesystem`, `png`, `tiff`, and/or `jpeg`.

For more details take a look at the Makefile provided.

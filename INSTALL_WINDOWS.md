# CARLA min — Install & Run on Windows (no build required)

This guide is for **using** the pre-built CARLA min simulator. You do NOT need
Visual Studio, Unreal Engine, or any build tools — just the package and Python.
(Building from source is covered in [CARLA_BUILD_GUIDE.md](CARLA_BUILD_GUIDE.md).)

## 1. Requirements

| | Minimum |
|---|---|
| OS | Windows 10/11, 64-bit |
| GPU | Dedicated, 6 GB VRAM (8 GB+ recommended) |
| Disk | ~15 GB free (5.2 GB zip + extracted files) |
| Python | 3.14, 64-bit — https://www.python.org/downloads/ |
| Network | Ports 2000–2002 free on localhost |

## 2. Install the simulator

1. Get the package `CARLA_771ad8c92.zip` (5.2 GB — produced by `make package`
   on the build machine, found under `Build\UE4Carla\`).
2. Extract it anywhere, e.g. `C:\CARLA\`. You end up with:
   ```
   C:\CARLA\WindowsNoEditor\
       CarlaUE4.exe          <- the simulator/server
       PythonAPI\            <- client library, examples, utils
       Co-Simulation\  HDMaps\  Engine\  CarlaUE4\
   ```
   That is the whole installation — nothing is written to the registry.

## 3. Install the Python client

Open a terminal (PowerShell or cmd):

```
python -m venv C:\CARLA\venv
C:\CARLA\venv\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install C:\CARLA\WindowsNoEditor\PythonAPI\carla\dist\carla-0.9.16-cp314-cp314-win_amd64.whl
python -m pip install pygame numpy
```

(`pygame`/`numpy` are needed by the example scripts, not by the `carla` module itself.)

## 4. Start the simulator

```
C:\CARLA\WindowsNoEditor\CarlaUE4.exe
```

A spectator window opens (Town01); the server listens on port **2000**.
Useful variants:

| Command | Effect |
|---------|--------|
| `CarlaUE4.exe -RenderOffScreen` | headless (no window) — for servers/CI |
| `CarlaUE4.exe -quality-level=Low` | lower GPU load |
| `CarlaUE4.exe -carla-rpc-port=3000` | use a different port |
| `CarlaUE4.exe -benchmark -fps=20` | fixed time step |

The first start takes noticeably longer than later ones (shader warm-up).

## 5. Verify the connection

In a second terminal (venv active):

```
python -c "import carla; c = carla.Client('127.0.0.1', 2000); c.set_timeout(30); print('Server:', c.get_server_version())"
```

Expected output: `Server: 771ad8c92` (or the version the package was built from).

Then try an example:

```
cd C:\CARLA\WindowsNoEditor\PythonAPI\examples
python manual_control.py
```

A pygame window with a drivable vehicle appears (`WASD` to drive, `Esc` to quit).

## 6. What this "min" build contains

- Maps: **Town01**, **Town04**, `AnnotationColorLandscape`
- 41 vehicle blueprints, full sensor suite (cameras incl. GBuffer outputs,
  lidar, radar, GNSS/IMU), Traffic Manager, Co-Simulation bridges
- Not included: the remaining stock towns and the full asset library
  (that is the point of the min build)

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Client hangs / `time-out` | Server not started yet, or firewall blocks localhost 2000–2002 — allow `CarlaUE4.exe` in Windows Firewall |
| `ImportError: DLL load failed` on `import carla` | Python is not 3.14/64-bit, or the wheel does not match the Python version |
| Black window / crash at start | Update the GPU driver; try `-quality-level=Low`; check `WindowsNoEditor\CarlaUE4\Saved\Logs\CarlaUE4.log` |
| Port already in use | Another CARLA instance is running — `taskkill /im CarlaUE4-Win64-Shipping.exe /f`, or use `-carla-rpc-port` |
| Very low FPS | Close the spectator view camera (it renders too); prefer `-RenderOffScreen` when only clients need images |

## 8. Uninstall

Delete the extracted folder (and the venv). Nothing else was installed.

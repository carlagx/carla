# CARLA bauen, starten und testen (Linux, lokal und Docker)

Gilt für Branch `ue4-build` (UE 4.26, Ubuntu 22.04, NVIDIA-GPU mit Vulkan).
Ersetzt die früheren Einzeldokumente (START_HERE, QUICK_START, README_BUILD, BUILD_STEPS, BUILD_SUMMARY, BUILD_COMPLETION_REPORT, TESTING_GUIDE). Zum Beschleunigen von Rendering und Map-Laden siehe [MAP_LOADING_TIPS.md](MAP_LOADING_TIPS.md).

## 1. Schnellstart: alles testen

```bash
./test-carla.sh minimal                # Server + Python-Verbindung
./test-carla.sh middle                 # + Fahrzeug, Kamera, C++-Client
./test-carla.sh full --mode=docker     # + Sync-Modus, Kartenwechsel, GPU-Test, Traffic
```

Das Skript startet den Server selbst, räumt danach auf und gibt als Exit-Code die Zahl der Fehler zurück. Logs liegen in `test-logs/<zeit>/`. Optionen: `--mode=local|docker`, `--image`, `--dist`, `--host`, `--port`, `--timeout`, `--use-running`, `--keep-server` (`./test-carla.sh --help`).

| Stufe | Prüft |
|---|---|
| minimal | GPU/Vulkan/ulimit bzw. Docker, Serverstart, Python-Verbindung, Versionsgleichheit Client/Server, Karte, Blueprints |
| middle | Fahrzeug mit Autopilot fährt, RGB-Kamera liefert Bilder, `cpp_client` |
| full | Sync-Modus, Wechsel Town04↔Town06, `gpu_test`, `generate_traffic.py`, keine Fatal Errors im Serverlog |

## 2. Voraussetzungen

- Ubuntu 22.04, NVIDIA-Treiber ≥ 450 mit Vulkan (`vulkaninfo --summary` zeigt die GPU), ≥ 8 GB VRAM empfohlen.
- `ulimit -n` ≥ 4096 (z. B. `ulimit -n 10240`). Das Testskript prüft das.
- Für den Quellbaum: `UE4_ROOT` auf Unreal Engine 4.26 setzen, `git`, `make`, `cmake`, `ninja`, `gcc/g++`, `python3`.
- Für Docker: Docker mit NVIDIA-Container-Toolkit (`docker run --gpus all …`).
- `./check-drivers.sh` prüft System, GPU, Vulkan und Docker-Runtime und gibt einen Bericht aus.

## 3. Bauen

### 3.1 Server (gepacktes Spiel)
```bash
export UE4_ROOT=/pfad/zu/UnrealEngine_4.26
./build-carla-server.sh [--config=Shipping] [--maps=Town06,Town04] [--all-maps] [--skip-libcarla] [--skip-editor]
# Ergebnis: Dist/CARLA_<config>_<version>/LinuxNoEditor/CarlaUE4.sh
```

### 3.2 Python-API (muss zum Server passen)
```bash
make PythonAPI          # baut PythonAPI/carla/dist/carla-*.whl und installiert es
python3 -c "import carla; print(carla.Client('localhost',2000).get_client_version())"
```
Das PyPI-Paket `carla==0.9.16` passt **nicht** zu diesem Branch. Die Versionen müssen übereinstimmen (hier z. B. `e78db150c-dirty`).

### 3.3 C++-Client
```bash
cd Examples/CppClient
make build                          # baut LibCarla.client selbst (dauert beim ersten Mal), dann bin/cpp_client
make gpu_test                       # bin/gpu_test (Fahrzeug + Kameras)
```
`build-client-final.sh` ist ein alternativer Skript-Weg und nur Notlösung, falls `make` nicht klappt.

## 4. Starten

### Lokal
```bash
cd Dist/CARLA_*/LinuxNoEditor
ulimit -n 10240
./CarlaUE4.sh -RenderOffScreen -nosound -carla-rpc-port=2000     # headless
./CarlaUE4.sh -vulkan                                            # mit Fenster
```
Der erste Start einer Karte baut Shader und kann lange dauern. Ports 2000–2002 müssen frei sein.

### Docker
```bash
cd Dist/CARLA_*/LinuxNoEditor
docker build -t carla-xil:local .       # Dockerfile liegt im Paket, .dockerignore spart Debug-Dateien
docker run --rm --gpus all -p 2000-2002:2000-2002 carla-xil:local \
    /bin/bash CarlaUE4.sh -RenderOffScreen -nosound
```
Die Clients laufen auf dem Host und verbinden sich mit `localhost:2000`. Der offene Port bedeutet bei Docker nicht, dass der Server bereit ist (der Proxy öffnet ihn sofort). Das Testskript wartet deshalb auf einen echten RPC-Aufruf.

## 5. Clients von Hand

```bash
Examples/CppClient/bin/cpp_client [host port [meter]]     # Town06, Autopilot, Standard 20 m
Examples/CppClient/bin/gpu_test host port [sekunden [kameras [breite hoehe]]]
python3 PythonAPI/examples/generate_traffic.py --host localhost -p 2000 -n 30
python3 PythonAPI/examples/manual_control.py
```

## 6. Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| `time-out … while waiting for the simulator` | Server noch beim Laden (Shader), Port belegt, oder Timeout zu klein (`client.set_timeout(120)`). |
| Python-Client meldet andere Version als Server | PyPI-Paket installiert. `make PythonAPI` ausführen. |
| `import carla` schlägt mit `python -I` fehl | `-I` ignoriert `~/.local`. Ohne `-I` starten. |
| Server stürzt beim Start ab / Vulkan-Fehler | `./check-drivers.sh`, `vulkaninfo --summary`, Crashlogs in `Unreal/CarlaUE4/Saved/Crashes/`. |
| `Too many open files` | `ulimit -n 10240`. |
| Hybrid-Laptop | `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./CarlaUE4.sh -vulkan` |
| GPU überwachen | `./monitor-carla-gpu.sh -l gpu.csv` |

## 7. Bekannte Einschränkungen dieses Branches

- **OSM→OpenDRIVE (osm2odr) ist deaktiviert** (xerces-c/C++-Stdlib-Konflikt, Libraries in `Carla.Build.cs` auskommentiert). `ConvertOSMInOpenDrive` loggt einen Fehler und konvertiert nichts, das Laden von OSM-Karten im Map-Generator funktioniert nicht.
- **Engine-Zuordnung:** `CarlaUE4.uproject` steht auf `"EngineAssociation": "4.26"`. Ist die Engine nur unter einer GUID registiert (`~/.config/Epic/UnrealEngine/Install.ini`), schreibt der Editor die GUID beim Öffnen ins Projekt. Diese lokale Änderung nicht committen (`git restore -p` oder per Hand zurücksetzen).
- **Schnelleres Laden im Editor (lokal, nicht committen):** `r.GenerateMeshDistanceFields=False` und eine kleinere `EditorStartupMap` beschleunigen das Öffnen von Karten, ändern aber Rendering/Sensordaten. Siehe [MAP_LOADING_TIPS.md](MAP_LOADING_TIPS.md). Beim Packen setzt `build-carla-server.sh` Standardkarte und Kartenliste selbst.
- Das Paket heißt `…-dirty`, solange der Git-Stand nicht committet ist.

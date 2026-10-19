# CARLA-Dev-Umgebung: Starten, Entwickeln, Bauen, Ausliefern

Written for: Entwickler, die die Docker-Umgebung selbst hochfahren und fertige Builds auf einem zweiten Rechner (Zielsystem) betreiben.

Die technischen Details stehen in [OFFLINE_DOCKER.md](OFFLINE_DOCKER.md) und [BUILD_AND_TEST.md](BUILD_AND_TEST.md). Diese Anleitung führt die Schritte in der richtigen Reihenfolge auf.

## Begriffe

| Begriff | Bedeutung |
|---|---|
| **Entwicklungsrechner** | Rechner mit dem Repo, Docker und Unreal Engine 4.26 (UE4). Hier wird gebaut. |
| **Zielsystem** | Rechner, auf dem der fertige CARLA-Server und die Clients laufen. Braucht kein Docker und keine UE4. |
| **Container `carla-dev`** | Build-Umgebung mit Compiler, Python und Web-VS-Code. |
| **Artefakte** | Ergebnis eines Builds: Python-Wheel, C++-Client, Server-Paket, `SHA256SUMS`, `manifest.json`. |

Ports auf dem Entwicklungsrechner:

| Port | Dienst |
|---|---|
| 8080 | VS Code im Browser |
| 8081 | Artefakt-Download (Basic Auth) |
| 2000–2002 | CARLA-Server (RPC), wenn der Server im Container läuft |

---

## Teil A: Entwicklungsrechner

### A1. Voraussetzungen prüfen

```bash
lsb_release -rs                 # Ubuntu 22.04 erwartet
docker --version
docker compose version
nvidia-smi                      # nur für GPU-Betrieb nötig
vulkaninfo --summary            # Vulkan muss die GPU zeigen
df -h .                         # mindestens ~100 GB frei (UE4 + Build + Cooking)
```

Für GPU im Container zusätzlich: NVIDIA Container Toolkit (`docker run --rm --gpus all ubuntu nvidia-smi` muss funktionieren).

Falls `vulkaninfo` fehlt: `sudo apt install vulkan-tools`.

### A2. Repo und Branch

```bash
cd /home/carlagx/carla-xil/carla
git status
git branch --show-current       # ue4-docker
```

Lokale Änderungen, die nicht committet werden sollen (z. B. `gpu.csv`, `check-buildable.sh`), vorher bewusst entscheiden.

### A3. Unreal Engine 4.26 bereitstellen

Die Engine wird **nicht** ins Image gepackt. Sie wird als Ordner eingebunden.

Variante 1, Engine ist schon vorhanden:
```bash
export UE4_ROOT_HOST=~/UnrealEngine_4.26
ls "$UE4_ROOT_HOST/Engine/Build/BatchFiles/RunUAT.sh"    # muss existieren
```

Variante 2, Engine fehlt (braucht GitHub-Zugang über einen mit Epic verknüpften Account):
```bash
# GITHUB_TOKEN wird aus credentials.env gelesen, siehe Schritt A4
# Im Container nach dem Start:
./manage.sh shell
carla-fetch-engine              # klont CarlaUnreal/UnrealEngine (Branch carla) nach /opt/UnrealEngine_4.26
exit
```
Das dauert lange und braucht viel Speicher. Die Engine liegt danach auf dem Host unter `UE4_ROOT_HOST`.

### A4. Credentials anlegen

```bash
cd Util/Docker/DevEnv
./manage.sh creds               # legt credentials/credentials.env mit Zufallspasswort an (chmod 600)
```

Dann `credentials/credentials.env` öffnen und mindestens ausfüllen:

- `GIT_USER_NAME`, `GIT_USER_EMAIL`
- `GITHUB_USER`, `GITHUB_TOKEN` (nur nötig für Engine-Download und Plugins)
- `CODE_SERVER_PASSWORD` steht schon drin (das Passwort von `creds`). Für Login und Artefakt-Download merken.

Die Datei nie committen. Sie ist per `.gitignore` ausgeschlossen. Firmennetz? Dann zusätzlich `HTTP_PROXY`, `HTTPS_PROXY`, `CA_CERT_FILE` setzen (siehe `credentials/credentials.env.example`).

### A5. Image bauen (einmalig, braucht Internet)

Das Image `carla-dev:latest` ist auf diesem Rechner schon vorhanden. Neu bauen nur nötig, wenn sich `Dockerfile`, `requirements.txt` oder `extensions.txt` ändern:

```bash
./manage.sh build
```

### A6. Container starten

```bash
export UE4_ROOT_HOST=~/UnrealEngine_4.26   # oder der Pfad aus A3
GPU=1 ./manage.sh up                       # ohne GPU=1, wenn nur gebaut wird
./manage.sh logs                           # Strg+C beendet nur die Anzeige
```

Im Log steht das Passwort, falls `CODE_SERVER_PASSWORD` leer war. Danach:

- VS Code: http://localhost:8080 (Passwort aus `credentials.env`)
- Artefakte: http://localhost:8081/latest/ (Benutzer `carla`, gleiches Passwort)

### A7. Smoke-Test der Umgebung

```bash
./manage.sh shell
which carla-build carla-collect                 # Tools vorhanden
ls /workspace/carla | head                      # Repo gemountet
ls "$UE4_ROOT/Engine/Build/BatchFiles/RunUAT.sh"  # Engine gemountet
nvidia-smi                                      # nur mit GPU=1
exit
```

Eine Warnung im Entrypoint-Log „no Unreal Engine“ oder „is empty“ heißt: der Mount oder `UE4_ROOT_HOST` stimmt nicht.

---

## Teil B: Entwickeln

### B1. Im Browser (VS Code)

Öffne http://localhost:8080. Der Ordner `/workspace/carla` ist das Repo auf dem Host. Änderungen wirken sofort auf dem Host, es gibt keine Kopie.

Terminal in VS Code arbeitet im Container. Dort sind alle Build-Werkzeuge und Credentials vorhanden.

### B2. Lokal auf dem Host entwickeln

Dasselbe Repo kann auch direkt auf dem Host bearbeitet werden. Der Container sieht die Änderungen über den Mount. Git-Befehle lieber auf einer Seite ausführen, nicht parallel.

### B3. Schnelltests während der Entwicklung

```bash
./manage.sh build-carla pythonapi           # nur Python-Wheel, schnell
./test-carla.sh minimal                     # Server + Python-Verbindung (auf dem Host)
```

`test-carla.sh minimal` startet einen Server aus `Dist/` und prüft ihn. Vorher muss ein Server gebaut sein (Teil C).

---

## Teil C: Bauen

### C1. Komplettbuild

```bash
./manage.sh build-carla all
```

Das baut in dieser Reihenfolge:

1. `setup` (Abhängigkeiten, Plugins)
2. `pythonapi`: Python-Wheel
3. `client`: C++-Client (`cpp_client`, `gpu_test`)
4. `server`: gepacktes Server-Paket mit den Karten Town06 (Standard) und Town04

Dauer: mehrere Stunden beim ersten Mal. Fortschritt im Log:
```bash
./manage.sh logs
ls Util/Docker/DevEnv/artifacts/logs/   # Einzellogs pro Stufe
```

### C2. Einzelne Stufen

```bash
./manage.sh build-carla pythonapi
./manage.sh build-carla client
./manage.sh build-carla server
./manage.sh build-carla maps Town01,Town02   # Server mit zusätzlichen Karten neu bauen
```

### C3. Ergebnis prüfen

```bash
ls Util/Docker/DevEnv/artifacts/latest/
cat Util/Docker/DevEnv/artifacts/latest/manifest.json
(cd Util/Docker/DevEnv/artifacts/latest && sha256sum -c SHA256SUMS)
```

Erwartet: Wheel (`carla-*.whl`), `cpp-client/`, `libcarla-client-install.tar.zst`, Server-Paket (`.tar.gz`), `SHA256SUMS`, `manifest.json`. Alle Prüfsummen `OK`.

Die Versionen von Wheel und Server müssen zusammenpassen. Beide stammen aus demselben Build, daher ist das automatisch der Fall. Nicht mit einem PyPI-Paket `carla==0.9.x` mischen.

---

## Teil D: Artefakte holen

Vom Entwicklungsrechner aus, oder von einem anderen Rechner im Netz (dann `localhost` durch Host-Namen ersetzen):

**Variante 1: Browser**
`http://HOST:8081/latest/` öffnen, Datei anklicken. Ganzer Ordner als Zip: Link `zip` in der Liste oder `…/latest/?zip=1`.

**Variante 2: curl (fortsetzbar bei Abbruch)**
```bash
curl -C - -O -u carla:PASSWORT http://HOST:8081/latest/<dateiname>
curl -C - -u carla:PASSWORT -o latest.zip "http://HOST:8081/latest/?zip=1"
```

**Variante 3: Skript auf dem Entwicklungsrechner**
```bash
cd Util/Docker/DevEnv
./manage.sh pull-artifacts ./download      # schreibt ./download/latest.zip
```

Danach Prüfsummen auf dem Zielsystem kontrollieren (Teil E4).

---

## Teil E: Zielsystem einrichten

Das Zielsystem braucht **kein** Docker, **keine** UE4 und **keinen** Build. Nur das fertige Paket.

### E1. Voraussetzungen

- Ubuntu 22.04 (gleiche Version wie der Build)
- NVIDIA-Treiber ≥ 450 mit Vulkan (`vulkaninfo --summary` zeigt die GPU)
- Python 3 (Ubuntu 22.04: 3.10), pip
- ≥ 8 GB VRAM empfohlen, ≥ 60 GB freier Speicher für das entpackte Paket

```bash
sudo apt update
sudo apt install -y python3-pip python3-venv vulkan-tools libvulkan1 unzip zstd
vulkaninfo --summary
```

### E2. Paket übertragen

Auf dem Zielsystem im gewünschten Ordner, z. B. `~/carla-release`:

```bash
mkdir -p ~/carla-release && cd ~/carla-release
curl -C - -O -u carla:PASSWORT http://ENTWICKLUNGSRECHNER:8081/latest/<server-paket>.tar.gz
curl -C - -O -u carla:PASSWORT http://ENTWICKLUNGSRECHNER:8081/latest/SHA256SUMS
curl -C - -O -u carla:PASSWORT http://ENTWICKLUNGSRECHNER:8081/latest/manifest.json
curl -C - -O -u carla:PASSWORT http://ENTWICKLUNGSRECHNER:8081/latest/carla-*.whl
```

Alternativ: Zip von `?zip=1` laden und entpacken (`unzip latest.zip`). Der Zip-Ordner heißt wie der Build (`<zeit>-<version>`).

Nicht vergessen: `ENTWICKLUNGSRECHNER` muss vom Zielsystem aus erreichbar sein (Firewall, Port 8081).

### E3. Server entpacken

```bash
cd ~/carla-release
tar -xzf <server-paket>.tar.gz
ls                                   # enthält CarlaUE4.sh, CarlaUE4/, Engine/, …
```

Das Paket ist ein `LinuxNoEditor`-Ordner mit `CarlaUE4.sh`. Ein Dockerfile liegt ebenfalls bei (für Teil E7).

### E4. Prüfsummen kontrollieren

```bash
cd ~/carla-release
sha256sum -c SHA256SUMS
```

Jede Zeile muss mit `OK` enden. Bei `FAILED` die Datei erneut laden, nicht verwenden.

### E5. Python-Client installieren

Wichtig: Das Wheel muss zur Python-Version passen (Ubuntu 22.04: `cp310`). Empfohlen mit venv, damit nichts systemweit verändert wird:

```bash
cd ~/carla-release
python3 -m venv ~/carla-venv
source ~/carla-venv/bin/activate
pip install carla-*.whl numpy
python -c "import carla; print(carla.Client('localhost', 2000).get_client_version())"  # Fehler, solange Server nicht läuft: ok
deactivate
```

Vor dem Aufruf von `python` immer `source ~/carla-venv/bin/activate` ausführen.

### E6. Server starten und prüfen

Terminal 1:
```bash
cd ~/carla-release/<LinuxNoEditor-Ordner>     # der Ordner mit CarlaUE4.sh
ulimit -n 10240
./CarlaUE4.sh -RenderOffScreen -nosound -carla-rpc-port=2000     # headless
# oder mit Fenster:
./CarlaUE4.sh -vulkan
```

Der erste Start dauert lange (Shader). Erst dann ist der Server bereit.

Terminal 2 (Client-Test):
```bash
source ~/carla-venv/bin/activate
python -c "
import carla
c = carla.Client('localhost', 2000); c.set_timeout(120)
print('Server', c.get_server_version(), 'Client', c.get_client_version())
w = c.get_world(); print('Karte:', w.get_map().name)
"
```

Client- und Server-Version müssen gleich sein. Karte sollte `Town06` sein.

### E7. C++-Client

Der Ordner `cpp-client/` aus dem Artefakt-Download enthält `cpp_client` und `gpu_test` fertig gebaut.

```bash
cd ~/carla-release
chmod +x cpp-client/cpp_client cpp-client/gpu_test
./cpp-client/cpp_client localhost 2000        # Town06, Autopilot
./cpp-client/gpu_test localhost 2000          # Fahrzeug + Kameras
```

Die Datei `libcarla-client-install.tar.zst` braucht man nur, um eigene C++-Programme gegen LibCarla zu bauen (`zstd -dc libcarla-client-install.tar.zst | tar -x`).

Falls `cpp_client` eine fehlende Bibliothek meldet: `ldd ./cpp-client/cpp_client` zeigt sie. Die fehlende Bibliothek aus dem Build-Ordner nachkopieren oder den Client auf dem Entwicklungsrechner neu bauen.

### E8. Alternative: Server im Docker auf dem Zielsystem

Nur sinnvoll, wenn Docker dort ohnehin vorhanden ist. Docker mit NVIDIA-Toolkit nötig.

```bash
cd ~/carla-release/<LinuxNoEditor-Ordner>
docker build -t carla-xil:local .
docker run --rm --gpus all -p 2000-2002:2000-2002 carla-xil:local \
    /bin/bash CarlaUE4.sh -RenderOffScreen -nosound
```

Clients laufen dann auf dem Zielsystem und verbinden sich mit `localhost:2000`.

---

## Teil F: Abnahme auf dem Zielsystem

Reihenfolge, jeder Punkt muss bestehen:

| # | Prüfung | Erfolg |
|---|---|---|
| 1 | `sha256sum -c SHA256SUMS` | alle `OK` |
| 2 | `vulkaninfo --summary` | GPU sichtbar |
| 3 | Server startet (E6) | Log ohne `Fatal` |
| 4 | Python-Client verbindet (E6) | Server- = Client-Version |
| 5 | `cpp_client` läuft (E7) | Fahrzeug fährt, keine Verbindungsfehler |

Für tiefere Prüfung auf dem Entwicklungsrechner: `./test-carla.sh full`. Auf dem Zielsystem liegt dieses Skript nicht vor, daher die Punkte 1–5 von Hand.

---

## Teil G: Updates ausliefern

1. Auf dem Entwicklungsrechner ändern und committen.
2. `./manage.sh build-carla all` (oder nur die betroffene Stufe).
3. `./manage.sh pull-artifacts` oder den neuen Ordner unter `…/latest/` holen.
4. Auf dem Zielsystem: alten Server-Ordner nicht überschreiben, sondern neben dem alten entpacken. Dann `ulimit`, Server und Clients auf den neuen Ordner umstellen. Das Wheel immer mit `pip install --force-reinstall` aus demselben Build installieren.

---

## Offline-Betrieb

Für Rechner ohne Internet:

```bash
# Quellrechner (mit Internet)
./manage.sh save carla-dev.tar.zst

# Zielrechner für die Entwicklung
./manage.sh load carla-dev.tar.zst
# credentials.env: OFFLINE=1 setzen
# Download-Cache nach OFFLINE_CACHE_DIR kopieren (docs/BUILD_AND_TEST.md, Abschnitt 8)
```

Das Zielsystem für die Auslieferung braucht davon nichts. Es braucht nur das Paket aus Teil E.

---

## Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| `manage.sh up` schlägt fehl, Port 8080 belegt | `CODE_PORT=8090 ./manage.sh up` |
| Login in VS Code geht nicht | `./manage.sh logs` zeigt das Passwort, sonst in `credentials.env` nachsehen |
| Im Container „no Unreal Engine“ | `UE4_ROOT_HOST` prüfen, dann `./manage.sh down && ./manage.sh up` |
| `build-carla server` bricht bei Cooking ab | Speicher prüfen (`df -h`), Log in `artifacts/logs/` |
| Server auf Zielsystem stürzt beim Start ab | `vulkaninfo --summary`, `check-drivers.sh` (Repo-Ordner) |
| `time-out … while waiting for the simulator` | Server lädt noch (Shader), Port belegt. `c.set_timeout(120)` setzen |
| Python: andere Version als Server | Falsches Wheel oder PyPI-Paket installiert. Wheel aus dem Build neu installieren |
| `Too many open files` | `ulimit -n 10240` vor dem Serverstart |
| Download bricht ab | `curl -C - …` mit denselben Parametern wiederholen (fortsetzbar) |
| `sha256sum` meldet `FAILED` | Datei erneut laden |

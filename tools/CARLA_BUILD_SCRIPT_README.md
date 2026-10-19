# 🚗 CARLA 0.9.16 Build-Script für Ubuntu 22.04 LTS

**Kombiniertes, optimiertes Build-Script mit automatischem Git-Clone, Xerces-Fix und vollständiger Pipeline.**

## ✨ Was das Script leistet

| Feature | Status |
|---------|--------|
| **Auto Git-Clone** | ✅ Falls Repo nicht existiert → wird automatisch geklont |
| **Xerces-C pthread-Fix** | ✅ Automatisch erkannt & angewendet (glibc ≥ 2.34) |
| **Branch-Management** | ✅ Neue Branches erstellen, Reuse-Modus für vorhandene Repos |
| **Content-Download** | ✅ Update.sh mit parallelem Download (aria2c) |
| **Vollständige Pipeline** | ✅ PythonAPI → launch → package |
| **Robustes Logging** | ✅ Jeder Schritt in separates Logfile |
| **Preflight-Checks** | ✅ Detaillierte Diagnose (Tools, UE4, Speicher, glibc) |
| **Fehler-Handling** | ✅ Aussagekräftige Fehlerausgaben mit Log-Hinweisen |

## 🚀 Quick Start

```bash
# Skripte ins richtige Verzeichnis kopieren
mkdir -p ~/repos/helper
cp build_carla.sh carla_build.conf ~/repos/helper/
chmod +x ~/repos/helper/build_carla.sh

# Nur Checks (keine Änderungen)
cd ~/repos/helper
./build_carla.sh --preflight-only

# Normaler Build (mit Config anpassen, siehe unten)
./build_carla.sh
```

## 📋 Konfiguration: `carla_build.conf`

Alle Variablen hier setzen, nicht im Script selbst:

### Repository-Einstellungen
```bash
REPO_URL="https://github.com/carla-simulator/carla.git"
SOURCE_BRANCH="ue4-dev"
NEW_BRANCH="ue4-ubuntu22"
```

### Pfade
```bash
CLONE_BASE_DIR="/home/carlagx/repos"      # Basis-Ordner
CLONE_DIR_NAME="carla"                    # Repo-Name (→ /repos/carla)
UE4_ROOT="/home/carlagx/UnrealEngine_4.26"  # UE4 Installation
```

### Abhängigkeiten
```bash
INSTALL_APT_DEPS=false                    # System-Pakete via apt
INSTALL_PYTHON_DEPS=true                  # Python-Requirements via pip
RUN_UPDATE=true                           # Content herunterladen (~20 GB)
UPDATE_SKIP_DOWNLOAD=false                # Nur Ordnerstruktur (schneller)
```

### Build-Schritte
```bash
BUILD_STEPS=("PythonAPI" "launch" "package")
```

Schritte entfernen zum Überspringen (z.B. nur PythonAPI: `("PythonAPI")`).

### Logging
```bash
LOG_DIR="/home/carlagx/repos/carla_build_logs"
```

Jeder Schritt schreibt sein Log hierher.

## ⚡ Nutzung

### Normaler Build
```bash
./build_carla.sh
```
→ Nutzt `carla_build.conf` im gleichen Verzeichnis

### Nur Preflight-Checks (kein Build)
```bash
./build_carla.sh --preflight-only
```
Prüft Tools, UE4, Speicher, glibc → zeigt, ob Build möglich ist.

### Xerces-Fix überspringen
```bash
./build_carla.sh --skip-xerces
```
Falls der Fix Probleme macht oder nicht nötig ist.

### Custom Config-Datei
```bash
./build_carla.sh --config ~/my_special_carla.conf
```

### Help anzeigen
```bash
./build_carla.sh --help
```

## 🔄 Auto-Clone & Reuse-Modus

Das Script ist **idempotent** — kann mehrfach sicher laufen:

1. **Erstes Mal**: Kein Repo vorhanden → `git clone` wird ausgeführt
2. **Zweites Mal**: Repo existiert → `git fetch origin` + Branch-Management
3. **Reuse-Modus**: `ON_EXISTING_DIR="reuse"` (Config) → vorhandenes Repo wird weiterverwenden

Mit `ON_EXISTING_DIR="fail"` bricht das Script ab, wenn das Zielverzeichnis bereits existiert.

## 🛠️ Der Xerces-C pthread-Fix

**Problem:** Auf Ubuntu 22.04 mit glibc ≥ 2.34 wurden die pthread-Symbole in `libc` integriert und `libpthread.so` ist ein leerer Stub, sodass implizites pthread-Linking nicht mehr funktioniert. Xerces-C 3.2.3 linkt seine test/sample/doc-Binaries (im Server-Build gegen UE's `libc++`) ohne `-pthread` → Link-Fehler.

**Lösung:** Füge `-pthread` zu den `CMAKE_CXX_FLAGS` beider Xerces-C cmake-Aufrufe in `Setup.sh` hinzu (Client + Server). Root-Cause-Fix — Upstream-Quellen bleiben unangetastet und alle Targets (inkl. Tests) bauen weiter.

**Automatik:** Das Script erkennt glibc ≥ 2.34 automatisch und wendet den Fix an (idempotent — ist `-pthread` bereits gesetzt, wird übersprungen).

## 📝 Logging & Debugging

Jeder Schritt schreibt sein Log separat:

```
carla_build_logs/
├── 01_Preflight-Checks.log
├── 02_Repository_klonen_reuse__Branch-Setup.log
├── 03_Xerces-C_pthread-Fix_anwenden.log
├── 04_Content_herunterladen__Update.sh_.log
├── 05_Python_Build-Requirements__pip_.log
├── 06_make_PythonAPI.log
├── 07_make_launch.log
└── 08_make_package.log
```

Falls ein Schritt fehlschlägt, wird der genaue Log-Pfad angezeigt.

## ✅ Nach dem erfolgreichen Build

Das Script zeigt die nächsten Schritte an:

```bash
# 1. PythonAPI installieren
pip install /home/carlagx/repos/carla/PythonAPI/carla/dist/carla-*.whl

# 2. CARLA Server starten
cd /home/carlagx/repos/carla && ./CarlaUE4.sh

# 3. Mit Python verbinden
python3 PythonAPI/examples/manual_control.py
```

## 🚨 Häufige Fehler

### "UE4_ROOT existiert nicht"
```bash
# Check: Existiert /home/carlagx/UnrealEngine_4.26?
ls -d ~/UnrealEngine_4.26

# Falls anderswo installiert, in carla_build.conf anpassen:
UE4_ROOT="/pfad/zu/ue4.26"
```

### "Setup.sh nicht gefunden"
→ Das Repo wurde nicht geklont. Check:
- Ist `CLONE_BASE_DIR` beschreibbar?
- Hat die Git URL Zugriff? (`git clone https://... <test-dir>`)

### "make" schlägt fehl, aber "PythonAPI" war erfolgreich
→ Das ist normal. Nur `make PythonAPI` wird oft erfolgreich beendet. Die anderen Targets (`launch`, `package`) sind optional.

### "Weniger als 100 GB Speicher"
Das ist eine Warnung, kein Fehler. Der Build läuft trotzdem.
- CARLA Source: ~5 GB
- UE4 Build-Objekte: ~50 GB
- Content-Download: ~20 GB
- Total: ~80 GB + Reserve

## 📚 Beispiel-Workflows

### Nur PythonAPI bauen (schnell)
```bash
# carla_build.conf anpassen:
BUILD_STEPS=("PythonAPI")

# Bauen
./build_carla.sh
```

### Content nicht herunterladen (sehr schnell)
```bash
# carla_build.conf anpassen:
RUN_UPDATE=false

# Bauen (Repo + Fix, aber ohne 20 GB Download)
./build_carla.sh
```

### Custom UE4-Pfad
```bash
# carla_build.conf anpassen:
UE4_ROOT="/opt/UnrealEngine"

# Bauen
./build_carla.sh
```

### Fork mit eigenen Änderungen bauen
```bash
# carla_build.conf anpassen:
REPO_URL="https://github.com/<dein-github>/carla.git"
NEW_BRANCH="my-custom-build"

# Bauen
./build_carla.sh
```

## 🔗 Weitere Ressourcen

- **CARLA Doku:** https://carla.readthedocs.io/
- **GitHub:** https://github.com/carla-simulator/carla
- **Unreal Engine 4.26:** https://github.com/EpicGames/UnrealEngine (Branch 4.26)

## 📄 Lizenz & Hinweise

Dieses Script wendet einen Open-Source-Fix auf das CARLA-Repo an. CARLA selbst unterliegt der CARLA License (dual Apache 2.0 / Community License).

---

**Getestet auf:**
- Ubuntu 22.04 LTS (glibc 2.35)
- CARLA 0.9.16 (branch ue4-dev)
- UE4 4.26

---

## 🤝 Support

Falls Fehler auftreten:

1. **Logfile prüfen** (Pfad wird angezeigt)
2. **Preflight-Only Mode testen:** `./build_carla.sh --preflight-only`
3. **Manuell testen:**
   ```bash
   cd ~/repos/carla
   git status
   ./Setup.sh          # Sollte durchlaufen
   make PythonAPI      # Sollte PythonAPI bauen
   ```

---

**Viel Erfolg beim Bauen! 🎉**

#!/usr/bin/env bash
# ============================================================================
#  reduce-linux-package.sh
#  Trimmt LOSE, unnoetige Dateien aus einem bereits gebauten/entpackten
#  Linux-CARLA-Paket (Ordner "LinuxNoEditor") - schnell, ohne Rebuild.
#
#  Entfernt (nur lose Dateien, NICHT den gecookten .pak-Content):
#    - ueberzaehlige HDMaps/*.pcd  (behaelt nur die Towns in KEEP_PCD)    ~1 GB
#    - Debug-Symbole *.debug / *.sym / *.pdb                             ~1,7 GB
#    - PythonAPI/examples/nvidia   (cosmos-Demodaten)                    ~140 MB
#    - Co-Simulation/              (SUMO/PTV-Vissim/Chrono)              ~25 MB
#    - statische Link-Libs in CarlaDependencies (*.a / *.lib)            ~44 MB
#    - PythonAPI/util/opendrive/TownBig.xodr                            ~15 MB
#
#  Aufruf:
#    bash reduce-linux-package.sh /pfad/zu/LinuxNoEditor        # fragt nach
#    bash reduce-linux-package.sh /pfad/zu/LinuxNoEditor -y     # ohne Nachfrage
#    (ohne Pfad -> aktuelles Verzeichnis)
#
#  HINWEIS: Content-Reduktionen (Maps/Gebaeude/Fahrzeuge/Fussgaenger) sind in
#  den .pak gecookt und koennen hier NICHT entfernt werden. Dafuer aus dem
#  reduzierten Branch bauen. Siehe reduce-package-size.report.md.
# ============================================================================
set -uo pipefail

# --- Welche Town-HD-Punktwolken BEHALTEN (Leerzeichen-getrennt, ohne .pcd) ---
KEEP_PCD="Town01 Town04"
# --- optional: komplette PythonAPI/examples loeschen (1=ja, 0=nur nvidia) ---
REMOVE_ALL_EXAMPLES=0

ASSUME_YES=0
ROOT=""
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) ROOT="$a" ;;
  esac
done
ROOT="${ROOT:-$PWD}"
ROOT="${ROOT%/}"

if [[ ! -d "$ROOT/CarlaUE4" ]]; then
  echo "[FEHLER] '$ROOT' sieht nicht nach einem CARLA-Paket aus (kein CarlaUE4-Ordner)." >&2
  echo "Uebergib den Pfad zum entpackten LinuxNoEditor-Ordner." >&2
  exit 1
fi

echo "Ziel-Paket : $ROOT"
echo "Behalte pcd: $KEEP_PCD"

before=$(du -sb "$ROOT" 2>/dev/null | cut -f1)

if [[ "$ASSUME_YES" != "1" ]]; then
  read -r -p "Loeschen jetzt durchfuehren? [y/N] " ans
  [[ "$ans" == [yY] ]] || { echo "Abgebrochen."; exit 0; }
fi

echo
echo "=== Entferne ueberzaehlige Dateien ==="

# 1) HDMaps: jede .pcd loeschen, deren Town nicht in KEEP_PCD steht
if [[ -d "$ROOT/HDMaps" ]]; then
  shopt -s nullglob
  for f in "$ROOT"/HDMaps/*.pcd; do
    name=$(basename "$f" .pcd)
    keep=0
    for k in $KEEP_PCD; do
      if [[ "$name" == "$k" ]]; then keep=1; fi
    done
    if [[ "$keep" == 0 ]]; then
      echo "  [del ] HDMaps/$(basename "$f")"; rm -f "$f"
    else
      echo "  [keep] HDMaps/$(basename "$f")"
    fi
  done
  shopt -u nullglob
fi

# 2) Debug-Symbole (gesamtes Paket)
while IFS= read -r -d '' f; do
  echo "  [del ] ${f#$ROOT/}"; rm -f "$f"
done < <(find "$ROOT" -type f \( -name '*.debug' -o -name '*.sym' -o -name '*.pdb' \) -print0 2>/dev/null)

# 3) PythonAPI/examples
if [[ "$REMOVE_ALL_EXAMPLES" == 1 ]]; then
  if [[ -d "$ROOT/PythonAPI/examples" ]]; then
    echo "  [rmdir] PythonAPI/examples"; rm -rf "$ROOT/PythonAPI/examples"
  fi
elif [[ -d "$ROOT/PythonAPI/examples/nvidia" ]]; then
  echo "  [rmdir] PythonAPI/examples/nvidia"; rm -rf "$ROOT/PythonAPI/examples/nvidia"
fi

# 4) Co-Simulation
if [[ -d "$ROOT/Co-Simulation" ]]; then
  echo "  [rmdir] Co-Simulation"; rm -rf "$ROOT/Co-Simulation"
fi

# 5) statische Link-Libs (zur Laufzeit nie geladen)
if [[ -d "$ROOT/CarlaUE4/Plugins/Carla/CarlaDependencies" ]]; then
  while IFS= read -r -d '' f; do
    echo "  [del ] $(basename "$f")"; rm -f "$f"
  done < <(find "$ROOT/CarlaUE4/Plugins/Carla/CarlaDependencies" -type f \( -name '*.a' -o -name '*.lib' \) -print0 2>/dev/null)
fi

# 6) Beispiel-OpenDRIVE
if [[ -f "$ROOT/PythonAPI/util/opendrive/TownBig.xodr" ]]; then
  echo "  [del ] TownBig.xodr"; rm -f "$ROOT/PythonAPI/util/opendrive/TownBig.xodr"
fi

after=$(du -sb "$ROOT" 2>/dev/null | cut -f1)
echo
echo "=== Fertig ==="
if [[ -n "${before:-}" && -n "${after:-}" ]]; then
  awk -v b="$before" -v a="$after" 'BEGIN{
    printf "  Freigegeben: %.1f MB\n", (b-a)/1048576;
    printf "  Neue Groesse: %.2f GB\n", a/1073741824 }'
fi

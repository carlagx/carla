#!/usr/bin/env bash
# ============================================================================
#  fix-trafficmanager-server.sh
#  Haertet den Traffic-Manager-RPC-Server in LibCarla ab - idempotent.
#  Datei: LibCarla/source/carla/trafficmanager/TrafficManagerServer.h
#  Konstruktor: TrafficManagerServer(uint16_t &RPCPort, TrafficManagerBase* tm)
#
#  Wendet drei Aenderungen an (nur falls noch nicht vorhanden):
#    1. SECURITY  Bind nur auf localhost: new ::rpc::server("127.0.0.1", RPCPort)
#                 statt auf 0.0.0.0 / allen Interfaces.
#    2. FALLBACK  Bei Bind-Fehler den Port wirklich hochzaehlen (RPCPort++),
#                 damit der naechste Versuch einen freien Port nimmt - statt
#                 MIN_TRY_COUNT-mal denselben (belegten) Port zu probieren.
#    3. REPORT    Nach erfolgreichem Bind _RPCPort = RPCPort setzen, damit
#                 port() den TATSAECHLICH gebundenen Port liefert. Da RPCPort
#                 eine Referenz ist, sieht auch der Aufrufer (TrafficManagerLocal
#                 -> AddTrafficManagerRunning / DestroyTrafficManager) den echten
#                 Port.
#
#  Danach (optional) Build + Verifikation des LibCarla-Clients (kompiliert den
#  Traffic Manager). Inkrementell via ninja - kein Full-Rebuild.
#
#  Aufruf:
#    bash fix-trafficmanager-server.sh                 # CARLA-Root automatisch,
#                                                        # fragt vor dem Patchen
#    bash fix-trafficmanager-server.sh -y              # ohne Nachfrage
#    bash fix-trafficmanager-server.sh /pfad/zu/carla  # expliziter Repo-Root
#    bash fix-trafficmanager-server.sh --no-build      # nur patchen+verifizieren
#    bash fix-trafficmanager-server.sh --pythonapi     # zusaetzlich PythonAPI bauen
#    bash fix-trafficmanager-server.sh --check         # nur pruefen, nichts aendern
# ============================================================================
set -uo pipefail

ASSUME_YES=0
DO_BUILD=1
DO_PYTHONAPI=0
CHECK_ONLY=0
ROOT=""

for a in "$@"; do
  case "$a" in
    -y|--yes)       ASSUME_YES=1 ;;
    --no-build)     DO_BUILD=0 ;;
    --pythonapi)    DO_PYTHONAPI=1 ;;
    --check)        CHECK_ONLY=1; DO_BUILD=0 ;;
    -h|--help)      sed -n '2,42p' "$0"; exit 0 ;;
    -*)             echo "[FEHLER] Unbekannte Option: $a" >&2; exit 2 ;;
    *)              ROOT="$a" ;;
  esac
done

# --- CARLA-Root bestimmen ----------------------------------------------------
if [[ -z "$ROOT" ]]; then
  # vom Script-Verzeichnis (Util/BuildTools) zwei Ebenen hoch
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
ROOT="${ROOT%/}"

TARGET="$ROOT/LibCarla/source/carla/trafficmanager/TrafficManagerServer.h"
if [[ ! -f "$TARGET" ]]; then
  echo "[FEHLER] '$ROOT' sieht nicht nach einem CARLA-Repo aus." >&2
  echo "         Erwartet: $TARGET" >&2
  exit 1
fi

echo "[i] CARLA-Root : $ROOT"
echo "[i] Zieldatei  : ${TARGET#$ROOT/}"

# --- Aktuellen Zustand pruefen ----------------------------------------------
have_localhost=$(grep -c 'new ::rpc::server("127.0.0.1", RPCPort)' "$TARGET" || true)
have_increment=$(grep -cE 'RPCPort\s*\+\+\s*;' "$TARGET" || true)
have_report=$(grep -cE '_RPCPort\s*=\s*RPCPort\s*;' "$TARGET" || true)

echo "[i] Status: localhost-bind=$have_localhost  port-increment=$have_increment  report-port=$have_report"

if [[ "$have_localhost" -ge 1 && "$have_increment" -ge 1 && "$have_report" -ge 1 ]]; then
  echo "[ok] Alle drei Aenderungen sind bereits vorhanden - nichts zu patchen."
  NEED_PATCH=0
else
  NEED_PATCH=1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  [[ "$NEED_PATCH" -eq 0 ]] && exit 0 || { echo "[!] Fix fehlt (siehe Status oben)."; exit 1; }
fi

# --- Patchen (idempotent, via Python) ---------------------------------------
if [[ "$NEED_PATCH" -eq 1 ]]; then
  if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "TrafficManagerServer.h jetzt patchen? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Abgebrochen."; exit 0; }
  fi

  cp -f "$TARGET" "$TARGET.bak"
  echo "[i] Backup: ${TARGET#$ROOT/}.bak"

  python3 - "$TARGET" <<'PY'
import re, sys, pathlib
f = pathlib.Path(sys.argv[1])
src = f.read_text()
changed = []

# 1) SECURITY: Bind auf localhost normalisieren (deckt 0.0.0.0 und arg-loses
#    new ::rpc::server(RPCPort) ab; bei bereits korrektem Bind no-op).
src2, n = re.subn(r'new ::rpc::server\([^)]*\bRPCPort\s*\)',
                  'new ::rpc::server("127.0.0.1", RPCPort)', src)
if n and src2 != src:
    changed.append("localhost-bind")
src = src2

# 2) REPORT: nach erfolgreichem new den echten Port festhalten.
if not re.search(r'_RPCPort\s*=\s*RPCPort\s*;', src):
    m = re.search(r'^([ \t]*)server = new ::rpc::server\("127\.0\.0\.1", RPCPort\);\n',
                  src, re.M)
    if m:
        ind = m.group(1)
        ins = (f'\n{ind}/// Bind erfolgreich: tatsaechlich gebundenen Port merken.\n'
               f'{ind}/// RPCPort ist eine Referenz -> Aufrufer + _RPCPort halten den\n'
               f'{ind}/// echten Port; port() bleibt damit korrekt.\n'
               f'{ind}_RPCPort = RPCPort;\n')
        src = src[:m.end()] + ins + src[m.end():]
        changed.append("report-port")

# 3) FALLBACK: im catch-Block den Port hochzaehlen (vor dem sleep).
if not re.search(r'RPCPort\s*\+\+\s*;', src):
    m = re.search(r'^([ \t]*)std::this_thread::sleep_for\(500ms\);', src, re.M)
    if m:
        ind = m.group(1)
        ins = (f'{ind}/// Bind-Fehler (z.B. Port von altem Prozess belegt): naechsten\n'
               f'{ind}/// Port nehmen, damit wir automatisch auf einen freien fallen.\n'
               f'{ind}RPCPort++;\n')
        src = src[:m.start()] + ins + src[m.start():]
        changed.append("port-increment")

f.write_text(src)
print("[patch] geaendert: " + (", ".join(changed) if changed else "nichts"))
PY

  # Re-Check nach Patch
  have_localhost=$(grep -c 'new ::rpc::server("127.0.0.1", RPCPort)' "$TARGET" || true)
  have_increment=$(grep -cE 'RPCPort\s*\+\+\s*;' "$TARGET" || true)
  have_report=$(grep -cE '_RPCPort\s*=\s*RPCPort\s*;' "$TARGET" || true)
  if [[ "$have_localhost" -ge 1 && "$have_increment" -ge 1 && "$have_report" -ge 1 ]]; then
    echo "[ok] Patch verifiziert (localhost + increment + report-port vorhanden)."
    rm -f "$TARGET.bak"
  else
    echo "[FEHLER] Patch unvollstaendig - stelle Backup wieder her." >&2
    mv -f "$TARGET.bak" "$TARGET"
    exit 1
  fi
fi

# --- Build + Verifikation ----------------------------------------------------
if [[ "$DO_BUILD" -eq 1 ]]; then
  echo "[i] Baue LibCarla-Client (kompiliert den Traffic Manager) ..."
  ( cd "$ROOT" && make LibCarla.client.release ) || {
    echo "[FEHLER] LibCarla.client.release Build fehlgeschlagen." >&2; exit 1; }
  echo "[ok] LibCarla-Client baut und linkt sauber."

  if [[ "$DO_PYTHONAPI" -eq 1 ]]; then
    echo "[i] Baue PythonAPI (uebernimmt die neue libcarla_client.a) ..."
    ( cd "$ROOT" && make PythonAPI ) || {
      echo "[FEHLER] PythonAPI Build fehlgeschlagen." >&2; exit 1; }
    echo "[ok] PythonAPI gebaut."
  fi
fi

echo "[fertig] Traffic-Manager-Server abgehaertet:"
echo "         - Bind nur localhost (127.0.0.1)"
echo "         - Port-Fallback bei Belegung (RPCPort++)"
echo "         - port() liefert den real gebundenen Port (_RPCPort + Referenz)"

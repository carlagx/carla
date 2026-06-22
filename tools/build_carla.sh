#!/usr/bin/env bash
# ============================================================================
#  build_carla.sh
#  CARLA 0.9.16 Vollständiger Build für Ubuntu 22.04 LTS
#
#  🎯 Funktionen:
#    • Auto Git-Clone: Falls Repo nicht existiert, wird es automatisch geklont
#    • Xerces-C pthread-Fix: Automatisch erkannt & angewendet (glibc >= 2.34)
#    • Content-Download: Update.sh mit parallelem Download (aria2c)
#    • Vollständige Pipeline: Clone → Fix → Update → PythonAPI → launch → package
#    • Robustes Logging: Jeder Schritt in separates Logfile
#    • Preflight-Checks: Detaillierte Diagnose vor dem Build
#
#  📋 Konfiguration: carla_build.conf (gleiches Verzeichnis)
#  ⚡ Nutzung:
#    ./build_carla.sh                    # Normaler Build mit carla_build.conf
#    ./build_carla.sh --preflight-only   # Nur Checks, keine Änderungen
#    ./build_carla.sh --skip-xerces      # Build ohne Xerces-Fix
#    ./build_carla.sh --config my.conf   # Custom Config-Datei
#    ./build_carla.sh --help             # Diese Hilfe
#
# ============================================================================

set -euo pipefail
export GIT_TERMINAL_PROMPT=0 DEBIAN_FRONTEND=noninteractive

# ============================================================================
# KONFIGURATION & ARGUMENTE
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/carla_build.conf"
PREFLIGHT_ONLY=false
SKIP_XERCES=false

print_help() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --config=*) CONFIG_FILE="${1#*=}"; shift ;;
    --preflight-only) PREFLIGHT_ONLY=true; shift ;;
    --skip-xerces) SKIP_XERCES=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "❌ Unbekanntes Argument: $1" >&2; print_help; exit 2 ;;
  esac
done

# ============================================================================
# FARBEN & AUSGABE-FUNKTIONEN
# ============================================================================
if [[ -t 1 ]]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_BLUE="\033[34m"
  C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"; C_CYAN="\033[36m"
else
  C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

info() { echo -e "${C_CYAN}ℹ ${*}${C_RESET}"; }
ok()   { echo -e "${C_GREEN}✔ ${*}${C_RESET}"; }
warn() { echo -e "${C_YELLOW}⚠ ${*}${C_RESET}"; }
fail() { echo -e "${C_RED}✗ FEHLER: ${*}${C_RESET}" >&2; exit 1; }
sep()  { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

fmt_dur() {
  local s=$1 h m; h=$(( s/3600 )); m=$(( (s%3600)/60 )); s=$(( s%60 ))
  printf '%dh %02dm %02ds' "$h" "$m" "$s"
}

# ============================================================================
# KONFIGURATION LADEN
# ============================================================================
[[ -f "$CONFIG_FILE" ]] || fail "Config nicht gefunden: $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

TARGET_DIR="${CLONE_BASE_DIR%/}/${CLONE_DIR_NAME}"
LOG_DIR="${LOG_DIR:-${CLONE_BASE_DIR%/}/carla_build_logs}"
mkdir -p "$LOG_DIR"
export UE4_ROOT

info "Config: $CONFIG_FILE"
info "Ziel: $TARGET_DIR"

# ============================================================================
# SCHRITT-VERWALTUNG
# ============================================================================
START_TIME=$(date +%s)
CURRENT_STEP=0
TOTAL_STEPS=0
CURRENT_STEP_NAME=""
CURRENT_LOG=""

# Schritte zählen
if [[ "${PREFLIGHT_ONLY}" == "true" ]]; then
  TOTAL_STEPS=1
else
  TOTAL_STEPS=2  # Preflight + Clone/reuse
  [[ "${INSTALL_APT_DEPS}" == "true" ]]    && TOTAL_STEPS=$((TOTAL_STEPS+1))
  [[ "${SKIP_XERCES}" == "false" ]]        && TOTAL_STEPS=$((TOTAL_STEPS+1))
  [[ "${RUN_UPDATE}" == "true" ]]          && TOTAL_STEPS=$((TOTAL_STEPS+1))
  [[ "${INSTALL_PYTHON_DEPS}" == "true" ]] && TOTAL_STEPS=$((TOTAL_STEPS+1))
  TOTAL_STEPS=$(( TOTAL_STEPS + ${#BUILD_STEPS[@]} ))
fi

banner() {
  local elapsed; elapsed=$(( $(date +%s) - START_TIME ))
  echo
  echo -e "${C_BOLD}${C_BLUE}$(sep)${C_RESET}"
  echo -e "${C_BOLD}${C_BLUE}▶ Schritt ${CURRENT_STEP}/${TOTAL_STEPS}: ${1}${C_RESET}"
  echo -e "${C_BLUE}  📅 $(date '+%H:%M:%S')   ⏱️  Gesamt: $(fmt_dur "$elapsed")${C_RESET}"
  echo -e "${C_BOLD}${C_BLUE}$(sep)${C_RESET}"
}

run_step() {
  CURRENT_STEP=$((CURRENT_STEP+1))
  local desc="$1"; shift
  CURRENT_STEP_NAME="$desc"
  local slug; slug=$(echo "$desc" | tr ' /' '__' | tr -cd 'A-Za-z0-9_')
  CURRENT_LOG="${LOG_DIR}/$(printf '%02d' "$CURRENT_STEP")_${slug}.log"
  banner "$desc"
  info "📝 Log: $CURRENT_LOG"
  local t0; t0=$(date +%s)
  set +e
  "$@" 2>&1 | tee "$CURRENT_LOG"
  local rc=${PIPESTATUS[0]}
  set -e
  local t1; t1=$(date +%s)
  if [[ "$rc" -ne 0 ]]; then
    fail "Schritt fehlgeschlagen: '${desc}' (Exit ${rc}). Siehe: $CURRENT_LOG"
  fi
  ok "Fertig: ${desc}  ($(fmt_dur $((t1-t0))))"
}

on_err() {
  local rc=$?
  echo
  echo -e "${C_RED}${C_BOLD}$(sep)${C_RESET}"
  echo -e "${C_RED}${C_BOLD}✗ Build fehlgeschlagen in Schritt ${CURRENT_STEP}/${TOTAL_STEPS}:${C_RESET}"
  echo -e "${C_RED}  ${CURRENT_STEP_NAME:-<Vorbereitung>}${C_RESET}"
  [[ -n "$CURRENT_LOG" ]] && echo -e "${C_RED}📝 Log: ${CURRENT_LOG}${C_RESET}" >&2
  echo -e "${C_RED}${C_BOLD}$(sep)${C_RESET}" >&2
  exit "$rc"
}
trap on_err ERR

# ============================================================================
# SCHRITT-IMPLEMENTIERUNGEN
# ============================================================================

do_preflight() {
  cat << EOF
$(sep)
  Repository & Konfiguration
$(sep)
  URL           : $REPO_URL
  Source-Branch : $SOURCE_BRANCH
  Neuer Branch  : $NEW_BRANCH
  Zielordner    : $TARGET_DIR

$(sep)
  Build-Umgebung
$(sep)
  Python        : $($PYTHON_BIN --version 2>&1)
  UE4_ROOT      : $UE4_ROOT
  Log-Ordner    : $LOG_DIR

$(sep)
  Verfügbare Tools
$(sep)
EOF

  local missing=()
  for t in git make cmake ninja "$PYTHON_BIN" tar; do
    if command -v "$t" >/dev/null 2>&1; then
      echo "  ✓ $(command -v "$t")"
    else
      missing+=("$t")
    fi
  done

  if ! command -v wget >/dev/null 2>&1 && ! command -v aria2c >/dev/null 2>&1; then
    missing+=("wget/aria2c")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  ✗ Fehlend: ${missing[*]}"
    if [[ "${INSTALL_APT_DEPS}" == "true" ]]; then
      warn "Werden im apt-Schritt nachinstalliert"
    else
      fail "Bitte installieren oder INSTALL_APT_DEPS=true setzen"
    fi
  fi

  if command -v aria2c >/dev/null 2>&1; then
    echo "  ✓ aria2c (schneller Download)"
  else
    warn "aria2c fehlt, nutze wget (langsamer)"
  fi

  cat << EOF

$(sep)
  Speicher-Prüfung
$(sep)
EOF

  local free_gb; free_gb=$(df -BG --output=avail "$CLONE_BASE_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [[ -n "${free_gb:-}" ]]; then
    echo "  Frei: ${free_gb} GB unter $CLONE_BASE_DIR"
    if [[ "$free_gb" -lt 100 ]]; then
      warn "Unter 100 GB – Build könnte knapp werden (braucht ~80 GB CARLA + Content)"
    fi
  fi

  cat << EOF

$(sep)
  UE4 Check
$(sep)
EOF

  if [[ ! -d "$UE4_ROOT" ]]; then
    fail "UE4_ROOT existiert nicht: $UE4_ROOT"
  fi
  [[ -d "$UE4_ROOT/Engine" ]] && echo "  ✓ UE4 Engine-Ordner gefunden" || warn "Kein Engine/-Ordner in $UE4_ROOT"

  cat << EOF

$(sep)
  glibc & Xerces-Fix
$(sep)
EOF

  local glibc_ver; glibc_ver=$(ldd --version | head -1 | awk '{print $NF}')
  echo "  glibc: $glibc_ver"
  if (( $(echo "$glibc_ver >= 2.34" | bc -l) )); then
    echo "  → Xerces-Fix wird angewendet (--skip-xerces um zu überspringen)"
  else
    warn "glibc < 2.34 – Xerces-Fix evtl. nicht nötig"
  fi

  echo "$(sep)"
  return 0
}

do_apt() {
  warn "apt-Installation benötigt sudo (kann nach Passwort fragen)"
  [[ -x $(command -v sudo) ]] || fail "sudo nicht verfügbar"
  sudo apt-get update
  # shellcheck disable=SC2086
  sudo apt-get install -y $APT_PACKAGES
}

do_clone() {
  if [[ -d "$TARGET_DIR/.git" ]]; then
    info "Git-Repo existiert bereits unter $TARGET_DIR (reuse-Modus)"
    cd "$TARGET_DIR"
    git fetch origin
    if git show-ref --verify --quiet "refs/heads/${NEW_BRANCH}"; then
      info "Branch ${NEW_BRANCH} existiert bereits → checkout"
      git checkout "$NEW_BRANCH"
    else
      info "Erstelle neuen Branch ${NEW_BRANCH}"
      git checkout -b "$NEW_BRANCH"
    fi
  elif [[ -e "$TARGET_DIR" ]]; then
    if [[ "${ON_EXISTING_DIR}" == "fail" ]]; then
      fail "Zielordner existiert, ist aber kein Git-Repo: $TARGET_DIR (ON_EXISTING_DIR=fail)"
    else
      fail "Zielordner existiert und ist nicht Git-Repo"
    fi
  else
    info "Klone $REPO_URL (Branch: $SOURCE_BRANCH)..."
    mkdir -p "$CLONE_BASE_DIR"
    git clone --branch "$SOURCE_BRANCH" "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    info "Erstelle Branch ${NEW_BRANCH}"
    git checkout -b "$NEW_BRANCH"
  fi

  echo
  echo "📌 Git-Status:"
  echo "  Branch  : $(git rev-parse --abbrev-ref HEAD)"
  echo "  HEAD    : $(git rev-parse --short HEAD)"
  git log --oneline -1 | sed 's/^/  Commit : /'
  echo "  Origin  : $(git remote get-url origin)"
}

do_xerces_fix() {
  cd "$TARGET_DIR"
  local setup_sh="Util/BuildTools/Setup.sh"
  [[ -f "$setup_sh" ]] || fail "Setup.sh nicht gefunden: $setup_sh"

  # Fix already present (both Xerces cmake blocks pass -pthread)?
  if [[ "$(grep -c 'fPIC -w -pthread' "$setup_sh")" -ge 2 ]]; then
    info "Xerces-Fix bereits angewendet (-pthread vorhanden), überspringe"
    return 0
  fi

  info "Wende Xerces-C pthread-Linking-Fix an (-pthread)..."

  # Add -pthread to both Xerces-C cmake CXX flag lines (client + server). This
  # is the root-cause fix: the test/sample/doc executables fail to link the
  # pthread symbols on glibc >= 2.34 otherwise. Upstream sources stay untouched
  # and all targets keep building. (Older versions of this script commented out
  # the tests/samples/doc subdirectories instead, which patches upstream and
  # disables the tests.)
  python3 << 'PYTHON_PATCH'
import sys

setup_sh = "Util/BuildTools/Setup.sh"
with open(setup_sh) as f:
    content = f.read()

replacements = [
    ('-DCMAKE_CXX_FLAGS="-std=c++14 -fPIC -w"',
     '-DCMAKE_CXX_FLAGS="-std=c++14 -fPIC -w -pthread"'),
    ('-DCMAKE_CXX_FLAGS="-std=c++14 -stdlib=libc++ -fPIC -w ',
     '-DCMAKE_CXX_FLAGS="-std=c++14 -stdlib=libc++ -fPIC -w -pthread '),
]

applied = 0
for old, new in replacements:
    if old in content:
        content = content.replace(old, new, 1)
        applied += 1

if applied == 2:
    with open(setup_sh, 'w') as f:
        f.write(content)
    print("✓ -pthread zu beiden Xerces-cmake-Aufrufen hinzugefügt")
    sys.exit(0)
else:
    print(f"✗ Erwartete Xerces-Flags nicht gefunden ({applied}/2)", file=sys.stderr)
    sys.exit(1)
PYTHON_PATCH

  ok "Xerces-Fix angewendet"
}

do_update() {
  cd "$TARGET_DIR"
  [[ -x ./Update.sh ]] || fail "Update.sh nicht gefunden/ausführbar"
  info "Starte Content-Download..."
  if [[ "${UPDATE_SKIP_DOWNLOAD}" == "true" ]]; then
    ./Update.sh --skip-download
  else
    ./Update.sh
  fi
}

do_pip() {
  cd "$TARGET_DIR"
  local req="PythonAPI/carla/requirements.txt"
  [[ -f "$req" ]] || fail "requirements.txt nicht gefunden: $req"
  info "Installiere Python Build-Dependencies..."
  # shellcheck disable=SC2086
  "$PYTHON_BIN" -m pip install $PIP_ARGS -r "$req"
}

do_make() {
  cd "$TARGET_DIR"
  export UE4_ROOT
  info "Ausführe: make $1"
  make "$1"
}

# ============================================================================
# HAUPTABLAUF
# ============================================================================
echo
echo -e "${C_BOLD}${C_BLUE}╔════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}║  CARLA 0.9.16 Build-Pipeline – ${TOTAL_STEPS} Schritte                              ║${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}╚════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo

run_step "Preflight-Checks" do_preflight

if [[ "${PREFLIGHT_ONLY}" == "true" ]]; then
  echo
  ok "✅ Preflight-Only: Alle Checks erfolgreich, kein Build ausgeführt"
  exit 0
fi

[[ "${INSTALL_APT_DEPS}" == "true" ]] && run_step "System-Pakete (apt)" do_apt
run_step "Repository klonen/reuse & Branch-Setup" do_clone
[[ "${SKIP_XERCES}" == "false" ]] && run_step "Xerces-C pthread-Fix anwenden" do_xerces_fix
[[ "${RUN_UPDATE}" == "true" ]] && run_step "Content herunterladen (Update.sh)" do_update
[[ "${INSTALL_PYTHON_DEPS}" == "true" ]] && run_step "Python Build-Requirements (pip)" do_pip

for t in "${BUILD_STEPS[@]}"; do
  run_step "make ${t}" do_make "$t"
done

# ============================================================================
# ABSCHLUSS
# ============================================================================
TOTAL_ELAPSED=$(( $(date +%s) - START_TIME ))
echo
echo -e "${C_BOLD}${C_GREEN}╔════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}║  ✅ CARLA-Build erfolgreich abgeschlossen!                          ║${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}╚════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "${C_GREEN}"
echo "  📁 Repo        : $TARGET_DIR"
echo "  🌳 Branch      : $(cd "$TARGET_DIR" && git rev-parse --abbrev-ref HEAD)"
echo "  📍 HEAD        : $(cd "$TARGET_DIR" && git rev-parse --short HEAD)"
echo "  ⏱️  Gesamtdauer : $(fmt_dur "$TOTAL_ELAPSED")"
echo "  📝 Logs        : $LOG_DIR"

if [[ -d "$TARGET_DIR/Dist" ]] && [[ -n "$(ls -A "$TARGET_DIR/Dist" 2>/dev/null)" ]]; then
  echo "  📦 Pakete      :"
  ls -1 "$TARGET_DIR/Dist" 2>/dev/null | sed 's/^/    • /'
fi

echo
echo "  🚀 Nächste Schritte:"
echo "    1. PythonAPI installieren:"
echo "       pip install $TARGET_DIR/PythonAPI/carla/dist/carla-*.whl"
echo "    2. CARLA Server starten:"
echo "       cd $TARGET_DIR && ./CarlaUE4.sh"
echo "    3. Mit Python verbinden:"
echo "       python3 PythonAPI/examples/manual_control.py"
echo
echo -e "${C_GREEN}$(sep)${C_RESET}"

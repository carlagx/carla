#!/bin/bash

################################################################################
# CARLA Buildability Check (C++ client + C++ server)
#
# Verifies that the C++ parts of this branch can be built:
#   1. Preflight   tools, compilers, UE4_ROOT, disk space
#   2. C++ client  Examples/CppClient: LibCarla.client + bin/cpp_client + bin/gpu_test
#   3. C++ server  LibCarla.server (release)
#   4. UE4 server  CarlaUE4 C++ module (editor target, long)   [only with --ue4]
#
# Usage:
#   ./check-buildable.sh [options]
#
# Options:
#   --preflight-only   Only check prerequisites, build nothing
#   --client-only      Only the C++ client
#   --server-only      Only the C++ server
#   --ue4              Also compile the CarlaUE4 module (needs UE4_ROOT, takes long)
#   --jobs=N           Parallel jobs (default: nproc)
#   -h, --help         Show this help
#
# Environment:
#   UE4_ROOT           Unreal Engine 4.26 (default: ~/UnrealEngine_4.26)
#
# Exit code: number of failed checks (0 = everything buildable).
# Logs: build-check-logs/<time>/
################################################################################

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

CARLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
export UE4_ROOT="${UE4_ROOT:-$HOME/UnrealEngine_4.26}"
JOBS="$(nproc)"
DO_CLIENT=true; DO_SERVER=true; DO_UE4=false; DO_BUILD=true

for arg in "$@"; do
  case "$arg" in
    --preflight-only) DO_BUILD=false ;;
    --client-only)    DO_SERVER=false ;;
    --server-only)    DO_CLIENT=false ;;
    --ue4)            DO_UE4=true ;;
    --jobs=*)         JOBS="${arg#*=}" ;;
    -h|--help)        sed -n '3,28p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

LOGDIR="$CARLA_ROOT/build-check-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

FAILED=0
declare -a SUMMARY
# Results are mirrored to $LOGDIR/summary.txt for scan-carla-logs.sh.
pass()    { echo -e "${GREEN}[ OK ]${NC} $1"; SUMMARY+=("OK    $1"); printf 'PASS\t%s\n' "$1" >>"$LOGDIR/summary.txt"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; SUMMARY+=("FAIL  $1"); FAILED=$((FAILED+1)); printf 'FAIL\t%s\n' "$1" >>"$LOGDIR/summary.txt"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
section() { echo; echo -e "${BLUE}== $1 ==${NC}"; }

# run_step <name> <logfile> <dir> <cmd...>
run_step() {
  local name="$1" log="$LOGDIR/$2" dir="$3"; shift 3
  info "$name ..."
  local t0=$SECONDS
  if (cd "$dir" && "$@") >"$log" 2>&1; then
    pass "$name ($((SECONDS-t0)) s)"
    return 0
  fi
  fail "$name (log: $log)"
  echo "      last lines:"; tail -n 8 "$log" | sed 's/^/      | /'
  return 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1 && pass "tool: $1" || fail "tool missing: $1"; }

# ---------------------------------------------------------------- 1. Preflight
section "Preflight"
for t in git make cmake ninja gcc g++ python3; do need_cmd "$t"; done

if command -v g++ >/dev/null; then
  GCCV="$(g++ -dumpversion | cut -d. -f1)"
  [ "$GCCV" -ge 9 ] 2>/dev/null && pass "g++ $GCCV supports C++17" || fail "g++ $GCCV too old for C++17 (need >= 9)"
fi

FREE_GB=$(df -BG --output=avail "$CARLA_ROOT" | tail -1 | tr -dc '0-9')
NEED_GB=10; $DO_UE4 && NEED_GB=60
[ "${FREE_GB:-0}" -ge "$NEED_GB" ] && pass "disk space: ${FREE_GB} GB free (need ~${NEED_GB} GB)" \
                                   || fail "disk space: ${FREE_GB} GB free, need ~${NEED_GB} GB"

[ -f "$CARLA_ROOT/Examples/CppClient/main.cpp" ] && pass "sources: Examples/CppClient" || fail "Examples/CppClient/main.cpp missing"
[ -d "$CARLA_ROOT/LibCarla/source/carla" ]      && pass "sources: LibCarla"          || fail "LibCarla/source/carla missing"

if $DO_UE4; then
  if [ -x "$UE4_ROOT/Engine/Build/BatchFiles/RunUAT.sh" ]; then
    pass "UE4_ROOT = $UE4_ROOT"
  else
    fail "UE4_ROOT '$UE4_ROOT' invalid (RunUAT.sh not found)"
  fi
  [ -d "$CARLA_ROOT/Unreal/CarlaUE4/Plugins/Carla" ] && pass "sources: Unreal/CarlaUE4/Plugins/Carla" \
                                                     || fail "Unreal/CarlaUE4/Plugins/Carla missing"
fi

if [ "$FAILED" -gt 0 ]; then
  warn "Preflight failed, skipping builds."
  DO_BUILD=false
fi

# ---------------------------------------------------------------- 2. C++ client
if $DO_BUILD && $DO_CLIENT; then
  section "C++ client"
  CLIENT_DIR="$CARLA_ROOT/Examples/CppClient"
  if run_step "LibCarla.client + cpp_client" client.log "$CLIENT_DIR" make build; then
    [ -x "$CLIENT_DIR/bin/cpp_client" ] && pass "artifact: bin/cpp_client" || fail "bin/cpp_client missing after build"
  fi
  if run_step "gpu_test" client-gpu_test.log "$CLIENT_DIR" make gpu_test; then
    [ -x "$CLIENT_DIR/bin/gpu_test" ] && pass "artifact: bin/gpu_test" || fail "bin/gpu_test missing after build"
  fi
fi

# ---------------------------------------------------------------- 3. C++ server
if $DO_BUILD && $DO_SERVER; then
  section "C++ server (LibCarla.server)"
  if run_step "LibCarla.server.release" server-libcarla.log "$CARLA_ROOT" make LibCarla.server.release; then
    SRVLIB="$(find "$CARLA_ROOT/Build/libcarla-server-install" "$CARLA_ROOT/Unreal/CarlaUE4/Plugins/Carla/CarlaDependencies" \
                -name 'libcarla_server*.a' 2>/dev/null | head -1)"
    [ -n "$SRVLIB" ] && pass "artifact: ${SRVLIB#$CARLA_ROOT/}" || warn "libcarla_server*.a not found at the usual locations"
  fi
fi

# ---------------------------------------------------------------- 4. UE4 module
if $DO_BUILD && $DO_SERVER && $DO_UE4; then
  section "C++ server (CarlaUE4 module, UE4 ${UE4_ROOT##*/})"
  run_step "CarlaUE4 editor target" server-ue4.log "$CARLA_ROOT" \
    bash "$CARLA_ROOT/Util/BuildTools/BuildCarlaUE4.sh" --build
fi

# ---------------------------------------------------------------- Summary
section "Summary"
printf '%s\n' "${SUMMARY[@]}"
echo
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC} Logs: $LOGDIR"
else
  echo -e "${RED}$FAILED check(s) failed.${NC} Logs: $LOGDIR"
fi
printf 'TOTAL\tFAIL: %s\n' "$FAILED" >>"$LOGDIR/summary.txt"
exit "$FAILED"

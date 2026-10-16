#!/bin/bash

################################################################################
# CARLA Stand-alone Server Build Script (Linux)
#
# Builds a packaged, stand-alone CARLA server (cooked UE4 game, no editor
# needed to run it) from the current working tree.
#
# Pipeline:
#   1. LibCarla server (release)      -> make LibCarla.server.release
#   2. OSM2ODR                        -> make osm2odr
#   3. UE4 plugins + CarlaUE4 editor  -> BuildUE4Plugins.sh / BuildCarlaUE4.sh
#   4. Cook + package                 -> BuildTools/Package.sh
#
# Usage:
#   ./build-carla-server.sh [options]
#
# Options:
#   --config=<Development|Shipping|Debug>  Package configuration (default: Shipping)
#   --skip-libcarla                        Skip step 1 + 2
#   --skip-editor                          Skip step 3 (UE4 editor already built)
#   --maps=Town06,Town04                   Maps to cook; the first one is the default map
#                                          (default: Town06,Town04)
#   --all-maps                             Cook all maps from DefaultGame.ini (no config patching)
#   --no-zip                               Do not create the .tar.gz archive
#   --clean-intermediate                   Remove intermediate files after packaging
#   --jobs=N                               Parallel jobs (default: nproc)
#   -h, --help                             Show this help
#
# Environment variables:
#   UE4_ROOT    Path to Unreal Engine 4.26 (default: ~/UnrealEngine_4.26)
#
# Result:
#   Dist/CARLA_<config>_<version>/LinuxNoEditor/CarlaUE4.sh
#   Start e.g.:  ./CarlaUE4.sh -RenderOffScreen -carla-rpc-port=2000
#
################################################################################

set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

# Always use the repo this script lives in; ignore a CARLA_ROOT set in the shell
CARLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
export CARLA_ROOT
export UE4_ROOT="${UE4_ROOT:-$HOME/UnrealEngine_4.26}"
CONFIG="Shipping"
SKIP_LIBCARLA=false
SKIP_EDITOR=false
PACKAGE_ARGS=()
MAPS="Town06,Town04"
ALL_MAPS=false
JOBS="$(nproc)"

for arg in "$@"; do
  case "$arg" in
    --config=*)           CONFIG="${arg#*=}" ;;
    --skip-libcarla)      SKIP_LIBCARLA=true ;;
    --skip-editor)        SKIP_EDITOR=true ;;
    --maps=*)             MAPS="${arg#*=}" ;;
    --all-maps)           ALL_MAPS=true ;;
    --no-zip)             PACKAGE_ARGS+=("--no-zip") ;;
    --clean-intermediate) PACKAGE_ARGS+=("--clean-intermediate") ;;
    --jobs=*)             JOBS="${arg#*=}" ;;
    -h|--help)            sed -n '3,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                    fail "Unknown option: $arg (see --help)" ;;
  esac
done

case "$CONFIG" in
  Development|Shipping|Debug) ;;
  *) fail "Invalid --config '$CONFIG' (Development|Shipping|Debug)" ;;
esac

[ -f "$CARLA_ROOT/Makefile" ] || fail "No Makefile in $CARLA_ROOT "
[ -d "$UE4_ROOT" ] || fail "UE4_ROOT '$UE4_ROOT' does not exist (set UE4_ROOT)"
[ -x "$UE4_ROOT/Engine/Build/BatchFiles/RunUAT.sh" ] || fail "RunUAT.sh not found in UE4_ROOT"

cd "$CARLA_ROOT"
export MAKEFLAGS="-j${JOBS}"
TOOLS="$CARLA_ROOT/Util/BuildTools"
T0=$(date +%s)

info "CARLA_ROOT = $CARLA_ROOT"
info "UE4_ROOT   = $UE4_ROOT"
info "Config     = $CONFIG, jobs = $JOBS"
FREE_GB=$(df -BG --output=avail "$CARLA_ROOT" | tail -1 | tr -dc '0-9')
[ "$FREE_GB" -ge 60 ] || warn "Only ${FREE_GB} GB free; cooking needs roughly 60+ GB"

# 1+2: LibCarla server + OSM2ODR
if ! $SKIP_LIBCARLA; then
  info "[1/4] Building LibCarla server (release)"
  make LibCarla.server.release
  info "[2/4] Building OSM2ODR"
  make osm2odr
  ok "LibCarla + OSM2ODR done"
else
  warn "Skipping LibCarla/OSM2ODR"
fi

# 3: UE4 plugins + editor binaries (required by the cook step)
if ! $SKIP_EDITOR; then
  info "[3/4] Building UE4 plugins and CarlaUE4 editor"
  make downloadplugins
  "$TOOLS/BuildUE4Plugins.sh" --build
  "$TOOLS/BuildCarlaUE4.sh" --build
  ok "UE4 editor build done"
else
  warn "Skipping UE4 editor build"
fi

# Restrict cooked maps: temporarily patch DefaultGame.ini / DefaultEngine.ini,
# restored on exit (also on error/Ctrl+C). OpenDriveMap is always kept so
# generate_opendrive_world() keeps working.
GAME_INI="$CARLA_ROOT/Unreal/CarlaUE4/Config/DefaultGame.ini"
ENGINE_INI="$CARLA_ROOT/Unreal/CarlaUE4/Config/DefaultEngine.ini"
restore_ini() {
  [ -f "$GAME_INI.orig" ]   && mv -f "$GAME_INI.orig" "$GAME_INI"
  [ -f "$ENGINE_INI.orig" ] && mv -f "$ENGINE_INI.orig" "$ENGINE_INI"
}
if ! $ALL_MAPS; then
  IFS=',' read -r -a MAP_LIST <<< "$MAPS"
  for m in "${MAP_LIST[@]}"; do
    [ -f "$CARLA_ROOT/Unreal/CarlaUE4/Content/Carla/Maps/$m.umap" ] || fail "Map '$m' not found in Content/Carla/Maps"
  done
  DEFAULT_MAP="${MAP_LIST[0]}"
  info "Cooking only maps: ${MAP_LIST[*]} (default: $DEFAULT_MAP)"
  cp "$GAME_INI" "$GAME_INI.orig"; cp "$ENGINE_INI" "$ENGINE_INI.orig"
  trap restore_ini EXIT
  MAPS_CSV="$MAPS" DEFAULT_MAP="$DEFAULT_MAP" GAME_INI="$GAME_INI" ENGINE_INI="$ENGINE_INI" python3 - <<'PY'
import os, re
game, eng = os.environ["GAME_INI"], os.environ["ENGINE_INI"]
maps = os.environ["MAPS_CSV"].split(",")
d = os.environ["DEFAULT_MAP"]
lines = open(game).read().splitlines()
out, done = [], False
for l in lines:
    if l.startswith("+MapsToCook=") and "/Game/Carla/Maps/" in l:
        if not done:
            out += ['+MapsToCook=(FilePath="/Game/Carla/Maps/%s")' % m for m in maps + [x for x in ["OpenDriveMap"] if x not in maps]]
            done = True
        continue
    out.append(l)
assert done, "no MapsToCook entries found"
open(game, "w").write("\n".join(out) + "\n")
e = open(eng).read()
for key in ("GameDefaultMap", "ServerDefaultMap", "TransitionMap", "EditorStartupMap"):
    e = re.sub(r"^%s=.*$" % key, "%s=/Game/Carla/Maps/%s.%s" % (key, d, d), e, flags=re.M)
open(eng, "w").write(e)
PY
fi

# 4: cook + package
info "[4/4] Cooking and packaging server (this takes a long time)"
# The Python wheel is not part of a server-only build; an empty dir avoids rsync errors
mkdir -p "$CARLA_ROOT/PythonAPI/carla/dist"
# Package.sh may return non-zero for harmless copy errors; success is judged below
"$TOOLS/Package.sh" --config="$CONFIG" "${PACKAGE_ARGS[@]}" || warn "Package.sh exited with code $? (checking result)"

# Locate result
OUT=$(ls -dt "$CARLA_ROOT"/Dist/CARLA_*/LinuxNoEditor 2>/dev/null | head -1 || true)
[ -n "$OUT" ] && [ -x "$OUT/CarlaUE4.sh" ] || fail "Package finished but CarlaUE4.sh not found under Dist/"

ELAPSED=$(( $(date +%s) - T0 ))
ok "Stand-alone server built in $((ELAPSED/60)) min"
echo "  Location : $OUT"
echo "  Start    : $OUT/CarlaUE4.sh -RenderOffScreen -carla-rpc-port=2000"

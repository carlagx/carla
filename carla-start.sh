#!/usr/bin/env bash
# Starts the CARLA server (optional) and a client using the Python or C++ API.
# All defaults live in carla.conf next to this script.
# Prints a report with versions, paths, rendering mode and GPU usage.
#
# Usage:
#   ./carla-start.sh                        # use API from carla.conf
#   ./carla-start.sh --api cpp              # C++ client instead
#   ./carla-start.sh --api cpp-manual       # C++ manual_control (keyboard driving, SDL2)
#   ./carla-start.sh --api cpp-gtk          # same with GTK3 + Cairo (no SDL2 needed)
#   ./carla-start.sh --map Town03           # override map
#   ./carla-start.sh --config other.conf    # use another config file
#   ./carla-start.sh --report               # only print the report, start nothing
#   ./carla-start.sh -- --res 1280x720      # everything after -- goes to the client

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/carla.conf"
OVERRIDE_API=""
OVERRIDE_MAP=""
REPORT_ONLY=0
CLIENT_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        --api)    OVERRIDE_API="$2"; shift 2 ;;
        --map)    OVERRIDE_MAP="$2"; shift 2 ;;
        --report) REPORT_ONLY=1; shift ;;
        --)       shift; CLIENT_ARGS=("$@"); break ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ ! -f "$CONFIG" ]; then
    echo "Config file not found: $CONFIG" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"

[ -n "$OVERRIDE_API" ] && API="$OVERRIDE_API"
[ -n "$OVERRIDE_MAP" ] && CARLA_MAP="/Game/Carla/Maps/$OVERRIDE_MAP"

port_open() { (exec 3<>/dev/tcp/"$CARLA_HOST"/"$CARLA_PORT") 2>/dev/null; }

# ---- Python client package (unpacked once, must match the server) -----------
ensure_py_carla() {
    if ! compgen -G "$PY_CARLA_DIR/carla/libcarla*.so" > /dev/null; then
        echo "Unpacking $PY_WHEEL -> $PY_CARLA_DIR"
        mkdir -p "$PY_CARLA_DIR"
        unzip -q -o "$PY_WHEEL" -d "$PY_CARLA_DIR"
    fi
}

# ---- Report -----------------------------------------------------------------
yes_no() { if [ -e "$1" ]; then echo "ok"; else echo "MISSING"; fi; }

render_mode() {
    local args=" $CARLA_SERVER_ARGS "
    local mode backend quality
    if [[ "$args" == *" -nullrhi "* ]]; then
        mode="no rendering (-nullrhi)"
    elif [[ "$args" == *" -RenderOffScreen "* ]]; then
        mode="offscreen (-RenderOffScreen)"
    else
        mode="windowed, DISPLAY=${DISPLAY:-not set}"
    fi
    if [[ "$args" == *" -vulkan "* ]]; then backend="Vulkan (-vulkan)"
    elif [[ "$args" == *" -opengl"* ]]; then backend="OpenGL (-opengl)"
    else backend="UE default"; fi
    quality=$(grep -o -- '-quality-level=[^ ]*' <<< "$args" || true)
    echo "  mode:        $mode"
    echo "  backend:     $backend"
    echo "  quality:     ${quality:-server default}"
}

gpu_list() {
    if command -v nvidia-smi > /dev/null; then
        nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader \
            | sed 's/^/  GPU /'
    else
        echo "  nvidia-smi not found, no NVIDIA driver detected"
    fi
}

report_static() {
    echo "=== CARLA start report ==="
    echo "Config:        $CONFIG"
    echo "API:           $API"
    echo "Server"
    echo "  root:        $CARLA_ROOT [$(yes_no "$CARLA_ROOT/CarlaUE4.sh")]"
    echo "  version:     $(cat "$CARLA_ROOT/VERSION" 2>/dev/null || echo unknown)"
    echo "  binary:      $CARLA_ROOT/CarlaUE4/Binaries/Linux/CarlaUE4-Linux-Shipping [$(yes_no "$CARLA_ROOT/CarlaUE4/Binaries/Linux/CarlaUE4-Linux-Shipping")]"
    echo "  start map:   ${CARLA_MAP:-server default}"
    echo "  address:     $CARLA_HOST:$CARLA_PORT"
    echo "  args:        ${CARLA_SERVER_ARGS:-none}"
    echo "Python client"
    echo "  wheel:       $PY_WHEEL [$(yes_no "$PY_WHEEL")]"
    echo "  version:     $(basename "$PY_WHEEL" | sed -E 's/^carla-([0-9.]+).*/\1/')"
    echo "  unpacked to: $PY_CARLA_DIR"
    echo "  script:      $PY_SCRIPT [$(yes_no "$PY_SCRIPT")]"
    echo "  vehicle:     ${VEHICLE:-random}"
    echo "  interpreter: $(command -v "$PY_INTERPRETER" || echo MISSING) ($("$PY_INTERPRETER" --version 2>&1))"
    echo "C++ client"
    echo "  binary:      $CPP_CLIENT_BIN [$(yes_no "$CPP_CLIENT_BIN")]"
    echo "C++ manual control"
    echo "  binary:      $CPP_MANUAL_BIN [$(yes_no "$CPP_MANUAL_BIN")]"
    echo "  vehicle:     ${VEHICLE:-random}"
    echo "C++ manual control (GTK)"
    echo "  binary:      $CPP_GTK_BIN [$(yes_no "$CPP_GTK_BIN")]"
    echo "  vehicle:     ${VEHICLE:-random}, map: ${CARLA_MAP##*/}"
    echo "Rendering"
    render_mode
    echo "GPU"
    gpu_list
}

report_runtime() {
    local pid info server_version client_version map_name
    pid=$(pgrep -f "CarlaUE4-Linux-Shipping CarlaUE4.*-carla-rpc-port=$CARLA_PORT" | head -1 || true)
    ensure_py_carla
    info=$(PYTHONPATH="$PY_CARLA_DIR" "$PY_INTERPRETER" -c "
import carla
c = carla.Client('$CARLA_HOST', $CARLA_PORT)
c.set_timeout(20)
print(c.get_server_version())
print(c.get_client_version())
print(c.get_world().get_map().name)" 2>/dev/null || true)
    server_version=$(sed -n 1p <<< "$info")
    client_version=$(sed -n 2p <<< "$info")
    map_name=$(sed -n 3p <<< "$info")

    echo "=== CARLA runtime ==="
    echo "  server:      version ${server_version:-unknown}, pid ${pid:-unknown}"
    echo "  client:      version ${client_version:-unknown}"
    map_name=${map_name##*/}
    echo "  map:         ${map_name:-unknown}"

    if [[ " $CARLA_SERVER_ARGS " == *" -nullrhi "* ]]; then
        echo "  GPU use:     no rendering, GPU not used for drawing"
    elif [ -z "$pid" ]; then
        echo "  GPU use:     unknown, server process not found"
    elif grep -q -E "libnvidia-glcore|libGLX_nvidia|nvidia_icd|libnvidia-rtcore" "/proc/$pid/maps" 2>/dev/null; then
        echo "  GPU use:     YES, NVIDIA driver libraries loaded by the server"
        local apps
        apps=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null | grep "^$pid," || true)
        echo "  GPU memory:  ${apps:-not listed by nvidia-smi (graphics processes may not show)}"
    else
        echo "  GPU use:     NO, NVIDIA driver libraries not loaded by the server"
    fi
    echo "======================================"
}

if [ "$REPORT_ONLY" = 1 ]; then
    report_static
    exit 0
fi
report_static

# ---- Server -----------------------------------------------------------------
SERVER_PID=""

# Runs when the client ends: stop our server and repeat the key facts,
# so the report is also the last thing on screen after a long session.
on_exit() {
    local rc=$?
    [ -n "$SERVER_PID" ] && kill -- -$SERVER_PID 2>/dev/null
    echo
    echo "=== CARLA session ended: API $API, server $CARLA_ROOT (version $(cat "$CARLA_ROOT/VERSION" 2>/dev/null || echo unknown)), exit code $rc ==="
    echo "Config: $CONFIG"
}
trap on_exit EXIT
start_server() {
    case "$START_SERVER" in
        no)  echo "START_SERVER=no, expecting a server on port $CARLA_PORT"; return ;;
        yes) ;;
        *)   if port_open; then
                 echo "Server already running on port $CARLA_PORT, reusing it."
                 return
             fi ;;
    esac

    if port_open; then
        echo "Port $CARLA_PORT is already in use, cannot start a new server." >&2
        exit 1
    fi

    echo "Starting server from $CARLA_ROOT (map: ${CARLA_MAP:-server default})"
    # Own process group, so stopping it also stops the Unreal binary that CarlaUE4.sh starts
    # shellcheck disable=SC2086
    setsid "$CARLA_ROOT/CarlaUE4.sh" ${CARLA_MAP:+"$CARLA_MAP"} -carla-rpc-port="$CARLA_PORT" $CARLA_SERVER_ARGS &
    SERVER_PID=$!

    for _ in $(seq "$SERVER_TIMEOUT"); do
        port_open && return
        sleep 1
    done
    echo "Server did not open port $CARLA_PORT within ${SERVER_TIMEOUT}s." >&2
    exit 1
}

start_server

# The map argument at server start is not applied by this build, so check the
# map and load it. A reused server is never changed, only reported.
if [ -n "$CARLA_MAP" ]; then
    ensure_py_carla
    CURRENT_MAP=$(PYTHONPATH="$PY_CARLA_DIR" "$PY_INTERPRETER" -c \
        "import carla; c=carla.Client('$CARLA_HOST', $CARLA_PORT); c.set_timeout(60); print(c.get_world().get_map().name)" 2>/dev/null || true)
    if [ -n "$CURRENT_MAP" ] && [ "${CURRENT_MAP##*/}" != "${CARLA_MAP##*/}" ]; then
        if [ -n "$SERVER_PID" ]; then
            echo "Loading map ${CARLA_MAP##*/} (server started on ${CURRENT_MAP##*/})"
            PYTHONPATH="$PY_CARLA_DIR" "$PY_INTERPRETER" -c \
                "import carla; c=carla.Client('$CARLA_HOST', $CARLA_PORT); c.set_timeout(120); c.load_world('${CARLA_MAP##*/}')"
        else
            echo "WARNING: running server uses ${CURRENT_MAP##*/}, config asks for ${CARLA_MAP##*/}." >&2
        fi
    fi
fi

report_runtime

# ---- Client -----------------------------------------------------------------
case "$API" in
    python)
        ensure_py_carla
        echo "Starting Python client: $PY_SCRIPT"
        VEHICLE_ARGS=()
        [ -n "$VEHICLE" ] && VEHICLE_ARGS=(--filter "$VEHICLE")
        # shellcheck disable=SC2086
        PYTHONPATH="$PY_CARLA_DIR" "$PY_INTERPRETER" "$PY_SCRIPT" \
            --host "$CARLA_HOST" --port "$CARLA_PORT" "${VEHICLE_ARGS[@]}" $PY_ARGS "${CLIENT_ARGS[@]}"
        ;;
    cpp)
        if [ ! -x "$CPP_CLIENT_BIN" ]; then
            echo "C++ client not found or not executable: $CPP_CLIENT_BIN" >&2
            echo "Build it with: make -C $(dirname "$(dirname "$CPP_CLIENT_BIN")")" >&2
            exit 1
        fi
        echo "Starting C++ client: $CPP_CLIENT_BIN"
        # shellcheck disable=SC2086
        "$CPP_CLIENT_BIN" ${CPP_ARGS:-$CARLA_HOST $CARLA_PORT} "${CLIENT_ARGS[@]}"
        ;;
    cpp-manual)
        if [ ! -x "$CPP_MANUAL_BIN" ]; then
            echo "C++ manual control not found or not executable: $CPP_MANUAL_BIN" >&2
            echo "Build it with: make -C $(dirname "$(dirname "$CPP_MANUAL_BIN")") manual_control" >&2
            echo "(needs SDL2: sudo apt install libsdl2-dev libsdl2-ttf-dev)" >&2
            exit 1
        fi
        echo "Starting C++ manual control: $CPP_MANUAL_BIN"
        # The binary reads CARLA_HOST, CARLA_PORT, VEHICLE and CPP_MANUAL_ARGS from the config itself.
        "$CPP_MANUAL_BIN" --config "$CONFIG" "${CLIENT_ARGS[@]}"
        ;;
    cpp-gtk)
        if [ ! -x "$CPP_GTK_BIN" ]; then
            echo "C++ GTK manual control not found or not executable: $CPP_GTK_BIN" >&2
            echo "Build it with: make -C $(dirname "$(dirname "$CPP_GTK_BIN")") manual_control_gtk" \
                 "CARLA_SRC=/home/carlagx/carla-xil/carla-0.9.16" >&2
            exit 1
        fi
        if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
            echo "No display found (DISPLAY is not set): the GTK client needs a desktop session." >&2
            exit 1
        fi
        echo "Starting C++ GTK manual control: $CPP_GTK_BIN (vehicle: ${VEHICLE:-random}, map: ${CARLA_MAP##*/})"
        # The binary reads CARLA_HOST, CARLA_PORT, VEHICLE and CPP_GTK_ARGS from the config itself.
        "$CPP_GTK_BIN" --config "$CONFIG" "${CLIENT_ARGS[@]}"
        ;;
    *)
        echo "Unknown API '$API' in $CONFIG (use python, cpp, cpp-manual or cpp-gtk)" >&2
        exit 1
        ;;
esac

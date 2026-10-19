#!/usr/bin/env bash
# Compares the three real manual_control clients against a CARLA 0.9.16 server on this machine:
#   python/pygame (the original), C++/SDL2, C++/GTK3 + Cairo.
# All run the same scenario: autopilot, default RGB camera, 1280x720, asynchronous mode.
# For each client the CPU time of the whole process (all threads) is measured over MEASURE
# seconds after a warm-up, plus the peak memory (VmHWM).
#   ./run_apps.sh [measure seconds] [repetitions]       (defaults: 25, 2)
# Needs a desktop session ($DISPLAY): every client opens a window for about 40 s and takes
# the focus. The server is started offscreen if none is running, and stopped again then.
# Paths come from ../../carla.conf. Results go to stdout and results/apps.txt.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT=$(cd ../.. && pwd)
# shellcheck disable=SC1091
source "$ROOT/carla.conf"
MEASURE=${1:-25}
REPEAT=${2:-2}
WARMUP=10
TICKS=$(getconf CLK_TCK)
mkdir -p results
LOG=$(mktemp -d)

[ -n "$DISPLAY" ] || { echo "No DISPLAY: the clients need a desktop session." >&2; exit 1; }

port_open() { (exec 3<>/dev/tcp/"$CARLA_HOST"/"$CARLA_PORT") 2>/dev/null; }
SERVER_PID=""
stop_server() {
    [ -n "$SERVER_PID" ] || return 0
    kill -- -"$SERVER_PID" 2>/dev/null || true
    sleep 5
    pkill -9 -f CarlaUE4-Linux-Shipping 2>/dev/null || true
}
trap stop_server EXIT
if ! port_open; then
    setsid "$CARLA_ROOT/CarlaUE4.sh" -RenderOffScreen -nosound -carla-rpc-port="$CARLA_PORT" > "$LOG/server.log" 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 120); do port_open && break; sleep 1; done
    sleep 5
fi

cleanup_actors() {
    PYTHONPATH="$PY_CARLA_DIR" python3 - <<EOF >/dev/null 2>&1 || true
import carla
c = carla.Client('$CARLA_HOST', $CARLA_PORT); c.set_timeout(30); w = c.get_world()
for a in list(w.get_actors().filter('sensor.*')) + list(w.get_actors().filter('vehicle.*')): a.destroy()
EOF
}

# Display server and compositor draw the window on screen; their CPU belongs to the cost of a
# GUI too (a Cairo window hands its pixels to the X server, an OpenGL window uploads itself).
SYSTEM_PIDS=$(pgrep -x -d' ' 'Xorg|Xwayland|gnome-shell|kwin_x11|kwin_wayland|mutter|picom|xfwm4' || true)
system_ticks() {
    local sum=0 p t
    for p in $SYSTEM_PIDS; do
        t=$(sed 's/^.*) //' "/proc/$p/stat" 2>/dev/null | awk '{print $12 + $13}')
        sum=$((sum + ${t:-0}))
    done
    echo "$sum"
}

# writes "<tid> <name> <cpu ticks>" for every thread of process $1 to file $2
thread_snapshot() {
    local t stat
    for t in /proc/"$1"/task/*; do
        stat=$(cat "$t/stat" 2>/dev/null) || continue
        # name is in parentheses and may contain blanks; the fields after ") " start at #3
        echo "${t##*/} $(sed 's/^[0-9]* (\(.*\)) .*$/\1/' <<< "$stat" | tr ' ' '_') $(sed 's/^.*) //' <<< "$stat" | awk '{print $12 + $13}')" >> "$2"
    done
}

# prints "<cpu seconds> <VmRSS kB>" of process $1 (all threads)
sample() {
    local stat
    stat=$(sed 's/^.*) //' "/proc/$1/stat")
    # after the ") " the fields start at #3, so utime (14) is field 12 and stime (15) is field 13
    echo "$(awk '{print $12 + $13}' <<< "$stat") $(awk '/^VmRSS/ {print $2}' "/proc/$1/status")"
}

# Ends a client: SIGINT (clean quit; a background job of a non-interactive shell may ignore
# it, and Python then ignores it too), then SIGTERM, then SIGKILL.
stop_client() {
    local pid=$1 i
    for sig in INT TERM KILL; do
        kill -"$sig" "$pid" 2>/dev/null || return 0
        for i in $(seq 10); do kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; return 0; }; sleep 0.5; done
    done
}

run() {
    local name=$1; shift
    cleanup_actors
    "$@" > "$LOG/$name.log" 2>&1 &
    local pid=$!
    sleep "$WARMUP"
    if ! kill -0 "$pid" 2>/dev/null; then echo "$name: client exited early, see $LOG/$name.log"; return; fi
    local t0 t1 c0 c1 rss_before rss_after
    : > "$LOG/$name.t0"; : > "$LOG/$name.t1"
    thread_snapshot "$pid" "$LOG/$name.t0"
    local x0 x1; x0=$(system_ticks)
    read -r c0 rss_before <<< "$(sample "$pid")"
    sleep "$MEASURE"
    read -r c1 rss_after <<< "$(sample "$pid")"
    x1=$(system_ticks)
    thread_snapshot "$pid" "$LOG/$name.t1"
    local hwm
    hwm=$(awk '/^VmHWM/ {print $2}' "/proc/$pid/status")
    stop_client "$pid"
    awk -v n="$name" -v c0="$c0" -v c1="$c1" -v x0="$x0" -v x1="$x1" -v t="$TICKS" -v m="$MEASURE" -v hwm="$hwm" -v rss="$rss_after" \
        'BEGIN { c = 100 * (c1 - c0) / t / m; x = 100 * (x1 - x0) / t / m;
                 printf "%-14s client %5.1f%% + display pipeline %5.1f%% = total %5.1f%% of one core (%d s)   rss=%d MB   peak=%d MB\n", n, c, x, c + x, m, rss / 1024, hwm / 1024 }'
    # the busiest threads, CPU% of one core each (the main thread has tid == pid)
    join -j1 <(sort -k1,1 "$LOG/$name.t0") <(sort -k1,1 "$LOG/$name.t1") \
        | awk -v t="$TICKS" -v m="$MEASURE" -v pid="$pid" \
            '{ d = ($5 - $3) / t / m * 100; if (d >= 1.0) printf "%5.1f%%  %s%s\n", d, ($1 == pid ? "[main] " : ""), $2 }' \
        | sort -n -r | head -6 | sed 's/^/                 thread /'
}

{
    echo "# $(date -Is)  host: $(hostname), $(lscpu | sed -n 's/^Model name:[ \t]*//p'), $(nproc) threads"
    echo "# gpu: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo unknown); session ${XDG_SESSION_TYPE:-?} on ${DISPLAY}"
    echo "# server: CARLA $(cat "$CARLA_ROOT/VERSION"), offscreen; scenario: autopilot, vehicle ${VEHICLE:-random}, RGB camera 1280x720, async"
    echo "# ${WARMUP} s warm-up, then ${MEASURE} s measured; client = all threads of the client process;"
    echo "# display pipeline = X server + compositor ($(for p in $SYSTEM_PIDS; do ps -o comm= -p "$p"; done | tr '\n' ' ')), idle ~2%"
    for i in $(seq "$REPEAT"); do
        echo "## run $i"
        run python-pygame env PYTHONPATH="$PY_CARLA_DIR" python3 "$PY_SCRIPT" --host "$CARLA_HOST" --port "$CARLA_PORT" \
            --filter "${VEHICLE:-vehicle.*}" -a --res 1280x720
        run cpp-sdl2 "$CPP_MANUAL_BIN" --config "$ROOT/carla.conf" -a --res 1280x720
        run cpp-gtk3 "$CPP_GTK_BIN" --config "$ROOT/carla.conf" -a --res 1280x720
    done
    cleanup_actors
} 2>&1 | tee results/apps.txt

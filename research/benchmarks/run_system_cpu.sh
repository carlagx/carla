#!/usr/bin/env bash
# Measures the CPU cost of the whole drawing pipeline, not just the client process:
# the client plus the X server (Xorg/Xwayland) and the compositor (gnome-shell/mutter/kwin),
# which receive the pixels of a window and put them on the screen. For a GTK/Cairo window the
# client only draws into memory and sends it to the X server, so the client's own CPU time
# (what bench_* print) understates the cost; an SDL/OpenGL window uploads in the client.
#   ./run_system_cpu.sh [seconds]       (default 6)
# Opens windows on $DISPLAY. Results: stdout and results/system_cpu.txt.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
SECONDS_PER_RUN=${1:-6}
OUT=${OUT:-/tmp/gui-bench-build}
mkdir -p "$OUT" results
TICKS=$(getconf CLK_TCK)

build() {  # name source flags...
    local name=$1 src=$2; shift 2
    g++ -std=c++17 -O2 -o "$OUT/$name" "$src" "$@"
}
for res in "1280 720" "1920 1080"; do
    set -- $res
    build "bench_sdl_$1x$2" bench_sdl.cpp -DBENCH_W="$1" -DBENCH_H="$2" $(pkg-config --cflags --libs sdl2 SDL2_ttf)
    build "bench_gtk_$1x$2" bench_gtk.cpp -DBENCH_W="$1" -DBENCH_H="$2" $(pkg-config --cflags --libs gtk+-3.0 pangocairo)
done

clean() {
    env -u GTK_PATH -u GTK_EXE_PREFIX -u GIO_MODULE_DIR -u GDK_PIXBUF_MODULE_FILE \
        -u GDK_PIXBUF_MODULEDIR -u GSETTINGS_SCHEMA_DIR -u LOCPATH -u GTK_IM_MODULE_FILE "$@"
}

# display server and compositor processes that draw our window on screen
SYSTEM_PIDS=$(pgrep -x -d' ' 'Xorg|Xwayland|gnome-shell|kwin_x11|kwin_wayland|mutter|picom|xfwm4' || true)
ticks_of() { awk '{print $12 + $13}' < <(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null) 2>/dev/null || echo 0; }
system_ticks() { local sum=0 p t; for p in $SYSTEM_PIDS; do t=$(ticks_of "$p"); sum=$((sum + ${t:-0})); done; echo "$sum"; }

# run <label> <command...>: client output line plus the CPU of the display pipeline during the run
run() {
    local label=$1; shift
    "$@" > "$OUT/last.out" 2>&1 &
    local pid=$!
    sleep 2.5                                  # warm-up and window creation
    local s0 w0; s0=$(system_ticks); w0=$(date +%s.%N)
    sleep $((SECONDS_PER_RUN - 3))
    local s1 w1; s1=$(system_ticks); w1=$(date +%s.%N)
    wait "$pid" 2>/dev/null
    awk -v l="$label" -v s0="$s0" -v s1="$s1" -v w0="$w0" -v w1="$w1" -v t="$TICKS" -v out="$(cat "$OUT/last.out")" \
        'BEGIN { split(out, a, "cpu="); split(a[2], b, "%"); c = b[1];
                 printf "%-34s client %5.1f%%   X server+compositor %5.1f%%   total %5.1f%%\n", l, c, 100*(s1-s0)/t/(w1-w0), c + 100*(s1-s0)/t/(w1-w0) }'
}

{
    echo "# $(date -Is)  $(. /etc/os-release && echo "$PRETTY_NAME"), session ${XDG_SESSION_TYPE:-?}, DISPLAY=${DISPLAY:-unset}"
    echo "# display pipeline processes sampled: $(for p in $SYSTEM_PIDS; do ps -o comm= -p "$p"; done | sort | uniq -c | tr '\n' ' ')"
    echo "# ${SECONDS_PER_RUN} s per run at 60 fps; CPU in % of one core; idle baseline first (no benchmark running)"
    # idle baseline of the display pipeline
    s0=$(system_ticks); sleep 4; s1=$(system_ticks)
    echo "idle display pipeline (4 s)        X server+compositor $(awk -v a="$s0" -v b="$s1" -v t="$TICKS" 'BEGIN {printf "%.1f", 100*(b-a)/t/4}')%"
    for res in 1280x720 1920x1080; do
        echo "## $res"
        run "sdl accel (OpenGL) +cache" "$OUT/bench_sdl_$res" accel "$SECONDS_PER_RUN" --cache
        run "sdl software"              "$OUT/bench_sdl_$res" software "$SECONDS_PER_RUN"
        run "gtk window (Cairo) +cache" clean "$OUT/bench_gtk_$res" window "$SECONDS_PER_RUN" --cache
    done
} 2>&1 | tee results/system_cpu.txt

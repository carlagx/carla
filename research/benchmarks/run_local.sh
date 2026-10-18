#!/usr/bin/env bash
# Builds both benchmarks and runs every variant REPEAT times on this machine.
#   ./run_local.sh [seconds per run] [repetitions]      (defaults: 6, 2)
# Window variants open a 1280x720 window on $DISPLAY for about 7 s each (they take the focus).
# Results go to stdout and results/local.txt.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
SECONDS_PER_RUN=${1:-6}
REPEAT=${2:-2}
OUT=${OUT:-/tmp/gui-bench-build}
mkdir -p "$OUT" results

g++ -std=c++17 -O2 -Wall -Wextra -o "$OUT/bench_sdl" bench_sdl.cpp $(pkg-config --cflags --libs sdl2 SDL2_ttf)
g++ -std=c++17 -O2 -Wall -Wextra -o "$OUT/bench_gtk" bench_gtk.cpp $(pkg-config --cflags --libs gtk+-3.0 pangocairo)

# A terminal started from the VS Code snap exports GTK_PATH & co. into /snap/code, which
# breaks GTK (see ../README.md). Run the benchmarks with a clean GTK environment.
clean() {
    env -u GTK_PATH -u GTK_EXE_PREFIX -u GIO_MODULE_DIR -u GDK_PIXBUF_MODULE_FILE \
        -u GDK_PIXBUF_MODULEDIR -u GSETTINGS_SCHEMA_DIR -u LOCPATH -u GTK_IM_MODULE_FILE "$@"
}

{
    echo "# $(date -Is)  host: $(hostname)"
    echo "# cpu:     $(lscpu | sed -n 's/^Model name:[ \t]*//p')"
    echo "# gpu:     $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo unknown)"
    echo "# os:      $(. /etc/os-release && echo "$PRETTY_NAME"), kernel $(uname -r), session ${XDG_SESSION_TYPE:-?}, DISPLAY=${DISPLAY:-unset}"
    echo "# sdl2:    $(pkg-config --modversion sdl2), SDL2_ttf $(pkg-config --modversion SDL2_ttf)"
    echo "# gtk:     $(pkg-config --modversion gtk+-3.0), cairo $(pkg-config --modversion cairo), pango $(pkg-config --modversion pango)"
    echo "# scene:   1280x720 camera picture + HUD (28 text lines, 9 of them changing every frame, 3 bars, graph), ${SECONDS_PER_RUN} s per run at 60 fps, ${REPEAT} runs"
    for i in $(seq "$REPEAT"); do
        echo "## run $i"
        SDL_VIDEODRIVER=dummy "$OUT/bench_sdl" offscreen "$SECONDS_PER_RUN"
        SDL_VIDEODRIVER=dummy "$OUT/bench_sdl" offscreen "$SECONDS_PER_RUN" --cache
        clean "$OUT/bench_gtk" offscreen "$SECONDS_PER_RUN"
        clean "$OUT/bench_gtk" offscreen "$SECONDS_PER_RUN" --cache
        if [ -n "$DISPLAY" ]; then
            "$OUT/bench_sdl" accel "$SECONDS_PER_RUN"
            "$OUT/bench_sdl" accel "$SECONDS_PER_RUN" --cache
            "$OUT/bench_sdl" software "$SECONDS_PER_RUN"
            clean "$OUT/bench_gtk" window "$SECONDS_PER_RUN"
            clean "$OUT/bench_gtk" window "$SECONDS_PER_RUN" --cache
        fi
    done
} 2>&1 | tee results/local.txt

#!/usr/bin/env bash
# Runs INSIDE a container (see run_distros.sh). Installs the distribution's own SDL2 and GTK3
# packages, builds both benchmarks with them and checks that they work under X11 (Xvfb) and
# Wayland (weston headless). Prints a report; never aborts on a failing step.
# usage: distro_test.sh   (benchmark sources are mounted read-only at /src)

step() { printf '\n== %s\n' "$*"; }
. /etc/os-release
FAMILY=$ID
case "$ID $ID_LIKE" in
    *debian*|*ubuntu*) FAMILY=debian ;;
    *fedora*|*rhel*)   FAMILY=fedora ;;
    *arch*)            FAMILY=arch ;;
    *suse*)            FAMILY=suse ;;
esac
echo "distro: $PRETTY_NAME  (family $FAMILY)   glibc: $(ldd --version 2>&1 | head -1 | sed 's/.* //')   arch: $(uname -m)"

step "install packages"
case $FAMILY in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y -qq --no-install-recommends g++ pkg-config fontconfig fonts-dejavu-core \
            libsdl2-dev libsdl2-ttf-dev libgtk-3-dev xvfb xauth weston \
            libgl1-mesa-dri libegl1 libglx-mesa0 > /tmp/install.log 2>&1 \
            || apt-get install -y -qq --no-install-recommends g++ pkg-config fontconfig fonts-dejavu-core \
                libsdl2-dev libsdl2-ttf-dev libgtk-3-dev xvfb xauth weston libgl1-mesa-dri libegl1-mesa > /tmp/install.log 2>&1
        ;;
    fedora)
        dnf install -y -q gcc-c++ pkgconf-pkg-config fontconfig dejavu-sans-mono-fonts SDL2-devel SDL2_ttf-devel \
            gtk3-devel xorg-x11-server-Xvfb xauth weston mesa-dri-drivers mesa-libEGL > /tmp/install.log 2>&1
        ;;
    arch)
        pacman -Sy --noconfirm --needed gcc pkgconf fontconfig ttf-dejavu sdl2 sdl2_ttf gtk3 \
            xorg-server-xvfb xorg-xauth weston mesa > /tmp/install.log 2>&1
        ;;
    suse)
        zypper -n --gpg-auto-import-keys in -y gcc-c++ pkg-config fontconfig dejavu-fonts SDL2-devel SDL2_ttf-devel \
            gtk3-devel xorg-x11-server-Xvfb xauth weston Mesa-dri Mesa-libEGL1 gawk > /tmp/install.log 2>&1
        ;;
    *) echo "unsupported family"; exit 1 ;;
esac
echo "install exit: $?   (log tail: $(tail -1 /tmp/install.log | cut -c1-100))"

step "versions"
for m in sdl2 SDL2_ttf gtk+-3.0 cairo pango; do printf '%-10s %s\n' "$m" "$(pkg-config --modversion $m 2>&1 | head -1)"; done
echo "gcc        $(g++ --version | head -1)"
SDL_LIB=$(ldconfig -p | grep 'libSDL2-2.0.so.0' | head -1 | sed 's/.*=> //')
case $FAMILY in
    debian) OWNER=$(dpkg -S "$(readlink -f "$SDL_LIB")" 2>/dev/null | head -1 | cut -d: -f1) ;;
    arch)   OWNER=$(pacman -Qo "$(readlink -f "$SDL_LIB")" 2>/dev/null | sed 's/.*is owned by //') ;;
    *)      OWNER=$(rpm -qf "$(readlink -f "$SDL_LIB")" 2>/dev/null) ;;
esac
echo "SDL2 runtime library: $(readlink -f "$SDL_LIB"), provided by: ${OWNER:-?}; links SDL3: $(ldd "$SDL_LIB" 2>/dev/null | grep -c 'libSDL3')"
FONT=$(fc-match -f '%{file}' monospace 2>/dev/null)
echo "fontconfig monospace: $FONT"

step "newer toolkits in the distribution (package query only)"
case $FAMILY in
    debian) for p in libsdl3-dev libgtk-4-dev libqt6widgets6 qt6-base-dev; do printf '%-18s %s\n' $p "$(apt-cache policy $p 2>/dev/null | awk '/Candidate/ {print $2}')"; done ;;
    fedora) for p in SDL3-devel gtk4-devel qt6-qtbase-devel; do printf '%-18s %s\n' $p "$(dnf -q info $p 2>/dev/null | awk '/^Version/ {print $3; exit}')"; done ;;
    arch)   for p in sdl3 gtk4 qt6-base; do printf '%-18s %s\n' $p "$(pacman -Si $p 2>/dev/null | awk '/^Version/ {print $3}')"; done ;;
    suse)   for p in SDL3-devel gtk4-devel qt6-base-devel; do printf '%-18s %s\n' $p "$(zypper -n info $p 2>/dev/null | awk '/^Version/ {print $3}')"; done ;;
esac

step "build"
mkdir -p /tmp/b && cd /tmp/b || exit 1
g++ -std=c++17 -O2 -Wall -Wextra -I/src -o bench_sdl /src/bench_sdl.cpp $(pkg-config --cflags --libs sdl2 SDL2_ttf) > sdl.build 2>&1
echo "bench_sdl build exit: $?   warnings: $(grep -c warning sdl.build)"
g++ -std=c++17 -O2 -Wall -Wextra -I/src -o bench_gtk /src/bench_gtk.cpp $(pkg-config --cflags --libs gtk+-3.0 pangocairo) > gtk.build 2>&1
echo "bench_gtk build exit: $?   warnings: $(grep -c warning gtk.build)"
head -3 sdl.build gtk.build | grep -i error | head -3

step "offscreen (no display)"
SDL_VIDEODRIVER=dummy timeout 30 ./bench_sdl offscreen 2 --font "$FONT" 2>&1 | tail -2
timeout 30 ./bench_gtk offscreen 2 2>&1 | tail -2

step "X11 (Xvfb)"
Xvfb :9 -screen 0 1280x720x24 -nolisten tcp > xvfb.log 2>&1 &
sleep 2
export DISPLAY=:9
for v in "accel" "software"; do
    LIBGL_ALWAYS_SOFTWARE=1 timeout 30 ./bench_sdl $v 3 --font "$FONT" 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] /"
done
GDK_BACKEND=x11 timeout 30 ./bench_gtk window 3 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] /"
kill %1 2>/dev/null; unset DISPLAY

step "Wayland (weston headless)"
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
(weston --backend=headless --width=1280 --height=720 --socket=wl-test --idle-time=0 --use-pixman > weston.log 2>&1 \
  || weston --backend=headless-backend.so --width=1280 --height=720 --socket=wl-test --idle-time=0 > weston.log 2>&1) &
for _ in $(seq 20); do [ -S $XDG_RUNTIME_DIR/wl-test ] && break; sleep 0.5; done
if [ -S $XDG_RUNTIME_DIR/wl-test ]; then
    export WAYLAND_DISPLAY=wl-test
    GDK_BACKEND=wayland timeout 30 ./bench_gtk window 3 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] gtk wayland: /"
    SDL_VIDEODRIVER=wayland LIBGL_ALWAYS_SOFTWARE=1 timeout 30 ./bench_sdl software 3 --font "$FONT" 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] sdl wayland software: /"
    SDL_VIDEODRIVER=wayland LIBGL_ALWAYS_SOFTWARE=1 timeout 30 ./bench_sdl accel 3 --font "$FONT" 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] sdl wayland accel: /"
    # no SDL_VIDEODRIVER and no X display: which driver does SDL pick, does it work?
    env -u DISPLAY -u SDL_VIDEODRIVER LIBGL_ALWAYS_SOFTWARE=1 timeout 30 ./bench_sdl software 3 --font "$FONT" 2>&1 | tail -1 | cut -c1-150 | sed "s/^/[exit ${PIPESTATUS[0]}] sdl auto (wayland only): /"
else
    echo "weston headless did not start: $(tail -2 weston.log | tr '\n' ' ' | cut -c1-200)"
fi
pkill weston 2>/dev/null

step "prebuilt CARLA clients (built on Ubuntu 22.04, mounted at /apps): do they start here?"
if [ -d /apps ]; then
    for b in manual_control manual_control_gtk; do
        missing=$(ldd /apps/$b 2>&1 | grep -E "not found|version .* not found" | sed 's/^[ \t]*//' | cut -c1-110)
        out=$(/apps/$b --help 2>&1 | head -1 | cut -c1-100)
        printf '%-20s %s\n' "$b" "${missing:+MISSING/INCOMPATIBLE: $(echo "$missing" | tr '\n' ';')}${missing:-starts: $out}"
    done
else
    echo "(not mounted)"
fi
echo; echo "done"

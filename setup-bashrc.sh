#!/usr/bin/env bash
# Adds CARLA helper functions to ~/.bashrc so they work from any directory.
# Safe to run repeatedly: the managed block is replaced, not duplicated.
#
# Usage:
#   ./setup-bashrc.sh              # install or update
#   ./setup-bashrc.sh --remove     # remove the block
#   ./setup-bashrc.sh --bashrc F   # use another file instead of ~/.bashrc

set -e

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
REMOVE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --remove) REMOVE=1; shift ;;
        --bashrc) BASHRC="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

BEGIN="# >>> carla helpers >>>"
END="# <<< carla helpers <<<"

touch "$BASHRC"
cp "$BASHRC" "$BASHRC.bak-carla"

# Drop an existing block
sed -i "/^$BEGIN\$/,/^$END\$/d" "$BASHRC"

if [ "$REMOVE" -eq 1 ]; then
    echo "Removed CARLA block from $BASHRC (backup: $BASHRC.bak-carla)"
    exit 0
fi

cat >> "$BASHRC" <<EOF
$BEGIN
export CARLA_REPO="$REPO"
export UE4_ROOT="\${UE4_ROOT:-\$HOME/UnrealEngine_4.26}"

# Newest packaged server in Dist/
carla_server_dir() {
    ls -dt "\$CARLA_REPO"/Dist/CARLA_Shipping_*/LinuxNoEditor 2>/dev/null | head -n1
}

# Start the packaged server, e.g. carla_server -RenderOffScreen -nosound
carla_server() {
    local d; d="\$(carla_server_dir)"
    [ -n "\$d" ] || { echo "No server in \$CARLA_REPO/Dist" >&2; return 1; }
    "\$d/CarlaUE4.sh" "\$@"
}

# Open the project in the Unreal Editor
carla_editor() {
    "\$UE4_ROOT/Engine/Binaries/Linux/UE4Editor" "\$CARLA_REPO/Unreal/CarlaUE4/CarlaUE4.uproject" "\$@"
}

# Server + client via carla.conf, e.g. carla_start --api cpp
carla_start() { "\$CARLA_REPO/carla-start.sh" "\$@"; }

# Build the C++ examples, e.g. carla_cpp manual_control
carla_cpp() { make -C "\$CARLA_REPO/Examples/CppClient" "\$@"; }

# True if the server port answers
carla_port() { (exec 3<>/dev/tcp/\${1:-127.0.0.1}/\${2:-2000}) 2>/dev/null && echo "Port \${2:-2000} OFFEN" || echo "Port \${2:-2000} ZU"; }
$END
EOF

echo "Installed CARLA block in $BASHRC (backup: $BASHRC.bak-carla)"
echo "Activate now with: source $BASHRC"
echo "Commands: carla_server  carla_editor  carla_start  carla_cpp  carla_port"

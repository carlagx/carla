#!/usr/bin/env bash
# Runs distro_test.sh in one container per Linux distribution (needs docker and network).
#   ./run_distros.sh [image ...]      default: the list below
# Also tests the prebuilt clients from $APPS (default Examples/CppClient/bin-carla-0.9.16).
# Results: results/distros/<image>.txt
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
IMAGES=("$@")
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=(ubuntu:20.04 ubuntu:22.04 ubuntu:24.04 ubuntu:26.04 debian:12 debian:13 fedora:latest archlinux:latest opensuse/tumbleweed)
APPS=${APPS:-$(cd ../../Examples/CppClient/bin-carla-0.9.16 2>/dev/null && pwd)}
mkdir -p results/distros
for image in "${IMAGES[@]}"; do
    out="results/distros/${image//[:\/]/_}.txt"
    echo ">> $image -> $out"
    docker run --rm -v "$PWD":/src:ro ${APPS:+-v "$APPS":/apps:ro} "$image" bash /src/distro_test.sh > "$out" 2>&1
    echo "   finished with exit $?"
done

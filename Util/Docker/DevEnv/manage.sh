#!/bin/bash
# Manage the CARLA dev container.  ./manage.sh help
set -eo pipefail
cd "$(dirname "$0")"
export HOST_UID="${HOST_UID:-$(id -u)}" HOST_GID="${HOST_GID:-$(id -g)}"
DC="docker compose"
[ -n "$GPU" ] && DC="docker compose -f docker-compose.yml -f docker-compose.gpu.yml"
IMAGE=carla-dev:latest

case "$1" in
  creds)    # create credentials file with a random password
    f=credentials/credentials.env
    [ -e "$f" ] && { echo "$f exists"; exit 1; }
    cp credentials/credentials.env.example "$f"; chmod 600 "$f"
    pw="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
    sed -i "s/^CODE_SERVER_PASSWORD=.*/CODE_SERVER_PASSWORD=$pw/" "$f"
    echo "created $f (password: $pw). Fill in the git/GitHub values." ;;
  build)    $DC build ;;                                  # needs internet
  up)       mkdir -p artifacts offline-cache; $DC up -d; echo "VS Code: http://localhost:${CODE_PORT:-8080}   Artifacts: http://localhost:${ARTIFACT_PORT:-8081}" ;;
  down)     $DC down ;;
  logs)     $DC logs -f ;;
  shell)    $DC exec carla-dev bash ;;
  build-carla) shift; $DC exec carla-dev carla-build "$@" ;;   # e.g. build-carla all | maps Town01,Town02
  save)     # export image for a machine without internet
    out="${2:-carla-dev-image.tar.zst}"; docker save "$IMAGE" | zstd -T0 -3 -o "$out"; echo "wrote $out" ;;
  load)     zstd -dc "${2:?usage: load FILE}" | docker load ;;
  pull-artifacts) # download the latest build to a local folder (needs credentials file for password)
    dest="${2:-./download}"; mkdir -p "$dest"
    pw="$(grep -E '^(ARTIFACT_PASSWORD|CODE_SERVER_PASSWORD)=' credentials/credentials.env | sed 's/^[^=]*=//' | tail -1)"
    curl -fL -C - -u "carla:$pw" -o "$dest/latest.zip" "http://localhost:${ARTIFACT_PORT:-8081}/latest/?zip=1" && echo "$dest/latest.zip" ;;
  *) sed -n '2,2p;/^  [a-z-]*)/s/).*#\?/ /p' "$0" | sed 's/^  /  /' ; echo "commands: creds build up down logs shell build-carla save load pull-artifacts"; echo "GPU=1 ./manage.sh up   adds the NVIDIA GPU" ;;
esac

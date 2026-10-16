#!/usr/bin/env bash
# Shortcut: starts server + Python manual_control client with settings from carla.conf.
exec "$(dirname "${BASH_SOURCE[0]}")/carla-start.sh" --api python -- "$@"

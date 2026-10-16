#! /bin/bash

# Offline cache for the build scripts. Sourced by Environment.sh and Plugins.sh.
#
# Wraps wget, curl and 'git clone' so that downloads can be recorded once on a
# machine with internet and replayed on a machine without it:
#
#   CARLA_OFFLINE_CACHE=<dir>                  replay from <dir>, never touch the network
#   CARLA_OFFLINE_CACHE=<dir> CARLA_OFFLINE_RECORD=1   download and store a copy in <dir>
#
# Without CARLA_OFFLINE_CACHE nothing changes.

if [ -n "${CARLA_OFFLINE_CACHE}" ]; then

  mkdir -p "${CARLA_OFFLINE_CACHE}"
  CARLA_OFFLINE_CACHE="$(cd "${CARLA_OFFLINE_CACHE}" && pwd)"
  export CARLA_OFFLINE_CACHE

  function _offline_key {
    echo -n "$*" | sha1sum | cut -c1-16
  }

  # _offline_url <args...>: first http(s)/git URL in the arguments
  function _offline_url {
    local a
    for a in "$@"; do
      case "$a" in
        http://*|https://*|git://*) echo "$a"; return ;;
      esac
    done
  }

  # Shared by wget and curl: <tool> <out_file> <url>
  function _offline_fetch {
    local tool="$1" out="$2" url="$3"
    local entry="${CARLA_OFFLINE_CACHE}/files/$(_offline_key "${url}")-$(basename "${url%%\?*}")"
    mkdir -p "${CARLA_OFFLINE_CACHE}/files"
    if [ -n "${CARLA_OFFLINE_RECORD}" ]; then
      shift 3
      command "${tool}" "$@" || return $?
      cp -p "${out}" "${entry}"
    elif [ -f "${entry}" ]; then
      cp -p "${entry}" "${out}"
    else
      echo "offline cache: miss for ${url}" >&2
      return 1
    fi
  }

  function wget {
    local url out="" prev="" a
    url="$(_offline_url "$@")"
    for a in "$@"; do
      [ "${prev}" = "-O" ] && out="${a}"
      prev="${a}"
    done
    [ -z "${out}" ] && out="$(basename "${url%%\?*}")"
    [ -z "${url}" ] && { command wget "$@"; return $?; }
    _offline_fetch wget "${out}" "${url}" "$@"
  }

  function curl {
    local url out="" prev="" a
    url="$(_offline_url "$@")"
    for a in "$@"; do
      [ "${prev}" = "-o" ] && out="${a}"
      prev="${a}"
    done
    [ -z "${url}" -o -z "${out}" ] && { command curl "$@"; return $?; }
    _offline_fetch curl "${out}" "${url}" "$@"
  }

  # Only 'git clone' is intercepted. The clone is stored as a tarball of the
  # working directory (including .git and submodules).
  function git {
    if [ "$1" != "clone" ]; then
      command git "$@"
      return $?
    fi
    local url dest rest=() a
    url="$(_offline_url "$@")"
    [ -z "${url}" ] && { command git "$@"; return $?; }
    for a in "${@:2}"; do
      [ "${a}" = "${url}" ] && continue
      rest+=("${a}")
    done
    # destination is a trailing positional argument that is not an option value
    dest="$(basename "${url%.git}")"
    local n=${#rest[@]}
    if [ $n -gt 0 ] && [[ "${rest[$((n-1))]}" != -* ]]; then
      case "${rest[$((n-2))]:-}" in
        -b|--branch|--depth) ;;
        *) dest="${rest[$((n-1))]}" ;;
      esac
    fi
    local entry="${CARLA_OFFLINE_CACHE}/git/$(_offline_key "$*").tar"
    mkdir -p "${CARLA_OFFLINE_CACHE}/git"
    if [ -n "${CARLA_OFFLINE_RECORD}" ]; then
      command git "$@" || return $?
      tar -cf "${entry}" -C "$(dirname "${dest}")" "$(basename "${dest}")"
    elif [ -f "${entry}" ]; then
      mkdir -p "$(dirname "${dest}")"
      tar -xf "${entry}" -C "$(dirname "${dest}")"
    else
      echo "offline cache: miss for git clone ${url}" >&2
      return 1
    fi
  }

fi

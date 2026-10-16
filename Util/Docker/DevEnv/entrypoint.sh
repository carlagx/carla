#!/bin/bash
# Container entrypoint: reads credentials from files, configures git/ssh/proxy/CA
# and starts web VS Code + artifact server ("serve") or runs the given command.
#
# Credential files are looked up in this order:
#   $CARLA_CREDENTIALS_FILE, /run/credentials/credentials.env, /run/secrets/credentials.env
# Format: KEY=VALUE per line (no shell evaluation). KEY_FILE=<path> reads the value from a file.
set -eo pipefail

log() { echo "[carla-dev] $*"; }

# -- 1. Load credentials file (parsed, never sourced) --------------------------
CRED_FILE=""
for f in "${CARLA_CREDENTIALS_FILE:-}" /run/credentials/credentials.env /run/secrets/credentials.env; do
  [ -n "$f" ] && [ -r "$f" ] && { CRED_FILE="$f"; break; }
done

if [ -n "$CRED_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { log "ignoring malformed line in $CRED_FILE"; continue; }
    [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]] && val="${BASH_REMATCH[1]}"
    export "$key=$val"
  done < "$CRED_FILE"
  log "credentials loaded from $CRED_FILE"
else
  log "no credentials file found (continuing without)"
fi

# KEY_FILE=<path> -> KEY=<content of path>
for var in $(compgen -e | grep -E '_FILE$' || true); do
  base="${var%_FILE}"; path="${!var}"
  case "$base" in CARLA_CREDENTIALS|SSH_KEY|SSH_KNOWN_HOSTS|CA_CERT) continue ;; esac
  if [ -z "${!base:-}" ] && [ -r "$path" ]; then export "$base=$(cat "$path")"; fi
done

# -- 2. Git -------------------------------------------------------------------
[ -n "${GIT_USER_NAME:-}" ]  && git config --global user.name  "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "$GIT_USER_EMAIL"
git config --global --add safe.directory '*'

umask 077
: > "$HOME/.git-credentials"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "https://${GITHUB_USER:-x-access-token}:${GITHUB_TOKEN}@github.com" >> "$HOME/.git-credentials"
fi
# GIT_CREDENTIAL_<name>=https://user:token@host  (any number of extra hosts)
for var in $(compgen -e | grep -E '^GIT_CREDENTIAL_' || true); do echo "${!var}" >> "$HOME/.git-credentials"; done
git config --global credential.helper "store --file=$HOME/.git-credentials"

# -- 3. SSH -------------------------------------------------------------------
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [ -n "${SSH_KEY_FILE:-}" ] && [ -r "$SSH_KEY_FILE" ]; then
  cp "$SSH_KEY_FILE" "$HOME/.ssh/id_carla"; chmod 600 "$HOME/.ssh/id_carla"
  printf 'Host *\n  IdentityFile ~/.ssh/id_carla\n  StrictHostKeyChecking accept-new\n' > "$HOME/.ssh/config"
fi
[ -n "${SSH_KNOWN_HOSTS_FILE:-}" ] && [ -r "$SSH_KNOWN_HOSTS_FILE" ] && cp "$SSH_KNOWN_HOSTS_FILE" "$HOME/.ssh/known_hosts"

# -- 4. Proxy and custom CA (no root needed: build a private bundle) ----------
for p in HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  [ -n "${!p:-}" ] && export "${p,,}=${!p}"
done
if [ -n "${CA_CERT_FILE:-}" ] && [ -r "$CA_CERT_FILE" ]; then
  mkdir -p "$HOME/.certs"
  cat /etc/ssl/certs/ca-certificates.crt "$CA_CERT_FILE" > "$HOME/.certs/ca-bundle.crt"
  export SSL_CERT_FILE="$HOME/.certs/ca-bundle.crt" REQUESTS_CA_BUNDLE="$HOME/.certs/ca-bundle.crt" \
         CURL_CA_BUNDLE="$HOME/.certs/ca-bundle.crt" GIT_SSL_CAINFO="$HOME/.certs/ca-bundle.crt"
fi

# -- 5. Offline mode ----------------------------------------------------------
if [ "${OFFLINE:-0}" = "1" ]; then
  export PIP_NO_INDEX=1 PIP_FIND_LINKS=/opt/wheelhouse
  export CARLA_OFFLINE_CACHE="${CARLA_OFFLINE_CACHE:-/opt/offline-cache}"
  log "offline mode: pip from /opt/wheelhouse, downloads from $CARLA_OFFLINE_CACHE"
fi
[ -n "${PIP_INDEX_URL:-}" ] && export PIP_INDEX_URL

# -- 6. Passwords -------------------------------------------------------------
if [ -z "${CODE_SERVER_PASSWORD:-}" ]; then
  CODE_SERVER_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
  log "no CODE_SERVER_PASSWORD set, generated: $CODE_SERVER_PASSWORD"
fi
export ARTIFACT_PASSWORD="${ARTIFACT_PASSWORD:-$CODE_SERVER_PASSWORD}"

# -- 7. Workspace -------------------------------------------------------------
mkdir -p "$HOME/.local/share/code-server/User" "$HOME/.config/code-server"
[ -f "$HOME/.local/share/code-server/User/settings.json" ] || cp /opt/code-server-settings.json "$HOME/.local/share/code-server/User/settings.json"
if [ ! -f /workspace/carla/Makefile ] && [ -n "${CARLA_REPO_URL:-}" ]; then
  log "cloning $CARLA_REPO_URL"
  git clone ${CARLA_REPO_BRANCH:+-b "$CARLA_REPO_BRANCH"} "$CARLA_REPO_URL" /workspace/carla
fi
[ -f /workspace/carla/Makefile ] || log "WARNING: /workspace/carla is empty (mount the CARLA sources or set CARLA_REPO_URL)"
[ -x "$UE4_ROOT/Engine/Build/BatchFiles/RunUAT.sh" ] || log "WARNING: no Unreal Engine in $UE4_ROOT (mount it or run carla-fetch-engine)"

# -- 8. Run -------------------------------------------------------------------
if [ "${1:-serve}" = "serve" ]; then
  mkdir -p "$ARTIFACT_DIR"
  artifact-server &
  log "web VS Code on :8080, artifacts on :8081"
  PASSWORD="$CODE_SERVER_PASSWORD" exec code-server --bind-addr 0.0.0.0:8080 --auth password \
      --disable-telemetry --disable-update-check /workspace/carla
fi
exec "$@"

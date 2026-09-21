#!/usr/bin/env bash
# Server backend: Docker Compose on macOS and Linux, same layout as the reference box:
#   ~/cliproxyapi/{docker-compose.yml,config.yaml,auths/,logs/,plugins/,ngrok/}

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_dc() { docker compose -f "$CPA_COMPOSE_FILE" "$@"; }
_bin="/CLIProxyAPI/CLIProxyAPI"

_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    if [ "$CPA_OS" = darwin ]; then
      die "docker not found — install Docker Desktop (https://docs.docker.com/desktop/setup/install/mac-install/) or OrbStack, then re-run"
    fi
    die "docker not found — install it: curl -fsSL https://get.docker.com | sh"
  fi
  docker info >/dev/null 2>&1 || die "docker daemon not running — start Docker Desktop / dockerd and re-run"
  docker compose version >/dev/null 2>&1 || die "docker compose plugin missing"
}

# On macOS an older Homebrew install may be present. Adopt its config + OAuth files into
# the docker layout, then stop the brew service so the port is free. Nothing is deleted.
_adopt_brew_install() {
  [ "$CPA_OS" = darwin ] || return 0
  local brew_prefix brew
  if [ -x /opt/homebrew/bin/brew ]; then brew_prefix=/opt/homebrew; else brew_prefix=/usr/local; fi
  brew="$brew_prefix/bin/brew"
  [ -x "$brew" ] || return 0
  "$brew" list --formula cliproxyapi >/dev/null 2>&1 || return 0

  log "found Homebrew cliproxyapi — migrating to Docker"
  local brew_conf="$brew_prefix/etc/cliproxyapi.conf" brew_auth="$HOME/.cli-proxy-api"
  if [ -f "$brew_conf" ] && [ ! -f "$CPA_CONFIG_FILE" ]; then
    local tmp; tmp="$(mktemp)"
    # inside the container auths live at /root/.cli-proxy-api and the API binds all interfaces
    sed -E -e "s|^auth-dir:.*|auth-dir: \"$CPA_CONTAINER_AUTH_DIR\"|" -e 's|^host:.*|host: ""|' "$brew_conf" >"$tmp"
    write_if_changed "$CPA_CONFIG_FILE" "$tmp"
    rm -f "$tmp"
  fi
  if [ -d "$brew_auth" ]; then
    local n=0 f
    for f in "$brew_auth"/*.json; do
      [ -f "$f" ] || continue
      if [ ! -e "$CPA_AUTH_DIR/$(basename "$f")" ]; then
        [ "${CPA_DRY_RUN:-0}" = 1 ] || cp -p "$f" "$CPA_AUTH_DIR/"
        n=$((n+1))
      fi
    done
    [ "$n" -gt 0 ] && info "copied $n OAuth credential file(s) from $brew_auth"
  fi
  if "$brew" services list 2>/dev/null | grep -qE '^cliproxyapi[[:space:]]+started'; then
    log "stopping brew service (port $CPA_PORT is needed by the container)"
    [ "${CPA_DRY_RUN:-0}" = 1 ] || "$brew" services stop cliproxyapi >/dev/null
  fi
  info "brew formula left installed; remove with:  brew uninstall cliproxyapi"
}

server_install() {
  _require_docker
  mkdir -p "$CPA_RUNTIME_DIR"/{auths,logs,plugins,ngrok}
  _adopt_brew_install
  local tmp; tmp="$(mktemp)"
  cp "$CPA_HOME/config/docker-compose.yml" "$tmp"
  write_if_changed "$CPA_COMPOSE_FILE" "$tmp" 644
  rm -f "$tmp"
  # optional ngrok tunnel (CPA_NGROK_AUTHTOKEN + CPA_NGROK_DOMAIN, via --ngrok-* or the env file)
  if [ -n "$CPA_NGROK_AUTHTOKEN" ] && [ -n "$CPA_NGROK_DOMAIN" ]; then
    tmp="$(mktemp)"
    sed -e "s|{{AUTHTOKEN}}|$CPA_NGROK_AUTHTOKEN|" -e "s|{{DOMAIN}}|$CPA_NGROK_DOMAIN|" \
      "$CPA_HOME/config/ngrok.template.yml" >"$tmp"
    write_if_changed "$CPA_RUNTIME_DIR/ngrok/ngrok.yml" "$tmp"
    rm -f "$tmp"
    tmp="$(mktemp)"; printf 'COMPOSE_PROFILES=ngrok\n' >"$tmp"
    write_if_changed "$CPA_RUNTIME_DIR/.env" "$tmp" 644; rm -f "$tmp"
    info "ngrok tunnel: https://$CPA_NGROK_DOMAIN"
  elif [ -n "$CPA_NGROK_DOMAIN$CPA_NGROK_AUTHTOKEN" ]; then
    warn "ngrok needs both --ngrok-domain and --ngrok-authtoken; tunnel not configured"
  fi
  [ "${CPA_DRY_RUN:-0}" = 1 ] || { log "docker compose pull"; _dc pull -q; }
}

_wait_ready() { # poll /v1/models for up to ~15s
  local key tries=30; key="$(config_primary_key 2>/dev/null || true)"
  while [ "$tries" -gt 0 ]; do
    curl -sf -m 2 -H "Authorization: Bearer $key" "http://127.0.0.1:$CPA_PORT/v1/models" >/dev/null 2>&1 && return 0
    sleep 0.5; tries=$((tries-1))
  done
  return 1
}

server_upgrade() { log "pulling latest image"; _dc pull -q; _dc up -d; server_status; }
server_start()   { log "docker compose up -d";   _dc up -d; }
server_stop()    { log "docker compose stop";    _dc stop; }
server_restart() {
  # `up -d` creates the container if it doesn't exist yet and recreates it if the compose
  # file changed; `restart` alone is a no-op in both cases. Then restart to reload config.
  log "docker compose up -d && restart"
  _dc up -d
  _dc restart cli-proxy-api
  _wait_ready || true
  server_status
}
server_logs()    { _dc logs -f --tail 50 cli-proxy-api; }

server_status() {
  _dc ps
  local key; key="$(config_primary_key 2>/dev/null || true)"
  if curl -sf -m 5 -H "Authorization: Bearer $key" "http://127.0.0.1:$CPA_PORT/v1/models" >/dev/null 2>&1; then
    log "proxy answering on http://127.0.0.1:$CPA_PORT"
  else
    warn "proxy not answering on http://127.0.0.1:$CPA_PORT"
  fi
}

server_version() { _dc exec -T cli-proxy-api "$_bin" --help 2>&1 | head -1 || true; }

# Run the binary in the container. Allocate a TTY only when we have one
# (OAuth flows are interactive; `ssh host cpa …` is not).
_dc_exec() {
  local flags=()
  [ -t 0 ] || flags+=(-T)
  _dc exec "${flags[@]}" cli-proxy-api "$_bin" "$@"
}

server_auth() { # runs inside the container; auth files land in $CPA_AUTH_DIR
  case "$1" in
    claude)
      log "Claude OAuth login. Open the printed URL in a browser on this machine."
      info "Headless server? From your laptop first run:  ssh -L 1455:localhost:1455 <this-host>"
      _dc_exec --claude-login --no-browser ;;
    codex)
      log "Codex device-code login"
      _dc_exec --codex-device-login ;;
    *) die "usage: cpa auth claude|codex" ;;
  esac
}

server_exec() { _dc_exec "$@"; }

#!/usr/bin/env bash
# Linux backend: Docker Compose, same layout as the reference box:
#   ~/cliproxyapi/{docker-compose.yml,config.yaml,auths/,logs/,plugins/,ngrok/}

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_dc() { docker compose -f "$CPA_COMPOSE_FILE" "$@"; }

server_install() {
  need docker "https://get.docker.com"
  docker compose version >/dev/null 2>&1 || die "docker compose plugin missing"
  mkdir -p "$CPA_RUNTIME_DIR"/{auths,logs,plugins,ngrok}
  local tmp; tmp="$(mktemp)"
  cp "$CPA_HOME/config/docker-compose.yml" "$tmp"
  write_if_changed "$CPA_COMPOSE_FILE" "$tmp" 644
  rm -f "$tmp"
  # optional ngrok tunnel: set CPA_NGROK_AUTHTOKEN + CPA_NGROK_DOMAIN in $CPA_ENV_FILE
  if [ -n "${CPA_NGROK_AUTHTOKEN:-}" ] && [ -n "${CPA_NGROK_DOMAIN:-}" ]; then
    tmp="$(mktemp)"
    sed -e "s|{{AUTHTOKEN}}|$CPA_NGROK_AUTHTOKEN|" -e "s|{{DOMAIN}}|$CPA_NGROK_DOMAIN|" \
      "$CPA_HOME/config/ngrok.template.yml" >"$tmp"
    write_if_changed "$CPA_RUNTIME_DIR/ngrok/ngrok.yml" "$tmp"
    rm -f "$tmp"
    printf 'COMPOSE_PROFILES=ngrok\n' >"$CPA_RUNTIME_DIR/.env"
  fi
  [ "${CPA_DRY_RUN:-0}" = 1 ] || { log "docker compose pull"; _dc pull -q; }
}

server_upgrade() { log "pulling latest image"; _dc pull -q; _dc up -d; server_status; }
server_start()   { log "docker compose up -d";      _dc up -d; }
server_stop()    { log "docker compose stop";       _dc stop; }
server_restart() { log "docker compose restart";    _dc restart cli-proxy-api; _dc ps; }
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

server_auth() { # runs inside the container; auth files land in $CPA_AUTH_DIR
  case "$1" in
    claude)
      log "Claude OAuth login (headless). Open the printed URL in a local browser."
      info "The callback goes to localhost:1455 — from your laptop first run:  ssh -L 1455:localhost:1455 <this-host>"
      _dc exec cli-proxy-api /CLIProxyAPI/CLIProxyAPI --claude-login --no-browser ;;
    codex)
      log "Codex device-code login"
      _dc exec cli-proxy-api /CLIProxyAPI/CLIProxyAPI --codex-device-login ;;
    *) die "usage: cpa auth claude|codex" ;;
  esac
}

server_exec() { _dc exec cli-proxy-api /CLIProxyAPI/CLIProxyAPI "$@"; }

#!/usr/bin/env bash
# macOS backend: Homebrew formula `cliproxyapi` + `brew services` (launchd).
# Config path is compiled into the formula: $BREW_PREFIX/etc/cliproxyapi.conf

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_brew() { "$BREW_PREFIX/bin/brew" "$@"; }
CPA_BIN="$BREW_PREFIX/opt/cliproxyapi/bin/cliproxyapi"

server_install() {
  need "$BREW_PREFIX/bin/brew" "install Homebrew first: https://brew.sh"
  if _brew list --formula cliproxyapi >/dev/null 2>&1; then
    info "cliproxyapi already installed ($(_brew list --versions cliproxyapi))"
  else
    log "brew install cliproxyapi"
    [ "${CPA_DRY_RUN:-0}" = 1 ] || _brew install cliproxyapi
  fi
  mkdir -p "$CPA_AUTH_DIR"
}

server_upgrade() {
  log "brew upgrade cliproxyapi"
  _brew upgrade cliproxyapi || true
  server_restart
}

server_start()   { log "brew services start cliproxyapi";   _brew services start cliproxyapi; }
server_stop()    { log "brew services stop cliproxyapi";    _brew services stop cliproxyapi; }
server_restart() { log "brew services restart cliproxyapi"; _brew services restart cliproxyapi; sleep 1; server_status; }

server_status() {
  _brew services info cliproxyapi 2>/dev/null || _brew services list | grep -E '^cliproxyapi' || true
  local key; key="$(config_primary_key 2>/dev/null || true)"
  if curl -sf -m 5 -H "Authorization: Bearer $key" "http://127.0.0.1:$CPA_PORT/v1/models" >/dev/null 2>&1; then
    log "proxy answering on http://127.0.0.1:$CPA_PORT"
  else
    warn "proxy not answering on http://127.0.0.1:$CPA_PORT"
  fi
}

server_logs() {
  # brew services runs the binary with no log redirection by default; use the unified log.
  info "tailing launchd/system log for cliproxyapi (Ctrl-C to stop)"
  log stream --predicate 'process == "cliproxyapi"' --style compact 2>/dev/null \
    || tail -f "$BREW_PREFIX/var/log/cliproxyapi.log" 2>/dev/null \
    || die "no log source found"
}

server_auth() { # server_auth claude|codex
  [ -x "$CPA_BIN" ] || die "cliproxyapi binary not found at $CPA_BIN"
  case "$1" in
    claude) log "Claude OAuth login (browser will open)"; "$CPA_BIN" -config "$CPA_CONFIG_FILE" --claude-login ;;
    codex)  log "Codex device-code login";               "$CPA_BIN" -config "$CPA_CONFIG_FILE" --codex-device-login ;;
    *) die "usage: cpa auth claude|codex" ;;
  esac
}

server_exec() { [ -x "$CPA_BIN" ] || die "cliproxyapi binary not found"; "$CPA_BIN" -config "$CPA_CONFIG_FILE" "$@"; }

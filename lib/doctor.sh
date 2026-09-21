#!/usr/bin/env bash
# `cpa doctor` — health checks. Exits non-zero if anything fails.

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_fail=0
_ok()  { printf '  %s✔%s %s\n' "$_c_grn" "$_c_off" "$*" >&2; }
_bad() { printf '  %s✘%s %s\n' "$_c_red" "$_c_off" "$*" >&2; _fail=1; }
_meh() { printf '  %s•%s %s\n' "$_c_ylw" "$_c_off" "$*" >&2; }

_check_server_process() {
  if [ "$CPA_OS" = darwin ]; then
    if "$BREW_PREFIX/bin/brew" services list 2>/dev/null | grep -qE '^cliproxyapi[[:space:]]+started'; then
      _ok "brew service running"
    else
      _bad "brew service not running (cpa server start)"
    fi
  else
    if docker compose -f "$CPA_COMPOSE_FILE" ps --status running 2>/dev/null | grep -q cli-proxy-api; then
      _ok "docker container running"
    else
      _bad "container not running (cpa server start)"
    fi
  fi
}

_check_auth_files() {
  local n
  n="$(find "$CPA_AUTH_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -gt 0 ]; then
    _ok "$n OAuth credential file(s) in $CPA_AUTH_DIR"
  else
    _meh "no OAuth credentials yet — run auth-claude / auth-codex"
  fi
}

_check_api() { # _check_api <base_url> <api_key> <check_aliases:0|1>
  local base_url=$1 api_key=$2 check_aliases=$3 models count alias missing=0 total
  if [ -z "$api_key" ]; then
    _bad "no API key known (env or config)"; return
  fi
  if ! models="$(curl -sf -m 8 -H "Authorization: Bearer $api_key" "$base_url/v1/models" 2>/dev/null)"; then
    _bad "$base_url/v1/models unreachable or rejected the key"; return
  fi
  count="$(printf '%s' "$models" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')"
  _ok "$base_url/v1/models → $count models"
  [ "$check_aliases" = 1 ] || return
  while IFS= read -r alias; do
    if ! printf '%s' "$models" | python3 -c 'import json,sys; ids={m["id"] for m in json.load(sys.stdin)["data"]}; sys.exit(0 if sys.argv[1] in ids else 1)' "$alias"; then
      _bad "alias not served: $alias"; missing=1
    fi
  done < <(list_aliases)
  total="$(list_aliases | wc -l | tr -d ' ')"
  [ "$missing" = 0 ] && _ok "all $total aliases from aliases.tsv are served"
}

# Actual routing state read from the client files (not the persisted flag).
# Prints one of: proxy | direct | mismatch | missing
claude_state() { # claude_state <base_url> <api_key>
  local f="$HOME/.claude/settings.json"
  [ -f "$f" ] || { echo missing; return; }
  python3 - "$f" "$1" "$2" <<'PY'
import json, sys
env = json.load(open(sys.argv[1])).get("env", {})
url, tok = env.get("ANTHROPIC_BASE_URL"), env.get("ANTHROPIC_AUTH_TOKEN")
if not url and not tok:
    print("direct")
elif (url or "").rstrip("/") == sys.argv[2].rstrip("/") and tok == sys.argv[3]:
    print("proxy")
else:
    print("mismatch")
PY
}

codex_state() { # codex_state <base_url> <api_key>
  local f="$HOME/.codex/config.toml"
  [ -f "$f" ] || { echo missing; return; }
  if ! grep -qE '^model_provider[[:space:]]*=' "$f"; then
    echo direct
  elif grep -qE '^model_provider[[:space:]]*=[[:space:]]*"cliproxyapi"' "$f" \
       && grep -qF "base_url = \"$1/v1\"" "$f" \
       && grep -qF "experimental_bearer_token = \"$2\"" "$f"; then
    echo proxy
  else
    echo mismatch
  fi
}

_report_client() { # _report_client <name> <state> <expected:on|off> <target>
  local name=$1 state=$2 expected=$3 target=$4
  case "$state" in
    missing)  _meh "$name not configured" ;;
    proxy)    if [ "$expected" = on ]; then _ok "$name → $target"; else _bad "$name still routed through the proxy (cpa off)"; fi ;;
    direct)   if [ "$expected" = off ]; then _ok "$name → direct"; else _bad "$name is routed direct (cpa on)"; fi ;;
    mismatch) _bad "$name points somewhere else — run cpa on to fix" ;;
  esac
}

_check_claude() { _report_client "Claude Code" "$(claude_state "$1" "$2")" "$3" "$1"; }
_check_codex()  { _report_client "Codex"       "$(codex_state  "$1" "$2")" "$3" "$1/v1"; }

routing_status() {
  local base_url api_key
  load_env
  base_url="${CPA_BASE_URL:-http://127.0.0.1:$CPA_PORT}"
  api_key="${CPA_API_KEY:-$(config_primary_key 2>/dev/null || true)}"
  log "routing: ${CPA_ROUTING:-on}  (proxy: $base_url)"
  printf '  %-12s %s\n' "Claude Code" "$(claude_state "$base_url" "$api_key")" >&2
  printf '  %-12s %s\n' "Codex"       "$(codex_state  "$base_url" "$api_key")" >&2
  printf '  %-12s %s\n' "Cursor"      "manual — check Settings → Models → Override OpenAI Base URL" >&2
}

_check_shell() {
  local rc; rc="$(rc_file)"
  if grep -qF 'cliproxyapi/shell/aliases.sh' "$rc" 2>/dev/null; then
    _ok "shell aliases sourced from $rc"
  else
    _meh "shell aliases not in $rc (cpa install adds them)"
  fi
  if grep -qE '^alias (auth-claude|auth-codex|cliproxyapi)' "$rc" 2>/dev/null; then
    _meh "older hand-written cliproxyapi aliases also present in $rc — safe to delete"
  fi
}

doctor() {
  local base_url api_key mode routing
  _fail=0
  load_env
  mode="${CPA_MODE:-server}"
  routing="${CPA_ROUTING:-on}"
  base_url="${CPA_BASE_URL:-http://127.0.0.1:$CPA_PORT}"
  api_key="${CPA_API_KEY:-$(config_primary_key 2>/dev/null || true)}"

  log "cpa doctor  (mode: $mode, routing: $routing, os: $CPA_OS)"

  if [ "$mode" = server ]; then
    if [ -f "$CPA_CONFIG_FILE" ]; then _ok "config: $CPA_CONFIG_FILE"; else _bad "config missing: $CPA_CONFIG_FILE"; fi
    _check_server_process
    _check_auth_files
    _check_api "$base_url" "$api_key" 1
  else
    _check_api "$base_url" "$api_key" 0
  fi

  _check_claude "$base_url" "$api_key" "$routing"
  _check_codex  "$base_url" "$api_key" "$routing"
  _check_shell

  if [ "$_fail" = 0 ]; then
    log "all good"
  else
    warn "problems found"; return 1
  fi
}

#!/usr/bin/env bash
# Client configuration: Claude Code, Codex, Cursor (print-only).

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_py() {
  local args=("$@")
  [ "${CPA_DRY_RUN:-0}" = 1 ] && args+=(--dry-run)
  PYTHONPATH="$CPA_HOME/lib" python3 "$CPA_HOME/lib/${args[0]}" "${args[@]:1}"
}

client_claude() { log "Claude Code → $1";  _py client-claude.py "$1" "$2"; }
client_codex()  { log "Codex → $1/v1";     _py client-codex.py  "$1" "$2"; }

# Cursor keeps the base URL and model list in an opaque SQLite blob and the API key in
# encrypted safeStorage, so it is configured by hand. This prints exactly what to enter.
client_cursor() {
  local base_url=$1 api_key=$2
  cat >&2 <<EOF

┌─ Cursor (manual, ~1 minute) ─────────────────────────────────────────────
│ Cursor Settings → Models  (⌘⇧J on macOS, Ctrl+Shift+J on Linux)
│
│  1. OpenAI API Key:              $api_key
│  2. ☑ Override OpenAI Base URL:  $base_url/v1
│     → click Verify
│  3. Model Names → + Add Model, one per line:
EOF
  list_aliases | sed 's/^/│        /' >&2
  cat >&2 <<EOF
│
│  Base models (claude-fable-5-1, gpt-6-astra, …) also work by their real names.
│  Cursor sometimes unticks "Override OpenAI Base URL" on its own — re-tick it if
│  requests stop reaching the proxy. Custom base URLs power Chat/Agent only, not Tab.
└──────────────────────────────────────────────────────────────────────────
EOF
}

clients_all() { # clients_all <base-url> <api-key> [which...]
  local base_url=$1 api_key=$2; shift 2
  local which=("$@"); [ ${#which[@]} -eq 0 ] && which=(claude codex cursor)
  for c in "${which[@]}"; do
    case "$c" in
      claude) client_claude "$base_url" "$api_key" ;;
      codex)  client_codex  "$base_url" "$api_key" ;;
      cursor) client_cursor "$base_url" "$api_key" ;;
      *) die "unknown client: $c (claude|codex|cursor)" ;;
    esac
  done
}

#!/usr/bin/env bash
# Client routing: point Claude Code / Codex / Cursor at the proxy (on) or back at
# their providers directly (off).

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_py() {
  local args=("$@")
  [ "${CPA_DRY_RUN:-0}" = 1 ] && args+=(--dry-run)
  PYTHONPATH="$CPA_HOME/lib" python3 "$CPA_HOME/lib/${args[0]}" "${args[@]:1}"
}

# ---------- on ----------
client_claude_on() { log "Claude Code → $1";  _py client-claude.py on "$1" "$2"; }
client_codex_on()  { log "Codex → $1/v1";     _py client-codex.py  on "$1" "$2"; }

# Cursor keeps the base URL and model list in an opaque SQLite blob and the API key in
# encrypted safeStorage, so it is configured by hand. This prints exactly what to enter.
client_cursor_on() {
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

# ---------- off ----------
client_claude_off() { log "Claude Code → direct (Anthropic login)"; _py client-claude.py off; }
client_codex_off()  { log "Codex → direct (ChatGPT login)";         _py client-codex.py  off; }
client_cursor_off() {
  cat >&2 <<'EOF'

┌─ Cursor (manual) ────────────────────────────────────────────────────────
│ Cursor Settings → Models → ☐ untick "Override OpenAI Base URL".
│ The key and custom model names can stay; they're inert while the override is off.
│ Cursor's own models go through Cursor again.
└──────────────────────────────────────────────────────────────────────────
EOF
}

# ---------- dispatch ----------
# clients_route on|off <base-url> <api-key> [claude|codex|cursor ...]
clients_route() {
  local action=$1 base_url=$2 api_key=$3; shift 3
  local which=("$@")
  [ ${#which[@]} -eq 0 ] && which=(claude codex cursor)
  local c
  for c in "${which[@]}"; do
    case "$c" in
      claude|codex|cursor) "client_${c}_${action}" "$base_url" "$api_key" ;;
      *) die "unknown client: $c (claude|codex|cursor)" ;;
    esac
  done
}

clients_all() { clients_route on "$@"; }

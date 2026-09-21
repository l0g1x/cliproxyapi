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

# ---------- cursor ----------
# Cursor keeps the base URL, override flag and model list in a SQLite state DB (which cpa
# edits) and the API key in Keychain-backed encrypted storage (which only the Cursor UI can
# write). So: cpa applies everything else, and prints the key for the user to paste once.

_cursor_running() { pgrep -x Cursor >/dev/null 2>&1 || pgrep -x cursor >/dev/null 2>&1; }

# Quit Cursor (macOS: politely via AppleScript) so the DB row isn't rewritten under us.
# Returns 0 if it was running and we quit it (caller relaunches), 1 if it wasn't running.
_cursor_quit() {
  _cursor_running || return 1
  if [ "$CPA_OS" = darwin ]; then
    log "quitting Cursor"
    osascript -e 'quit app "Cursor"' >/dev/null 2>&1 || true
  else
    log "stopping Cursor"
    pkill -x cursor 2>/dev/null || true
  fi
  local tries=40
  while _cursor_running && [ "$tries" -gt 0 ]; do sleep 0.5; tries=$((tries-1)); done
  _cursor_running && die "Cursor did not quit — close it and retry"
  return 0
}

_cursor_relaunch() {
  if [ "$CPA_OS" = darwin ]; then
    log "relaunching Cursor"; open -a Cursor 2>/dev/null || true
  else
    info "start Cursor again when ready"
  fi
}

# Only register aliases whose upstream this proxy actually serves (e.g. no f51-* on a
# Codex-only box). Falls back to the full alias list if the proxy can't be reached.
_cursor_models() { # _cursor_models <base_url> <api_key>
  local served
  if served="$(curl -sf -m 8 -H "Authorization: Bearer $2" "$1/v1/models" 2>/dev/null)"; then
    printf '%s' "$served" | python3 -c '
import json,sys
ids={m["id"] for m in json.load(sys.stdin)["data"]}
for line in open(sys.argv[1]):
    up,alias=line.rstrip("\n").split("\t")
    if up in ids: print(alias)' <(list_alias_pairs)
  else
    list_aliases
  fi
}

client_cursor_on() {
  local base_url=$1 api_key=$2 relaunch=1 m
  local models=()
  while IFS= read -r m; do [ -n "$m" ] && models+=("$m"); done < <(_cursor_models "$base_url" "$api_key")   # bash 3.2 has no mapfile
  [ ${#models[@]} -gt 0 ] || { warn "no usable aliases for Cursor (no upstream models served yet)"; return 0; }
  log "Cursor → $base_url/v1  (${#models[@]} models)"
  if [ "${CPA_DRY_RUN:-0}" != 1 ]; then _cursor_quit || relaunch=0; fi
  _py client-cursor.py on "$base_url" "${models[@]}"
  [ "${CPA_DRY_RUN:-0}" != 1 ] && [ "$relaunch" = 1 ] && _cursor_relaunch
  cat >&2 <<EOF

┌─ Cursor: one manual step ────────────────────────────────────────────────
│ Cursor Settings → Models → OpenAI API Key  (⌘⇧J on macOS, Ctrl+Shift+J on Linux)
│
│     $api_key
│
│ Base URL override and model names are already set. Pick one of:
EOF
  printf '%s
' "${models[@]}" | sed 's/^/│     /' >&2
  cat >&2 <<'EOF'
│ in the chat model dropdown.
│
│ Cursor sometimes unticks "Override OpenAI Base URL" on its own; `cpa on cursor`
│ re-ticks it. Custom base URLs power Chat/Agent only, not Tab.
└──────────────────────────────────────────────────────────────────────────
EOF
}

client_cursor_print() { # print-only variant for `cpa cursor`
  local base_url=$1 api_key=$2
  cat >&2 <<EOF

┌─ Cursor (manual) ────────────────────────────────────────────────────────
│ Cursor Settings → Models  (⌘⇧J on macOS, Ctrl+Shift+J on Linux)
│  1. OpenAI API Key:              $api_key
│  2. ☑ Override OpenAI Base URL:  $base_url/v1   → Verify
│  3. Model Names → + Add Model:
EOF
  _cursor_models "$base_url" "$api_key" | sed 's/^/│        /' >&2
  printf '│
│ Or let cpa do 2 and 3:  cpa on cursor
└──────────────────────────────────────────────────────────────────────────
' >&2
}

# ---------- off ----------
client_claude_off() { log "Claude Code → direct (Anthropic login)"; _py client-claude.py off; }
client_codex_off()  { log "Codex → direct (ChatGPT login)";         _py client-codex.py  off; }
client_cursor_off() {
  local relaunch=1
  log "Cursor → direct (override unticked)"
  if [ "${CPA_DRY_RUN:-0}" != 1 ]; then _cursor_quit || relaunch=0; fi
  _py client-cursor.py off
  [ "${CPA_DRY_RUN:-0}" != 1 ] && [ "$relaunch" = 1 ] && _cursor_relaunch
  true
}

cursor_state() { PYTHONPATH="$CPA_HOME/lib" python3 "$CPA_HOME/lib/client-cursor.py" status 2>/dev/null || echo unset; }

# ---------- dispatch ----------
# clients_route on|off <base-url> <api-key> [claude|codex|cursor ...]
clients_route() {
  local action=$1 base_url=$2 api_key=$3; shift 3
  local which=("$@")
  # Cursor is opt-in: switching it quits and relaunches the app.
  [ ${#which[@]} -eq 0 ] && which=(claude codex)
  local c
  for c in "${which[@]}"; do
    case "$c" in
      claude|codex|cursor) "client_${c}_${action}" "$base_url" "$api_key" ;;
      *) die "unknown client: $c (claude|codex|cursor)" ;;
    esac
  done
}

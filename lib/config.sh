#!/usr/bin/env bash
# Server config rendering + alias sync + api-key management. Sourced by bin/cpa.

# Requires lib/common.sh to be sourced first.
# shellcheck source=lib/common.sh
[ -n "${CPA_HOME:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_managed_begin='# >>> cpa-managed aliases'
_managed_end='# <<< cpa-managed aliases'

render_alias_block() { python3 "$CPA_HOME/lib/render_aliases.py" "$CPA_HOME/config/aliases.tsv"; }
list_aliases()       { python3 "$CPA_HOME/lib/render_aliases.py" "$CPA_HOME/config/aliases.tsv" --list; }
list_alias_pairs()   { python3 "$CPA_HOME/lib/render_aliases.py" "$CPA_HOME/config/aliases.tsv" --pairs; }

# config_render <api-key>  — full render from template (fresh install / --force)
config_render() {
  local api_key=$1 aliases tmp
  aliases="$(render_alias_block)" || die "alias rendering failed"
  tmp="$(mktemp)"
  # host "" = bind all interfaces inside the container; compose publishes it on 127.0.0.1 only.
  python3 - "$CPA_HOME/config/config.template.yaml" "" "$CPA_CONTAINER_AUTH_DIR" "$api_key" "$aliases" >"$tmp" <<'PY'
import sys
tpl, host, auth_dir, key, aliases = sys.argv[1:6]
s = open(tpl, encoding="utf-8").read()
for k, v in {"HOST": host, "AUTH_DIR": auth_dir, "API_KEY": key, "ALIASES": aliases}.items():
    s = s.replace("{{" + k + "}}", v)
sys.stdout.write(s)
PY
  write_if_changed "$CPA_CONFIG_FILE" "$tmp"
  rm -f "$tmp"
}

# config_sync_aliases — replace only the managed region in an existing config (or append it)
config_sync_aliases() {
  [ -f "$CPA_CONFIG_FILE" ] || die "no config at $CPA_CONFIG_FILE — run 'cpa install' first"
  local aliases tmp
  aliases="$(render_alias_block)" || die "alias rendering failed"
  tmp="$(mktemp)"
  python3 - "$CPA_CONFIG_FILE" "$_managed_begin" "$_managed_end" "$aliases" >"$tmp" <<'PY'
import sys
path, begin, end, block = sys.argv[1:5]
lines = open(path, encoding="utf-8").read().split("\n")
b = next((i for i, l in enumerate(lines) if l.startswith(begin)), None)
e = next((i for i, l in enumerate(lines) if l.startswith(end)), None)
region = [begin + " (generated from config/aliases.tsv — do not edit by hand) >>>", *block.split("\n"), end + " <<<"]
if b is None or e is None or e < b:
    if lines and lines[-1] == "": lines.pop()
    lines += ["", *region, ""]
else:
    lines[b:e + 1] = region
sys.stdout.write("\n".join(lines))
PY
  write_if_changed "$CPA_CONFIG_FILE" "$tmp"
  rm -f "$tmp"
}

config_path() { echo "$CPA_CONFIG_FILE"; }

config_show() {
  [ -f "$CPA_CONFIG_FILE" ] || die "no config at $CPA_CONFIG_FILE"
  sed -E 's/^(\s*- )"(.{4})[^"]{4,}(.{4})"/\1"\2…\3"/; s/(secret-key: ")[^"]+"/\1<redacted>"/' "$CPA_CONFIG_FILE"
}

# ---------- api keys ----------
# First key in the file (the one cpa hands to clients).
config_primary_key() {
  [ -f "$CPA_CONFIG_FILE" ] || return 1
  awk '/^api-keys:/{f=1;next} f&&/^[[:space:]]*- /{gsub(/^[[:space:]]*- *"?|"?[[:space:]]*$/,""); print; exit}' "$CPA_CONFIG_FILE"
}

# key_add — generate a fresh key, append it to api-keys, print ONLY the key to stdout.
key_add() {
  [ -f "$CPA_CONFIG_FILE" ] || die "no config at $CPA_CONFIG_FILE — run 'cpa install' first"
  local key tmp
  key="$(gen_api_key)"
  tmp="$(mktemp)"
  python3 - "$CPA_CONFIG_FILE" "$key" >"$tmp" <<'PY' || die "failed to insert key"
import re, sys
path, key = sys.argv[1:3]
lines = open(path, encoding="utf-8").read().split("\n")
start = next((i for i, l in enumerate(lines) if l.startswith("api-keys:")), None)
if start is None:
    sys.exit("no 'api-keys:' section in config")
last = start
for i in range(start + 1, len(lines)):
    if re.match(r"^\s*- ", lines[i]):
        last = i
    elif lines[i].strip() and not lines[i].lstrip().startswith("#"):
        break
lines.insert(last + 1, f'  - "{key}"')
sys.stdout.write("\n".join(lines))
PY
  write_if_changed "$CPA_CONFIG_FILE" "$tmp" 2>/dev/null
  rm -f "$tmp"
  printf '%s\n' "$key"
}

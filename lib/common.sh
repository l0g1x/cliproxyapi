#!/usr/bin/env bash
# Shared helpers for cpa. Sourced, never executed.
# All human-facing output goes to stderr so `$(cpa key)` / `$(cpa url)` stay clean.

# ---------- output ----------
if [ -t 2 ]; then
  _c_dim=$'\e[2m'; _c_red=$'\e[31m'; _c_grn=$'\e[32m'; _c_ylw=$'\e[33m'; _c_off=$'\e[0m'
else
  _c_dim=''; _c_red=''; _c_grn=''; _c_ylw=''; _c_off=''
fi
export _c_dim _c_red _c_grn _c_ylw _c_off
log()  { printf '%s==>%s %s\n' "$_c_grn" "$_c_off" "$*" >&2; }
info() { printf '%s    %s%s\n' "$_c_dim" "$*" "$_c_off" >&2; }
warn() { printf '%sWARN%s %s\n' "$_c_ylw" "$_c_off" "$*" >&2; }
die()  { printf '%sERROR%s %s\n' "$_c_red" "$_c_off" "$*" >&2; exit 1; }

confirm() { # confirm "question" -> 0 yes / 1 no ; CPA_YES=1 auto-yes
  [ "${CPA_YES:-0}" = 1 ] && return 0
  printf '%s [y/N] ' "$1" >&2
  read -r ans </dev/tty || return 1
  [[ "$ans" =~ ^[Yy]$ ]]
}

need() { # need cmd [hint]
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1${2:+ — $2}"
}

# ---------- paths ----------
# Exported so the other lib/*.sh files and the Python writers see the same values.
export CPA_HOME="${CPA_HOME:-$HOME/.cliproxyapi}"           # repo checkout
export CPA_STATE_DIR="${CPA_STATE_DIR:-$HOME/.config/cliproxyapi}"
export CPA_ENV_FILE="$CPA_STATE_DIR/env"
export CPA_PORT=8317

detect_os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux)  echo linux ;;
    *)      die "unsupported OS: $(uname -s)" ;;
  esac
}
CPA_OS="$(detect_os)"; export CPA_OS

# The server always runs in Docker (macOS and Linux alike), with the layout of the
# reference box:  ~/cliproxyapi/{docker-compose.yml,config.yaml,auths/,logs/,plugins/,ngrok/}
export CPA_RUNTIME_DIR="${CPA_RUNTIME_DIR:-$HOME/cliproxyapi}"
export CPA_CONFIG_FILE="${CPA_CONFIG_FILE:-$CPA_RUNTIME_DIR/config.yaml}"
export CPA_AUTH_DIR="${CPA_AUTH_DIR:-$CPA_RUNTIME_DIR/auths}"
export CPA_COMPOSE_FILE="$CPA_RUNTIME_DIR/docker-compose.yml"
export CPA_CONTAINER_AUTH_DIR="/root/.cli-proxy-api"

# Values populated by load_env (declared here so every sourcing file sees them defined).
CPA_MODE=""; CPA_BASE_URL=""; CPA_API_KEY=""; CPA_ROUTING=""
CPA_NGROK_AUTHTOKEN="${CPA_NGROK_AUTHTOKEN:-}"; CPA_NGROK_DOMAIN="${CPA_NGROK_DOMAIN:-}"
export CPA_MODE CPA_BASE_URL CPA_API_KEY CPA_ROUTING CPA_NGROK_AUTHTOKEN CPA_NGROK_DOMAIN

# ---------- env (mode / base url / key / ngrok) ----------
# Stored as plain KEY=VALUE lines (no quoting/escaping) and read explicitly rather than sourced,
# so a tampered env file can't execute code. Environment variables take precedence over the file.
load_env() {
  [ -f "$CPA_ENV_FILE" ] || return 0
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      CPA_MODE)            CPA_MODE=$value ;;
      CPA_BASE_URL)        CPA_BASE_URL=$value ;;
      CPA_API_KEY)         CPA_API_KEY=$value ;;
      CPA_ROUTING)         CPA_ROUTING=$value ;;
      CPA_NGROK_AUTHTOKEN) [ -n "$CPA_NGROK_AUTHTOKEN" ] || CPA_NGROK_AUTHTOKEN=$value ;;
      CPA_NGROK_DOMAIN)    [ -n "$CPA_NGROK_DOMAIN" ]    || CPA_NGROK_DOMAIN=$value ;;
    esac
  done <"$CPA_ENV_FILE"
}
save_env() { # save_env MODE BASE_URL API_KEY [ROUTING=on] — ngrok fields carried from current values
  mkdir -p "$CPA_STATE_DIR"
  local tmp; tmp="$(mktemp)"
  {
    printf 'CPA_MODE=%s\nCPA_BASE_URL=%s\nCPA_API_KEY=%s\nCPA_ROUTING=%s\n' "$1" "$2" "$3" "${4:-on}"
    [ -n "$CPA_NGROK_AUTHTOKEN" ] && printf 'CPA_NGROK_AUTHTOKEN=%s\n' "$CPA_NGROK_AUTHTOKEN"
    [ -n "$CPA_NGROK_DOMAIN" ]    && printf 'CPA_NGROK_DOMAIN=%s\n'    "$CPA_NGROK_DOMAIN"
  } >"$tmp"
  write_if_changed "$CPA_ENV_FILE" "$tmp"
  rm -f "$tmp"
}
set_routing() { # set_routing on|off — persists the flag, keeps the other values
  load_env
  save_env "${CPA_MODE:-server}" "${CPA_BASE_URL:-http://127.0.0.1:$CPA_PORT}" "${CPA_API_KEY:-}" "$1"
}
# The URL clients should use: the ngrok domain when a tunnel is configured, else loopback.
# Cursor in particular requires a public URL (its verification runs from Cursor's servers).
public_base_url() {
  if [ -n "$CPA_NGROK_DOMAIN" ]; then echo "https://$CPA_NGROK_DOMAIN"; else echo "http://127.0.0.1:$CPA_PORT"; fi
}

# ---------- backups ----------
# First modification of a file gets <file>.bak (pristine original, never overwritten).
# Later modifications get <file>.bak.<timestamp>. Nothing is written if content is unchanged.
backup_file() {
  local f=$1
  [ -e "$f" ] || return 0
  if [ ! -e "$f.bak" ]; then
    cp -p "$f" "$f.bak"; info "backup: $f.bak"
  else
    local b; b="$f.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$f" "$b"; info "backup: $b"
  fi
}

write_if_changed() { # write_if_changed <target> <tmpfile> [mode]
  local target=$1 src=$2 mode=${3:-600}
  if [ -e "$target" ] && cmp -s "$target" "$src"; then
    info "unchanged: $target"; return 0
  fi
  if [ "${CPA_DRY_RUN:-0}" = 1 ]; then
    log "[dry-run] would write $target"
    if [ -e "$target" ]; then diff -u "$target" "$src" >&2 || true; else sed 's/^/    + /' "$src" >&2; fi
    return 0
  fi
  backup_file "$target"
  mkdir -p "$(dirname "$target")"
  install -m "$mode" "$src" "$target"
  log "wrote: $target"
}

append_line_once() { # append_line_once <file> <line> — adds line if not present (with backup)
  local f=$1 line=$2
  [ -e "$f" ] || : >"$f"
  grep -qxF -- "$line" "$f" && { info "already present in $f"; return 0; }
  [ "${CPA_DRY_RUN:-0}" = 1 ] && { log "[dry-run] would append to $f: $line"; return 0; }
  backup_file "$f"
  printf '\n%s\n' "$line" >>"$f"
  log "appended to $f"
}

# ---------- misc ----------
gen_api_key() { need openssl; printf 'cpa-%s' "$(openssl rand -hex 20)"; }
rc_file() { case "$(basename "${SHELL:-bash}")" in zsh) echo "$HOME/.zshrc" ;; *) echo "$HOME/.bashrc" ;; esac; }
mask() { local s=$1; [ ${#s} -le 8 ] && { echo '****'; return; }; printf '%s…%s' "${s:0:4}" "${s: -4}"; }

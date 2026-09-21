#!/usr/bin/env bash
# One-command bootstrap:
#   curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --client --base-url https://proxy.example.com --api-key KEY
# Clones (or updates) the repo into ~/.cliproxyapi and runs `cpa install` with any arguments given.
set -euo pipefail

REPO="${CPA_REPO:-https://github.com/l0g1x/cliproxyapi.git}"
DEST="${CPA_HOME:-$HOME/.cliproxyapi}"

for t in git curl python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "error: '$t' is required. Install it and re-run." >&2; exit 1; }
done

if [ -d "$DEST/.git" ]; then
  echo "==> updating $DEST" >&2
  git -C "$DEST" pull --ff-only -q
else
  echo "==> cloning into $DEST" >&2
  git clone -q "$REPO" "$DEST"
fi

exec "$DEST/bin/cpa" install "$@"

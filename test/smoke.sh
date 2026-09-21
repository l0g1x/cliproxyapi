#!/usr/bin/env bash
# Offline checks: alias rendering, config rendering, key add, client writers (against a temp HOME).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok   $*"; }

# 1. aliases.tsv renders and every alias is unique
python3 "$ROOT/lib/render_aliases.py" "$ROOT/config/aliases.tsv" >/tmp/cpa-aliases.yaml
n_rows=$(python3 "$ROOT/lib/render_aliases.py" "$ROOT/config/aliases.tsv" --list | wc -l | tr -d ' ')
n_yaml=$(grep -c '      alias: ' /tmp/cpa-aliases.yaml)
[ "$n_rows" = "$n_yaml" ] || fail "expected $n_rows alias entries in YAML, got $n_yaml"
grep -q '"f51-high-proxy"' /tmp/cpa-aliases.yaml || fail "f51-high-proxy missing"
grep -q '"g6a-xhigh-proxy"' /tmp/cpa-aliases.yaml || fail "g6a-xhigh-proxy missing"
grep -q '"reasoning.effort": "xhigh"' /tmp/cpa-aliases.yaml || fail "codex xhigh override missing"
grep -q '"output_config.effort": "max"' /tmp/cpa-aliases.yaml || fail "claude max override missing"
grep -q '"service_tier": "priority"' /tmp/cpa-aliases.yaml || fail "codex fast tier must render as wire value priority"
grep -q '"service_tier": "fast"' /tmp/cpa-aliases.yaml && fail "codex tier 'fast' leaked to the wire (must be priority)"
grep -A6 'name: "g6a-max-fast-proxy"' /tmp/cpa-aliases.yaml | grep -q '"reasoning.effort": "max"' || fail "g6a-max-fast-proxy lost effort"
[ "$(grep -c 'fork: true' /tmp/cpa-aliases.yaml)" = "$n_rows" ] || fail "every alias must fork"
pass "aliases render ($n_rows aliases)"

# 2. YAML validity, if pyyaml happens to be around
if python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' /tmp/cpa-aliases.yaml || fail "alias YAML invalid"
  pass "alias YAML parses"
fi

# 3. bad TSV rows are rejected
printf 'claude\tclaude-fable-5-1\tdup\t-\nclaude\tclaude-fable-5-1\tdup\t-\n' >/tmp/cpa-bad.tsv
python3 "$ROOT/lib/render_aliases.py" /tmp/cpa-bad.tsv >/dev/null 2>&1 && fail "duplicate alias not rejected"
printf 'codex\tgpt-6-astra\tx\tultra\n' >/tmp/cpa-bad.tsv
python3 "$ROOT/lib/render_aliases.py" /tmp/cpa-bad.tsv >/dev/null 2>&1 && fail "invalid effort not rejected"
printf 'claude\tclaude-opus-5\tx\thigh\tfast\n' >/tmp/cpa-bad.tsv
python3 "$ROOT/lib/render_aliases.py" /tmp/cpa-bad.tsv >/dev/null 2>&1 && fail "tier on claude not rejected"
pass "validation rejects bad rows"

# 4. full flow in a sandbox HOME
SANDBOX="$(mktemp -d)"
export HOME="$SANDBOX" CPA_HOME="$ROOT" CPA_STATE_DIR="$SANDBOX/state" CPA_YES=1
mkdir -p "$HOME/.claude" "$HOME/.codex"
cat >"$HOME/.claude/settings.json" <<'EOF'
{"env":{"ANTHROPIC_BASE_URL":"https://old.example","ANTHROPIC_AUTH_TOKEN":"old"},"model":"keep-me","permissions":{"defaultMode":"bypassPermissions"}}
EOF
cat >"$HOME/.codex/config.toml" <<'EOF'
model = "gpt-6-astra"
model_reasoning_effort = "max"

[projects."/tmp"]
trust_level = "trusted"
EOF

PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-claude.py" on https://new.example cpa-test-key 2>/dev/null
python3 - "$HOME/.claude/settings.json" <<'PY' || fail "claude settings wrong"
import json,sys; d=json.load(open(sys.argv[1]))
assert d["env"]["ANTHROPIC_BASE_URL"]=="https://new.example" and d["env"]["ANTHROPIC_AUTH_TOKEN"]=="cpa-test-key"
assert d["model"]=="keep-me" and d["permissions"]["defaultMode"]=="bypassPermissions"
PY
[ -f "$HOME/.claude/settings.json.bak" ] || fail "claude .bak not created"
grep -q '"old"' "$HOME/.claude/settings.json.bak" || fail "claude .bak is not the original"
pass "claude writer (+ .bak)"

PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py" on https://new.example cpa-test-key 2>/dev/null
grep -q '^model_provider = "cliproxyapi"' "$HOME/.codex/config.toml" || fail "codex model_provider missing"
grep -q '^model_reasoning_effort = "max"' "$HOME/.codex/config.toml" || fail "codex reasoning effort clobbered"
grep -q '^base_url = "https://new.example/v1"' "$HOME/.codex/config.toml" || fail "codex base_url wrong"
grep -q '^\[projects."/tmp"\]' "$HOME/.codex/config.toml" || fail "codex projects section lost"
[ -f "$HOME/.codex/config.toml.bak" ] || fail "codex .bak not created"
# second run: unchanged → no new backup
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py" on https://new.example cpa-test-key 2>/dev/null
[ "$(find "$HOME/.codex" -name 'config.toml.bak*' | wc -l | tr -d ' ')" = 1 ] || fail "unchanged rewrite created extra backup"
# third run with new key: replaces block, timestamped backup
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py" on https://new.example cpa-key-2 2>/dev/null
[ "$(grep -c 'experimental_bearer_token' "$HOME/.codex/config.toml")" = 1 ] || fail "codex provider block duplicated"
[ "$(find "$HOME/.codex" -name 'config.toml.bak*' | wc -l | tr -d ' ')" = 2 ] || fail "timestamped backup missing"
grep -q '"old"' "$HOME/.claude/settings.json.bak" || fail "pristine .bak was overwritten"
pass "codex writer (+ idempotent, + timestamped .bak)"

# 4b. off → direct, on → proxy again (round trip)
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-claude.py" off 2>/dev/null
python3 - "$HOME/.claude/settings.json" <<'PY2' || fail "claude off left proxy keys"
import json,sys; d=json.load(open(sys.argv[1])); env=d.get("env",{})
assert "ANTHROPIC_BASE_URL" not in env and "ANTHROPIC_AUTH_TOKEN" not in env
assert d["model"]=="keep-me"
PY2
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py" off 2>/dev/null
grep -q '^model_provider' "$HOME/.codex/config.toml" && fail "codex off left model_provider"
grep -q '^\[model_providers.cliproxyapi\]' "$HOME/.codex/config.toml" || fail "codex off should keep provider table"
grep -q '^model = "gpt-6-astra"' "$HOME/.codex/config.toml" || fail "codex off clobbered model"
# off twice is a no-op (no extra backup)
n_before=$(find "$HOME/.codex" -name 'config.toml.bak*' | wc -l | tr -d ' ')
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py" off 2>/dev/null
[ "$(find "$HOME/.codex" -name 'config.toml.bak*' | wc -l | tr -d ' ')" = "$n_before" ] || fail "second off created a backup"
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-claude.py" on https://new.example cpa-key-2 2>/dev/null
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-codex.py"  on https://new.example cpa-key-2 2>/dev/null
grep -q '^model_provider = "cliproxyapi"' "$HOME/.codex/config.toml" || fail "codex on didn't restore model_provider"
[ "$(grep -c 'experimental_bearer_token' "$HOME/.codex/config.toml")" = 1 ] || fail "codex on duplicated provider block"
python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["env"]; assert e["ANTHROPIC_AUTH_TOKEN"]=="cpa-key-2"' "$HOME/.claude/settings.json" || fail "claude on didn't restore"
pass "off/on round trip (claude + codex)"

# 4c. cursor writer against a minimal synthetic state DB (cursor not running in CI)
if [ "$(uname -s)" = Darwin ]; then CDB="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
else CDB="$HOME/.config/Cursor/User/globalStorage/state.vscdb"; fi
mkdir -p "$(dirname "$CDB")"
python3 - "$CDB" <<'PY2'
import json, sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
blob = {"aiSettings": {"userAddedModels": ["existing-model"], "modelOverrideEnabled": ["default"], "modelOverrideDisabled": ["g6a-max-proxy"]},
        "availableDefaultModels2": [{"name": "default", "isUserAdded": False}]}
con.execute("INSERT INTO ItemTable VALUES (?,?)", ("src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser", json.dumps(blob)))
con.commit()
PY2
[ "$(PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-cursor.py" status)" = unset ] || fail "cursor status should be unset"
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-cursor.py" on https://new.example g6a-max-proxy g6a-high-proxy 2>/dev/null
python3 - "$CDB" <<'PY2' || fail "cursor on wrote wrong state"
import json, sqlite3, sys
d = json.loads(sqlite3.connect(sys.argv[1]).execute("SELECT value FROM ItemTable").fetchone()[0])
ai = d["aiSettings"]
assert d["openAIBaseUrl"] == "https://new.example/v1" and d["useOpenAIKey"] is True
assert ai["userAddedModels"] == ["existing-model", "g6a-max-proxy", "g6a-high-proxy"]
assert "g6a-max-proxy" in ai["modelOverrideEnabled"] and "g6a-max-proxy" not in ai["modelOverrideDisabled"]
recs = {m["name"]: m for m in d["availableDefaultModels2"]}
assert recs["g6a-max-proxy"]["isUserAdded"] and recs["g6a-max-proxy"]["serverModelName"] == "g6a-max-proxy"
assert "default" in recs
PY2
[ -f "$CDB.applicationUser.bak" ] || fail "cursor row backup missing"
[ "$(PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-cursor.py" status)" = proxy ] || fail "cursor status should be proxy"
PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-cursor.py" off 2>/dev/null
[ "$(PYTHONPATH="$ROOT/lib" python3 "$ROOT/lib/client-cursor.py" status)" = direct ] || fail "cursor status should be direct after off"
pass "cursor writer (on/off/status, + row backup)"

# 5. config render + key add
export CPA_DRY_RUN=0
CFG="$SANDBOX/cliproxyapi.conf"
bash -c '
  set -e; . "$CPA_HOME/lib/common.sh"; . "$CPA_HOME/lib/config.sh"
  CPA_CONFIG_FILE="'"$CFG"'"
  config_render cpa-first-key 2>/dev/null
  grep -q "^  - \"cpa-first-key\"" "$CPA_CONFIG_FILE"
  grep -q "^oauth-model-alias:" "$CPA_CONFIG_FILE"
  k=$(key_add); [[ "$k" == cpa-* ]] || exit 1
  [ "$(grep -c "^  - \"cpa-" "$CPA_CONFIG_FILE")" = 2 ] || exit 1
  [ -f "$CPA_CONFIG_FILE.bak" ] || exit 1
  # sync-aliases leaves the api-keys alone and keeps exactly one managed region
  config_sync_aliases 2>/dev/null
  [ "$(grep -c "cpa-managed aliases" "$CPA_CONFIG_FILE")" = 2 ] || exit 1
  grep -q "\"$k\"" "$CPA_CONFIG_FILE"
' || fail "config render / key add / sync-aliases"
pass "config render, key add, sync-aliases"

rm -rf "$SANDBOX" /tmp/cpa-aliases.yaml /tmp/cpa-bad.tsv
echo "all smoke tests passed"

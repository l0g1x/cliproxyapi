# cliproxyapi

One command to run a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) server on macOS or Linux and point **Claude Code**, **Codex**, and **Cursor** at it — with a curated set of model aliases that bake a thinking-effort level into the model name.

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash
```

Then, in a new shell:

```sh
auth-claude      # OAuth into your Claude subscription
auth-codex       # OAuth into your ChatGPT/Codex subscription
cpa doctor       # everything green?
```

That's it. Claude Code and Codex are already configured. Cursor needs one minute of clicking — see [Cursor](#cursor).

## What it does

- **Server** — macOS: `brew install cliproxyapi` + `brew services` (launchd). Linux: Docker Compose (`eceasy/cli-proxy-api`), bound to `127.0.0.1:8317`, with an optional ngrok tunnel.
- **Config** — renders a minimal `config.yaml` (fill-first routing, session affinity, one generated API key) plus the [aliases](#model-aliases).
- **Clients** — writes the base URL and API key into `~/.claude/settings.json` and `~/.codex/config.toml`; prints what to paste into Cursor.
- **Shell** — installs the `auth-claude`, `auth-codex`, `cliproxyapi-restart`, … aliases.
- **Backups** — every file it touches gets a `.bak` first. Details [below](#what-gets-modified).

## Install modes

**Server** (default) — installs and starts the proxy on this machine and points the clients at `http://127.0.0.1:8317`:

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash
```

**Client only** — no server; point this machine's clients at a proxy running elsewhere (a home server behind ngrok, a VPS over an SSH tunnel, …):

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash -s -- \
  --client --base-url https://proxy.example.com --api-key <key from the server>
```

Options: `--clients claude,codex` to skip some, `--dry-run` to preview every change without writing, `--yes` to skip prompts, `--force-config` to re-render the server config from the template.

Re-running the installer is safe: it updates the repo, keeps your config, re-syncs aliases, and rewrites client files only if their content would actually change.

## What gets modified

| File | Change | Backup |
|---|---|---|
| macOS `/opt/homebrew/etc/cliproxyapi.conf`<br>Linux `~/cliproxyapi/config.yaml` | Rendered from `config/config.template.yaml` on first install; afterwards only the `# >>> cpa-managed aliases` region is rewritten | `<file>.bak` |
| Linux `~/cliproxyapi/docker-compose.yml` | Copied from `config/docker-compose.yml` | `<file>.bak` |
| `~/.claude/settings.json` | Sets `env.ANTHROPIC_BASE_URL` and `env.ANTHROPIC_AUTH_TOKEN`; every other key untouched | `<file>.bak` |
| `~/.codex/config.toml` | Sets top-level `model_provider = "cliproxyapi"` and replaces/appends the `[model_providers.cliproxyapi]` table; your `model`, `model_reasoning_effort`, projects, MCP servers, etc. are untouched | `<file>.bak` |
| `~/.zshrc` or `~/.bashrc` | Appends one line that sources `shell/aliases.sh` | `<file>.bak` |
| `~/.config/cliproxyapi/env` | New file: mode, base URL, API key (`0600`) | — |

Backup policy: the **first** time a file is modified it gets `<file>.bak` — a pristine copy that is never overwritten. Later modifications get `<file>.bak.<timestamp>`. If the new content is byte-identical, nothing is written and no backup is made. `cpa uninstall` restores the client files from `.bak`.

## Model aliases

The proxy serves every model your OAuth accounts have access to under their real names. On top of that, `config/aliases.tsv` adds **extra** names that map to a base model with a thinking-effort level pre-applied. Base models are never renamed or hidden.

Why: Cursor can't set thinking effort per request, so the effort lives in the alias name. Pick `f51-high-proxy` in Cursor's model picker and you get Claude Fable 5.1 at high effort.

| Base model | Aliases |
|---|---|
| `claude-fable-5-1` | `f51-proxy` (client decides effort) · `f51-low-proxy` · `f51-medium-proxy` · `f51-high-proxy` · `f51-max-proxy` · `claude-fable-5-1[1m]` |
| `gpt-6-astra` | `g6a-proxy` · `g6a-low-proxy` · `g6a-medium-proxy` · `g6a-high-proxy` · `g6a-xhigh-proxy` · `g6a-max-proxy` |
| `claude-opus-5` | `o5-proxy` · `claude-opus-5[1m]` |
| `claude-sonnet-5` | `s5-proxy` |

Valid effort levels (verified against the upstream APIs): Claude `low | medium | high | max`; Codex `low | medium | high | xhigh | max`.

To add or change one: edit `config/aliases.tsv`, then

```sh
cpa config sync-aliases && cliproxyapi-restart && cpa models
```

`sync-aliases` rewrites only the managed region of the config, so anything you've hand-edited elsewhere survives. The TSV is validated (duplicate aliases and invalid effort levels are rejected).

## Cursor

Cursor stores its base URL and model list in an opaque SQLite blob and the API key in encrypted storage, so `cpa` doesn't write to it. `cpa cursor` prints exactly what to enter:

```
Cursor Settings → Models   (⌘⇧J)
  1. OpenAI API Key:              <your key>
  2. ☑ Override OpenAI Base URL:  http://127.0.0.1:8317/v1   → Verify
  3. Model Names → + Add Model:   f51-high-proxy, g6a-xhigh-proxy, …
```

Two known Cursor quirks: it occasionally unticks "Override OpenAI Base URL" on its own (re-tick it), and custom base URLs power Chat/Agent only — Tab autocomplete stays on Cursor's backend.

## Commands and aliases

| Command | |
|---|---|
| `cpa install [opts]` | Full install (see above) |
| `cpa server start\|stop\|restart\|status\|logs\|upgrade` | Manage the service |
| `cpa auth claude\|codex` | OAuth login |
| `cpa clients [claude\|codex\|cursor] [--base-url U] [--api-key K]` | (Re)configure clients |
| `cpa cursor` | Print the Cursor settings |
| `cpa key` | Print the primary API key |
| `cpa key add` | Generate and register a new API key; prints only the key |
| `cpa url` | Print the base URL |
| `cpa models` | List served models, base vs. alias |
| `cpa config render\|sync-aliases\|path\|show` | Config management (`show` masks secrets) |
| `cpa doctor` | Health check: service, API, every alias served, client configs match |
| `cpa uninstall` | Restore client files from `.bak`, remove the shell hook |

Shell aliases (from `shell/aliases.sh`):

| Alias | Runs |
|---|---|
| `auth-claude` | `cpa auth claude` |
| `auth-codex` | `cpa auth codex` |
| `cliproxyapi-restart` | `cpa server restart` |
| `cliproxyapi-logs` | `cpa server logs` |
| `cliproxyapi-status` | `cpa server status` |
| `cliproxyapi-models` | `cpa models` |
| `cliproxyapi` (Linux only) | runs the binary inside the container; macOS gets it from brew |

Scripting: `cpa key` and `cpa url` print only the value, so `cpa clients --api-key "$(cpa key add)"` works.

## Remote access

**ngrok (Linux)** — add to `~/.config/cliproxyapi/env` before running `cpa install` (or `cpa server install`):

```
CPA_NGROK_AUTHTOKEN=<token>
CPA_NGROK_DOMAIN=yourname.ngrok.dev
```

This renders `~/cliproxyapi/ngrok/ngrok.yml` and enables the `ngrok` compose profile. Other machines then use client mode with `--base-url https://yourname.ngrok.dev`.

**SSH tunnel** — `ssh -L 8317:localhost:8317 server` and use `--base-url http://127.0.0.1:8317`.

### Claude OAuth on a headless Linux server

Claude's OAuth callback goes to `localhost:1455`, which the compose file binds on the server's loopback. From your laptop:

```sh
ssh -L 1455:localhost:1455 server     # keep this open
# on the server:
auth-claude                           # prints a URL — open it in the laptop's browser
```

Codex uses a device-code flow and needs no tunnel.

## Layout

```
bin/cpa                  CLI entry point (bash)
lib/common.sh            logging, paths, backup_file / write_if_changed
lib/config.sh            render config, sync aliases, key add
lib/render_aliases.py    aliases.tsv → YAML block (validates)
lib/server-mac.sh        brew + brew services
lib/server-linux.sh      docker compose
lib/clients.sh           client orchestration + Cursor printout
lib/client-claude.py     ~/.claude/settings.json writer
lib/client-codex.py      ~/.codex/config.toml writer
lib/cpa_backup.py        backup policy for the Python writers
lib/doctor.sh            health checks
config/config.template.yaml
config/aliases.tsv       ← the one file you'll edit
config/docker-compose.yml
config/ngrok.template.yml
shell/aliases.sh         sourced from your rc file
test/smoke.sh            offline tests (bash test/smoke.sh)
```

Requirements: `bash`, `python3` (stdlib only), `curl`, `git`; plus Homebrew on macOS or Docker on Linux.

## License

MIT

# cliproxyapi

One command to run a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) server on macOS or Linux and point **Claude Code**, **Codex**, and **Cursor** at it — with a curated set of model aliases that bake a thinking-effort level into the model name.

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash
```

Then, in a new shell:

```sh
auth-claude      # OAuth into your Claude subscription
auth-codex       # OAuth into your ChatGPT/Codex subscription
cpa on           # route Claude Code + Codex through the proxy
cpa doctor       # everything green?
```

Install is deliberately hands-off: it sets up the server and shell aliases but **does not change how your tools connect** until you run `cpa on`. Cursor needs one minute of clicking — see [Cursor](#cursor).

## What it does

- **Server** — Docker Compose (`eceasy/cli-proxy-api`) on macOS and Linux alike, bound to `127.0.0.1:8317`, with an optional ngrok tunnel. Layout: `~/cliproxyapi/{docker-compose.yml,config.yaml,auths/,logs/}`. An existing Homebrew install on macOS is adopted (config + OAuth files copied, brew service stopped).
- **Config** — renders a minimal `config.yaml` (fill-first routing, session affinity, one generated API key) plus the [aliases](#model-aliases).
- **Clients** — on `cpa on`, writes the base URL and API key into `~/.claude/settings.json` and `~/.codex/config.toml`, and prints what to paste into Cursor. `cpa off` reverts.
- **Shell** — installs the `auth-claude`, `auth-codex`, `proxy-on`, `proxy-off`, `cliproxyapi-restart`, … aliases.
- **Backups** — every file it touches gets a `.bak` first. Details [below](#what-gets-modified).

## Install modes

**Server** (default) — installs and starts the proxy on this machine and points the clients at `http://127.0.0.1:8317`:

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash
```

**Client only** — no server; record the address of a proxy running elsewhere (a home server behind ngrok, a VPS over an SSH tunnel, …), then `cpa on`:

```sh
curl -fsSL https://raw.githubusercontent.com/l0g1x/cliproxyapi/main/install.sh | bash -s -- \
  --client --base-url https://proxy.example.com --api-key <key from the server>
cpa on
```

Options: `--on` to route immediately instead of waiting for `cpa on` (with `--clients claude,codex` to pick a subset), `--dry-run` to preview every change without writing, `--yes` to skip prompts, `--force-config` to re-render the server config from the template.

Re-running the installer is safe: it updates the repo, keeps your config, re-syncs aliases, and rewrites client files only if their content would actually change.

## Turning the proxy off and on

Sometimes you want requests to go straight to Anthropic / OpenAI again — the proxy is down, you're debugging, or you want your subscription's native behavior. Two commands, no reinstall:

```sh
proxy-off        # cpa off  — Claude Code and Codex talk to their providers directly
proxy-on         # cpa on   — back through the proxy, same URL and key as before
proxy-status     # cpa status — what each client is actually doing right now
```

What `off` does: Claude Code loses `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` and falls back to its own login; Codex loses the `model_provider = "cliproxyapi"` line and falls back to ChatGPT auth (the `[model_providers.cliproxyapi]` table stays behind, inert, so `on` is instant). Cursor gets a one-line instruction to untick the override. Everything else in those files — your model choice, effort level, permissions, MCP servers — is untouched, and the usual `.bak` policy applies.

Both accept a client list: `cpa off codex` leaves Claude Code on the proxy. `cpa status` reads the real files, so it tells the truth even if you edited them by hand.

## What gets modified

| File | Change | Backup |
|---|---|---|
| `~/cliproxyapi/config.yaml` | Rendered from `config/config.template.yaml` on first install (or adopted from a Homebrew install on macOS); afterwards only the `# >>> cpa-managed aliases` region is rewritten | `<file>.bak` |
| `~/cliproxyapi/docker-compose.yml` | Copied from `config/docker-compose.yml` | `<file>.bak` |
| `~/.claude/settings.json` (on `cpa on`) | Sets `env.ANTHROPIC_BASE_URL` and `env.ANTHROPIC_AUTH_TOKEN`; every other key untouched | `<file>.bak` |
| `~/.codex/config.toml` (on `cpa on`) | Sets top-level `model_provider = "cliproxyapi"` and replaces/appends the `[model_providers.cliproxyapi]` table; your `model`, `model_reasoning_effort`, projects, MCP servers, etc. are untouched | `<file>.bak` |
| Cursor `state.vscdb` (on `cpa on cursor`) | Sets `openAIBaseUrl`, `useOpenAIKey`, adds aliases to the model list | affected row → `state.vscdb.applicationUser.bak` |
| `~/.zshrc` or `~/.bashrc` | Appends one line that sources `shell/aliases.sh` | `<file>.bak` |
| `~/.config/cliproxyapi/env` | New file: mode, base URL, API key, ngrok settings (`0600`) | — |

Backup policy: the **first** time a file is modified it gets `<file>.bak` — a pristine copy that is never overwritten. Later modifications get `<file>.bak.<timestamp>`. If the new content is byte-identical, nothing is written and no backup is made. `cpa uninstall` restores the client files from `.bak`.

## Model aliases

The proxy serves every model your OAuth accounts have access to under their real names. On top of that, `config/aliases.tsv` adds **extra** names that map to a base model with a thinking-effort level pre-applied. Base models are never renamed or hidden.

Why: Cursor can't set thinking effort per request, so the effort lives in the alias name. Pick `f51-high-proxy` in Cursor's model picker and you get Claude Fable 5.1 at high effort.

| Base model | Aliases |
|---|---|
| `claude-fable-5-1` | `f51-proxy` (client decides effort) · `f51-low-proxy` · `f51-medium-proxy` · `f51-high-proxy` · `f51-max-proxy` · `claude-fable-5-1[1m]` |
| `gpt-6-astra` | `g6a-proxy` · `g6a-low-proxy` · `g6a-medium-proxy` · `g6a-high-proxy` · `g6a-xhigh-proxy` · `g6a-max-proxy` · `g6a-max-fast-proxy` (max effort + Codex Fast mode — ~1.2× generation speed at ~2.4× quota) |
| `claude-opus-5` | `o5-proxy` · `claude-opus-5[1m]` |
| `claude-sonnet-5` | `s5-proxy` |

Valid effort levels (verified against the upstream APIs): Claude `low | medium | high | max`; Codex `low | medium | high | xhigh | max`. Codex rows take an optional fifth column for `service_tier` (`fast | priority | flex`); `fast` is rendered as the wire value `priority`, since the `/v1/chat/completions` path Cursor uses doesn't translate it.

To add or change one: edit `config/aliases.tsv`, then

```sh
cpa config sync-aliases && cliproxyapi-restart && cpa models
```

`sync-aliases` rewrites only the managed region of the config, so anything you've hand-edited elsewhere survives. The TSV is validated (duplicate aliases and invalid effort levels are rejected).

## Cursor

`cpa on cursor` sets everything Cursor needs except the API key:

- ☑ Override OpenAI Base URL → `<proxy>/v1`
- Model Names → every alias whose upstream this proxy serves (e.g. only `g6a-*` on a Codex-only box)

Cursor stores those in its state database, which `cpa` edits directly (after quitting Cursor, then relaunching it). The **API key** is the one thing it can't write: Cursor encrypts it with a password kept in the login Keychain, which is only available to the GUI session. So `cpa on cursor` ends by printing the key for you to paste once:

```
Cursor Settings → Models → OpenAI API Key   (⌘⇧J)
```

After that, pick e.g. `g6a-max-proxy` in the chat model dropdown. `cpa off cursor` unticks the override; `cpa cursor` prints the manual steps without changing anything.

Cursor is opt-in for `cpa on` / `cpa off` (it isn't in the default client list) because switching it restarts the app. Two known Cursor quirks: it occasionally unticks the override on its own (`cpa on cursor` re-ticks it), and custom base URLs power Chat/Agent only — Tab autocomplete stays on Cursor's backend.

## Commands and aliases

| Command | |
|---|---|
| `cpa install [opts]` | Full install (see above) |
| `cpa on [claude\|codex\|cursor]` | Route through the proxy (default: claude + codex) |
| `cpa off [claude\|codex\|cursor]` | Route directly to the providers |
| `cpa status` | Current routing per client |
| `cpa server start\|stop\|restart\|status\|logs\|upgrade\|version` | Manage the container |
| `cpa auth claude\|codex` | OAuth login |
| `cpa clients [claude\|codex\|cursor] [--base-url U] [--api-key K]` | (Re)configure clients |
| `cpa cursor` | Print the Cursor settings without changing anything |
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
| `proxy-on` / `proxy-off` / `proxy-status` | `cpa on` / `cpa off` / `cpa status` |
| `cliproxyapi-restart` | `cpa server restart` |
| `cliproxyapi-logs` | `cpa server logs` |
| `cliproxyapi-status` | `cpa server status` |
| `cliproxyapi-models` | `cpa models` |
| `cliproxyapi` | runs the binary inside the container (`cpa server exec`) |

Scripting: `cpa key` and `cpa url` print only the value, so `cpa clients --api-key "$(cpa key add)"` works.

## Remote access

**ngrok** — pass it at install time (it's remembered in `~/.config/cliproxyapi/env`):

```sh
cpa install --ngrok-domain yourname.ngrok.dev --ngrok-authtoken <token>
```

This renders `~/cliproxyapi/ngrok/ngrok.yml`, enables the `ngrok` compose profile, and makes `https://yourname.ngrok.dev` the base URL that `cpa on` gives to clients. The proxy still requires the API key, so the public URL isn't public access.

**Cursor needs this.** Cursor's base-URL verification runs from Cursor's own servers, so `http://127.0.0.1:8317` is rejected ("access to private network is forbidden"). Claude Code and Codex are fine with localhost. Other machines can also use client mode with `--base-url https://yourname.ngrok.dev`.

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
lib/server.sh            docker compose (+ brew → docker migration on macOS)
lib/clients.sh           client orchestration + Cursor printout
lib/client-claude.py     ~/.claude/settings.json writer
lib/client-codex.py      ~/.codex/config.toml writer
lib/client-cursor.py     Cursor state.vscdb writer (all but the API key)
lib/cpa_backup.py        backup policy for the Python writers
lib/doctor.sh            health checks
config/config.template.yaml
config/aliases.tsv       ← the one file you'll edit
config/docker-compose.yml
config/ngrok.template.yml
shell/aliases.sh         sourced from your rc file
test/smoke.sh            offline tests (bash test/smoke.sh)
```

Requirements: `bash`, `python3` (stdlib only), `curl`, `git`, and Docker (Docker Desktop / OrbStack on macOS, `get.docker.com` on Linux).

## License

MIT

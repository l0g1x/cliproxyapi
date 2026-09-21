#!/usr/bin/env python3
"""Route Claude Code through the proxy, or back to direct access, by editing
~/.claude/settings.json. Every other key is preserved verbatim.

  client-claude.py on <base-url> <api-key> [--dry-run]
      sets env.ANTHROPIC_BASE_URL and env.ANTHROPIC_AUTH_TOKEN
  client-claude.py off [--dry-run]
      removes both, so Claude Code uses its own login again
"""
import json
import os
import sys

from cpa_backup import info, write_if_changed

SETTINGS = os.path.expanduser("~/.claude/settings.json")
KEYS = ("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN")


def load():
    if not os.path.exists(SETTINGS):
        return {}
    with open(SETTINGS, encoding="utf-8") as fh:
        return json.load(fh)


def save(data, dry):
    write_if_changed(SETTINGS, json.dumps(data, indent=2) + "\n", dry_run=dry)


def on(base_url, api_key, dry):
    data = load()
    env = data.setdefault("env", {})
    env["ANTHROPIC_BASE_URL"] = base_url
    env["ANTHROPIC_AUTH_TOKEN"] = api_key
    # An empty ANTHROPIC_API_KEY placeholder would shadow the auth token.
    if env.get("ANTHROPIC_API_KEY") == "":
        env.pop("ANTHROPIC_API_KEY")
    save(data, dry)


def off(dry):
    data = load()
    env = data.get("env")
    if not env or not any(k in env for k in KEYS):
        info(f"Claude Code already direct: {SETTINGS}")
        return
    for k in KEYS:
        env.pop(k, None)
    if not env:
        data.pop("env")
    save(data, dry)


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if args[:1] == ["on"] and len(args) == 3:
        on(args[1].rstrip("/"), args[2], dry)
    elif args == ["off"]:
        off(dry)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

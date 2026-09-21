#!/usr/bin/env python3
"""Point Claude Code at the proxy: sets env.ANTHROPIC_BASE_URL / env.ANTHROPIC_AUTH_TOKEN
in ~/.claude/settings.json. Every other key is preserved verbatim.

Usage: client-claude.py <base-url> <api-key> [--dry-run]
"""
import json
import os
import sys

from cpa_backup import write_if_changed

SETTINGS = os.path.expanduser("~/.claude/settings.json")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    base_url, api_key = sys.argv[1].rstrip("/"), sys.argv[2]
    dry = "--dry-run" in sys.argv

    data = {}
    if os.path.exists(SETTINGS):
        with open(SETTINGS, encoding="utf-8") as fh:
            data = json.load(fh)

    env = data.setdefault("env", {})
    env["ANTHROPIC_BASE_URL"] = base_url
    env["ANTHROPIC_AUTH_TOKEN"] = api_key
    # An API key here would take precedence over the auth token; only clear it if it was a placeholder.
    if env.get("ANTHROPIC_API_KEY", None) == "":
        env.pop("ANTHROPIC_API_KEY")

    write_if_changed(SETTINGS, json.dumps(data, indent=2) + "\n", dry_run=dry)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Route Codex CLI/app through the proxy, or back to OpenAI directly, by editing
~/.codex/config.toml line-by-line (no TOML library, so comments and formatting
elsewhere survive). `model` and `model_reasoning_effort` are yours — untouched.

  client-codex.py on <base-url> <api-key> [--dry-run]
      1. top-level  model_provider = "cliproxyapi"   (replaced in place, or inserted at the top)
      2. section    [model_providers.cliproxyapi]     (replaced wholesale, or appended)
  client-codex.py off [--dry-run]
      removes the top-level model_provider line. The provider table is left in place
      (inert without model_provider), so `on` is cheap and your key isn't lost.
"""
import os
import re
import sys

from cpa_backup import info, write_if_changed

CONFIG = os.path.expanduser("~/.codex/config.toml")
HEADER = "[model_providers.cliproxyapi]"
IS_HEADER = re.compile(r"^\s*\[")
MODEL_PROVIDER = re.compile(r"^\s*model_provider\s*=")


def load():
    if not os.path.exists(CONFIG):
        return []
    with open(CONFIG, encoding="utf-8") as fh:
        return fh.read().split("\n")


def save(lines, dry):
    content = "\n".join(lines)
    if not content.endswith("\n"):
        content += "\n"
    write_if_changed(CONFIG, content, dry_run=dry)


def provider_block(base_url, api_key):
    return [
        HEADER,
        'name = "cliproxyapi"',
        f'base_url = "{base_url}/v1"',
        'wire_api = "responses"',
        f'experimental_bearer_token = "{api_key}"',
        "requires_openai_auth = true",
    ]


def top_level_end(lines):
    return next((i for i, l in enumerate(lines) if IS_HEADER.match(l)), len(lines))


def on(base_url, api_key, dry):
    lines = load()
    end = top_level_end(lines)
    idx = next((i for i in range(end) if MODEL_PROVIDER.match(lines[i])), None)
    if idx is None:
        lines.insert(0, 'model_provider = "cliproxyapi"')
    else:
        lines[idx] = 'model_provider = "cliproxyapi"'

    start = next((i for i, l in enumerate(lines) if l.strip() == HEADER), None)
    block = provider_block(base_url, api_key)
    if start is None:
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", *block, ""]
    else:
        stop = next((i for i in range(start + 1, len(lines)) if IS_HEADER.match(lines[i])), len(lines))
        lines[start:stop] = block + [""]
    save(lines, dry)


def off(dry):
    lines = load()
    end = top_level_end(lines)
    idx = next((i for i in range(end) if MODEL_PROVIDER.match(lines[i])), None)
    if idx is None:
        info(f"Codex already direct: {CONFIG}")
        return
    del lines[idx]
    save(lines, dry)


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

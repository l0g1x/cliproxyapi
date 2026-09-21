#!/usr/bin/env python3
"""Point Codex CLI/app at the proxy by editing ~/.codex/config.toml line-by-line
(no TOML library, so comments and formatting elsewhere survive):

  1. top-level  model_provider = "cliproxyapi"   (replaced in place, or inserted at the top)
  2. section    [model_providers.cliproxyapi]     (replaced wholesale, or appended)

`model` and `model_reasoning_effort` are yours — untouched.

Usage: client-codex.py <base-url> <api-key> [--dry-run]
"""
import os
import re
import sys

from cpa_backup import write_if_changed

CONFIG = os.path.expanduser("~/.codex/config.toml")
HEADER = "[model_providers.cliproxyapi]"


def provider_block(base_url, api_key):
    return [
        HEADER,
        'name = "cliproxyapi"',
        f'base_url = "{base_url}/v1"',
        'wire_api = "responses"',
        f'experimental_bearer_token = "{api_key}"',
        "requires_openai_auth = true",
    ]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    base_url, api_key = sys.argv[1].rstrip("/"), sys.argv[2]
    dry = "--dry-run" in sys.argv

    lines = []
    if os.path.exists(CONFIG):
        with open(CONFIG, encoding="utf-8") as fh:
            lines = fh.read().split("\n")

    is_header = re.compile(r"^\s*\[")
    first_header = next((i for i, l in enumerate(lines) if is_header.match(l)), len(lines))

    # 1. model_provider in the top-level (pre-header) region
    mp = re.compile(r"^\s*model_provider\s*=")
    idx = next((i for i in range(first_header) if mp.match(lines[i])), None)
    if idx is None:
        lines.insert(0, 'model_provider = "cliproxyapi"')
        first_header += 1
    else:
        lines[idx] = 'model_provider = "cliproxyapi"'

    # 2. provider section
    start = next((i for i, l in enumerate(lines) if l.strip() == HEADER), None)
    block = provider_block(base_url, api_key)
    if start is None:
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", *block, ""]
    else:
        end = next((i for i in range(start + 1, len(lines)) if is_header.match(lines[i])), len(lines))
        # keep a trailing blank line inside the region so the next section stays separated
        lines[start:end] = block + [""]

    content = "\n".join(lines)
    if not content.endswith("\n"):
        content += "\n"
    write_if_changed(CONFIG, content, dry_run=dry)


if __name__ == "__main__":
    main()

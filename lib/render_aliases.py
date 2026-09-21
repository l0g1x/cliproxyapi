#!/usr/bin/env python3
"""Render the cpa-managed YAML block (oauth-model-alias + payload.override) from aliases.tsv.

Usage: render_aliases.py <aliases.tsv>            -> YAML block on stdout
       render_aliases.py <aliases.tsv> --list     -> one alias per line (for doctor/tests)
Stdlib only. Exits 1 on duplicate aliases or bad effort levels.
"""
import sys

CHANNEL_EFFORTS = {
    "claude": {"low", "medium", "high", "max"},
    "codex": {"low", "medium", "high", "xhigh", "max"},
}


def parse(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                sys.exit(f"{path}:{n}: expected 4 tab-separated columns, got {len(parts)}")
            channel, upstream, alias, effort = (p.strip() for p in parts)
            if channel not in CHANNEL_EFFORTS:
                sys.exit(f"{path}:{n}: unknown channel {channel!r}")
            if effort != "-" and effort not in CHANNEL_EFFORTS[channel]:
                sys.exit(f"{path}:{n}: effort {effort!r} not valid for {channel} "
                         f"(valid: {sorted(CHANNEL_EFFORTS[channel])})")
            if alias == upstream:
                sys.exit(f"{path}:{n}: alias must differ from upstream name ({alias})")
            rows.append((channel, upstream, alias, effort))
    seen = {}
    for _, _, alias, _ in rows:
        if alias in seen:
            sys.exit(f"duplicate alias {alias!r}")
        seen[alias] = True
    return rows


def q(s):
    return '"' + s.replace('"', '\\"') + '"'


def render(rows):
    out = ["oauth-model-alias:"]
    for channel in ("claude", "codex"):
        chan_rows = [r for r in rows if r[0] == channel]
        if not chan_rows:
            continue
        out.append(f"  {channel}:")
        for _, upstream, alias, _ in chan_rows:
            out += [f"    - name: {q(upstream)}",
                    f"      alias: {q(alias)}",
                    "      fork: true",
                    "      force-mapping: true"]
    overrides = [r for r in rows if r[3] != "-"]
    if overrides:
        out.append("payload:")
        out.append("  override:")
        for channel, _, alias, effort in overrides:
            out += ["    - models:",
                    f"        - name: {q(alias)}",
                    f"          protocol: {q(channel)}",
                    "      params:"]
            if channel == "claude":
                out += ['        "thinking.type": "adaptive"',
                        f'        "output_config.effort": {q(effort)}']
            else:
                out += [f'        "reasoning.effort": {q(effort)}']
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rows = parse(sys.argv[1])
    if "--list" in sys.argv:
        print("\n".join(r[2] for r in rows))
    else:
        print(render(rows))


if __name__ == "__main__":
    main()

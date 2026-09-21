#!/usr/bin/env python3
"""Render the cpa-managed YAML block (oauth-model-alias + payload.override) from aliases.tsv.

Usage: render_aliases.py <aliases.tsv>            -> YAML block on stdout
       render_aliases.py <aliases.tsv> --list     -> one alias per line (for doctor/tests)
       render_aliases.py <aliases.tsv> --pairs    -> "<upstream>\t<alias>" per line
Stdlib only. Exits 1 on duplicate aliases, bad effort levels, or bad tiers.
"""
import sys

CHANNEL_EFFORTS = {
    "claude": {"low", "medium", "high", "max"},
    "codex": {"low", "medium", "high", "xhigh", "max"},
}
CHANNEL_TIERS = {
    "claude": set(),
    "codex": {"fast", "priority", "flex"},
}


class Row:
    __slots__ = ("channel", "upstream", "alias", "effort", "tier")

    def __init__(self, channel, upstream, alias, effort, tier):
        self.channel, self.upstream, self.alias, self.effort, self.tier = channel, upstream, alias, effort, tier

    @property
    def has_override(self):
        return self.effort != "-" or self.tier != "-"


def parse(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("\t")]
            if len(parts) == 4:
                parts.append("-")
            if len(parts) != 5:
                sys.exit(f"{path}:{n}: expected 4 or 5 tab-separated columns, got {len(parts)}")
            channel, upstream, alias, effort, tier = parts
            if channel not in CHANNEL_EFFORTS:
                sys.exit(f"{path}:{n}: unknown channel {channel!r}")
            if effort != "-" and effort not in CHANNEL_EFFORTS[channel]:
                sys.exit(f"{path}:{n}: effort {effort!r} not valid for {channel} "
                         f"(valid: {sorted(CHANNEL_EFFORTS[channel])})")
            if tier != "-" and tier not in CHANNEL_TIERS[channel]:
                sys.exit(f"{path}:{n}: tier {tier!r} not valid for {channel} "
                         f"(valid: {sorted(CHANNEL_TIERS[channel]) or 'none'})")
            if alias == upstream:
                sys.exit(f"{path}:{n}: alias must differ from upstream name ({alias})")
            rows.append(Row(channel, upstream, alias, effort, tier))
    seen = set()
    for r in rows:
        if r.alias in seen:
            sys.exit(f"duplicate alias {r.alias!r}")
        seen.add(r.alias)
    return rows


def q(s):
    return '"' + s.replace('"', '\\"') + '"'


def render(rows):
    out = ["oauth-model-alias:"]
    for channel in ("claude", "codex"):
        chan_rows = [r for r in rows if r.channel == channel]
        if not chan_rows:
            continue
        out.append(f"  {channel}:")
        for r in chan_rows:
            out += [f"    - name: {q(r.upstream)}",
                    f"      alias: {q(r.alias)}",
                    "      fork: true",
                    "      force-mapping: true"]
    overrides = [r for r in rows if r.has_override]
    if overrides:
        out.append("payload:")
        out.append("  override:")
        for r in overrides:
            out += ["    - models:",
                    f"        - name: {q(r.alias)}",
                    f"          protocol: {q(r.channel)}",
                    "      params:"]
            if r.channel == "claude":
                if r.effort != "-":
                    out += ['        "thinking.type": "adaptive"',
                            f'        "output_config.effort": {q(r.effort)}']
            else:
                if r.effort != "-":
                    out.append(f'        "reasoning.effort": {q(r.effort)}')
                if r.tier != "-":
                    out.append(f'        "service_tier": {q(r.tier)}')
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rows = parse(sys.argv[1])
    if "--list" in sys.argv:
        print("\n".join(r.alias for r in rows))
    elif "--pairs" in sys.argv:
        print("\n".join(f"{r.upstream}\t{r.alias}" for r in rows))
    else:
        print(render(rows))


if __name__ == "__main__":
    main()

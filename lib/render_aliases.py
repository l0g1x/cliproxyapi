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
# Wire values. Codex CLI's "fast" is a display name; the API field is service_tier: "priority".
# The proxy only translates fast->priority on /v1/responses, not on /v1/chat/completions (Cursor),
# so we must emit the wire value ourselves.
TIER_WIRE = {"fast": "priority"}

# `set` directives: extra managed config emitted alongside the aliases.
SETTINGS = {
    # Version the proxy claims to be when impersonating Claude Code. Anthropic gates new models on
    # a minimum Claude Code version; upstream's baked-in default lags new releases.
    "claude-code-version",
}


class Row:
    __slots__ = ("channel", "upstream", "wire", "alias", "effort", "tier")

    def __init__(self, channel, upstream, wire, alias, effort, tier):
        self.channel, self.upstream, self.wire = channel, upstream, wire
        self.alias, self.effort, self.tier = alias, effort, tier

    @property
    def has_override(self):
        return self.effort != "-" or self.tier != "-" or self.wire != self.upstream


def parse(path):
    rows, settings = [], {}
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("\t")]
            if parts[0] == "set":
                if len(parts) != 3:
                    sys.exit(f"{path}:{n}: expected 'set<TAB>key<TAB>value'")
                if parts[1] not in SETTINGS:
                    sys.exit(f"{path}:{n}: unknown setting {parts[1]!r} (valid: {sorted(SETTINGS)})")
                settings[parts[1]] = parts[2]
                continue
            if len(parts) == 4:
                parts.append("-")
            if len(parts) != 5:
                sys.exit(f"{path}:{n}: expected 4 or 5 tab-separated columns, got {len(parts)}")
            channel, upstream, alias, effort, tier = parts
            if channel not in CHANNEL_EFFORTS:
                sys.exit(f"{path}:{n}: unknown channel {channel!r}")
            # "catalog>wire": route via a model the proxy's catalog knows, but send `wire` upstream.
            # Bridges the gap until the proxy's model catalog learns a newly released model.
            wire = upstream
            if ">" in upstream:
                upstream, wire = (p.strip() for p in upstream.split(">", 1))
                if channel != "claude":
                    sys.exit(f"{path}:{n}: catalog>wire is only verified for the claude channel")
                if not upstream or not wire or upstream == wire:
                    sys.exit(f"{path}:{n}: bad catalog>wire spec {parts[1]!r}")
            if effort != "-" and effort not in CHANNEL_EFFORTS[channel]:
                sys.exit(f"{path}:{n}: effort {effort!r} not valid for {channel} "
                         f"(valid: {sorted(CHANNEL_EFFORTS[channel])})")
            if tier != "-" and tier not in CHANNEL_TIERS[channel]:
                sys.exit(f"{path}:{n}: tier {tier!r} not valid for {channel} "
                         f"(valid: {sorted(CHANNEL_TIERS[channel]) or 'none'})")
            if alias in (upstream, wire):
                sys.exit(f"{path}:{n}: alias must differ from upstream name ({alias})")
            rows.append(Row(channel, upstream, wire, alias, effort, tier))
    seen = set()
    for r in rows:
        if r.alias in seen:
            sys.exit(f"duplicate alias {r.alias!r}")
        seen.add(r.alias)
    return rows, settings


def q(s):
    return '"' + s.replace('"', '\\"') + '"'


def render(rows, settings):
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
            if r.wire != r.upstream:
                out.append(f"        model: {q(r.wire)}")
            if r.channel == "claude":
                if r.effort != "-":
                    out += ['        "thinking.type": "adaptive"',
                            f'        "output_config.effort": {q(r.effort)}']
            else:
                if r.effort != "-":
                    out.append(f'        "reasoning.effort": {q(r.effort)}')
                if r.tier != "-":
                    out.append(f'        "service_tier": {q(TIER_WIRE.get(r.tier, r.tier))}')
    if "claude-code-version" in settings:
        out += ["claude-header-defaults:",
                f"  user-agent: {q('claude-cli/' + settings['claude-code-version'] + ' (external, cli)')}"]
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rows, settings = parse(sys.argv[1])
    if "--list" in sys.argv:
        print("\n".join(r.alias for r in rows))
    elif "--pairs" in sys.argv:
        print("\n".join(f"{r.upstream}\t{r.alias}" for r in rows))
    else:
        print(render(rows, settings))


if __name__ == "__main__":
    main()

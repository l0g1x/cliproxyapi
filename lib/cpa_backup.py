"""Backup + write helpers shared by the Python client writers.

Mirrors lib/common.sh: first modification of a file produces <file>.bak (pristine copy,
never overwritten); later ones produce <file>.bak.<timestamp>. No write, no backup, if
the content is unchanged.
"""
import os
import shutil
import sys
import time


def log(msg):
    print(f"==> {msg}", file=sys.stderr)


def info(msg):
    print(f"    {msg}", file=sys.stderr)


def backup_file(path):
    if not os.path.exists(path):
        return
    bak = path + ".bak"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
        info(f"backup: {bak}")
    else:
        bak = f"{path}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(path, bak)
        info(f"backup: {bak}")


def write_if_changed(path, content, mode=0o600, dry_run=False):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            if fh.read() == content:
                info(f"unchanged: {path}")
                return False
    if dry_run:
        log(f"[dry-run] would write {path}")
        return True
    backup_file(path)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".cpa-tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    log(f"wrote: {path}")
    return True

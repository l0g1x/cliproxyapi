#!/usr/bin/env python3
"""Configure Cursor's "Override OpenAI Base URL" + custom model list by editing its
state database. The API key can NOT be written from here (it is encrypted with a
password held in the login Keychain, which is unavailable to non-GUI sessions), so
the caller prints it for the user to paste.

  client-cursor.py on  <base-url> <model>... [--dry-run]
      sets openAIBaseUrl=<base-url>/v1, useOpenAIKey=true, and registers each model
  client-cursor.py off [--dry-run]
      sets useOpenAIKey=false (models and URL are left in place, inert)
  client-cursor.py status
      prints one of: proxy | direct | unset

Cursor must not be running (it holds the DB open and rewrites this row on exit).
Backs up the affected row (not the multi-GB database) to <db>.applicationUser.bak.
"""
import json
import os
import platform
import sqlite3
import subprocess
import sys
import time

KEY = ("src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl"
       ".persistentStorage.applicationUser")


def db_path():
    home = os.path.expanduser("~")
    if platform.system() == "Darwin":
        return os.path.join(home, "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    return os.path.join(home, ".config/Cursor/User/globalStorage/state.vscdb")


def cursor_running():
    try:
        out = subprocess.run(["pgrep", "-x", "Cursor"], capture_output=True, text=True)
        if out.returncode == 0:
            return True
        # Linux binary is usually "cursor"
        out = subprocess.run(["pgrep", "-x", "cursor"], capture_output=True, text=True)
        return out.returncode == 0
    except FileNotFoundError:
        return False


def info(msg):
    print(f"    {msg}", file=sys.stderr)


def log(msg):
    print(f"==> {msg}", file=sys.stderr)


def load(db):
    con = sqlite3.connect(db)
    row = con.execute("SELECT value FROM ItemTable WHERE key=?", (KEY,)).fetchone()
    con.close()
    if row is None:
        sys.exit("Cursor state row not found — open Cursor once, quit it, and retry")
    return json.loads(row[0])


def save(db, data, original_raw, dry):
    new_raw = json.dumps(data)
    if new_raw == original_raw:
        info(f"unchanged: {db}")
        return
    if dry:
        log(f"[dry-run] would update Cursor state in {db}")
        return
    bak = db + ".applicationUser.bak"
    if not os.path.exists(bak):
        with open(bak, "w", encoding="utf-8") as fh:
            fh.write(original_raw)
        os.chmod(bak, 0o600)
        info(f"backup: {bak}")
    else:
        stamped = f"{bak}.{time.strftime('%Y%m%d-%H%M%S')}"
        with open(stamped, "w", encoding="utf-8") as fh:
            fh.write(original_raw)
        os.chmod(stamped, 0o600)
        info(f"backup: {stamped}")
    con = sqlite3.connect(db)
    with con:
        con.execute("UPDATE ItemTable SET value=? WHERE key=?", (new_raw, KEY))
    con.close()
    log(f"wrote: {db}")


def model_record(name):
    # Shape copied from a record Cursor itself creates via Settings → Models → Add Model.
    return {
        "name": name,
        "defaultOn": False,
        "supportsAgent": True,
        "degradationStatus": 0,
        "supportsThinking": True,
        "supportsImages": True,
        "supportsMaxMode": True,
        "supportsNonMaxMode": True,
        "serverModelName": name,
        "isRecommendedForBackgroundComposer": False,
        "supportsPlanMode": True,
        "supportsSandboxing": True,
        "isUserAdded": True,
        "inputboxShortModelName": name,
        "parameterDefinitions": [],
        "variants": [],
        "legacySlugs": [],
        "idAliases": [],
        "namedModelSectionIndex": 1,
        "cloudAgentEffortModes": [],
        "modelPickerBadges": [],
    }


def on(db, base_url, models, dry):
    con = sqlite3.connect(db)
    original_raw = con.execute("SELECT value FROM ItemTable WHERE key=?", (KEY,)).fetchone()
    con.close()
    if original_raw is None:
        sys.exit("Cursor state row not found — open Cursor once, quit it, and retry")
    original_raw = original_raw[0]
    d = json.loads(original_raw)

    d["openAIBaseUrl"] = base_url.rstrip("/") + "/v1"
    d["useOpenAIKey"] = True

    ai = d.setdefault("aiSettings", {})
    added = ai.setdefault("userAddedModels", [])
    enabled = ai.setdefault("modelOverrideEnabled", [])
    disabled = ai.setdefault("modelOverrideDisabled", [])
    catalog = d.setdefault("availableDefaultModels2", [])
    known = {m.get("name") for m in catalog}

    new = []
    for m in models:
        if m not in added:
            added.append(m)
        if m not in enabled:
            enabled.append(m)
        if m in disabled:
            disabled.remove(m)
        if m not in known:
            catalog.append(model_record(m))
            known.add(m)
            new.append(m)
    info(f"models: {len(models)} registered ({len(new)} new)")
    save(db, d, original_raw, dry)


def off(db, dry):
    con = sqlite3.connect(db)
    row = con.execute("SELECT value FROM ItemTable WHERE key=?", (KEY,)).fetchone()
    con.close()
    if row is None:
        info("Cursor state row not found; nothing to do")
        return
    original_raw = row[0]
    d = json.loads(original_raw)
    if not d.get("useOpenAIKey"):
        info("Cursor already direct")
        return
    d["useOpenAIKey"] = False
    save(db, d, original_raw, dry)


def status(db):
    if not os.path.exists(db):
        print("unset")
        return
    d = load(db)
    if d.get("useOpenAIKey") and d.get("openAIBaseUrl"):
        print("proxy")
    elif d.get("openAIBaseUrl"):
        print("direct")
    else:
        print("unset")


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if not args:
        sys.exit(__doc__)
    db = db_path()
    if args[0] == "status":
        status(db)
        return
    if not os.path.exists(db):
        sys.exit(f"Cursor state DB not found at {db} — is Cursor installed and has it been opened once?")
    if cursor_running():
        sys.exit("Cursor is running — quit it first (it rewrites this row on exit): "
                 "macOS: osascript -e 'quit app \"Cursor\"'")
    if args[0] == "on" and len(args) >= 3:
        on(db, args[1], args[2:], dry)
    elif args[0] == "off" and len(args) == 1:
        off(db, dry)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

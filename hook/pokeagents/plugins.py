"""Installing hook configuration for harnesses that run shell commands.

Goose and Crush both invoke a command on lifecycle events, so neither needs a
code shim — only a config file pointing at the hook. They disagree on where that
file lives and what shape it takes, which is all this module encodes.

The same discipline as every other installer here: back up before touching a
file that is not ours, mark what we add, and remove exactly that.
"""

import json
import os
import shutil
import time
from typing import Optional

from . import atomicio

MARKER_NAME = "poke-agents"


class PluginError(Exception):
    pass


# --------------------------------------------------------------------------- goose

def goose_directory() -> str:
    return os.path.expanduser("~/.agents/plugins/poke-agents")


def goose_path() -> str:
    return os.path.join(goose_directory(), "hooks", "hooks.json")


def goose_available() -> bool:
    return os.path.isdir(os.path.expanduser("~/.config/goose")) or bool(
        shutil.which("goose"))


def goose_is_installed() -> bool:
    return os.path.exists(goose_path())


def goose_install(hook_path: str, python: Optional[str] = None) -> str:
    """Write a hooks.json that calls the hook on every tracked goose event."""
    from . import harness

    command = _command(hook_path, python, "goose")
    hooks = {
        # No matcher: fire for every event of the type, not a subset of tools.
        event: [{"hooks": [{"type": "command", "command": command}]}]
        for event in sorted(harness.GOOSE.event_map)
    }

    atomicio.write_text(goose_path(),
                        json.dumps({"hooks": hooks}, indent=2) + "\n")
    return goose_path()


def goose_uninstall() -> bool:
    if not goose_is_installed():
        return False
    try:
        os.unlink(goose_path())
        # Leave the tree tidy, but never remove a directory holding anything else.
        for directory in (os.path.dirname(goose_path()), goose_directory()):
            try:
                os.rmdir(directory)
            except OSError:
                break
    except OSError:
        return False
    return True


# --------------------------------------------------------------------------- crush

def crush_path() -> str:
    return os.path.expanduser("~/.config/crush/crush.json")


def crush_available() -> bool:
    return os.path.exists(crush_path()) or bool(shutil.which("crush"))


def crush_is_installed() -> bool:
    try:
        with open(crush_path()) as fh:
            config = json.load(fh)
    except (OSError, ValueError):
        return False
    return any(_is_ours(entry)
               for entries in (config.get("hooks") or {}).values()
               if isinstance(entries, list)
               for entry in entries)


def crush_install(hook_path: str, python: Optional[str] = None) -> str:
    """Merge our entry into the user's crush.json, preserving everything else.

    Crush's hook entries are flat objects with a name, unlike the nested shape
    Claude Code and goose use.
    """
    from . import harness

    config = _load_json(crush_path())
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise PluginError("'hooks' is not an object in %s" % crush_path())

    _backup(crush_path())
    command = _command(hook_path, python, "crush")

    for event in sorted(harness.CRUSH.event_map):
        entries = hooks.get(event)
        entries = [e for e in entries if not _is_ours(e)] if isinstance(entries, list) else []
        entries.append({"name": MARKER_NAME, "command": command, "timeout": 10})
        hooks[event] = entries

    atomicio.write_text(crush_path(), json.dumps(config, indent=2) + "\n")
    return crush_path()


def crush_uninstall() -> bool:
    if not os.path.exists(crush_path()):
        return False
    config = _load_json(crush_path())
    hooks = config.get("hooks")
    if not isinstance(hooks, dict):
        return False

    removed = False
    for event in list(hooks):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        remaining = [e for e in entries if not _is_ours(e)]
        if len(remaining) != len(entries):
            removed = True
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]

    if not removed:
        return False

    _backup(crush_path())
    atomicio.write_text(crush_path(), json.dumps(config, indent=2) + "\n")
    return True


# --------------------------------------------------------------------------- shared

def _is_ours(entry) -> bool:
    return isinstance(entry, dict) and entry.get("name") == MARKER_NAME


def _command(hook_path: str, python: Optional[str], harness_name: str) -> str:
    import shlex

    interpreter = python or "/usr/bin/env python3"
    quoted = " ".join(shlex.quote(part) for part in shlex.split(interpreter))
    return "%s %s --harness %s" % (quoted, shlex.quote(hook_path), harness_name)


def _load_json(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise PluginError("cannot read %s: %s" % (path, exc))
    if not isinstance(data, dict):
        raise PluginError("%s is not a JSON object" % path)
    return data


def _backup(path: str) -> None:
    if not os.path.exists(path):
        return
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = "%s.backup-%s" % (path, stamp)
    suffix = 1
    while os.path.exists(target):
        target = "%s.backup-%s.%d" % (path, stamp, suffix)
        suffix += 1
    shutil.copy2(path, target)

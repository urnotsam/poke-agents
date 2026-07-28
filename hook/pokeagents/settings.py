"""Installing and removing PokeAgents's hook entries in a Claude Code settings file.

The user's settings.json is theirs, not ours. Every operation here preserves
unrelated settings and unrelated hooks, marks its own entries so uninstall can
find exactly them, and refuses to act on a file it cannot parse.
"""

import json
import os
import shlex
import shutil
import time
from typing import List, Optional

from . import atomicio

# Identifies an entry as ours. Matching on this rather than on the command
# string means uninstall still works after the hook has been moved.
MARKER = "pokeAgentsManaged"

EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "Notification",
          "Stop", "SessionEnd")

# PreToolUse groups are matcher-scoped; the rest are not.
_MATCHERS = {"PreToolUse": "*"}


class SettingsError(Exception):
    pass


def default_path() -> str:
    return os.path.expanduser("~/.claude/settings.json")


def install(path: str, hook_path: str, python: Optional[str] = None) -> None:
    """Add or refresh PokeAgents's hook entries. Idempotent."""
    data = _load(path)
    _backup(path)

    command = _command(hook_path, python)
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise SettingsError("'hooks' is not an object in %s" % path)

    for event in EVENTS:
        groups = hooks.get(event)
        if not isinstance(groups, list):
            groups = []
        groups = _without_ours(groups)
        groups.append(_group(event, command))
        hooks[event] = groups

    _save(path, data)


def uninstall(path: str) -> None:
    """Remove only the entries we added, leaving everything else intact."""
    if not os.path.exists(path):
        return
    data = _load(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return

    _backup(path)
    for event in list(hooks):
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        remaining = _without_ours(groups)
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]

    _save(path, data)


def is_installed(path: str) -> bool:
    try:
        data = _load(path)
    except SettingsError:
        return False
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return False
    return any(_ours(g) for groups in hooks.values()
               if isinstance(groups, list) for g in groups)


def _command(hook_path: str, python: Optional[str]) -> str:
    """Compose the hook command line.

    Claude Code runs hook commands through a shell, and this lands in a file
    that executes on every event of every session, so both halves are quoted
    properly rather than by a space-detecting heuristic. `--python` in
    particular is raw user input.
    """
    interpreter = python or "/usr/bin/env python3"
    # An interpreter may legitimately be several words ("/usr/bin/env python3"),
    # so quote each word rather than the whole string.
    quoted = " ".join(shlex.quote(part) for part in shlex.split(interpreter))
    return "%s %s" % (quoted, shlex.quote(hook_path))


def _group(event: str, command: str) -> dict:
    entry = {"type": "command", "command": command, MARKER: True}
    group = {"hooks": [entry]}
    matcher = _MATCHERS.get(event)
    if matcher:
        group["matcher"] = matcher
    return group


def _ours(group) -> bool:
    if not isinstance(group, dict):
        return False
    entries = group.get("hooks")
    if not isinstance(entries, list):
        return False
    return any(isinstance(e, dict) and e.get(MARKER) is True for e in entries)


def _without_ours(groups: list) -> List[dict]:
    return [g for g in groups if not _ours(g)]


def _load(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SettingsError("cannot read %s: %s" % (path, exc))
    if not isinstance(data, dict):
        raise SettingsError("%s is not a JSON object" % path)
    return data


def _save(path: str, data: dict) -> None:
    atomicio.write_text(path, json.dumps(data, indent=2) + "\n")


def _backup(path: str) -> None:
    """Copy the settings file aside before mutating it.

    Timestamps are second-granular, so two runs in the same second would
    otherwise silently overwrite the earlier backup — losing the copy taken
    before the first change, which is the one worth keeping.
    """
    if not os.path.exists(path):
        return

    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = "%s.backup-%s" % (path, stamp)
    suffix = 1
    while os.path.exists(target):
        target = "%s.backup-%s.%d" % (path, stamp, suffix)
        suffix += 1
    shutil.copy2(path, target)

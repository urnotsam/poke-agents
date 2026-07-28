"""Session records on disk.

One JSON file per live session. The filesystem is the message bus between hooks
and the overlay: no server, no database, no socket, and either side works fine
when the other is absent.
"""

import errno
import json
import os
import re
import time
from dataclasses import dataclass, asdict
from typing import List, Optional

from . import atomicio
from .events import RUNNING, ATTENTION, DONE  # noqa: F401  (re-exported)

MAX_AGE_SECONDS = 24 * 60 * 60

# Session ids are uuids in practice. Constraining the charset keeps a hostile or
# malformed id from escaping the state directory when used as a filename.
_SAFE_ID = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")

_FIELDS = (
    "session_id", "label", "cwd", "species", "shiny", "state", "pid", "tty",
    "terminal", "started_at", "updated_at", "last_tool", "focusable",
)

# Fields without which a sprite cannot be drawn at all. Everything else is
# optional and may legitimately be null.
_REQUIRED = ("session_id", "label", "cwd", "species", "state")


@dataclass
class SessionRecord:
    session_id: str
    label: str
    cwd: str
    species: str
    shiny: bool
    state: str
    pid: Optional[int]
    tty: Optional[str]
    terminal: Optional[str]
    started_at: int
    updated_at: int
    last_tool: Optional[str] = None

    # False for a session with nowhere to jump to — a background agent has no
    # controlling terminal at all. Defaults true so a record written by an older
    # version is not mistaken for a headless one.
    focusable: bool = True


def _safe_path(directory: str, session_id: str) -> str:
    if not isinstance(session_id, str) or not _SAFE_ID.match(session_id):
        raise ValueError("unsafe session id: %r" % (session_id,))
    return os.path.join(directory, session_id + ".json")


def write(directory: str, record: SessionRecord) -> None:
    """Write a record atomically so readers never see a partial file."""
    path = _safe_path(directory, record.session_id)
    atomicio.write_text(path, json.dumps(asdict(record), indent=2, sort_keys=True))


def read(directory: str, session_id: str) -> Optional[SessionRecord]:
    try:
        path = _safe_path(directory, session_id)
    except ValueError:
        return None
    return _load(path)


def read_all(directory: str) -> List[SessionRecord]:
    """Every valid record in the directory. Corrupt files are skipped, not fatal."""
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return []

    records = []
    for name in names:
        if not name.endswith(".json") or name.startswith("."):
            continue
        record = _load(os.path.join(directory, name))
        if record is not None:
            records.append(record)
    return records


def delete(directory: str, session_id: str) -> None:
    try:
        path = _safe_path(directory, session_id)
    except ValueError:
        return
    _unlink(path)


def is_adopted(record: SessionRecord) -> bool:
    """True for a record synthesised by `poke-agents adopt`, rather than written
    by the session's own hook."""
    return record.session_id.startswith("adopted-")


def prune(directory: str, now: Optional[int] = None) -> List[str]:
    """Delete records nothing will clean up otherwise. Returns the ids removed.

    Two kinds go:

    Dead sessions. SessionEnd covers the clean case, and the overlay stops
    *drawing* stale records, but nothing removes the files. A process killed
    with SIGKILL — including `poke-agents simulate` — would otherwise leave
    records behind permanently.

    Superseded adopted records. Adopt keys records by pid and the hook keys them
    by session id, so a session adopted before its hook ever fired ends up
    described twice. The overlay refuses to draw both, but the stale file would
    linger and keep showing up in `ls`.
    """
    records = read_all(directory)
    hooked_pids = {r.pid for r in records if r.pid and not is_adopted(r)}

    removed = []
    for record in records:
        superseded = is_adopted(record) and record.pid in hooked_pids
        if superseded or is_stale(record, now):
            delete(directory, record.session_id)
            removed.append(record.session_id)
    return removed


def _load(path: str) -> Optional[SessionRecord]:
    try:
        with open(path) as fh:
            raw = json.load(fh)
    except (OSError, ValueError):
        return None

    if not isinstance(raw, dict):
        return None
    if any(raw.get(field) is None for field in _REQUIRED):
        return None

    # Drop unknown keys so a newer writer cannot break an older reader.
    known = {k: raw.get(k) for k in _FIELDS}
    if known.get("focusable") is None:
        known["focusable"] = True
    try:
        return SessionRecord(**known)
    except TypeError:
        return None


def pid_alive(pid: Optional[int]) -> bool:
    """True when a process with this pid exists and we may signal it."""
    if not pid or not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError as exc:
        # EPERM means it exists but belongs to someone else, which still counts.
        return exc.errno == errno.EPERM
    return True


def is_stale(record: SessionRecord, now: Optional[int] = None) -> bool:
    """A record is stale when its process is gone or it is simply too old.

    SessionEnd does not fire on a crash or kill -9, so without this the display
    fills with dead sprites and stops meaning anything. The age check is a
    backstop against a recycled pid resurrecting a ghost.
    """
    if not pid_alive(record.pid):
        return True
    now = int(time.time()) if now is None else now
    return (now - (record.updated_at or 0)) > MAX_AGE_SECONDS


def _unlink(path: str) -> None:
    try:
        os.unlink(path)
    except OSError:
        pass

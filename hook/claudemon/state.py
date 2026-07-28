"""Session records on disk.

One JSON file per live session. The filesystem is the message bus between hooks
and the overlay: no server, no database, no socket, and either side works fine
when the other is absent.
"""

import errno
import json
import os
import re
import tempfile
import time
from dataclasses import dataclass, asdict
from typing import List, Optional

from .events import RUNNING, ATTENTION, DONE  # noqa: F401  (re-exported)

MAX_AGE_SECONDS = 24 * 60 * 60

# Session ids are uuids in practice. Constraining the charset keeps a hostile or
# malformed id from escaping the state directory when used as a filename.
_SAFE_ID = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")

_FIELDS = (
    "session_id", "label", "cwd", "species", "shiny", "state", "pid", "tty",
    "terminal", "started_at", "updated_at", "last_tool",
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


def _safe_path(directory: str, session_id: str) -> str:
    if not isinstance(session_id, str) or not _SAFE_ID.match(session_id):
        raise ValueError("unsafe session id: %r" % (session_id,))
    return os.path.join(directory, session_id + ".json")


def write(directory: str, record: SessionRecord) -> None:
    """Write a record atomically so readers never see a partial file."""
    path = _safe_path(directory, record.session_id)
    os.makedirs(directory, exist_ok=True)

    payload = json.dumps(asdict(record), indent=2, sort_keys=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(payload)
        os.replace(tmp, path)
    except BaseException:
        _unlink(tmp)
        raise


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

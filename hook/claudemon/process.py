"""Finding the `claude` process that owns a hook invocation.

A hook runs in a shell several levels below the session's `claude` process, and
its own stdin is a JSON pipe rather than a terminal. The controlling tty we need
for click-to-focus therefore has to come from walking up the process tree.
"""

import os
import subprocess
from dataclasses import dataclass
from typing import Callable, Optional

MAX_DEPTH = 12
_PS_TIMEOUT = 2.0
_TARGET = "claude"


@dataclass(frozen=True)
class ProcInfo:
    pid: int
    ppid: int
    comm: str
    tty: str


def lookup_proc(pid: int) -> Optional[ProcInfo]:
    """Read one process from ps. Returns None if it does not exist."""
    try:
        out = subprocess.run(
            ["ps", "-o", "pid=,ppid=,tty=,comm=", "-p", str(pid)],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=_PS_TIMEOUT,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None

    line = out.stdout.decode("utf-8", "replace").strip()
    if not line:
        return None

    # comm may contain spaces, so split only the three fixed leading fields.
    parts = line.split(None, 3)
    if len(parts) < 4:
        return None
    try:
        return ProcInfo(pid=int(parts[0]), ppid=int(parts[1]),
                        tty=parts[2], comm=parts[3])
    except ValueError:
        return None


def find_claude(start_pid: int,
                lookup: Callable[[int], Optional[ProcInfo]] = lookup_proc
                ) -> Optional[ProcInfo]:
    """Walk up from start_pid to the owning `claude` process.

    Bounded by depth and a seen-set so a malformed or cyclic tree cannot hang a
    hook that runs on every event of every session.
    """
    seen = set()
    pid = start_pid

    for _ in range(MAX_DEPTH):
        if pid <= 1 or pid in seen:
            return None
        seen.add(pid)

        info = lookup(pid)
        if info is None:
            return None
        if os.path.basename(info.comm) == _TARGET:
            return info
        pid = info.ppid

    return None


def normalize_tty(tty: Optional[str]) -> Optional[str]:
    """Turn a ps tty field into an absolute device path, or None if there is none."""
    if not tty:
        return None
    tty = tty.strip()
    if not tty or tty.startswith("?"):
        return None
    return tty if tty.startswith("/") else "/dev/" + tty

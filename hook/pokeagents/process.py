"""Finding the `claude` process that owns a hook invocation.

A hook runs in a shell several levels below the session's `claude` process, and
its own stdin is a JSON pipe rather than a terminal. The controlling tty we need
for click-to-focus therefore has to come from walking up the process tree.
"""

import os
import subprocess
from dataclasses import dataclass
from typing import Callable, Optional, Sequence

MAX_DEPTH = 12
_PS_TIMEOUT = 2.0

# Shared plumbing that hosts sessions but is not one. A background agent's
# process tree runs under these, and they are named `claude` too, so a walk that
# only matches on the name attributes the session to the daemon — which is both
# wrong and, because every background session shares it, collapses them all onto
# one pid.
_INFRASTRUCTURE = ("--bg-pty-host", "bg-pty-host", "bg-spare", "daemon run")


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


def find_session_process(session_id: str) -> Optional[ProcInfo]:
    """The process running a specific session, found by its own argv.

    Exact where the tree walk is a guess. A background agent runs as a versioned
    binary — `.../versions/2.1.220 --session-id <id>` — so it does not match the
    name `claude` at all, and the walk lands on the pty-host daemon above it
    instead.
    """
    if not session_id or len(session_id) < 8:
        return None

    try:
        out = subprocess.run(["ps", "-eo", "pid=,ppid=,tty=,args="],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=_PS_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None

    # Require the id as an actual argument, not merely somewhere in the command
    # line. The pty-host daemon carries it inside a socket path, and any grep or
    # editor that happens to mention it would otherwise match too.
    needle = "--session-id %s" % session_id
    self_pid = os.getpid()

    for line in out.stdout.decode("utf-8", "replace").splitlines():
        if needle not in line:
            continue
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        if _is_infrastructure(parts[3]):
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        if pid == self_pid:
            continue
        try:
            return ProcInfo(pid=pid, ppid=int(parts[1]),
                            tty=parts[2], comm=parts[3].split()[0])
        except (ValueError, IndexError):
            continue
    return None


def _is_infrastructure(args: str) -> bool:
    return any(marker in args for marker in _INFRASTRUCTURE)


def find_agent(start_pid: int,
               commands: Sequence[str] = ("claude",),
               lookup: Callable[[int], Optional[ProcInfo]] = lookup_proc
               ) -> Optional[ProcInfo]:
    """Walk up from start_pid to the owning agent process.

    Which process names count is the harness's business, not this module's — a
    harness that can report its own pid never needs this at all.

    Bounded by depth and a seen-set so a malformed or cyclic tree cannot hang a
    hook that runs on every event of every session.
    """
    targets = set(commands)
    seen = set()
    pid = start_pid

    for _ in range(MAX_DEPTH):
        if pid <= 1 or pid in seen:
            return None
        seen.add(pid)

        info = lookup(pid)
        if info is None:
            return None
        if os.path.basename(info.comm) in targets and not _is_infrastructure(info.comm):
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


def find_claude(start_pid: int,
                lookup: Callable[[int], Optional[ProcInfo]] = lookup_proc
                ) -> Optional[ProcInfo]:
    """Backwards-compatible alias for the Claude Code case."""
    return find_agent(start_pid, ("claude",), lookup)

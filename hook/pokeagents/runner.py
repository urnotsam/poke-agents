"""Applying a hook event to the session state directory."""

import os
import time
from typing import Callable, Optional

from . import events, labels, process, species, state


def apply_event(directory: str, payload: dict,
                proc: Optional[process.ProcInfo] = None,
                resolve_proc: Optional[Callable[[], Optional[process.ProcInfo]]] = None
                ) -> None:
    """Update the session record for one hook event.

    Unknown events and unusable payloads are ignored rather than raising: this
    runs inside every live Claude session and must never become a problem.

    `resolve_proc` is called at most once, and only when the owning process is
    actually needed. Finding it means walking the process tree with one `ps` per
    level, and PreToolUse fires on every tool call, so resolving it eagerly
    would spend a dozen subprocesses per event to compute a value that an
    already-established record throws away.
    """
    resolved = {"proc": proc, "done": proc is not None}

    def owning_process():
        if not resolved["done"]:
            resolved["done"] = True
            if resolve_proc is not None:
                resolved["proc"] = resolve_proc()
        return resolved["proc"]

    if not isinstance(payload, dict):
        return

    transition = events.transition_for(payload.get("hook_event_name"))
    if transition is None:
        return

    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return

    if transition.deletes:
        state.delete(directory, session_id)
        return

    now = int(payload.get("_now") or time.time())
    existing = state.read(directory, session_id)

    if existing is None:
        record = _spawn(directory, session_id, payload, owning_process(), now)
        if record is None:
            return
    else:
        record = existing
        record.updated_at = now

    if transition.state:
        record.state = transition.state
    if transition.records_tool:
        tool = payload.get("tool_name")
        record.last_tool = tool if isinstance(tool, str) else None

    # Re-resolve process details when a record was adopted without them.
    if record.pid is None:
        adopted = owning_process()
        if adopted is not None:
            record.pid = adopted.pid
            record.tty = process.normalize_tty(adopted.tty)

    record.updated_at = now

    try:
        state.write(directory, record)
    except (ValueError, OSError):
        return


def _spawn(directory, session_id, payload, proc, now):
    """Build a fresh record. Also covers hooks installed mid-session, where the
    first event we ever see is something other than SessionStart."""
    cwd = payload.get("cwd") or os.getcwd()
    taken = {r.species for r in state.read_all(directory)}
    pick = species.assign(session_id, taken=taken)

    return state.SessionRecord(
        session_id=session_id,
        label=labels.derive(cwd, display_name=payload.get("session_name")),
        cwd=cwd,
        species=pick.name,
        shiny=pick.shiny,
        state=events.RUNNING,
        pid=proc.pid if proc else None,
        tty=process.normalize_tty(proc.tty) if proc else None,
        terminal=os.environ.get("TERM_PROGRAM"),
        started_at=now,
        updated_at=now,
        last_tool=None,
    )

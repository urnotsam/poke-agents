"""Applying a hook event to the session state directory."""

import os
import time
from typing import Callable, Optional

from . import events, harness as harnesses, labels, process, species, state


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

    def reported_pid():
        """A harness that knows its own pid can say so and skip the walk."""
        value = payload.get("pid")
        return value if isinstance(value, int) and value > 0 else None

    if not isinstance(payload, dict):
        return

    # Which harness produced this decides only how its event is named; from the
    # transition onwards nothing downstream can tell the difference.
    harness = harnesses.get(payload.get("harness"))
    transition = harness.transition_for(harness.event_name(payload))
    if transition is None:
        return

    session_id = harness.session_id(payload)
    if not session_id:
        return

    if transition.deletes:
        state.delete(directory, session_id)
        return

    now = int(payload.get("_now") or time.time())
    existing = state.read(directory, session_id)

    if existing is None:
        record = _spawn(directory, session_id, payload, owning_process(), now,
                        harness=harness, reported_pid=reported_pid())
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
        record.pid = reported_pid()
    if record.pid is None:
        adopted = owning_process()
        if adopted is not None:
            record.pid = adopted.pid
            record.tty = process.normalize_tty(adopted.tty)
            record.focusable = bool(record.tty)

    record.updated_at = now

    try:
        state.write(directory, record)
    except (ValueError, OSError):
        return


def _spawn(directory, session_id, payload, proc, now, harness, reported_pid=None):
    """Build a fresh record. Also covers hooks installed mid-session, where the
    first event we ever see is something other than SessionStart."""
    cwd = harness.cwd(payload) or os.getcwd()
    taken = {r.species for r in state.read_all(directory)}
    pick = species.assign(session_id, taken=taken)
    tty = process.normalize_tty(proc.tty) if proc else None

    return state.SessionRecord(
        session_id=session_id,
        label=labels.derive(cwd, display_name=payload.get("session_name")),
        cwd=cwd,
        species=pick.name,
        shiny=pick.shiny,
        state=events.RUNNING,
        pid=reported_pid or (proc.pid if proc else None),
        tty=tty,
        terminal=payload.get("terminal") or os.environ.get("TERM_PROGRAM"),
        started_at=now,
        updated_at=now,
        last_tool=None,
        # No controlling terminal means no terminal to raise. A background agent
        # is a real running session worth seeing; it just cannot be jumped to.
        focusable=bool(tty),
    )

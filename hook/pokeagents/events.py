"""The canonical lifecycle vocabulary, and what each event does to a session.

Harnesses name their events differently — Claude Code says `Notification`,
OpenCode says `permission.asked` — but they mean the same thing. Each harness
maps its own names onto the canonical events below, so this table stays the one
place that decides what a sprite does, whatever produced the event.

Pure lookup, no I/O.
"""

from dataclasses import dataclass
from typing import Optional

# Sprite states.
RUNNING = "running"
ATTENTION = "attention"
DONE = "done"

STATES = (RUNNING, ATTENTION, DONE)

# Canonical lifecycle events.
START = "start"              # a session began
ACTIVITY = "activity"        # the agent is doing something
TOOL = "tool"                # the agent is running a named tool
NEEDS_USER = "needs-user"    # the agent is blocked on the user
IDLE = "idle"                # the turn finished
END = "end"                  # the session is over

CANONICAL = (START, ACTIVITY, TOOL, NEEDS_USER, IDLE, END)


@dataclass(frozen=True)
class Transition:
    state: Optional[str]
    deletes: bool = False
    records_tool: bool = False


_TRANSITIONS = {
    START: Transition(state=RUNNING),
    ACTIVITY: Transition(state=RUNNING),
    TOOL: Transition(state=RUNNING, records_tool=True),
    NEEDS_USER: Transition(state=ATTENTION),
    IDLE: Transition(state=DONE),
    END: Transition(state=None, deletes=True),
}

HANDLED = list(_TRANSITIONS)


def transition_for(event_name: Optional[str]) -> Optional[Transition]:
    """Return the transition for a canonical event, or None if untracked."""
    if not event_name:
        return None
    return _TRANSITIONS.get(event_name)

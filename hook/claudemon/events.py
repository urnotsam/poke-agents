"""Hook event names mapped to session state transitions.

Pure lookup, no I/O, so the mapping that defines the whole product is trivially
testable and reviewable in one place.
"""

from dataclasses import dataclass
from typing import Optional

RUNNING = "running"
ATTENTION = "attention"
DONE = "done"

STATES = (RUNNING, ATTENTION, DONE)


@dataclass(frozen=True)
class Transition:
    state: Optional[str]
    creates: bool = False
    deletes: bool = False
    records_tool: bool = False


# Notification covers permission prompts and idle input requests alike, which is
# exactly the "blocked on you" condition. Stop means the turn ended, so the agent
# is finished rather than blocked.
_TRANSITIONS = {
    "SessionStart": Transition(state=RUNNING, creates=True),
    "UserPromptSubmit": Transition(state=RUNNING),
    "PreToolUse": Transition(state=RUNNING, records_tool=True),
    "Notification": Transition(state=ATTENTION),
    "Stop": Transition(state=DONE),
    "SessionEnd": Transition(state=None, deletes=True),
}

HANDLED = list(_TRANSITIONS)


def transition_for(event_name: Optional[str]) -> Optional[Transition]:
    """Return the transition for a hook event, or None if we do not track it."""
    if not event_name:
        return None
    return _TRANSITIONS.get(event_name)

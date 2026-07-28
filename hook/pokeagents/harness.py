"""Agent harnesses.

A harness is whatever runs the coding agent: Claude Code, OpenCode, and so on.
They differ in what their lifecycle events are called and where their config
lives, but they all describe the same three things — the agent is working, the
agent needs you, the agent is finished.

Each harness therefore only has to map its own event names onto the canonical
vocabulary in `events`. Everything downstream — the session record, the overlay,
the terminal adapters — never learns which harness produced a record.
"""

from dataclasses import dataclass
from typing import Dict, Optional, Tuple

from . import events


@dataclass(frozen=True)
class Harness:
    name: str
    title: str

    # Process names to look for when resolving which process owns a session.
    # Used only when the harness cannot tell us its pid directly.
    agent_commands: Tuple[str, ...]

    # This harness's event names, mapped onto the canonical vocabulary.
    event_map: Dict[str, str]

    def canonical(self, event_name: Optional[str]) -> Optional[str]:
        if not event_name:
            return None
        return self.event_map.get(event_name)

    def transition_for(self, event_name: Optional[str]):
        return events.transition_for(self.canonical(event_name))


CLAUDE_CODE = Harness(
    name="claude-code",
    title="Claude Code",
    agent_commands=("claude",),
    event_map={
        "SessionStart": events.START,
        "UserPromptSubmit": events.ACTIVITY,
        "PreToolUse": events.TOOL,
        # Covers permission prompts and idle input requests alike, which is
        # exactly the "blocked on you" condition.
        "Notification": events.NEEDS_USER,
        "Stop": events.IDLE,
        "SessionEnd": events.END,
    },
)

OPENCODE = Harness(
    name="opencode",
    title="OpenCode",
    agent_commands=("opencode",),
    event_map={
        "session.created": events.START,
        "tool.execute.before": events.TOOL,
        # More precise than Claude's equivalent: OpenCode says specifically that
        # it is waiting on a permission decision.
        "permission.asked": events.NEEDS_USER,
        "permission.replied": events.ACTIVITY,
        "session.error": events.NEEDS_USER,
        "session.idle": events.IDLE,
        "session.deleted": events.END,
    },
)

ALL = (CLAUDE_CODE, OPENCODE)
DEFAULT = CLAUDE_CODE

_BY_NAME = {h.name: h for h in ALL}


def get(name: Optional[str]) -> Harness:
    """Look up a harness, falling back to Claude Code.

    A record written by an unknown harness is still better than no record, and
    the canonical event names work for anyone willing to emit them directly.
    """
    if not name:
        return DEFAULT
    return _BY_NAME.get(name, DEFAULT)


def names() -> Tuple[str, ...]:
    return tuple(h.name for h in ALL)


def agent_commands() -> Tuple[str, ...]:
    """Every process name that might be running an agent."""
    seen = []
    for harness in ALL:
        for command in harness.agent_commands:
            if command not in seen:
                seen.append(command)
    return tuple(seen)

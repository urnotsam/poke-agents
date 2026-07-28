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

    # Harnesses disagree on what to call the fields in their payload: Claude
    # Code says hook_event_name and cwd, Goose says event and working_dir.
    # Naming them here keeps the runner from caring.
    event_field: str = "hook_event_name"
    cwd_field: str = "cwd"
    session_field: str = "session_id"

    # Set when the harness cannot report the whole lifecycle, with a note saying
    # what the user loses. Declaring it is required: an accidental gap and a
    # deliberate one look identical in the event map, and the accidental kind
    # produces sprites that never appear or never leave.
    limitations: str = ""

    def event_name(self, payload: dict) -> Optional[str]:
        value = payload.get(self.event_field)
        if value is None and self.event_field != "hook_event_name":
            value = payload.get("hook_event_name")
        return value if isinstance(value, str) else None

    def cwd(self, payload: dict) -> Optional[str]:
        value = payload.get(self.cwd_field)
        if value is None and self.cwd_field != "cwd":
            value = payload.get("cwd")
        return value if isinstance(value, str) else None

    def session_id(self, payload: dict) -> Optional[str]:
        value = payload.get(self.session_field)
        return value if isinstance(value, str) and value else None

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

GOOSE = Harness(
    name="goose",
    title="Goose",
    agent_commands=("goose",),
    # Goose follows the Open Plugins hooks spec, so the shape matches Claude
    # Code's closely, but the payload names its fields differently.
    event_field="event",
    cwd_field="working_dir",
    event_map={
        "SessionStart": events.START,
        "UserPromptSubmit": events.ACTIVITY,
        "PreToolUse": events.TOOL,
        "PostToolUse": events.ACTIVITY,
        "PostToolUseFailure": events.NEEDS_USER,
        "Stop": events.IDLE,
        "SessionEnd": events.END,
    },
)

CRUSH = Harness(
    name="crush",
    title="Crush",
    agent_commands=("crush",),
    event_field="event",
    # Crush implements only PreToolUse so far, so a sprite spawns on the first
    # tool call and then stays `running` for the life of the session: there is
    # no idle or end event to move it on. It still despawns, because the overlay
    # reaps sessions whose process has exited. This map grows for free as Crush
    # implements the rest.
    event_map={
        "PreToolUse": events.TOOL,
    },
    limitations=(
        "Crush currently implements only PreToolUse, so a sprite appears on the "
        "first tool call and stays 'running' for the life of the session — there "
        "is no idle or end event to move it on. It still despawns when Crush "
        "exits, because the overlay reaps sessions whose process is gone. This "
        "improves for free as Crush implements more events."
    ),
)

ALL = (CLAUDE_CODE, OPENCODE, GOOSE, CRUSH)
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

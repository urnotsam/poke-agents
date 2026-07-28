# Agent harnesses

A harness is whatever runs the coding agent — Claude Code, OpenCode, Goose,
Crush, your own script. poke-agents ships integrations for Claude Code and
OpenCode, and adding another is small.

## What the rest of the system knows about harnesses

Nothing. The overlay, the sprite layout, the terminal adapters and click-to-focus
all read a generic session record and never learn what produced it. A harness
only has to answer one question, repeatedly:

> which session is in which of three states — working, needs the user, finished?

## The canonical events

Harnesses name their lifecycle events differently, so each one maps its own
names onto six canonical events. That map is the entire integration.

| Canonical event | Meaning | Effect |
|---|---|---|
| `start` | a session began | sprite spawns, `running` |
| `activity` | the agent is doing something | `running` |
| `tool` | the agent is running a named tool | `running`, records the tool name |
| `needs-user` | **the agent is blocked on you** | `attention` |
| `idle` | the turn finished | `done` |
| `end` | the session is over | sprite despawns |

`needs-user` is the one that matters most — the whole overlay exists to surface
it. If your harness distinguishes "waiting for a permission decision" from
"finished the turn", make sure those map to `needs-user` and `idle` respectively
rather than collapsing together.

The shipped maps, for reference:

| Canonical | Claude Code | OpenCode |
|---|---|---|
| `start` | `SessionStart` | `session.created` |
| `activity` | `UserPromptSubmit` | `permission.replied` |
| `tool` | `PreToolUse` | `tool.execute.before` |
| `needs-user` | `Notification` | `permission.asked`, `session.error` |
| `idle` | `Stop` | `session.idle` |
| `end` | `SessionEnd` | `session.deleted` |

## Adding a harness

### 1. Register it

Add a `Harness` to [`hook/pokeagents/harness.py`](../hook/pokeagents/harness.py):

```python
GOOSE = Harness(
    name="goose",
    title="Goose",
    agent_commands=("goose",),
    event_map={
        "SessionStart": events.START,
        "PostToolUse": events.TOOL,
        "SessionEnd": events.END,
        # ...
    },
)
```

`agent_commands` is only used to find the owning process when the harness cannot
report its own pid. Tests enforce that every harness maps onto real canonical
events and covers the whole lifecycle, so a half-wired harness fails loudly.

### 2. Make it call the hook

The hook reads one JSON object on stdin:

```json
{
  "harness": "goose",
  "hook_event_name": "SessionEnd",
  "session_id": "whatever-is-stable-for-this-session",
  "pid": 4242,
  "cwd": "/Users/you/project",
  "tool_name": "shell"
}
```

Only `harness` and `hook_event_name` are strictly required, but:

- **`session_id`** should be stable for the life of the session. If your harness
  has no session id, derive one from the pid, as the OpenCode plugin does.
- **`pid`** should be the process a terminal could focus. Supply it if you can —
  it makes click-to-focus exact and skips a process-tree walk that would
  otherwise run on every event.
- **`cwd`** is used for the label when nothing better is available.

Harnesses that run shell commands on events — Goose follows the Open Plugins
hooks spec, Crush has a hook engine — can invoke `hook/pokeagents_hook.py`
directly with that JSON. Harnesses with a programmatic plugin API need a small
shim; [`opencode/poke-agents.js`](opencode/poke-agents.js) is about 50 lines and
is a reasonable template.

### 3. Install it

Add an installer alongside [`opencode.py`](../hook/pokeagents/opencode.py) and
wire it into `poke-agents install --harness <name>`. Two rules, both tested:
never overwrite a file you did not write, and remove exactly what you added.

## Two rules for anything running inside a session

These are not style preferences; breaking either one degrades the agent you are
trying to observe.

1. **Never fail loudly.** The hook always exits 0. Your shim should swallow its
   own errors too — observing a session must not be able to break it.
2. **Never write to stdout.** Some harnesses feed hook stdout back into the
   model's context, so a stray `print` silently pollutes the conversation.
   Diagnostics go to `~/.claude/poke-agents/hook.log`.

Also keep it fast. A `tool` event fires on *every* tool call, so avoid adding
subprocesses or file reads to that path.

## Not using a harness at all

You do not need one. A session record is just a JSON file, and anything that can
write one gets a sprite — see the record format in the
[main README](../README.md#how-it-works). A terminal adapter's `discover` can
also enumerate sessions without any harness integration, which is how
`poke-agents adopt` works.

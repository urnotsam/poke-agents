#!/usr/bin/env python3
"""Claude Code hook entry point for PokeAgents.

Wire this into SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop,
and SessionEnd. It updates one JSON file per session and gets out of the way.

Two rules govern everything here, because this code runs inside every live
Claude Code session:

  1. Always exit 0. A hook that fails loudly disrupts real work.
  2. Never write to stdout. SessionStart stdout is injected into the session as
     context, so a stray print would silently pollute the conversation.

Diagnostics go to ~/.claude/poke-agents/hook.log. Set POKEAGENTS_DISABLE=1 to turn
the whole thing off without uninstalling.
"""

import os
import sys

MAX_LOG_BYTES = 256 * 1024


def _log(message: str) -> None:
    """Best-effort diagnostics. Never raises, never touches stdout."""
    try:
        from pokeagents import paths

        path = paths.log_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path) and os.path.getsize(path) > MAX_LOG_BYTES:
            os.replace(path, path + ".1")
        with open(path, "a") as fh:
            fh.write(message.rstrip() + "\n")
    except Exception:
        pass


def main() -> int:
    try:
        import json

        from pokeagents import harness, paths, process, runner

        if paths.disabled():
            return 0

        raw = sys.stdin.read()
        if not raw.strip():
            return 0

        payload = json.loads(raw)

        # Harnesses that cannot add a field to their payload say so on the
        # command line instead: `pokeagents_hook.py --harness goose`.
        if "--harness" in sys.argv:
            index = sys.argv.index("--harness")
            if index + 1 < len(sys.argv):
                payload["harness"] = sys.argv[index + 1]

        runner.apply_event(
            paths.sessions_dir(), payload,
            resolve_proc=lambda: process.find_agent(os.getpid(),
                                                    harness.agent_commands()))
    except Exception as exc:  # noqa: BLE001 - a hook must never propagate
        _log("pokeagents hook error: %r" % (exc,))
    return 0


if __name__ == "__main__":
    # Guard the exit itself, so even an unimportable interpreter state exits 0.
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        sys.exit(0)

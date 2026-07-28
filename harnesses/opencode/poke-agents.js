/**
 * poke-agents plugin for OpenCode.
 *
 * Reports session lifecycle to poke-agents, which draws a Pokémon on your
 * desktop for every running agent. Install with:
 *
 *     poke-agents install --harness opencode
 *
 * OpenCode loads plugins from ~/.config/opencode/plugins/ (global) or
 * .opencode/plugins/ (per project). Verify yours is picked up with
 * `opencode debug config`, which lists the plugin files it resolved.
 *
 * Three deliberate choices:
 *
 * It spawns the hook through node:child_process rather than OpenCode's `$`
 * helper. OpenCode runs on Bun, and Bun's ShellPromise has no stdin method —
 * an earlier version tried `$`...`.stdin(payload)` and threw on every event,
 * silently, because the handler caught its own error.
 *
 * It never throws. Observing a session must not be able to disturb it.
 *
 * It reports its own pid instead of letting poke-agents walk the process tree.
 * The plugin runs inside OpenCode, so it simply knows, and the pid is what
 * terminal adapters match on for click-to-focus.
 */

import { spawn } from "node:child_process";

const HOOK = process.env.POKE_AGENTS_HOOK
  || `${process.env.HOME}/.claude/poke-agents/harnesses/pokeagents_hook.py`;

/** The first candidate that looks like a real project directory.
 *
 * `worktree` is "/" for a non-worktree checkout rather than empty, so taking it
 * first silently labels every session "session" and points the label at the
 * filesystem root.
 */
const projectDirectory = (...candidates) =>
  candidates.find((c) => typeof c === "string" && c.length > 1) || "/";

export const PokeAgents = async ({ directory, worktree }) => {
  // One sprite per OpenCode process. Session ids are not handed to plugins, and
  // the pid is the key everything else joins on anyway.
  const sessionID = `opencode-${process.pid}`;
  const cwd = projectDirectory(directory, worktree, process.cwd());

  const report = (event, extra = {}) => {
    try {
      const payload = JSON.stringify({
        harness: "opencode",
        hook_event_name: event,
        session_id: sessionID,
        pid: process.pid,
        cwd,
        ...extra,
      });

      const child = spawn("/usr/bin/env", ["python3", HOOK], {
        // Arguments, never a shell string. Output is discarded: the hook is
        // required to stay silent, and nothing here reads it.
        stdio: ["pipe", "ignore", "ignore"],
      });
      child.on("error", () => {});
      child.stdin.on("error", () => {});
      child.stdin.end(payload);
    } catch {
      // Never let telemetry break the session it is watching.
    }
  };

  // Plugins are constructed once per OpenCode process, which is the earliest
  // point a sprite can appear.
  report("session.created");

  return {
    "session.created": async () => report("session.created"),
    "session.idle": async () => report("session.idle"),
    "session.error": async () => report("session.error"),
    "session.deleted": async () => report("session.deleted"),

    // OpenCode is more specific than most harnesses here: it says exactly when
    // it is blocked on a permission decision, which is the one state this whole
    // overlay exists to surface.
    "permission.asked": async () => report("permission.asked"),
    "permission.replied": async () => report("permission.replied"),

    "tool.execute.before": async (input) => report("tool.execute.before", {
      tool_name: input?.tool ?? input?.name ?? null,
    }),

    // Belt and braces. OpenCode documents per-event handler keys, but a generic
    // `event` handler is also supported, and which of the two actually fires
    // has varied. Unknown event names are ignored by the hook, so handling both
    // costs nothing and means state transitions survive either dispatch style.
    event: async ({ event }) => {
      const type = event?.type;
      if (typeof type === "string" && TRACKED.has(type)) report(type);
    },
  };
};

const TRACKED = new Set([
  "session.created", "session.idle", "session.error", "session.deleted",
  "permission.asked", "permission.replied",
]);

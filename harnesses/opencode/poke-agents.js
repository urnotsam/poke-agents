/**
 * poke-agents plugin for OpenCode.
 *
 * Reports session lifecycle to poke-agents, which draws a Pokémon on your
 * desktop for every running agent. Install with:
 *
 *     poke-agents install --harness opencode
 *
 * OpenCode loads plugins from ~/.config/opencode/plugins/ (global) or
 * .opencode/plugins/ (per project).
 *
 * Two things this deliberately does not do:
 *
 * It never throws. A plugin fault should not disturb the session it is
 * observing, so every handler swallows its own errors.
 *
 * It reports its own pid rather than letting poke-agents work it out by walking
 * the process tree. The plugin runs inside OpenCode, so it simply knows.
 */

const HOOK = process.env.POKE_AGENTS_HOOK
  || `${process.env.HOME}/.claude/poke-agents/harnesses/pokeagents_hook.py`;

export const PokeAgents = async ({ directory, worktree, $ }) => {
  // One sprite per OpenCode process. Session ids are not exposed to plugins,
  // and the pid is what terminal adapters match on for click-to-focus anyway.
  const sessionID = `opencode-${process.pid}`;

  const report = async (event, extra = {}) => {
    try {
      const payload = JSON.stringify({
        harness: "opencode",
        hook_event_name: event,
        session_id: sessionID,
        pid: process.pid,
        cwd: worktree || directory || process.cwd(),
        ...extra,
      });
      // Piped on stdin, never interpolated into the command line.
      await $`/usr/bin/env python3 ${HOOK}`.stdin(payload).quiet().nothrow();
    } catch {
      // Observing a session must never be able to break it.
    }
  };

  await report("session.created");

  return {
    "session.created": async () => report("session.created"),
    "session.idle": async () => report("session.idle"),
    "session.error": async () => report("session.error"),
    "session.deleted": async () => report("session.deleted"),

    // OpenCode is more specific than most harnesses here: it tells us exactly
    // when it is blocked on a permission decision, which is the one state the
    // whole overlay exists to surface.
    "permission.asked": async () => report("permission.asked"),
    "permission.replied": async () => report("permission.replied"),

    "tool.execute.before": async (input) => report("tool.execute.before", {
      tool_name: input?.tool ?? input?.name ?? null,
    }),
  };
};

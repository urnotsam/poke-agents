---
name: Agent harness support
about: Request or contribute support for another coding agent
labels: harness
---

## Which harness

Name and version:

## How does it let you react to events?

- [ ] Runs a shell command on lifecycle events (like Claude Code, goose, Crush)
- [ ] Has a plugin API (like OpenCode)
- [ ] Neither — but a terminal can enumerate its sessions
- [ ] Neither, and no way to observe it

Link to its hooks or plugin documentation:

## Which events does it expose?

The six that matter are: session start, activity, tool use, **blocked on the
user**, turn finished, session end. `needs-user` is the important one — it is
what the whole overlay exists to surface. A harness missing some of these can
still be supported; it just has to declare the gap.

## Are you writing it?

See [harnesses/README.md](../../harnesses/README.md). If it runs shell commands
on events, it needs no code at all — only an event map and an installer.

---
name: Bug report
about: Something behaves differently than described
labels: bug
---

## What happened

## What you expected

## Steps to reproduce

## Diagnostics

Please include the output of:

```bash
poke-agents doctor
poke-agents ls
poke-agents terminals
```

And the last few lines of these, if they exist:

```bash
tail -20 ~/.claude/poke-agents/overlay.log   # clicks, focus attempts, adapters
tail -20 ~/.claude/poke-agents/hook.log      # hook errors (usually empty)
```

## Environment

- macOS version:
- Harness (Claude Code / OpenCode / goose / Crush):
- Terminal:

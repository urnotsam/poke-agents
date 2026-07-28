# Contributing

## Terminal adapters

The most useful contribution is an adapter for a terminal that isn't supported
yet. It's one small executable and needs no Swift — the full contract, with a
worked example, is in [terminals/README.md](terminals/README.md).

Keep adapters dependency-free (POSIX shell, or Python 3 standard library), and
say in the PR which terminal and version you tested against. `focus` needs to do
both halves of the job: select the right tab or pane, *and* bring the host
application to the front.

## Running the tests

```bash
cd hook && PYTHONPATH=. python3 -m unittest discover -s tests
cd overlay && swift run ClaudemonTests
```

Swift tests run as a plain executable rather than through XCTest, which ships
only with full Xcode. The Command Line Tools are enough to build and test
everything here.

## What the tests are for

The layout invariants are the load-bearing ones: across all twelve display modes,
three sizes, and five screen sizes, sprites must never overlap, never leave the
screen except by an intentional marquee wrap, and never jump position when their
state changes. If you touch `Layout.swift`, those tests are the specification.

They have been mutation-tested — removing the capacity clamp, or redirecting
wander along the travel axis instead of across it, both make them fail. Please
keep them that way; a suite that cannot fail is not evidence.

## Things worth knowing before changing the hook

`hook/claudemon_hook.py` runs inside every Claude Code session on every event.
Two rules are not negotiable:

1. **Always exit 0.** A hook that fails loudly disrupts real work.
2. **Never write to stdout.** `SessionStart` stdout is injected into the model's
   context, so a stray `print` silently pollutes the user's conversation.

It is also a hot path — `PreToolUse` fires on every tool call — so avoid adding
subprocesses or file reads to it. The owning process is resolved lazily for
exactly this reason.

## Security

Session records live in a user-writable directory, so treat every field in them
as untrusted input on the read side. In particular, never interpolate a value
from a session record into a shell command or an AppleScript source string —
pass it as an argument. If you find something exploitable, open an issue.

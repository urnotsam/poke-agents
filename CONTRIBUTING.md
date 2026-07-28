# Contributing

Bug reports, terminal adapters, harness integrations, and arguments about the
species roster are all welcome.

## How changes get in

`main` is protected: changes land through a pull request with CI green. Fork or
branch, open a PR, and the checks run automatically on macOS.

You do not need an approving review — self-merge is fine once CI passes. The
protection exists so nothing lands untested or force-pushes over history, not to
add ceremony.

## Terminal adapters

The most useful contribution is an adapter for a terminal that isn't supported
yet. It's one small executable and needs no Swift — the full contract, with a
worked example, is in [terminals/README.md](terminals/README.md).

Keep adapters dependency-free (POSIX shell, or Python 3 standard library), and
say in the PR which terminal and version you tested against. `focus` needs to do
both halves of the job: select the right tab or pane, *and* bring the host
application to the front.

## What CI checks

Both test suites, an app-bundle build, that every terminal adapter is valid
executable shell, and that installing then uninstalling leaves an unrelated hook
in `settings.json` untouched. That last one matters more than it sounds: the
installer edits a file every one of your agent sessions depends on.

## Running the tests

```bash
cd hook && PYTHONPATH=. python3 -m unittest discover -s tests
cd overlay && swift run PokeAgentsTests
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

`hook/pokeagents_hook.py` runs inside every Claude Code session on every event.
Two rules are not negotiable:

1. **Always exit 0.** A hook that fails loudly disrupts real work.
2. **Never write to stdout.** `SessionStart` stdout is injected into the model's
   context, so a stray `print` silently pollutes the user's conversation.

It is also a hot path — `PreToolUse` fires on every tool call — so avoid adding
subprocesses or file reads to it. The owning process is resolved lazily for
exactly this reason.

## Reviewing your own work

Two things are easy to get wrong here and hard to notice:

**Silent failures.** Everything in this project is built to fail quietly so it
cannot disturb the agent it is watching — the hook always exits 0, adapters
swallow their errors, the plugin catches its own exceptions. That is right for
users and terrible for debugging. When something does not work, check
`~/.claude/poke-agents/overlay.log` and `hook.log` before assuming the code is
not running. Two real bugs in this project were `catch {}` blocks hiding a
broken call.

**Tests that cannot fail.** If you add an invariant, break the implementation on
purpose and confirm the test catches it. The layout and hidden-session suites
were both mutation-tested this way, and in both cases the first version of the
test passed against code that was actually wrong.

## Security

Session records live in a user-writable directory, so treat every field in them
as untrusted input on the read side. In particular, never interpolate a value
from a session record into a shell command or an AppleScript source string —
pass it as an argument. If you find something exploitable, open an issue.

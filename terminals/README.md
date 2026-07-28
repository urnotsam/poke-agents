# Terminal adapters

An adapter teaches Claudemon how to find and focus the terminal running a
session. Adding support for your terminal means writing one small executable —
**you never have to touch the Swift code or rebuild the app.**

Adapters live in `~/.claude/claudemon/terminals/`. Anything executable in that
directory is an adapter, in any language. `claudemon install` copies the
built-ins there; your own files are never overwritten.

## The contract

Your adapter is invoked with one subcommand and must communicate through its
**exit code**.

### `detect`

> Can you work on this machine right now?

Exit `0` if your terminal is installed and running, non-zero otherwise. Keep
this fast — it is called before a focus attempt. Results are cached briefly.

```bash
detect)  pgrep -x kitty >/dev/null ;;
```

### `focus`

> Bring the session in front of the user.

Called with the session's process id and tty:

```
myterm focus <pid> <tty>
```

`<tty>` may be the literal string `none` for a session with no controlling
terminal, such as a background agent. Exit `0` only if you actually focused
something — a non-zero exit lets Claudemon try the next adapter, and if they all
decline the sprite shakes to say "nowhere to go".

Focusing usually means two steps, and skipping the second is the most common
mistake: select the right tab or pane **and** bring the host application to the
front. If you only do the first, nothing appears to happen when another app is
focused.

### `discover` (optional)

> What sessions exist right now?

Hooks only learn about a session once it fires an event, so a fresh install
shows nothing until you type something. If your terminal can enumerate its own
sessions, implement `discover` and `claudemon adopt` will show them right away.

Print one JSON object per line:

```json
{"pid": 12345, "label": "refactor the parser", "state": "running"}
```

`pid` is required and must be the pid of the `claude` process — that is the key
everything else joins on. `label` and `state` are optional; `state` is one of
`running`, `attention`, or `done`. Exit non-zero if you cannot enumerate.

Anything you print on any other subcommand is ignored.

## Environment

| Variable | Meaning |
|---|---|
| `CLAUDEMON_SESSION_JSON` | The full session record, for adapters wanting more than pid and tty |
| `CLAUDEMON_HOME` | Claudemon's state directory |

## A complete example

```bash
#!/usr/bin/env bash
# ~/.claude/claudemon/terminals/kitty
set -euo pipefail

case "${1:-}" in
  detect)
    command -v kitty >/dev/null && pgrep -x kitty >/dev/null
    ;;
  focus)
    tty="${3:-none}"
    [ "$tty" = "none" ] && exit 1
    # Ask kitty which window owns this tty, focus it, then raise the app.
    win=$(kitty @ ls | python3 -c '
import json,sys
tty=sys.argv[1]
for os_win in json.load(sys.stdin):
    for tab in os_win["tabs"]:
        for w in tab["windows"]:
            if w.get("foreground_processes") and any(
                    p.get("cwd") is not None for p in w["foreground_processes"]):
                if w.get("tty") == tty:
                    print(w["id"]); sys.exit(0)
sys.exit(1)' "$tty") || exit 1
    kitty @ focus-window --match "id:$win" || exit 1
    osascript -e 'tell application "kitty" to activate'
    ;;
  *)
    exit 2
    ;;
esac
```

## Ordering

Adapters are tried in the order listed in `~/.claude/claudemon/config.json`:

```json
{ "terminals": ["herdr", "kitty", "terminal-app"] }
```

Unlisted adapters are tried afterwards in alphabetical order. To disable one,
list the others explicitly or remove the file.

## Testing yours

```bash
claudemon terminals              # which adapters are found, and which detect
claudemon terminals --focus PID  # run a real focus attempt and show the result
```

## Contributing one back

Adapters for new terminals are very welcome. Put it in `terminals/` in the
repository, keep it dependency-free (POSIX shell, or Python 3 standard library),
and note in the PR which terminal version you tested against.

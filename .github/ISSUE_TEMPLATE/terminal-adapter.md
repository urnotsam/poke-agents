---
name: Terminal support
about: Request or contribute support for a terminal
labels: terminal-adapter
---

## Which terminal

Name and version:

## Does it have a way to address a specific tab or pane?

This is the part that decides whether an adapter is possible. Focusing needs to
select the right tab **and** raise the host application. Useful signals:

- A CLI that can list and focus windows (`kitty @ ls`, `wezterm cli list`)
- An AppleScript dictionary exposing `tty` per tab
- Anything that maps a pid or tty to a window

If none of these exist, an adapter can still raise the app — better than
nothing, and that is what the Ghostty adapter does today.

## Are you writing it?

Adapters are one small executable and need no Swift. The contract, with a worked
example, is in [terminals/README.md](../../terminals/README.md). Happy to help
if you get stuck.

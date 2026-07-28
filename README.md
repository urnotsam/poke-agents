# Claudemon

Your running Claude Code sessions, as Pokémon on your desktop.

Every session gets a sprite. It wanders your screen while the agent works, stops
and waves an exclamation mark when the agent needs you, and curls up asleep when
the turn is done. Click one to jump straight to the terminal running it.

![Three sprite states at three sizes](docs/images/states-and-sizes.png)

*Left to right: `running`, `attention`, `done`. Top to bottom: large, medium, small.*

The point is peripheral vision. If you run several agents at once, the thing you
actually need to know is *which one is waiting on you* — and you need to know it
without alt-tabbing through terminals to check. A sprite that stops moving and
starts flashing in the corner of your eye answers that question for free.

---

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [How it works](#how-it-works)
- [Display modes](#display-modes)
- [Sizes](#sizes)
- [Sprite states](#sprite-states)
- [Species, and shiny rates](#species-and-shiny-rates)
- [Clicking a sprite](#clicking-a-sprite)
- [Adding your terminal](#adding-your-terminal)
- [Command reference](#command-reference)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [What this installs, and what it can do](#what-this-installs-and-what-it-can-do)
- [Sprites and licensing](#sprites-and-licensing)

---

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode is **not** needed
- Python 3.8+ (macOS ships this)
- Claude Code

## Install

```bash
git clone https://github.com/urnotsam/poke-agents.git
cd poke-agents

./overlay/build.sh            # builds Claudemon.app (~30s, no Xcode required)
./cli/claudemon fetch --all   # caches 180 species (~720 files, one time)
./cli/claudemon install       # wires the Claude Code hooks
open overlay/Claudemon.app
```

`install` backs up `~/.claude/settings.json` before touching it, and only ever
adds entries it marks as its own — see [what this installs](#what-this-installs-and-what-it-can-do).

Sessions already running won't have sprites until they next do something. To see
them immediately:

```bash
./cli/claudemon adopt --watch
```

Check everything landed:

```bash
./cli/claudemon doctor
```

## How it works

```
Claude Code session
      │  hook events (SessionStart, PreToolUse, Notification, Stop, …)
      ▼
claudemon_hook.py                  Python, standard library only
      │  one atomic JSON write
      ▼
~/.claude/claudemon/sessions/*.json      one file per live session
      │  FSEvents
      ▼
Claudemon.app                      Swift menu-bar agent
      │  one borderless window per sprite
      ▼
your desktop
```

The filesystem is the message bus. No server, no database, no socket, no network
listener. Each half works with the other absent: the hook writes files whether or
not the overlay is running, and the overlay happily animates hand-written JSON.

Two consequences worth knowing:

- **Dead sessions get cleaned up automatically.** `SessionEnd` doesn't fire on a
  crash or `kill -9`, so the overlay also checks every 10 seconds whether each
  recorded pid still exists and despawns the ones that don't. Without that, the
  display slowly fills with ghosts and stops meaning anything.
- **The hook is built to stay out of your way.** It always exits 0 and never
  writes to stdout — `SessionStart` stdout gets injected into the model's context,
  so a stray `print` would quietly pollute your conversation. Diagnostics go to
  `~/.claude/claudemon/hook.log`.

## Display modes

Twelve arrangements, from the menu bar icon under **Display**:

| Group | Modes | Behaviour |
|---|---|---|
| **Marquee** | Top, Bottom, Left, Right | Sprites travel along the edge and wrap around |
| **Static** | Top, Bottom, Left, Right | Evenly spaced along the edge, holding position |
| **Cluster** | Top Left, Top Right, Bottom Left, Bottom Right | A three-column grid tucked in the corner |

All twelve come from one geometry model rather than twelve special cases. The
rule that makes it work: **sprites wander only across their line of travel, never
along it.** Wandering along the line would let neighbours close the gap and
overlap; wandering across it never can. In the marquee modes every sprite also
travels at exactly the same speed, so the even spacing assigned once is spacing
kept forever.

Twelve modes × three sizes × five screen sizes are covered by ~298,000 assertions
checking that sprites never overlap, never leave the screen, and never jump when
their state changes.

## Sizes

Small (44pt), Medium (58pt), Large (72pt), from the menu bar under **Size**.

Gen 5 sprites are around 96px natively, so even Large is a slight downscale and
everything stays crisp — sampling is nearest-neighbour, because smoothing pixel
art is the fastest way to make it look cheap.

## Sprite states

| State | What it means | What you see |
|---|---|---|
| `running` | The agent is working | Idle animation loops, sprite drifts along |
| `attention` | **The agent is waiting on you** | Fast bob, orange `!` bubble, pulsing glow, label at full brightness |
| `done` | The turn finished | Static sprite, dimmed to 60%, `zZz` drifting up |

`attention` comes from Claude Code's `Notification` hook, which covers both
permission prompts and idle input requests. It's the state the whole thing exists
to surface, so it also wins any contest for screen space: if more sprites are
live than fit, an `attention` sprite will evict a `done` one rather than be
hidden itself.

## Species, and shiny rates

Species is derived from the session id:

```
species = SPECIES[fnv1a(session_id) % 180]
```

Session ids are random, so this feels like a wild encounter — but because it's
derived rather than stored, the same session keeps its species across an overlay
restart with nothing persisted. If two live sessions would draw the same species,
the second probes forward to the next free one, so you never see doubles.

The roster is 180 species, curated for silhouette legibility at 72pt — the test
of inclusion is whether you can tell what it is from across a desk.

### Shiny

**A sprite has a 1 in 64 chance of being shiny** (about 1.6%), decided by a second
hash of the session id. Like the species, it's derived rather than rolled, so a
shiny session stays shiny for its whole life and across restarts.

That is *far* more generous than the games: 1 in 8192 in Gen 2–5, 1 in 4096 from
Gen 6 on. Those odds are tuned for a game you play for hundreds of hours. At 1 in
4096 you would start roughly ten sessions a day and see your first shiny in about
a year, which is not a feature, it's a rumour. At 1 in 64 you'll see one every
week or two — rare enough to be a small event when it happens, common enough to
actually exist.

To change it, edit `SHINY_ODDS` in [`hook/claudemon/species.py`](hook/claudemon/species.py).
Set it to `1` if you want everything shiny, which is a legitimate aesthetic
choice and looks quite good in the cluster modes.

## Clicking a sprite

Clicking focuses the terminal running that session — the sprite is a launcher,
not just a status light. See the `!` in the corner of your eye, click it, you're
in the session that needs you.

If no adapter can focus the session — a background agent (`claude --bg`) has no
terminal at all — the sprite shakes instead.

## Adding your terminal

Claudemon ships adapters for **herdr**, **Terminal.app**, **iTerm2**, **tmux**,
**WezTerm**, and **Ghostty**. Adding your own means writing one small executable —
you never touch Swift or rebuild the app.

An adapter is any executable in `~/.claude/claudemon/terminals/`, in any language,
that answers two subcommands via its exit code:

```bash
myterm detect              # exit 0 if this terminal is usable right now
myterm focus <pid> <tty>   # exit 0 if you actually focused the session
```

There's an optional third, `discover`, which lets `claudemon adopt` list sessions
your terminal already knows about before they've fired any hook.

Full contract, worked examples, and testing instructions:
**[terminals/README.md](terminals/README.md)**.

Adapters for new terminals are very welcome as PRs.

## Command reference

| Command | What it does |
|---|---|
| `claudemon install` | Add the hooks to `~/.claude/settings.json` (backs it up first) |
| `claudemon uninstall` | Remove exactly the entries it added |
| `claudemon doctor` | Report hooks, state, sprite cache, overlay, and display mode |
| `claudemon ls` | List live sessions as a table |
| `claudemon adopt [--watch]` | Show sessions your terminal already knows about |
| `claudemon fetch --all` | Download and cache the sprite roster |
| `claudemon terminals` | List adapters and which ones detect |
| `claudemon simulate [--count N]` | Write fake sessions, for working on the overlay itself |

## Configuration

`~/.claude/claudemon/config.json`:

```json
{
  "mode": "marqueeTop",
  "size": "large",
  "terminals": ["herdr", "iterm2", "terminal-app"]
}
```

`mode` and `size` are normally set from the menu bar. `terminals` is optional and
sets adapter priority; unlisted adapters are tried afterwards in alphabetical
order.

Environment variables:

| Variable | Effect |
|---|---|
| `CLAUDEMON_DISABLE=1` | Hook does nothing — turn it off without uninstalling |
| `CLAUDEMON_HOME` | Move the state directory (default `~/.claude/claudemon`) |

## Troubleshooting

**No sprites appear.** Run `claudemon doctor`. Hooks only fire on a session's
*next* event, so try typing something, or run `claudemon adopt --watch`.

**Clicking does nothing.** Run `claudemon terminals` to see whether any adapter
detects. If yours isn't listed, [write an adapter](terminals/README.md) — it's
about ten lines. Check `~/.claude/claudemon/overlay.log`, which records every
click, the pid and tty it resolved, and whether focusing succeeded.

**Clicking switches the tab but doesn't bring the window forward.** Your adapter's
`focus` is doing half the job. It needs to select the tab *and* activate the host
application; this is the most common mistake when writing one.

**Sprites are Poké Balls.** The sprite cache is empty or the download failed. Run
`claudemon fetch --all`.

**A sprite is stuck.** The overlay reaps sessions whose process is gone within 10
seconds. If one persists, its pid is genuinely still alive — check with
`claudemon ls`, which flags stale records.

**Sprites cover something important.** Switch to a cluster mode, or Small, or hit
Pause in the menu bar.

## Uninstall

```bash
./cli/claudemon uninstall     # removes only its own hook entries
rm -rf ~/.claude/claudemon    # state, sprite cache, config, logs
```

Then quit the app from the menu bar and delete `Claudemon.app`.

## What this installs, and what it can do

Worth being explicit, because this asks you to run code on every Claude Code
event.

`claudemon install` adds six entries to `~/.claude/settings.json`, one per hook
event, each running `hook/claudemon_hook.py` from wherever you cloned this repo.
Claude Code hooks are arbitrary shell commands, so **anything in that script runs
with your user's full privileges, on every event, in every session.** That is
true of any Claude Code hook, and it's worth understanding before installing one
from the internet — including this one.

What this hook actually does: reads the event JSON on stdin, resolves the owning
process, and writes one small JSON file. It makes no network requests. The only
component that touches the network is `claudemon fetch`, which downloads sprites
over HTTPS from `play.pokemonshowdown.com` when you run it explicitly.

Everything stays on your machine. Nothing is sent anywhere. Session labels can
include your working-directory and terminal-title text, so they're written only
to `~/.claude/claudemon/` and drawn on your own screen.

The installer backs up your settings file first, marks its own entries so
`uninstall` removes exactly those and nothing else, and refuses to touch a
settings file it can't parse.

## Sprites and licensing

**The code** is MIT licensed. See [LICENSE](LICENSE).

**The sprites are not mine, and are not in this repository.** Claudemon ships a
downloader, not artwork. `claudemon fetch` pulls sprites at runtime from
[Pokémon Showdown](https://play.pokemonshowdown.com/sprites/) into a local cache
on your own machine. The only bundled image is a Poké Ball, drawn in code as a
fallback.

Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc.,
GAME FREAK Inc., and The Pokémon Company. This is an unofficial fan project,
unaffiliated with and unendorsed by any of them, intended for personal use. The
Gen 5 animated sprites for later-generation Pokémon were made by the Smogon
community; if you plan to do anything with these assets beyond running this on
your own desktop, talk to [Smogon](https://github.com/smogon/sprites) first.

## Contributing

Bug reports, terminal adapters, and species-roster arguments all welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

Run the tests:

```bash
cd hook && PYTHONPATH=. python3 -m unittest discover -s tests
cd overlay && swift run ClaudemonTests
```

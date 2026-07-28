## What this changes

<!-- One or two sentences. If it fixes an issue, link it. -->

## How you tested it

<!-- Be specific. "Ran the tests" is fine if that genuinely covers it; if you
     changed anything visual or anything that touches a terminal, say what you
     actually observed. -->

- [ ] `cd hook && PYTHONPATH=. python3 -m unittest discover -s tests`
- [ ] `cd overlay && swift run PokeAgentsTests`

## If you changed the layout

The layout invariants are the specification: across every display mode, sprite
size and screen size, sprites must never overlap, never leave the screen except
by an intentional marquee wrap, and never jump when their state changes.

- [ ] The invariant tests still pass
- [ ] I checked the tests can still fail — break the change deliberately and
      confirm they catch it

## If you added a terminal adapter

- [ ] `detect` exits 0 only when the terminal is genuinely usable
- [ ] `focus` selects the tab **and** brings the host app to the front
- [ ] Terminal and version tested against: <!-- e.g. kitty 0.35 -->

## If you added a harness

- [ ] Event map covers the lifecycle, or `limitations` says what is missing
- [ ] Tested against a real install of that harness, not only the docs

## Anything running inside a session

- [ ] Always exits 0
- [ ] Writes nothing to stdout

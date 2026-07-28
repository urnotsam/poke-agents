"""Terminal adapters.

An adapter is any executable in `~/.claude/poke-agents/terminals/` that answers
subcommands through its exit code:

    <adapter> detect              exit 0 if usable on this machine right now
    <adapter> focus <pid> <tty>   exit 0 if it actually focused the session
    <adapter> discover            optional; one JSON object per line

Everything ships as an adapter, built-ins included, so supporting a new terminal
never means changing this project's code. The Swift overlay implements the same
contract for focusing; this module is the Python half, used by the CLI for
discovery and diagnostics.

See `terminals/README.md` for the full contract.
"""

import json
import os
import subprocess
from typing import Dict, List, Optional

from . import paths

DETECT_TIMEOUT = 5
FOCUS_TIMEOUT = 15
DISCOVER_TIMEOUT = 15


def directory() -> str:
    return os.path.join(paths.home(), "terminals")


class Adapter:
    """One executable implementing the adapter contract."""

    def __init__(self, path: str):
        self.path = path
        self.name = os.path.basename(path)

    def __repr__(self) -> str:
        return "Adapter(%r)" % self.name

    def detects(self) -> bool:
        return self._run(["detect"], DETECT_TIMEOUT)[0]

    def can_discover(self) -> bool:
        """Whether `discover` is implemented and currently returns anything.

        The contract has no capability query, so this is answered by asking:
        an adapter that does not implement it exits non-zero.
        """
        return self._run(["discover"], DISCOVER_TIMEOUT)[0]

    def discover(self) -> List[Dict]:
        ok, output = self._run(["discover"], DISCOVER_TIMEOUT)
        if not ok:
            return []

        found = []
        for line in output.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                # One malformed line must not discard the rest.
                continue
            if isinstance(entry, dict):
                found.append(entry)
        return found

    def focus(self, pid: Optional[int], tty: Optional[str]) -> bool:
        # Passed as argv, never interpolated into a shell or script string.
        return self._run(["focus", str(pid or 0), tty or "none"], FOCUS_TIMEOUT)[0]

    def _run(self, args: List[str], timeout: int):
        env = dict(os.environ)
        env["POKEAGENTS_HOME"] = paths.home()
        try:
            out = subprocess.run(
                [self.path] + args, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                timeout=timeout, env=env,
            )
        except (OSError, subprocess.SubprocessError):
            return False, ""
        return out.returncode == 0, out.stdout.decode("utf-8", "replace")


def available(preferred: Optional[List[str]] = None) -> List[Adapter]:
    """Adapters on disk, most preferred first.

    Anything not named in `preferred` follows in alphabetical order, so dropping
    a new adapter into the directory works without also editing the config.
    """
    try:
        names = sorted(os.listdir(directory()))
    except OSError:
        return []

    found = []
    for name in names:
        if name.startswith(".") or name.endswith(".md"):
            continue
        path = os.path.join(directory(), name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            found.append(Adapter(path))

    if not preferred:
        return found

    by_name = {a.name: a for a in found}
    ordered = [by_name[n] for n in preferred if n in by_name]
    ordered.extend(a for a in found if a.name not in preferred)
    return ordered


def detected(preferred: Optional[List[str]] = None) -> List[Adapter]:
    return [a for a in available(preferred) if a.detects()]


def discovering(preferred: Optional[List[str]] = None) -> List[Adapter]:
    """Detected adapters that can enumerate sessions."""
    return [a for a in detected(preferred) if a.can_discover()]

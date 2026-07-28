"""Installing the OpenCode plugin.

OpenCode loads plugins as JavaScript modules from a directory, so installing is
copying one file with the hook's absolute path baked in — the plugin has no
other way to know where this checkout lives.

The same care as the Claude Code installer: never clobber a file we did not
write, and remove exactly what we added.
"""

import os
from typing import Optional

from . import atomicio

PLUGIN_NAME = "poke-agents.js"

# Present in every file we generate. Refusing to touch a file without it means a
# user's own plugin of the same name is safe.
MARKER = "poke-agents plugin for OpenCode"

_HOOK_PLACEHOLDER = """const HOOK = process.env.POKE_AGENTS_HOOK
  || `${process.env.HOME}/.claude/poke-agents/harnesses/pokeagents_hook.py`;"""


class OpenCodeError(Exception):
    pass


def default_directory() -> str:
    return os.path.expanduser("~/.config/opencode/plugins")


def plugin_path(directory: Optional[str] = None) -> str:
    return os.path.join(directory or default_directory(), PLUGIN_NAME)


def is_available() -> bool:
    """True when OpenCode looks installed.

    Its config directory is created on first run, so this is a reasonable proxy
    without launching anything.
    """
    return os.path.isdir(os.path.expanduser("~/.config/opencode"))


def is_installed(directory: Optional[str] = None) -> bool:
    path = plugin_path(directory)
    try:
        with open(path) as fh:
            return MARKER in fh.read()
    except OSError:
        return False


def install(template_path: str, hook_path: str,
            directory: Optional[str] = None) -> str:
    """Write the plugin with `hook_path` baked in. Returns where it landed."""
    try:
        with open(template_path) as fh:
            source = fh.read()
    except OSError as exc:
        raise OpenCodeError("cannot read plugin template: %s" % exc)

    if MARKER not in source:
        raise OpenCodeError("plugin template is missing its marker")

    target = plugin_path(directory)
    if os.path.exists(target) and not is_installed(directory):
        raise OpenCodeError(
            "%s exists and was not written by poke-agents; move it aside first"
            % target)

    # A JS string literal, so a path containing a quote or a backslash would
    # otherwise break the file.
    literal = '"%s"' % hook_path.replace("\\", "\\\\").replace('"', '\\"')
    source = source.replace(_HOOK_PLACEHOLDER,
                            "const HOOK = process.env.POKE_AGENTS_HOOK || %s;" % literal)

    atomicio.write_text(target, source)
    return target


def uninstall(directory: Optional[str] = None) -> bool:
    """Remove the plugin if we wrote it. Returns whether anything was removed."""
    if not is_installed(directory):
        return False
    try:
        os.unlink(plugin_path(directory))
    except OSError:
        return False
    return True

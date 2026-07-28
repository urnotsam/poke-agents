"""Filesystem locations, overridable for tests and alternate installs."""

import os

_ENV_HOME = "CLAUDEMON_HOME"
_ENV_DISABLE = "CLAUDEMON_DISABLE"


def home() -> str:
    override = os.environ.get(_ENV_HOME)
    if override:
        return os.path.expanduser(override)
    return os.path.expanduser("~/.claude/claudemon")


def sessions_dir() -> str:
    return os.path.join(home(), "sessions")


def sprites_dir() -> str:
    return os.path.join(home(), "sprites")


def log_path() -> str:
    return os.path.join(home(), "hook.log")


def disabled() -> bool:
    return os.environ.get(_ENV_DISABLE, "").strip() not in ("", "0", "false", "no")

"""Human-readable session labels.

Species is random, so the label carries all of a sprite's identity. It has to
survive worktree paths, which are the ugliest thing it will encounter.
"""

import os
import subprocess
from typing import Optional

# Wide enough for a repo@branch worktree label, which is the case the label
# most needs to disambiguate. Narrower cut real names in half.
MAX_LEN = 24
_GIT_TIMEOUT = 2.0
_FALLBACK = "session"


def format_label(display_name: Optional[str], repo: Optional[str],
                 branch: Optional[str], is_worktree: bool,
                 cwd_basename: str) -> str:
    """Compose a label from already-resolved parts. Pure."""
    if display_name and display_name.strip():
        return _truncate(display_name.strip())

    if repo:
        if is_worktree:
            suffix = branch or cwd_basename
            if suffix:
                return _truncate("%s@%s" % (repo, suffix))
        return _truncate(repo)

    return _truncate(cwd_basename or _FALLBACK)


def _truncate(text: str) -> str:
    if len(text) <= MAX_LEN:
        return text
    return text[: MAX_LEN - 1] + "…"


def derive(cwd: str, display_name: Optional[str] = None) -> str:
    """Resolve a label for a working directory, consulting git when possible."""
    if display_name and display_name.strip():
        return _truncate(display_name.strip())

    repo, branch, is_worktree = _git_context(cwd)
    return format_label(
        display_name=None, repo=repo, branch=branch,
        is_worktree=is_worktree, cwd_basename=os.path.basename(cwd.rstrip("/")),
    )


def _git_context(cwd):
    """Return (repo_name, branch, is_worktree). All-None when cwd is not a repo."""
    common = _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return None, None, False

    # In a linked worktree the common dir is the primary repo's .git, while the
    # per-worktree git dir lives under .git/worktrees/<name>. Comparing the two
    # is how you tell a worktree from the primary checkout.
    git_dir = _git(cwd, "rev-parse", "--path-format=absolute", "--git-dir")
    is_worktree = bool(git_dir) and os.path.normpath(git_dir) != os.path.normpath(common)

    repo_root = os.path.dirname(os.path.normpath(common))
    repo = os.path.basename(repo_root) or None
    if os.path.basename(os.path.normpath(common)) != ".git":
        # Bare repo: the common dir is the repo itself.
        repo = os.path.basename(os.path.normpath(common)) or None

    branch = _git(cwd, "rev-parse", "--abbrev-ref", "HEAD")
    if branch == "HEAD":  # detached
        branch = None

    return repo, branch, is_worktree


def _git(cwd: str, *args) -> Optional[str]:
    if not os.path.isdir(cwd):
        return None
    try:
        out = subprocess.run(
            ["git"] + list(args), cwd=cwd, timeout=_GIT_TIMEOUT,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.decode("utf-8", "replace").strip() or None

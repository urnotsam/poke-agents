"""Human-readable session labels.

Species is random, so the label carries all of a sprite's identity. It has to
survive worktree paths, which are the ugliest thing it will encounter.
"""

import os
import subprocess
from typing import Optional

# Labels sit under a sprite, and the card is sized to fit them, so a long label
# makes every sprite wider and the whole display heavier. Short enough to stay
# glanceable, long enough that a `repo@branch` worktree label — the case the
# label most needs to disambiguate — still fits whole.
MAX_LEN = 20
_GIT_TIMEOUT = 2.0
_FALLBACK = "session"

# Session titles are usually phrased as instructions, and the leading verb is
# the least distinguishing part — a great many of them start with "Implement"
# or "Add".
_LEADING_VERBS = frozenset("""
add build change check clean create debug design document draft fix
implement improve investigate make migrate move port refactor remove rename
research review rewrite set setup ship test try update upgrade wire write
""".split())

# Interrogatives and vague qualifiers carry no identity either: "why deployment"
# is a worse label than "deployment".
_STOPWORDS = frozenset("""
a an and are as at be by for from how in into is it its new of on onto or our
so that the their then there these this to up via what when where which who
why with within your
""".split())


def format_label(display_name: Optional[str], repo: Optional[str],
                 branch: Optional[str], is_worktree: bool,
                 cwd_basename: str) -> str:
    """Compose a label from already-resolved parts. Pure."""
    if display_name and display_name.strip():
        return _truncate(shorten(display_name))

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


def shorten(text: str, max_len: int = MAX_LEN) -> str:
    """Compress a session title into something that fits under a sprite.

    Titles read like instructions — "Implement the export feature for billing" —
    and plain truncation keeps the opening words, which are the ones every title
    shares. Dropping the leading verb and the filler words keeps the part that
    actually distinguishes one session from another.
    """
    words = text.strip().split()
    if not words:
        return ""

    # Only drop a leading verb when something recognisable survives it.
    if len(words) > 1 and words[0].strip(":,").lower() in _LEADING_VERBS:
        words = words[1:]

    meaningful = [w for w in words if w.lower().strip(".,:;") not in _STOPWORDS]
    if not meaningful:
        meaningful = words

    kept = []
    length = 0
    for word in meaningful:
        extra = len(word) + (1 if kept else 0)
        if kept and length + extra > max_len:
            break
        kept.append(word)
        length += extra

    result = " ".join(kept)
    # The first word is always taken, so one very long word can still overflow.
    if len(result) > max_len:
        result = result[: max_len - 1] + "…"
    return result


def derive(cwd: str, display_name: Optional[str] = None) -> str:
    """Resolve a label for a working directory, consulting git when possible."""
    if display_name and display_name.strip():
        return _truncate(shorten(display_name))

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

"""Atomic file writes.

Readers of the state directory must never observe a half-written file, so every
write in this project lands via a temp file plus `os.replace`. Centralised
because the naive `path + ".tmp"` version of this idiom is unsafe when two
writers target the same destination, and that difference is exactly the kind of
thing that drifts when the pattern is copy-pasted.
"""

import os
import tempfile


def write_bytes(path: str, data: bytes) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)

    # mkstemp in the destination directory keeps the replace atomic (same
    # filesystem) and gives concurrent writers distinct temp names.
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_text(path: str, text: str) -> None:
    write_bytes(path, text.encode("utf-8"))

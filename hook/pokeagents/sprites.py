"""Sprite naming and source URLs.

Sprites come from Pokémon Showdown and are cached on disk. They are Nintendo /
Game Freak / The Pokémon Company property, so this module describes where to
fetch them from and never ships them.

The animated GIF drives the running and attention states; the static PNG is what
a finished session settles into.
"""

from dataclasses import dataclass
from typing import List

BASE = "https://play.pokemonshowdown.com/sprites"
HOST = "play.pokemonshowdown.com"
USER_AGENT = "pokeagents/0.1 (personal desktop overlay)"

# Sprites are small; the largest in the roster is well under 200KB. Capping the
# read stops a redirect or a compromised CDN from filling the disk, and the
# magic-byte check stops whatever comes back from being cached as an image.
MAX_BYTES = 2 * 1024 * 1024

_MAGIC = {
    ".gif": (b"GIF87a", b"GIF89a"),
    ".png": (b"\x89PNG\r\n\x1a\n",),
}


def looks_like(extension: str, data: bytes) -> bool:
    """True when the bytes actually start with the format we asked for."""
    prefixes = _MAGIC.get(extension)
    if not prefixes:
        return False
    return any(data.startswith(prefix) for prefix in prefixes)


@dataclass(frozen=True)
class Variant:
    remote_dir: str
    suffix: str
    extension: str

    def filename(self, name: str) -> str:
        return name + self.suffix + self.extension

    def url(self, name: str) -> str:
        return "%s/%s/%s%s" % (BASE, self.remote_dir, name, self.extension)


VARIANTS: List[Variant] = [
    Variant(remote_dir="gen5ani", suffix="", extension=".gif"),
    Variant(remote_dir="gen5ani-shiny", suffix="-shiny", extension=".gif"),
    Variant(remote_dir="gen5", suffix="-static", extension=".png"),
    Variant(remote_dir="gen5-shiny", suffix="-shiny-static", extension=".png"),
]


def variant_for(shiny: bool, animated: bool) -> Variant:
    """The variant the overlay should draw for a given session."""
    suffix = ""
    if shiny:
        suffix += "-shiny"
    if not animated:
        suffix += "-static"
    for variant in VARIANTS:
        if variant.suffix == suffix:
            return variant
    raise KeyError(suffix)

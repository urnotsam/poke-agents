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
USER_AGENT = "claudemon/0.1 (personal desktop overlay)"


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

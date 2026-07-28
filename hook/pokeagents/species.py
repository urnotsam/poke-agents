"""Deterministic species assignment.

A session's species is derived from its id rather than stored, so it survives an
overlay restart with no persistence and no lookup table. Session ids are random,
so a hash of one feels like a wild encounter while staying reproducible.
"""

from dataclasses import dataclass
from typing import Set

# Curated for silhouette legibility at 72pt. Every one of these reads clearly as
# itself from across a desk, which matters more here than roster completeness.
SPECIES = [
    "bulbasaur", "charmander", "squirtle", "caterpie", "pidgey", "rattata",
    "pikachu", "sandshrew", "nidoranf", "nidoranm", "clefairy", "vulpix", "jigglypuff",
    "zubat", "oddish", "paras", "venonat", "diglett", "meowth", "psyduck",
    "mankey", "growlithe", "poliwag", "abra", "machop", "bellsprout",
    "tentacool", "geodude", "ponyta", "slowpoke", "magnemite", "farfetchd",
    "doduo", "seel", "grimer", "shellder", "gastly", "onix", "drowzee",
    "krabby", "voltorb", "exeggcute", "cubone", "hitmonlee", "lickitung",
    "koffing", "rhyhorn", "chansey", "tangela", "kangaskhan", "horsea",
    "goldeen", "staryu", "scyther", "jynx", "electabuzz", "magmar", "pinsir",
    "tauros", "magikarp", "lapras", "ditto", "eevee", "porygon", "omanyte",
    "kabuto", "aerodactyl", "snorlax", "dratini", "chikorita", "cyndaquil",
    "totodile", "sentret", "hoothoot", "ledyba", "spinarak", "chinchou",
    "togepi", "natu", "mareep", "marill", "sudowoodo", "hoppip", "aipom",
    "sunkern", "yanma", "wooper", "murkrow", "misdreavus", "wobbuffet",
    "girafarig", "pineco", "dunsparce", "gligar", "snubbull", "qwilfish",
    "shuckle", "heracross", "sneasel", "teddiursa", "slugma", "swinub",
    "corsola", "remoraid", "delibird", "mantine", "skarmory", "houndour",
    "phanpy", "stantler", "smeargle", "tyrogue", "smoochum", "elekid",
    "magby", "miltank", "larvitar", "treecko", "torchic", "mudkip",
    "poochyena", "zigzagoon", "wurmple", "lotad", "seedot", "taillow",
    "wingull", "ralts", "surskit", "shroomish", "slakoth", "nincada",
    "whismur", "makuhita", "azurill", "nosepass", "skitty", "sableye",
    "mawile", "aron", "meditite", "electrike", "plusle", "minun", "volbeat",
    "roselia", "gulpin", "carvanha", "wailmer", "numel", "torkoal", "spoink",
    "spinda", "trapinch", "cacnea", "swablu", "zangoose", "seviper",
    "lunatone", "solrock", "barboach", "corphish", "baltoy", "lileep",
    "anorith", "feebas", "castform", "kecleon", "shuppet", "duskull",
    "tropius", "chimecho", "absol", "snorunt", "spheal", "clamperl",
    "relicanth", "luvdisc", "bagon", "beldum",
]

SHINY_ODDS = 64

_FNV_OFFSET = 0x811C9DC5
_FNV_PRIME = 0x01000193
_MASK32 = 0xFFFFFFFF


def fnv1a(text: str) -> int:
    """FNV-1a 32-bit. Chosen over hash() because that is salted per process."""
    h = _FNV_OFFSET
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * _FNV_PRIME) & _MASK32
    return h


@dataclass(frozen=True)
class Assignment:
    name: str
    shiny: bool


def assign(session_id: str, taken: Set[str]) -> Assignment:
    """Pick a species for a session, avoiding any already on screen.

    Falls back to the natural choice when every species is taken, which only
    happens with more concurrent sessions than the roster has entries.
    """
    digest = fnv1a(session_id)
    start = digest % len(SPECIES)
    shiny = (fnv1a("shiny:" + session_id) % SHINY_ODDS) == 0

    for offset in range(len(SPECIES)):
        candidate = SPECIES[(start + offset) % len(SPECIES)]
        if candidate not in taken:
            return Assignment(name=candidate, shiny=shiny)

    return Assignment(name=SPECIES[start], shiny=shiny)

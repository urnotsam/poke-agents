"""Deterministic species assignment.

A session's species is derived from its id rather than stored, so it survives an
overlay restart with no persistence and no lookup table. Session ids are random,
so a hash of one feels like a wild encounter while staying reproducible.
"""

from dataclasses import dataclass
from typing import Set

# Every species Pokemon Showdown has Gen 5 sprites for in all four variants
# (animated, animated shiny, static, static shiny), which is what the running,
# attention and done states need between them.
#
# Female variants are excluded: they differ from the base by a handful of pixels
# and read as the same creature at 72pt, so they would only make two sessions
# harder to tell apart. Regional forms, megas and Gigantamax are included, since
# those are unmistakably different silhouettes.
SPECIES = [
    "abomasnow", "abomasnow-mega", "abra", "absol", "absol-mega", "accelgor",
    "aegislash", "aegislash-blade", "aerodactyl", "aggron", "aipom",
    "alakazam", "alakazam-mega", "alcremie", "alcremie-caramelswirl",
    "alcremie-lemoncream", "alcremie-matchacream", "alcremie-mintcream",
    "alcremie-rainbowswirl", "alcremie-rubycream", "alcremie-rubyswirl",
    "alcremie-saltedcream", "alomomola", "altaria", "amaura", "ambipom",
    "amoonguss", "ampharos", "ampharos-mega", "anorith", "applin",
    "araquanid", "arbok", "arcanine", "arceus", "arceus-bug", "arceus-dark",
    "arceus-dragon", "arceus-electric", "arceus-fairy", "arceus-fighting",
    "arceus-fire", "arceus-flying", "arceus-ghost", "arceus-grass",
    "arceus-ground", "arceus-ice", "arceus-normal", "arceus-poison",
    "arceus-psychic", "arceus-rock", "arceus-steel", "arceus-water", "archen",
    "archeops", "arctibax", "arctovish", "ariados", "armaldo", "aron",
    "arrokuda", "articuno", "articuno-galar", "audino", "aurumoth", "avalugg",
    "axew", "azelf", "azumarill", "azurill", "bagon", "baltoy", "banette",
    "banette-mega", "barboach", "barraskewda", "basculegion", "basculin",
    "basculin-bluestriped", "basculin-whitestriped", "bastiodon", "bayleef",
    "beartic", "beautifly", "beedrill", "beedrill-mega", "beheeyem", "beldum",
    "bellossom", "bellsprout", "bergmite", "bewear", "bibarel", "bidoof",
    "binacle", "bisharp", "blacephalon", "blastoise", "blaziken",
    "blaziken-mega", "blissey", "blitzle", "boldore", "bonsly", "bouffalant",
    "bounsweet", "braixen", "braviary", "breloom", "brionne", "bronzong",
    "bronzor", "bruxish", "budew", "buizel", "bulbasaur", "buneary", "burmy",
    "burmy-sandy", "burmy-trash", "butterfree", "buzzwole", "cacnea",
    "cacturne", "calyrex", "calyrex-ice", "camerupt", "carbink", "carnivine",
    "carracosta", "carvanha", "cascoon", "castform", "castform-rainy",
    "castform-snowy", "castform-sunny", "caterpie", "cawmodore", "celebi",
    "celesteela", "chandelure", "chansey", "charizard", "charizard-megax",
    "charjabug", "charmander", "charmeleon", "chatot", "cherrim",
    "cherrim-sunshine", "cherubi", "chewtle", "chienpao", "chikorita",
    "chimchar", "chimecho", "chinchou", "chingling", "chiyu", "cinccino",
    "cinderace-gmax", "clamperl", "clauncher", "clawitzer", "claydol",
    "clefable", "clefairy", "cleffa", "clobbopus", "clodsire", "cloyster",
    "coalossal", "coalossal-gmax", "cobalion", "cofagrigus", "colossoil",
    "combee", "combusken", "comfey", "conkeldurr", "corphish", "corsola",
    "corsola-galar", "corviknight", "corvisquire", "cosmoem", "cosmog",
    "cottonee", "crabominable", "crabrawler", "cradily", "cramorant",
    "cranidos", "crawdaunt", "cresselia", "croagunk", "crobat", "croconaw",
    "crustle", "cryogonal", "cubchoo", "cubone", "cufant", "cursola",
    "cutiefly", "cyndaquil", "darkrai", "darmanitan", "darmanitan-galarzen",
    "darmanitan-zen", "darumaka", "dedenne", "deerling", "deerling-autumn",
    "deerling-summer", "deerling-winter", "deino", "delcatty", "delibird",
    "deoxys", "deoxys-attack", "deoxys-defense", "deoxys-speed", "dewgong",
    "dewott", "dewpider", "dhelmise", "dialga", "dialga-origin", "diancie",
    "diglett", "diglett-alola", "ditto", "dodrio", "doduo", "donphan",
    "dracovish", "dracozolt", "dragalge", "dragapult", "dragonair",
    "dragonite", "drakloak", "drampa", "drapion", "dratini", "drednaw",
    "drednaw-gmax", "dreepy", "drifblim", "drifloon", "drilbur", "drizzile",
    "drowzee", "druddigon", "dubwool", "ducklett", "dugtrio", "dugtrio-alola",
    "dunsparce", "duosion", "duraludon", "durant", "dusclops", "dusknoir",
    "duskull", "dustox", "dwebble", "eelektrik", "eelektross", "eevee",
    "eevee-gmax", "eiscue", "eiscue-noice", "ekans", "eldegoss", "electabuzz",
    "electivire", "electrike", "electrode", "elekid", "elgyem", "emboar",
    "emolga", "empoleon", "entei", "escavalier", "espeon", "eternatus",
    "excadrill", "exeggcute", "exeggutor", "exeggutor-alola", "exploud",
    "farfetchd", "farfetchd-galar", "fearow", "feebas", "fennekin",
    "feraligatr", "ferroseed", "ferrothorn", "finneon", "flaaffy", "flabebe",
    "flabebe-blue", "flabebe-orange", "flabebe-white", "flabebe-yellow",
    "flareon", "fletchinder", "fletchling", "floatzel", "floette", "florges",
    "fluttermane", "flygon", "fomantis", "foongus", "forretress", "fraxure",
    "frigibax", "frillish", "froakie", "froslass", "frosmoth", "furret",
    "gabite", "gallade", "galvantula", "garbodor", "garbodor-gmax",
    "garchomp", "garchomp-mega", "gardevoir", "gardevoir-mega", "gastly",
    "gastrodon", "gastrodon-east", "genesect", "genesect-burn",
    "genesect-chill", "genesect-douse", "genesect-shock", "gengar", "geodude",
    "geodude-alola", "gholdengo", "gible", "gigalith", "gimmighoul",
    "girafarig", "giratina", "giratina-origin", "glaceon", "glalie",
    "glalie-mega", "glameow", "glastrier", "gligar", "glimmet", "gliscor",
    "gloom", "golbat", "goldeen", "golduck", "golem", "golem-alola", "golett",
    "golurk", "goodra", "goodra-hisui", "goomy", "gorebyss", "gothita",
    "gothitelle", "gothorita", "gougingfire", "granbull", "graveler",
    "graveler-alola", "greattusk", "greninja", "grimer", "grimer-alola",
    "grimmsnarl", "grookey", "grotle", "groudon", "groudon-primal", "grovyle",
    "growlithe", "grubbin", "grumpig", "gulpin", "gumshoos", "gurdurr",
    "gyarados", "hakamoo", "happiny", "hariyama", "hatenna", "hatterene",
    "hatterene-gmax", "haunter", "haxorus", "heatmor", "heatran",
    "helioptile", "heracross", "herdier", "hippopotas", "hippowdon",
    "hitmonchan", "hitmonlee", "hitmontop", "honchkrow", "honedge", "hooh",
    "hoopa", "hoopa-unbound", "hoothoot", "hoppip", "horsea", "houndoom",
    "houndour", "huntail", "hydrapple", "hydreigon", "hypno", "igglybuff",
    "illumise", "impidimp", "incineroar", "indeedee", "infernape", "inkay",
    "inteleon", "ironhands", "ironmoth", "ironthorns", "ironvaliant",
    "ivysaur", "jangmoo", "jellicent", "jigglypuff", "jirachi", "jolteon",
    "joltik", "jumpluff", "jynx", "kabuto", "kabutops", "kadabra", "kakuna",
    "kangaskhan", "karrablast", "kartana", "kecleon", "keldeo",
    "keldeo-resolute", "kingdra", "kingler", "kirlia", "klang", "klefki",
    "klink", "klinklang", "koffing", "komala", "kommoo", "krabby",
    "kricketot", "kricketune", "krokorok", "krookodile", "kyogre",
    "kyogre-primal", "kyurem", "kyurem-black", "kyurem-white", "lairon",
    "lampent", "landorus", "landorus-therian", "lanturn", "lapras",
    "larvesta", "larvitar", "latias", "latias-mega", "latios", "latios-mega",
    "leafeon", "leavanny", "ledian", "ledyba", "lickilicky", "lickitung",
    "liepard", "lileep", "lilligant", "lilligant-hisui", "lillipup",
    "linoone", "linoone-galar", "litleo", "litten", "litwick", "lombre",
    "lopunny", "lotad", "loudred", "lucario", "lucario-mega", "ludicolo",
    "lugia", "lumineon", "lunala", "lunatone", "lurantis", "luvdisc", "luxio",
    "luxray", "lycanroc", "lycanroc-dusk", "lycanroc-midnight", "machamp",
    "machoke", "machop", "magby", "magcargo", "magearna", "magearna-original",
    "magikarp", "magmar", "magmortar", "magnemite", "magneton", "magnezone",
    "makuhita", "malaconda", "malamar", "mamoswine", "manaphy", "mandibuzz",
    "manectric", "manectric-mega", "mankey", "mantine", "mantyke", "maractus",
    "mareep", "marill", "marowak", "marowak-alola", "marshadow", "marshtomp",
    "masquerain", "maushold", "maushold-four", "mawile", "mawile-mega",
    "medicham", "medicham-mega", "meditite", "meganium", "melmetal",
    "meloetta", "meloetta-pirouette", "meltan", "meowth", "meowth-alola",
    "meowth-galar", "meowth-gmax", "mesprit", "metagross", "metang",
    "metapod", "mew", "mewtwo", "mewtwo-megax", "mewtwo-megay", "mienfoo",
    "mienshao", "mightyena", "milcery", "milotic", "miltank", "mimejr",
    "mimikyu", "mimikyu-busted", "minccino", "minior", "minior-blue",
    "minior-green", "minior-indigo", "minior-meteor", "minior-orange",
    "minior-violet", "minior-yellow", "minun", "miraidon", "misdreavus",
    "mismagius", "mollux", "moltres", "monferno", "morelull", "morpeko",
    "morpeko-hangry", "mothim", "mrmime", "mrrime", "mudbray", "mudkip",
    "mudsdale", "muk", "muk-alola", "munchlax", "munna", "murkrow",
    "musharna", "nacli", "naganadel", "natu", "necrozma",
    "necrozma-dawnwings", "necrozma-duskmane", "necrozma-ultra", "necturna",
    "nidoking", "nidoqueen", "nidoranf", "nidoranm", "nidorina", "nidorino",
    "nihilego", "nincada", "ninetales", "ninetales-alola", "ninjask",
    "noctowl", "noibat", "nosepass", "numel", "nuzleaf", "obstagoon",
    "octillery", "oddish", "omanyte", "omastar", "onix", "orbeetle-gmax",
    "oricorio-pau", "oricorio-pompom", "oricorio-sensu", "oshawott",
    "overqwil", "pachirisu", "pajantom", "palkia", "palossand", "palpitoad",
    "pancham", "pangoro", "panpour", "pansage", "pansear", "paras",
    "parasect", "patrat", "pawniard", "pelipper", "perrserker", "persian",
    "persian-alola", "petilil", "phanpy", "phantump", "pheromosa", "phione",
    "pichu", "pidgeot", "pidgeotto", "pidgey", "pidove", "pignite", "pikachu",
    "pikachu-alola", "pikachu-hoenn", "pikachu-kalos", "pikachu-original",
    "pikachu-partner", "pikachu-sinnoh", "pikachu-starter", "pikachu-unova",
    "pikachu-world", "pikipek", "piloswine", "pincurchin", "pineco", "pinsir",
    "piplup", "plasmanta", "plusle", "pokestarblackbelt", "pokestarblackdoor",
    "pokestarbrycenman", "pokestarf00", "pokestarf002", "pokestargiant",
    "pokestarhumanoid", "pokestarmonster", "pokestarmt", "pokestarmt2",
    "pokestarsmeargle", "pokestarspirit", "pokestartransport", "pokestarufo",
    "pokestarufo2", "pokestarwhitedoor", "politoed", "poliwag", "poliwhirl",
    "poliwrath", "ponyta", "ponyta-galar", "poochyena", "popplio", "porygon",
    "porygon2", "porygonz", "primarina", "primeape", "prinplup", "probopass",
    "psyduck", "pupitar", "purrloin", "purugly", "pyroar", "pyukumuku",
    "quagsire", "quilava", "quilladin", "qwilfish", "raboot", "raichu",
    "raichu-alola", "raikou", "ralts", "rampardos", "rapidash", "raticate",
    "raticate-alola", "rattata", "rattata-alola", "rayquaza", "rayquaza-mega",
    "regice", "regidrago", "regigigas", "regirock", "registeel", "relicanth",
    "remoraid", "reshiram", "reuniclus", "rhydon", "rhyhorn", "rhyperior",
    "ribombee", "riolu", "rockruff", "roggenrola", "rolycoly", "rookidee",
    "roselia", "roserade", "rotom", "rotom-fan", "rotom-frost", "rotom-heat",
    "rotom-mow", "rotom-wash", "rowlet", "rufflet", "runerigus", "sableye",
    "salamence", "salamence-mega", "samurott", "samurott-hisui", "sandaconda",
    "sandile", "sandshrew", "sandshrew-alola", "sandslash", "sandslash-alola",
    "sandygast", "sawk", "sawsbuck", "sawsbuck-autumn", "sawsbuck-summer",
    "sawsbuck-winter", "scatterbug", "sceptile", "scizor", "scizor-mega",
    "scolipede", "scorbunny", "scrafty", "scraggy", "scyther", "seadra",
    "seaking", "sealeo", "seedot", "seel", "seismitoad", "sentret",
    "serperior", "servine", "seviper", "sewaddle", "sharpedo", "shaymin",
    "shaymin-sky", "shedinja", "shelgon", "shellder", "shellos",
    "shellos-east", "shelmet", "shieldon", "shiftry", "shiinotic", "shinx",
    "shroomish", "shuckle", "shuppet", "sigilyph", "silcoon", "silicobra",
    "silvally", "silvally-bug", "silvally-dark", "silvally-dragon",
    "silvally-electric", "silvally-fairy", "silvally-fighting",
    "silvally-fire", "silvally-flying", "silvally-ghost", "silvally-grass",
    "silvally-ground", "silvally-ice", "silvally-poison", "silvally-psychic",
    "silvally-rock", "silvally-steel", "silvally-water", "simipour",
    "simisage", "simisear", "skarmory", "skiddo", "skiploom", "skitty",
    "skorupi", "skuntank", "slaking", "slakoth", "sliggoo", "sliggoo-hisui",
    "slowbro", "slowbro-galar", "slowking", "slowking-galar", "slowpoke",
    "slowpoke-galar", "slugma", "slurpuff", "smeargle", "smoochum", "sneasel",
    "snivy", "snom", "snorlax", "snorunt", "snover", "snubbull", "sobble",
    "solgaleo", "solosis", "solrock", "spearow", "spewpa", "spheal",
    "spinarak", "spinda", "spiritomb", "spoink", "spritzee", "squirtle",
    "stakataka", "stantler", "staraptor", "staravia", "starly", "starmie",
    "staryu", "steelix", "steelix-mega", "steenee", "stonjourner",
    "stoutland", "stufful", "stunfisk", "stunky", "sudowoodo", "suicune",
    "sunflora", "sunkern", "surskit", "swablu", "swadloon", "swalot",
    "swampert", "swanna", "swellow", "swinub", "swirlix", "swoobat",
    "sylveon", "tadbulb", "taillow", "talonflame", "tandemaus", "tangela",
    "tangrowth", "tapubulu", "tapukoko", "tapulele", "tatsugiri",
    "tatsugiri-droopy", "tatsugiri-stretchy", "tauros", "teddiursa",
    "tentacool", "tentacruel", "tepig", "terapagos", "terapagos-stellar",
    "terapagos-terastal", "terrakion", "throh", "thundurus",
    "thundurus-therian", "thwackey", "timburr", "tinglu", "tirtouga",
    "togedemaru", "togekiss", "togepi", "togetic", "tomohawk", "torchic",
    "torkoal", "tornadus", "tornadus-therian", "torterra", "totodile",
    "toucannon", "toxapex", "toxel", "toxicroak", "toxtricity",
    "toxtricity-gmax", "tranquill", "trapinch", "treecko", "trevenant",
    "tropius", "trubbish", "trumbeak", "turtonator", "turtwig", "tympole",
    "tynamo", "typenull", "typhlosion", "tyranitar", "tyranitar-mega",
    "tyrantrum", "tyrogue", "tyrunt", "umbreon", "unfezant", "unown",
    "unown-b", "unown-c", "unown-d", "unown-e", "unown-g", "unown-h",
    "unown-i", "unown-j", "unown-k", "unown-l", "unown-m", "unown-n",
    "unown-o", "unown-p", "unown-q", "unown-r", "unown-s", "unown-t",
    "unown-u", "unown-v", "unown-w", "unown-x", "unown-y", "unown-z",
    "ursaluna", "ursaluna-bloodmoon", "ursaring", "uxie", "vanillish",
    "vanillite", "vanilluxe", "vaporeon", "venipede", "venomoth", "venonat",
    "venusaur", "vespiquen", "vibrava", "victini", "victreebel", "vigoroth",
    "vikavolt", "vileplume", "virizion", "vivillon", "vivillon-archipelago",
    "vivillon-continental", "vivillon-elegant", "vivillon-fancy",
    "vivillon-garden", "vivillon-highplains", "vivillon-icysnow",
    "vivillon-jungle", "vivillon-marine", "vivillon-modern",
    "vivillon-monsoon", "vivillon-ocean", "vivillon-pokeball",
    "vivillon-polar", "vivillon-river", "vivillon-sandstorm",
    "vivillon-savanna", "vivillon-sun", "vivillon-tundra", "volbeat",
    "volcanion", "volcarona", "volkraken", "voltorb", "voltorb-hisui",
    "vullaby", "vulpix", "vulpix-alola", "wailmer", "wailord", "walrein",
    "wartortle", "watchog", "weavile", "weedle", "weepinbell", "weezing",
    "weezing-galar", "whimsicott", "whirlipede", "whiscash", "whismur",
    "wigglytuff", "wimpod", "wingull", "wishiwashi", "wishiwashi-school",
    "wobbuffet", "wochien", "woobat", "wooloo", "wooper", "wooper-paldea",
    "wormadam", "wormadam-sandy", "wormadam-trash", "wurmple", "wynaut",
    "wyrdeer", "xatu", "xerneas", "xurkitree", "yamask", "yamper", "yanma",
    "yanmega", "yungoos", "yveltal", "zacian", "zacian-crowned", "zamazenta",
    "zamazenta-crowned", "zangoose", "zapdos", "zapdos-galar", "zebstrika",
    "zekrom", "zeraora", "zigzagoon", "zigzagoon-galar", "zoroark",
    "zoroark-hisui", "zorua", "zubat", "zweilous", "zygarde", "zygarde-10"
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

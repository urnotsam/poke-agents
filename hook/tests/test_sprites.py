import unittest

from pokeagents import species, sprites


class TestUrls(unittest.TestCase):
    """These caught a real bug: os.path.splitext('.gif') yields ('.gif', ''),
    so building the extension from the suffix produced extensionless 404 URLs."""

    def test_every_variant_url_ends_in_its_extension(self):
        for variant in sprites.VARIANTS:
            url = variant.url("psyduck")
            self.assertTrue(url.endswith(variant.extension), url)

    def test_animated_url_is_exact(self):
        self.assertEqual(
            sprites.variant_for(shiny=False, animated=True).url("psyduck"),
            "https://play.pokemonshowdown.com/sprites/gen5ani/psyduck.gif",
        )

    def test_shiny_animated_url_is_exact(self):
        self.assertEqual(
            sprites.variant_for(shiny=True, animated=True).url("psyduck"),
            "https://play.pokemonshowdown.com/sprites/gen5ani-shiny/psyduck.gif",
        )

    def test_static_url_is_exact(self):
        self.assertEqual(
            sprites.variant_for(shiny=False, animated=False).url("snorlax"),
            "https://play.pokemonshowdown.com/sprites/gen5/snorlax.png",
        )

    def test_shiny_static_url_is_exact(self):
        self.assertEqual(
            sprites.variant_for(shiny=True, animated=False).url("snorlax"),
            "https://play.pokemonshowdown.com/sprites/gen5-shiny/snorlax.png",
        )

    def test_no_url_contains_a_double_slash_in_the_path(self):
        for variant in sprites.VARIANTS:
            self.assertNotIn("//", variant.url("psyduck").split("://", 1)[1])


class TestFilenames(unittest.TestCase):
    def test_filenames_are_exact(self):
        self.assertEqual(
            sprites.variant_for(shiny=False, animated=True).filename("psyduck"),
            "psyduck.gif")
        self.assertEqual(
            sprites.variant_for(shiny=True, animated=True).filename("psyduck"),
            "psyduck-shiny.gif")
        self.assertEqual(
            sprites.variant_for(shiny=False, animated=False).filename("psyduck"),
            "psyduck-static.png")
        self.assertEqual(
            sprites.variant_for(shiny=True, animated=False).filename("psyduck"),
            "psyduck-shiny-static.png")

    def test_all_variant_filenames_are_distinct(self):
        names = {v.filename("psyduck") for v in sprites.VARIANTS}
        self.assertEqual(len(names), len(sprites.VARIANTS))

    def test_variant_for_covers_every_combination(self):
        seen = {sprites.variant_for(shiny=s, animated=a)
                for s in (True, False) for a in (True, False)}
        self.assertEqual(len(seen), len(sprites.VARIANTS))


class TestRoster(unittest.TestCase):
    def test_species_names_are_valid_showdown_ids(self):
        # Showdown ids strip punctuation: nidoran-f is nidoranf, farfetchd has
        # no apostrophe. A wrong id means a permanent placeholder sprite.
        for name in species.SPECIES:
            self.assertRegex(name, r"^[a-z0-9]+$", "%s is not a Showdown id" % name)


if __name__ == "__main__":
    unittest.main()

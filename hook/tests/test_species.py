import unittest

from pokeagents import species


class TestFnv1a(unittest.TestCase):
    def test_is_deterministic(self):
        self.assertEqual(species.fnv1a("abc"), species.fnv1a("abc"))

    def test_differs_for_different_input(self):
        self.assertNotEqual(species.fnv1a("abc"), species.fnv1a("abd"))

    def test_stays_in_32_bit_range(self):
        for s in ["", "a", "512c4f5d-f675-4f79-92a2-810422a25b00", "x" * 500]:
            self.assertTrue(0 <= species.fnv1a(s) < 2**32)


class TestAssign(unittest.TestCase):
    def test_same_session_id_always_gets_same_species(self):
        sid = "512c4f5d-f675-4f79-92a2-810422a25b00"
        first = species.assign(sid, taken=set())
        second = species.assign(sid, taken=set())
        self.assertEqual(first.name, second.name)

    def test_returns_a_known_species(self):
        got = species.assign("any-session", taken=set())
        self.assertIn(got.name, species.SPECIES)

    def test_probes_forward_when_species_is_taken(self):
        sid = "session-one"
        natural = species.assign(sid, taken=set()).name
        avoided = species.assign(sid, taken={natural}).name
        self.assertNotEqual(avoided, natural)
        self.assertIn(avoided, species.SPECIES)

    def test_probes_past_multiple_collisions(self):
        sid = "session-one"
        natural_index = species.fnv1a(sid) % len(species.SPECIES)
        blocked = {species.SPECIES[(natural_index + i) % len(species.SPECIES)] for i in range(3)}
        got = species.assign(sid, taken=blocked).name
        self.assertNotIn(got, blocked)

    def test_falls_back_to_natural_choice_when_every_species_is_taken(self):
        sid = "session-one"
        natural = species.assign(sid, taken=set()).name
        got = species.assign(sid, taken=set(species.SPECIES)).name
        self.assertEqual(got, natural)

    def test_shiny_is_deterministic_for_a_session(self):
        sid = "some-session-id"
        self.assertEqual(
            species.assign(sid, taken=set()).shiny,
            species.assign(sid, taken=set()).shiny,
        )

    def test_shiny_is_rare_but_happens(self):
        results = [species.assign("session-%d" % i, taken=set()).shiny for i in range(4096)]
        rate = sum(results) / len(results)
        self.assertGreater(rate, 0.0)
        self.assertLess(rate, 0.10)

    def test_species_table_has_no_duplicates(self):
        self.assertEqual(len(species.SPECIES), len(set(species.SPECIES)))

    def test_species_table_is_lowercase_and_url_safe(self):
        for name in species.SPECIES:
            self.assertRegex(name, r"^[a-z0-9-]+$")

    def test_a_large_roster_makes_collisions_rare(self):
        # With one species per session and linear probing, a bigger roster means
        # concurrent sessions almost never contend for the same sprite.
        assigned = {species.assign("session-%d" % i, taken=set()).name
                    for i in range(50)}
        self.assertGreater(len(assigned), 45)


if __name__ == "__main__":
    unittest.main()

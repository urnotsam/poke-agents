import os
import tempfile
import unittest

from pokeagents import opencode

TEMPLATE = os.path.join(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))),
    "harnesses", "opencode", "poke-agents.js")

HOOK = "/opt/poke-agents/hook/pokeagents_hook.py"


class OpenCodeTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def body(self):
        with open(opencode.plugin_path(self.dir)) as fh:
            return fh.read()


class TestTemplate(unittest.TestCase):
    def test_the_shipped_plugin_exists(self):
        self.assertTrue(os.path.exists(TEMPLATE))

    def test_it_carries_the_marker(self):
        with open(TEMPLATE) as fh:
            self.assertIn(opencode.MARKER, fh.read())

    def test_it_exports_a_named_plugin_function(self):
        # OpenCode loads a named export, not a default one.
        with open(TEMPLATE) as fh:
            self.assertIn("export const PokeAgents", fh.read())

    def test_it_handles_every_event_the_harness_maps(self):
        from pokeagents import harness
        with open(TEMPLATE) as fh:
            source = fh.read()
        for event in harness.OPENCODE.event_map:
            self.assertIn('"%s"' % event, source,
                          "the plugin never reports %s" % event)


class TestInstall(OpenCodeTestCase):
    def test_writes_the_plugin(self):
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertTrue(os.path.exists(opencode.plugin_path(self.dir)))

    def test_bakes_in_the_hook_path(self):
        # The plugin cannot otherwise know where this checkout lives.
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertIn(HOOK, self.body())

    def test_creates_the_directory(self):
        nested = os.path.join(self.dir, "deep", "plugins")
        opencode.install(TEMPLATE, HOOK, directory=nested)
        self.assertTrue(os.path.exists(opencode.plugin_path(nested)))

    def test_is_idempotent(self):
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        first = self.body()
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertEqual(self.body(), first)

    def test_reinstall_updates_a_moved_hook_path(self):
        opencode.install(TEMPLATE, "/old/hook.py", directory=self.dir)
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertIn(HOOK, self.body())
        self.assertNotIn("/old/hook.py", self.body())

    def test_a_path_with_a_quote_cannot_break_the_javascript(self):
        opencode.install(TEMPLATE, '/opt/we"ird/hook.py', directory=self.dir)
        self.assertIn('\\"', self.body())

    def test_refuses_to_overwrite_someone_elses_plugin(self):
        with open(opencode.plugin_path(self.dir), "w") as fh:
            fh.write("export const Mine = async () => ({})\n")
        with self.assertRaises(opencode.OpenCodeError):
            opencode.install(TEMPLATE, HOOK, directory=self.dir)

    def test_that_refusal_leaves_the_file_untouched(self):
        original = "export const Mine = async () => ({})\n"
        with open(opencode.plugin_path(self.dir), "w") as fh:
            fh.write(original)
        try:
            opencode.install(TEMPLATE, HOOK, directory=self.dir)
        except opencode.OpenCodeError:
            pass
        self.assertEqual(self.body(), original)

    def test_a_missing_template_is_reported(self):
        with self.assertRaises(opencode.OpenCodeError):
            opencode.install("/no/such/template.js", HOOK, directory=self.dir)


class TestStatus(OpenCodeTestCase):
    def test_not_installed_initially(self):
        self.assertFalse(opencode.is_installed(self.dir))

    def test_installed_after_install(self):
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertTrue(opencode.is_installed(self.dir))

    def test_a_foreign_file_does_not_count_as_installed(self):
        with open(opencode.plugin_path(self.dir), "w") as fh:
            fh.write("not ours")
        self.assertFalse(opencode.is_installed(self.dir))


class TestUninstall(OpenCodeTestCase):
    def test_removes_our_plugin(self):
        opencode.install(TEMPLATE, HOOK, directory=self.dir)
        self.assertTrue(opencode.uninstall(self.dir))
        self.assertFalse(os.path.exists(opencode.plugin_path(self.dir)))

    def test_leaves_a_foreign_file_alone(self):
        path = opencode.plugin_path(self.dir)
        with open(path, "w") as fh:
            fh.write("not ours")
        self.assertFalse(opencode.uninstall(self.dir))
        self.assertTrue(os.path.exists(path))

    def test_uninstalling_nothing_is_not_an_error(self):
        self.assertFalse(opencode.uninstall(self.dir))


if __name__ == "__main__":
    unittest.main()

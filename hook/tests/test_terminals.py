import os
import stat
import tempfile
import unittest

from claudemon import terminals


class AdapterTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self._tmp.name, "terminals")
        os.makedirs(self.dir)
        os.environ["CLAUDEMON_HOME"] = self._tmp.name

    def tearDown(self):
        os.environ.pop("CLAUDEMON_HOME", None)
        self._tmp.cleanup()

    def adapter(self, name, body, executable=True):
        path = os.path.join(self.dir, name)
        with open(path, "w") as fh:
            fh.write("#!/usr/bin/env bash\n" + body)
        if executable:
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return terminals.Adapter(path)


class TestDiscovery(AdapterTestCase):
    def test_finds_executables(self):
        self.adapter("alpha", "exit 0\n")
        self.assertEqual([a.name for a in terminals.available()], ["alpha"])

    def test_ignores_non_executable_files(self):
        self.adapter("notexec", "exit 0\n", executable=False)
        self.assertEqual(terminals.available(), [])

    def test_ignores_documentation(self):
        path = os.path.join(self.dir, "README.md")
        with open(path, "w") as fh:
            fh.write("docs")
        os.chmod(path, 0o755)
        self.assertEqual(terminals.available(), [])

    def test_ignores_dot_files(self):
        self.adapter(".hidden", "exit 0\n")
        self.assertEqual(terminals.available(), [])

    def test_missing_directory_is_not_an_error(self):
        os.environ["CLAUDEMON_HOME"] = "/no/such/place"
        self.assertEqual(terminals.available(), [])

    def test_default_order_is_alphabetical(self):
        for name in ["zulu", "alpha", "mike"]:
            self.adapter(name, "exit 0\n")
        self.assertEqual([a.name for a in terminals.available()],
                         ["alpha", "mike", "zulu"])

    def test_preferred_adapters_come_first(self):
        for name in ["alpha", "mike", "zulu"]:
            self.adapter(name, "exit 0\n")
        order = [a.name for a in terminals.available(["zulu", "mike"])]
        self.assertEqual(order, ["zulu", "mike", "alpha"])

    def test_unlisted_adapters_still_appear(self):
        # A newly dropped-in adapter must work without also editing the config.
        for name in ["alpha", "newcomer"]:
            self.adapter(name, "exit 0\n")
        self.assertIn("newcomer", [a.name for a in terminals.available(["alpha"])])

    def test_unknown_preferred_name_is_ignored(self):
        self.adapter("alpha", "exit 0\n")
        self.assertEqual([a.name for a in terminals.available(["ghost"])], ["alpha"])


class TestDetect(AdapterTestCase):
    def test_exit_zero_means_detected(self):
        self.assertTrue(self.adapter("yes", 'exit 0\n').detects())

    def test_nonzero_means_not_detected(self):
        self.assertFalse(self.adapter("no", 'exit 1\n').detects())

    def test_detected_filters_the_list(self):
        self.adapter("good", 'case "$1" in detect) exit 0 ;; esac\n')
        self.adapter("bad", 'exit 1\n')
        self.assertEqual([a.name for a in terminals.detected()], ["good"])

    def test_crashing_adapter_is_not_detected(self):
        self.assertFalse(self.adapter("boom", 'exit 3\n').detects())

    def test_missing_executable_is_not_detected(self):
        self.assertFalse(terminals.Adapter("/no/such/adapter").detects())


class TestFocus(AdapterTestCase):
    def test_reports_success(self):
        self.assertTrue(self.adapter("ok", "exit 0\n").focus(123, "/dev/ttys001"))

    def test_reports_refusal(self):
        self.assertFalse(self.adapter("no", "exit 1\n").focus(123, "/dev/ttys001"))

    def test_receives_pid_and_tty_as_arguments(self):
        probe = self.adapter("probe", '''
[ "$1" = "focus" ] && [ "$2" = "4242" ] && [ "$3" = "/dev/ttys009" ] && exit 0
exit 1
''')
        self.assertTrue(probe.focus(4242, "/dev/ttys009"))

    def test_missing_tty_is_passed_as_none(self):
        probe = self.adapter("probe", '[ "$3" = "none" ] && exit 0 || exit 1\n')
        self.assertTrue(probe.focus(4242, None))

    def test_missing_pid_is_passed_as_zero(self):
        probe = self.adapter("probe", '[ "$2" = "0" ] && exit 0 || exit 1\n')
        self.assertTrue(probe.focus(None, "/dev/ttys001"))

    def test_arguments_are_not_shell_evaluated(self):
        # Session files live in a user-writable directory, so a hostile tty must
        # stay inert data rather than becoming a command.
        marker = os.path.join(self._tmp.name, "pwned")
        probe = self.adapter("probe", 'exit 0\n')
        probe.focus(1, '"; touch %s; echo "' % marker)
        self.assertFalse(os.path.exists(marker), "adapter argument reached a shell")


class TestDiscover(AdapterTestCase):
    def test_parses_one_object_per_line(self):
        probe = self.adapter("probe", '''
case "$1" in
  discover)
    echo '{"pid": 1, "label": "one"}'
    echo '{"pid": 2, "label": "two"}'
    ;;
esac
''')
        found = probe.discover()
        self.assertEqual([f["pid"] for f in found], [1, 2])

    def test_adapter_without_discover_returns_nothing(self):
        self.assertEqual(self.adapter("plain", "exit 1\n").discover(), [])

    def test_malformed_line_does_not_discard_the_rest(self):
        probe = self.adapter("probe", '''
case "$1" in
  discover)
    echo 'not json'
    echo '{"pid": 7}'
    ;;
esac
''')
        self.assertEqual([f["pid"] for f in probe.discover()], [7])

    def test_blank_lines_are_skipped(self):
        probe = self.adapter("probe", '''
case "$1" in
  discover) printf '\\n{"pid": 3}\\n\\n' ;;
esac
''')
        self.assertEqual(len(probe.discover()), 1)

    def test_non_object_lines_are_skipped(self):
        probe = self.adapter("probe", '''
case "$1" in
  discover) echo '[1,2,3]'; echo '{"pid": 5}' ;;
esac
''')
        self.assertEqual([f["pid"] for f in probe.discover()], [5])

    def test_discovering_selects_only_capable_adapters(self):
        self.adapter("full", '''
case "$1" in
  detect) exit 0 ;;
  discover) echo '{"pid": 1}' ;;
  *) exit 1 ;;
esac
''')
        self.adapter("focus-only", '''
case "$1" in
  detect) exit 0 ;;
  *) exit 1 ;;
esac
''')
        self.assertEqual([a.name for a in terminals.discovering()], ["full"])

    def test_undetected_adapter_is_never_asked_to_discover(self):
        self.adapter("offline", '''
case "$1" in
  detect) exit 1 ;;
  discover) echo '{"pid": 1}' ;;
esac
''')
        self.assertEqual(terminals.discovering(), [])


class TestBundledAdapters(unittest.TestCase):
    """The adapters actually shipped must satisfy their own contract."""

    ROOT = os.path.join(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))), "terminals")

    def bundled(self):
        return [os.path.join(self.ROOT, n) for n in sorted(os.listdir(self.ROOT))
                if not n.endswith(".md")]

    def test_there_are_bundled_adapters(self):
        self.assertGreater(len(self.bundled()), 0)

    def test_all_are_executable(self):
        for path in self.bundled():
            self.assertTrue(os.access(path, os.X_OK), "%s is not executable" % path)

    def test_all_are_valid_shell(self):
        import subprocess
        for path in self.bundled():
            out = subprocess.run(["bash", "-n", path], stderr=subprocess.PIPE)
            self.assertEqual(out.returncode, 0,
                             "%s: %s" % (path, out.stderr.decode()))

    def test_unknown_subcommand_exits_nonzero(self):
        import subprocess
        for path in self.bundled():
            out = subprocess.run([path, "nonsense"], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, timeout=15)
            self.assertNotEqual(out.returncode, 0,
                                "%s accepted an unknown subcommand" % path)

    def test_detect_answers_without_hanging(self):
        import subprocess
        for path in self.bundled():
            # Exit code may be anything; it must simply terminate promptly.
            subprocess.run([path, "detect"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=20)

    def test_focus_declines_cleanly_with_no_tty(self):
        import subprocess
        for path in self.bundled():
            if os.path.basename(path) == "ghostty":
                continue  # raises the app regardless of tty, by design
            out = subprocess.run([path, "focus", "0", "none"],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, timeout=20)
            self.assertNotEqual(out.returncode, 0,
                                "%s claimed to focus a session with no tty" % path)


if __name__ == "__main__":
    unittest.main()

import copy
import json
import os
import shlex
import subprocess
import tempfile
import unittest

from claudemon import settings

HOOK = "/opt/claudemon/hook/claudemon_hook.py"


class SettingsTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self._tmp.name, "settings.json")

    def tearDown(self):
        self._tmp.cleanup()

    def save(self, data):
        with open(self.path, "w") as fh:
            json.dump(data, fh)

    def load(self):
        with open(self.path) as fh:
            return json.load(fh)


class TestInstall(SettingsTestCase):
    def test_adds_every_tracked_event(self):
        self.save({})
        settings.install(self.path, HOOK)
        hooks = self.load()["hooks"]
        for event in settings.EVENTS:
            self.assertIn(event, hooks)

    def test_preserves_unrelated_top_level_settings(self):
        self.save({"model": "opus", "env": {"FOO": "bar"}})
        settings.install(self.path, HOOK)
        got = self.load()
        self.assertEqual(got["model"], "opus")
        self.assertEqual(got["env"], {"FOO": "bar"})

    def test_preserves_existing_hooks_on_the_same_event(self):
        self.save({"hooks": {"Stop": [
            {"hooks": [{"type": "command", "command": "echo existing"}]}
        ]}})
        settings.install(self.path, HOOK)
        commands = _commands_for(self.load(), "Stop")
        self.assertIn("echo existing", commands)
        self.assertTrue(any(HOOK in c for c in commands))

    def test_preserves_hooks_on_events_we_do_not_touch(self):
        self.save({"hooks": {"PreCompact": [
            {"hooks": [{"type": "command", "command": "echo compact"}]}
        ]}})
        settings.install(self.path, HOOK)
        self.assertIn("echo compact", _commands_for(self.load(), "PreCompact"))

    def test_is_idempotent(self):
        self.save({})
        settings.install(self.path, HOOK)
        first = self.load()
        settings.install(self.path, HOOK)
        self.assertEqual(self.load(), first)

    def test_reinstall_updates_a_moved_hook_path(self):
        self.save({})
        settings.install(self.path, "/old/path/claudemon_hook.py")
        settings.install(self.path, HOOK)
        commands = _commands_for(self.load(), "Stop")
        self.assertTrue(any(HOOK in c for c in commands))
        self.assertFalse(any("/old/path" in c for c in commands))

    def test_creates_the_file_when_absent(self):
        settings.install(self.path, HOOK)
        self.assertTrue(os.path.exists(self.path))
        self.assertIn("Stop", self.load()["hooks"])

    def test_writes_a_backup_of_an_existing_file(self):
        self.save({"model": "opus"})
        settings.install(self.path, HOOK)
        backups = [n for n in os.listdir(self._tmp.name) if ".backup" in n]
        self.assertEqual(len(backups), 1)
        with open(os.path.join(self._tmp.name, backups[0])) as fh:
            self.assertEqual(json.load(fh), {"model": "opus"})

    def test_refuses_to_touch_a_corrupt_settings_file(self):
        with open(self.path, "w") as fh:
            fh.write("{not json")
        with self.assertRaises(settings.SettingsError):
            settings.install(self.path, HOOK)

    def test_entries_are_marked_so_uninstall_can_find_them(self):
        self.save({})
        settings.install(self.path, HOOK)
        entry = self.load()["hooks"]["Stop"][0]["hooks"][0]
        self.assertEqual(entry.get(settings.MARKER), True)


class TestCommandQuoting(SettingsTestCase):
    """The composed command lands in a file that a shell executes on every event
    of every session, so both halves must be quoted, not merely space-checked."""

    def test_path_with_spaces_is_quoted(self):
        self.save({})
        settings.install(self.path, "/opt/my hooks/claudemon_hook.py")
        command = _commands_for(self.load(), "Stop")[0]
        self.assertIn("'/opt/my hooks/claudemon_hook.py'", command)

    def test_shell_metacharacters_in_path_stay_one_argument(self):
        # The real property: a shell parsing this command must see the hostile
        # path as a single argument, not as extra commands to run.
        hostile = "/opt/x; touch /tmp/claudemon-pwned; #/hook.py"
        self.save({})
        settings.install(self.path, hostile)
        command = _commands_for(self.load(), "Stop")[0]
        self.assertEqual(shlex.split(command)[-1], hostile)

    def test_metacharacters_in_python_argument_stay_arguments(self):
        self.save({})
        settings.install(self.path, HOOK, python="python3; rm -rf /tmp/x")
        command = _commands_for(self.load(), "Stop")[0]
        tokens = shlex.split(command)
        self.assertNotIn("rm", tokens[:1])
        self.assertEqual(tokens[-1], HOOK)
        # No token is a bare shell operator.
        self.assertNotIn(";", tokens)

    def test_a_hostile_path_does_not_execute_when_the_shell_runs_it(self):
        marker = os.path.join(self._tmp.name, "pwned")
        self.save({})
        settings.install(self.path, "/nonexistent; touch %s; true" % marker)
        command = _commands_for(self.load(), "Stop")[0]
        subprocess.run(["/bin/sh", "-c", command], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=15)
        self.assertFalse(os.path.exists(marker),
                         "the hook command executed an injected command")

    def test_multiword_interpreter_still_works(self):
        self.save({})
        settings.install(self.path, HOOK, python="/usr/bin/env python3")
        command = _commands_for(self.load(), "Stop")[0]
        self.assertTrue(command.startswith("/usr/bin/env python3 "), command)

    def test_plain_path_is_still_readable(self):
        self.save({})
        settings.install(self.path, "/opt/claudemon/hook.py")
        self.assertIn("/opt/claudemon/hook.py", _commands_for(self.load(), "Stop")[0])


class TestBackups(SettingsTestCase):
    def test_repeated_installs_do_not_overwrite_a_backup(self):
        self.save({"model": "opus"})
        settings.install(self.path, HOOK)
        settings.install(self.path, HOOK)
        settings.uninstall(self.path)
        backups = [n for n in os.listdir(self._tmp.name) if ".backup" in n]
        self.assertEqual(len(backups), 3, "a backup was silently overwritten")

    def test_first_backup_preserves_the_original(self):
        self.save({"model": "opus"})
        settings.install(self.path, HOOK)
        backups = sorted(n for n in os.listdir(self._tmp.name) if ".backup" in n)
        with open(os.path.join(self._tmp.name, backups[0])) as fh:
            self.assertEqual(json.load(fh), {"model": "opus"})


class TestUninstall(SettingsTestCase):
    def test_removes_only_our_entries(self):
        self.save({"hooks": {"Stop": [
            {"hooks": [{"type": "command", "command": "echo existing"}]}
        ]}})
        settings.install(self.path, HOOK)
        settings.uninstall(self.path)
        commands = _commands_for(self.load(), "Stop")
        self.assertEqual(commands, ["echo existing"])

    def test_round_trip_restores_original_shape(self):
        original = {"model": "opus", "hooks": {"PreCompact": [
            {"hooks": [{"type": "command", "command": "echo compact"}]}
        ]}}
        self.save(copy.deepcopy(original))
        settings.install(self.path, HOOK)
        settings.uninstall(self.path)
        self.assertEqual(self.load(), original)

    def test_uninstall_without_install_is_a_noop(self):
        self.save({"model": "opus"})
        settings.uninstall(self.path)
        self.assertEqual(self.load(), {"model": "opus"})

    def test_uninstall_missing_file_is_a_noop(self):
        settings.uninstall(self.path)
        self.assertFalse(os.path.exists(self.path))

    def test_drops_events_left_empty(self):
        self.save({})
        settings.install(self.path, HOOK)
        settings.uninstall(self.path)
        self.assertEqual(self.load().get("hooks", {}), {})


class TestStatus(SettingsTestCase):
    def test_reports_not_installed(self):
        self.save({})
        self.assertFalse(settings.is_installed(self.path))

    def test_reports_installed(self):
        self.save({})
        settings.install(self.path, HOOK)
        self.assertTrue(settings.is_installed(self.path))

    def test_missing_file_is_not_installed(self):
        self.assertFalse(settings.is_installed(self.path))

    def test_corrupt_file_is_not_installed(self):
        with open(self.path, "w") as fh:
            fh.write("nope")
        self.assertFalse(settings.is_installed(self.path))


def _commands_for(data, event):
    out = []
    for group in data.get("hooks", {}).get(event, []):
        for entry in group.get("hooks", []):
            out.append(entry.get("command"))
    return out


if __name__ == "__main__":
    unittest.main()

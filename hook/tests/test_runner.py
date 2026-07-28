import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

from pokeagents import process, runner, state

HOOK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "pokeagents_hook.py")

PROC = process.ProcInfo(pid=4242, ppid=1, comm="claude", tty="ttys007")


class RunnerTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self._tmp.name, "sessions")
        self.cwd = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def fire(self, event, **extra):
        payload = {"hook_event_name": event, "session_id": "sid-1", "cwd": self.cwd}
        payload.update(extra)
        return runner.apply_event(self.dir, payload, proc=PROC)

    def current(self):
        return state.read(self.dir, "sid-1")


class TestSessionLifecycle(RunnerTestCase):
    def test_session_start_creates_a_running_record(self):
        self.fire("SessionStart")
        rec = self.current()
        self.assertIsNotNone(rec)
        self.assertEqual(rec.state, state.RUNNING)
        self.assertEqual(rec.session_id, "sid-1")

    def test_session_start_records_the_owning_process(self):
        self.fire("SessionStart")
        rec = self.current()
        self.assertEqual(rec.pid, 4242)
        self.assertEqual(rec.tty, "/dev/ttys007")

    def test_session_start_assigns_a_species(self):
        self.fire("SessionStart")
        self.assertTrue(self.current().species)

    def test_notification_moves_to_attention(self):
        self.fire("SessionStart")
        self.fire("Notification")
        self.assertEqual(self.current().state, state.ATTENTION)

    def test_stop_moves_to_done(self):
        self.fire("SessionStart")
        self.fire("Notification")
        self.fire("Stop")
        self.assertEqual(self.current().state, state.DONE)

    def test_pre_tool_use_returns_to_running_and_records_the_tool(self):
        self.fire("SessionStart")
        self.fire("Stop")
        self.fire("PreToolUse", tool_name="Bash")
        rec = self.current()
        self.assertEqual(rec.state, state.RUNNING)
        self.assertEqual(rec.last_tool, "Bash")

    def test_session_end_removes_the_record(self):
        self.fire("SessionStart")
        self.fire("SessionEnd")
        self.assertIsNone(self.current())

    def test_species_survives_state_changes(self):
        self.fire("SessionStart")
        original = self.current().species
        self.fire("Notification")
        self.fire("Stop")
        self.assertEqual(self.current().species, original)

    def test_started_at_is_preserved_across_updates(self):
        self.fire("SessionStart")
        started = self.current().started_at
        self.fire("Stop")
        self.assertEqual(self.current().started_at, started)

    def test_updated_at_advances(self):
        self.fire("SessionStart")
        first = self.current().updated_at
        self.fire("Stop", _now=first + 50)
        self.assertGreater(self.current().updated_at, first)


class TestLazyProcessResolution(RunnerTestCase):
    """Finding the owning process costs one `ps` per level of the process tree,
    and PreToolUse fires on every tool call, so it must only happen when the
    answer is actually needed."""

    def setUp(self):
        super().setUp()
        self.calls = []

    def resolver(self):
        self.calls.append(1)
        return PROC

    def fire_lazy(self, event, **extra):
        payload = {"hook_event_name": event, "session_id": "sid-1", "cwd": self.cwd}
        payload.update(extra)
        runner.apply_event(self.dir, payload, resolve_proc=self.resolver)

    def test_creating_a_record_resolves_the_process(self):
        self.fire_lazy("SessionStart")
        self.assertEqual(len(self.calls), 1)

    def test_updating_an_established_record_does_not_resolve_the_process(self):
        self.fire_lazy("SessionStart")
        self.calls.clear()
        for _ in range(5):
            self.fire_lazy("PreToolUse", tool_name="Bash")
            self.fire_lazy("Stop")
        self.assertEqual(self.calls, [], "process tree walked for an established record")

    def test_deleting_never_resolves_the_process(self):
        self.fire_lazy("SessionEnd")
        self.assertEqual(self.calls, [])

    def test_untracked_event_never_resolves_the_process(self):
        self.fire_lazy("SomeFutureHook")
        self.assertEqual(self.calls, [])

    def test_resolver_is_called_at_most_once_per_event(self):
        self.fire_lazy("SessionStart")
        self.assertLessEqual(len(self.calls), 1)

    def test_record_missing_a_pid_adopts_one_on_the_next_event(self):
        runner.apply_event(self.dir, {"hook_event_name": "SessionStart",
                                      "session_id": "sid-1", "cwd": self.cwd}, proc=None)
        self.assertIsNone(self.current().pid)
        self.fire_lazy("Stop")
        self.assertEqual(self.current().pid, PROC.pid)


class TestResilience(RunnerTestCase):
    def test_event_for_unknown_session_adopts_it_rather_than_dropping_it(self):
        # Hooks installed mid-session mean the first event may not be SessionStart.
        self.fire("Stop")
        rec = self.current()
        self.assertIsNotNone(rec)
        self.assertEqual(rec.state, state.DONE)

    def test_untracked_event_is_ignored(self):
        self.fire("SomeFutureHook")
        self.assertIsNone(self.current())

    def test_missing_session_id_is_ignored(self):
        runner.apply_event(self.dir, {"hook_event_name": "SessionStart"}, proc=PROC)
        self.assertEqual(state.read_all(self.dir), [])

    def test_hostile_session_id_is_ignored(self):
        runner.apply_event(
            self.dir,
            {"hook_event_name": "SessionStart", "session_id": "../escape", "cwd": self.cwd},
            proc=PROC,
        )
        self.assertEqual(state.read_all(self.dir), [])

    def test_missing_process_info_still_writes_a_record(self):
        runner.apply_event(
            self.dir,
            {"hook_event_name": "SessionStart", "session_id": "sid-1", "cwd": self.cwd},
            proc=None,
        )
        rec = self.current()
        self.assertIsNotNone(rec)
        self.assertIsNone(rec.tty)

    def test_two_sessions_get_different_species(self):
        self.fire("SessionStart")
        runner.apply_event(
            self.dir,
            {"hook_event_name": "SessionStart", "session_id": "sid-2", "cwd": self.cwd},
            proc=PROC,
        )
        names = {r.species for r in state.read_all(self.dir)}
        self.assertEqual(len(names), 2)


class TestHookEntryPoint(unittest.TestCase):
    """The hook runs inside every live session, so these are the load-bearing tests."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def run_hook(self, payload, extra_env=None):
        env = dict(os.environ)
        env["POKEAGENTS_HOME"] = self.home
        env["PYTHONPATH"] = os.path.dirname(HOOK)
        env.update(extra_env or {})
        return subprocess.run(
            [sys.executable, HOOK],
            input=json.dumps(payload).encode(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=15,
        )

    def sessions_dir(self):
        return os.path.join(self.home, "sessions")

    def test_exits_zero_and_writes_nothing_to_stdout(self):
        out = self.run_hook({"hook_event_name": "SessionStart",
                             "session_id": "abc", "cwd": os.getcwd()})
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout, b"")

    def test_creates_a_session_file(self):
        self.run_hook({"hook_event_name": "SessionStart",
                       "session_id": "abc", "cwd": os.getcwd()})
        self.assertTrue(os.path.exists(os.path.join(self.sessions_dir(), "abc.json")))

    def test_malformed_json_exits_zero_silently(self):
        env = dict(os.environ, POKEAGENTS_HOME=self.home,
                   PYTHONPATH=os.path.dirname(HOOK))
        out = subprocess.run([sys.executable, HOOK], input=b"{not json",
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=env, timeout=15)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout, b"")

    def test_empty_stdin_exits_zero_silently(self):
        env = dict(os.environ, POKEAGENTS_HOME=self.home,
                   PYTHONPATH=os.path.dirname(HOOK))
        out = subprocess.run([sys.executable, HOOK], input=b"",
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=env, timeout=15)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout, b"")

    def test_unwritable_state_dir_exits_zero(self):
        blocked = os.path.join(self.home, "blocked")
        os.makedirs(blocked)
        os.chmod(blocked, 0o500)
        try:
            out = self.run_hook({"hook_event_name": "SessionStart",
                                 "session_id": "abc", "cwd": os.getcwd()},
                                extra_env={"POKEAGENTS_HOME": blocked})
            self.assertEqual(out.returncode, 0)
            self.assertEqual(out.stdout, b"")
        finally:
            os.chmod(blocked, 0o700)

    def test_disable_flag_short_circuits(self):
        self.run_hook({"hook_event_name": "SessionStart",
                       "session_id": "abc", "cwd": os.getcwd()},
                      extra_env={"POKEAGENTS_DISABLE": "1"})
        self.assertFalse(os.path.exists(os.path.join(self.sessions_dir(), "abc.json")))

    def test_completes_quickly(self):
        import time
        start = time.time()
        self.run_hook({"hook_event_name": "Stop", "session_id": "abc", "cwd": os.getcwd()})
        self.assertLess(time.time() - start, 3.0)


if __name__ == "__main__":
    unittest.main()

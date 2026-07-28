import json
import os
import tempfile
import time
import unittest

from pokeagents import state


class StateDirTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self._tmp.name, "sessions")

    def tearDown(self):
        self._tmp.cleanup()

    def record(self, **over):
        base = dict(
            session_id="sid-1", label="widgets-api", cwd="/tmp/widgets-api",
            species="charizard", shiny=False, state=state.RUNNING,
            pid=os.getpid(), tty="/dev/ttys003", terminal="Apple_Terminal",
            started_at=1785271000, updated_at=1785271000, last_tool=None,
        )
        base.update(over)
        return state.SessionRecord(**base)


class TestRoundTrip(StateDirTestCase):
    def test_write_then_read_preserves_every_field(self):
        rec = self.record(last_tool="Bash", shiny=True)
        state.write(self.dir, rec)
        got = state.read(self.dir, "sid-1")
        self.assertEqual(got, rec)

    def test_write_creates_the_directory(self):
        state.write(self.dir, self.record())
        self.assertTrue(os.path.isdir(self.dir))

    def test_file_is_named_for_the_session(self):
        state.write(self.dir, self.record(session_id="abc-123"))
        self.assertTrue(os.path.exists(os.path.join(self.dir, "abc-123.json")))

    def test_written_json_is_a_flat_object(self):
        state.write(self.dir, self.record())
        with open(os.path.join(self.dir, "sid-1.json")) as fh:
            raw = json.load(fh)
        self.assertEqual(raw["species"], "charizard")
        self.assertEqual(raw["state"], "running")

    def test_read_missing_session_returns_none(self):
        self.assertIsNone(state.read(self.dir, "nope"))

    def test_write_leaves_no_temp_files_behind(self):
        state.write(self.dir, self.record())
        self.assertEqual(os.listdir(self.dir), ["sid-1.json"])

    def test_rewrite_replaces_rather_than_duplicates(self):
        state.write(self.dir, self.record())
        state.write(self.dir, self.record(state=state.DONE))
        self.assertEqual(os.listdir(self.dir), ["sid-1.json"])
        self.assertEqual(state.read(self.dir, "sid-1").state, state.DONE)


class TestSessionIdSafety(StateDirTestCase):
    def test_path_traversal_in_session_id_is_rejected(self):
        with self.assertRaises(ValueError):
            state.write(self.dir, self.record(session_id="../../evil"))

    def test_slash_in_session_id_is_rejected(self):
        with self.assertRaises(ValueError):
            state.write(self.dir, self.record(session_id="a/b"))

    def test_empty_session_id_is_rejected(self):
        with self.assertRaises(ValueError):
            state.write(self.dir, self.record(session_id=""))

    def test_reading_a_hostile_session_id_returns_none(self):
        self.assertIsNone(state.read(self.dir, "../../etc/passwd"))


class TestReadAll(StateDirTestCase):
    def test_missing_directory_yields_empty_list(self):
        self.assertEqual(state.read_all(self.dir), [])

    def test_returns_every_record(self):
        state.write(self.dir, self.record(session_id="a"))
        state.write(self.dir, self.record(session_id="b"))
        self.assertEqual({r.session_id for r in state.read_all(self.dir)}, {"a", "b"})

    def test_skips_corrupt_files_without_raising(self):
        state.write(self.dir, self.record(session_id="good"))
        with open(os.path.join(self.dir, "bad.json"), "w") as fh:
            fh.write("{not json")
        got = state.read_all(self.dir)
        self.assertEqual([r.session_id for r in got], ["good"])

    def test_skips_files_missing_required_fields(self):
        state.write(self.dir, self.record(session_id="good"))
        with open(os.path.join(self.dir, "partial.json"), "w") as fh:
            json.dump({"session_id": "partial"}, fh)
        self.assertEqual([r.session_id for r in state.read_all(self.dir)], ["good"])

    def test_ignores_non_json_files(self):
        os.makedirs(self.dir, exist_ok=True)
        open(os.path.join(self.dir, "README.txt"), "w").close()
        self.assertEqual(state.read_all(self.dir), [])

    def test_tolerates_unknown_extra_fields(self):
        os.makedirs(self.dir, exist_ok=True)
        payload = dict(
            session_id="future", label="x", cwd="/tmp", species="pikachu",
            shiny=False, state="running", pid=1, tty=None, terminal=None,
            started_at=1, updated_at=1, last_tool=None,
            some_field_from_the_future="hello",
        )
        with open(os.path.join(self.dir, "future.json"), "w") as fh:
            json.dump(payload, fh)
        self.assertEqual(len(state.read_all(self.dir)), 1)


class TestDelete(StateDirTestCase):
    def test_delete_removes_the_file(self):
        state.write(self.dir, self.record())
        state.delete(self.dir, "sid-1")
        self.assertEqual(state.read_all(self.dir), [])

    def test_delete_missing_session_is_a_noop(self):
        state.delete(self.dir, "never-existed")

    def test_delete_rejects_hostile_session_id(self):
        state.delete(self.dir, "../../etc/passwd")


class TestPrune(StateDirTestCase):
    """Nothing else ever removes a session file. Without pruning, a process
    killed with SIGKILL leaves records behind permanently."""

    def test_removes_records_whose_process_is_gone(self):
        state.write(self.dir, self.record(session_id="ghost", pid=4_000_000))
        removed = state.prune(self.dir)
        self.assertEqual(removed, ["ghost"])
        self.assertEqual(state.read_all(self.dir), [])

    def test_keeps_live_records(self):
        state.write(self.dir, self.record(session_id="alive",
                                          updated_at=int(time.time())))
        self.assertEqual(state.prune(self.dir), [])
        self.assertEqual(len(state.read_all(self.dir)), 1)

    def test_removes_only_the_dead(self):
        state.write(self.dir, self.record(session_id="alive",
                                          updated_at=int(time.time())))
        state.write(self.dir, self.record(session_id="ghost", pid=4_000_000))
        state.prune(self.dir)
        self.assertEqual([r.session_id for r in state.read_all(self.dir)], ["alive"])

    def test_removes_records_that_are_simply_too_old(self):
        old = int(time.time()) - state.MAX_AGE_SECONDS - 1
        state.write(self.dir, self.record(session_id="ancient", updated_at=old))
        self.assertEqual(state.prune(self.dir), ["ancient"])

    def test_empty_directory_is_fine(self):
        self.assertEqual(state.prune(self.dir), [])

    def test_missing_directory_is_fine(self):
        self.assertEqual(state.prune(os.path.join(self.dir, "nope")), [])

    def test_is_idempotent(self):
        state.write(self.dir, self.record(session_id="ghost", pid=4_000_000))
        state.prune(self.dir)
        self.assertEqual(state.prune(self.dir), [])


class TestLiveness(unittest.TestCase):
    def test_current_process_is_alive(self):
        self.assertTrue(state.pid_alive(os.getpid()))

    def test_pid_zero_is_not_alive(self):
        self.assertFalse(state.pid_alive(0))

    def test_absurd_pid_is_not_alive(self):
        self.assertFalse(state.pid_alive(4_000_000))

    def test_none_pid_is_not_alive(self):
        self.assertFalse(state.pid_alive(None))


class TestStale(unittest.TestCase):
    def make(self, **over):
        base = dict(
            session_id="s", label="l", cwd="/tmp", species="pikachu", shiny=False,
            state=state.RUNNING, pid=os.getpid(), tty=None, terminal=None,
            started_at=0, updated_at=int(time.time()), last_tool=None,
        )
        base.update(over)
        return state.SessionRecord(**base)

    def test_live_recent_record_is_not_stale(self):
        self.assertFalse(state.is_stale(self.make()))

    def test_dead_pid_is_stale(self):
        self.assertTrue(state.is_stale(self.make(pid=4_000_000)))

    def test_old_record_is_stale_even_with_a_live_pid(self):
        old = int(time.time()) - state.MAX_AGE_SECONDS - 1
        self.assertTrue(state.is_stale(self.make(updated_at=old)))

    def test_record_just_inside_the_age_limit_is_not_stale(self):
        recent = int(time.time()) - state.MAX_AGE_SECONDS + 60
        self.assertFalse(state.is_stale(self.make(updated_at=recent)))


if __name__ == "__main__":
    unittest.main()

import os
import unittest

from claudemon import process


class FakeTree:
    """Stand-in for ps, so tree walking is tested without spawning processes."""

    def __init__(self, table):
        self.table = table
        self.calls = []

    def __call__(self, pid):
        self.calls.append(pid)
        return self.table.get(pid)


class TestFindClaudeProcess(unittest.TestCase):
    def test_finds_claude_two_levels_up(self):
        tree = FakeTree({
            100: process.ProcInfo(pid=100, ppid=200, comm="python3", tty="??"),
            200: process.ProcInfo(pid=200, ppid=300, comm="zsh", tty="??"),
            300: process.ProcInfo(pid=300, ppid=1, comm="claude", tty="ttys003"),
        })
        got = process.find_claude(start_pid=100, lookup=tree)
        self.assertEqual(got.pid, 300)
        self.assertEqual(got.tty, "ttys003")

    def test_finds_claude_when_it_is_the_starting_process(self):
        tree = FakeTree({
            42: process.ProcInfo(pid=42, ppid=1, comm="claude", tty="ttys001"),
        })
        self.assertEqual(process.find_claude(start_pid=42, lookup=tree).pid, 42)

    def test_matches_claude_by_basename_of_a_full_path(self):
        tree = FakeTree({
            10: process.ProcInfo(pid=10, ppid=20, comm="zsh", tty="??"),
            20: process.ProcInfo(pid=20, ppid=1, comm="/opt/homebrew/bin/claude", tty="ttys009"),
        })
        self.assertEqual(process.find_claude(start_pid=10, lookup=tree).pid, 20)

    def test_returns_none_when_no_claude_in_the_chain(self):
        tree = FakeTree({
            1: process.ProcInfo(pid=1, ppid=0, comm="launchd", tty="??"),
            5: process.ProcInfo(pid=5, ppid=1, comm="zsh", tty="??"),
        })
        self.assertIsNone(process.find_claude(start_pid=5, lookup=tree))

    def test_stops_at_pid_one(self):
        tree = FakeTree({
            5: process.ProcInfo(pid=5, ppid=1, comm="zsh", tty="??"),
            1: process.ProcInfo(pid=1, ppid=0, comm="launchd", tty="??"),
        })
        process.find_claude(start_pid=5, lookup=tree)
        self.assertNotIn(0, tree.calls)

    def test_survives_a_cycle_without_hanging(self):
        tree = FakeTree({
            7: process.ProcInfo(pid=7, ppid=8, comm="a", tty="??"),
            8: process.ProcInfo(pid=8, ppid=7, comm="b", tty="??"),
        })
        self.assertIsNone(process.find_claude(start_pid=7, lookup=tree))

    def test_gives_up_after_the_depth_limit(self):
        table = {i: process.ProcInfo(pid=i, ppid=i + 1, comm="sh", tty="??")
                 for i in range(1000)}
        tree = FakeTree(table)
        self.assertIsNone(process.find_claude(start_pid=0, lookup=tree))
        self.assertLessEqual(len(tree.calls), process.MAX_DEPTH + 1)

    def test_missing_process_ends_the_walk(self):
        tree = FakeTree({5: process.ProcInfo(pid=5, ppid=999, comm="zsh", tty="??")})
        self.assertIsNone(process.find_claude(start_pid=5, lookup=tree))


class TestNormalizeTty(unittest.TestCase):
    def test_adds_dev_prefix(self):
        self.assertEqual(process.normalize_tty("ttys003"), "/dev/ttys003")

    def test_leaves_absolute_path_alone(self):
        self.assertEqual(process.normalize_tty("/dev/ttys003"), "/dev/ttys003")

    def test_question_marks_mean_no_tty(self):
        self.assertIsNone(process.normalize_tty("??"))

    def test_empty_means_no_tty(self):
        self.assertIsNone(process.normalize_tty(""))
        self.assertIsNone(process.normalize_tty("   "))
        self.assertIsNone(process.normalize_tty(None))


class TestRealLookup(unittest.TestCase):
    def test_reads_this_process_from_ps(self):
        info = process.lookup_proc(os.getpid())
        self.assertIsNotNone(info)
        self.assertEqual(info.pid, os.getpid())
        self.assertEqual(info.ppid, os.getppid())

    def test_absurd_pid_returns_none(self):
        self.assertIsNone(process.lookup_proc(4_000_000))


if __name__ == "__main__":
    unittest.main()

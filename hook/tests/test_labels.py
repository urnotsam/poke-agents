import os
import subprocess
import tempfile
import unittest

from claudemon import labels


class TestFormatLabel(unittest.TestCase):
    def test_display_name_wins_over_everything(self):
        got = labels.format_label(
            display_name="my agent", repo="widgets-api", branch="feat/x",
            is_worktree=True, cwd_basename="worker",
        )
        self.assertEqual(got, "my agent")

    def test_plain_repo_uses_repo_name(self):
        got = labels.format_label(
            display_name=None, repo="widgets-api", branch="main",
            is_worktree=False, cwd_basename="widgets-api",
        )
        self.assertEqual(got, "widgets-api")

    def test_worktree_appends_branch(self):
        got = labels.format_label(
            display_name=None, repo="acme", branch="feature-branch",
            is_worktree=True, cwd_basename="worker",
        )
        self.assertEqual(got, "acme@feature-branch")

    def test_worktree_without_branch_falls_back_to_directory(self):
        got = labels.format_label(
            display_name=None, repo="acme", branch=None,
            is_worktree=True, cwd_basename="worker",
        )
        self.assertEqual(got, "acme@worker")

    def test_non_git_directory_uses_basename(self):
        got = labels.format_label(
            display_name=None, repo=None, branch=None,
            is_worktree=False, cwd_basename="Documents",
        )
        self.assertEqual(got, "Documents")

    def test_truncates_to_max_length_with_ellipsis(self):
        got = labels.format_label(
            display_name=None, repo="acme-widgets-service", branch="shared-data-pipelines",
            is_worktree=True, cwd_basename="x",
        )
        self.assertLessEqual(len(got), labels.MAX_LEN)
        self.assertTrue(got.endswith("…"))

    def test_does_not_truncate_when_it_fits_exactly(self):
        name = "a" * labels.MAX_LEN
        got = labels.format_label(
            display_name=name, repo=None, branch=None,
            is_worktree=False, cwd_basename="x",
        )
        self.assertEqual(got, name)

    def test_blank_display_name_is_ignored(self):
        got = labels.format_label(
            display_name="   ", repo="widgets-api", branch="main",
            is_worktree=False, cwd_basename="widgets-api",
        )
        self.assertEqual(got, "widgets-api")

    def test_empty_everything_yields_a_placeholder_not_a_crash(self):
        got = labels.format_label(
            display_name=None, repo=None, branch=None,
            is_worktree=False, cwd_basename="",
        )
        self.assertTrue(got)


def _git(cwd, *args):
    subprocess.run(["git"] + list(args), cwd=cwd, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class TestDeriveAgainstRealGit(unittest.TestCase):
    def test_plain_repo(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "widgets-api")
            os.makedirs(repo)
            _git(repo, "init", "-q", "-b", "main")
            self.assertEqual(labels.derive(repo), "widgets-api")

    def test_subdirectory_of_repo_still_reports_repo_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "widgets-api")
            sub = os.path.join(repo, "src", "deep")
            os.makedirs(sub)
            _git(repo, "init", "-q", "-b", "main")
            self.assertEqual(labels.derive(sub), "widgets-api")

    def test_worktree_gets_branch_suffix(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "acme")
            os.makedirs(repo)
            _git(repo, "init", "-q", "-b", "main")
            _git(repo, "-c", "user.email=t@t", "-c", "user.name=t",
                 "commit", "-q", "--allow-empty", "-m", "init")
            wt = os.path.join(tmp, "wt-hotfix")
            _git(repo, "worktree", "add", "-q", "-b", "hotfix", wt)
            self.assertEqual(labels.derive(wt), "acme@hotfix")

    def test_non_git_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            plain = os.path.join(tmp, "scratchpad")
            os.makedirs(plain)
            self.assertEqual(labels.derive(plain), "scratchpad")

    def test_nonexistent_directory_does_not_raise(self):
        self.assertTrue(labels.derive("/no/such/path/anywhere"))

    def test_display_name_short_circuits_without_touching_git(self):
        self.assertEqual(labels.derive("/no/such/path", display_name="alpha"), "alpha")


if __name__ == "__main__":
    unittest.main()

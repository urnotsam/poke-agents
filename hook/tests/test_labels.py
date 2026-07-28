import os
import subprocess
import tempfile
import unittest

from pokeagents import labels


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


class TestShorten(unittest.TestCase):
    """Titles read like instructions, so plain truncation keeps the words every
    title shares and drops the ones that identify it."""

    def test_drops_the_leading_verb(self):
        self.assertEqual(labels.shorten("Implement the export feature"),
                         "export feature")

    def test_drops_filler_words(self):
        self.assertEqual(labels.shorten("Fix the bug in the login flow"),
                         "bug login flow")

    def test_result_fits_the_budget(self):
        long_titles = [
            "Implement Granola document demo feature requests",
            "Create visual dashboard for running agents with Pokemon sprites",
            "Investigate why the deployment pipeline keeps failing randomly",
            "Refactor the authentication middleware to support single sign on",
        ]
        for title in long_titles:
            self.assertLessEqual(len(labels.shorten(title)), labels.MAX_LEN, title)

    def test_keeps_whole_words(self):
        got = labels.shorten("Implement Granola document demo feature requests")
        self.assertFalse(got.endswith("…"))
        self.assertTrue(all(word in
                            "Implement Granola document demo feature requests"
                            for word in got.split()))

    def test_a_single_long_word_is_truncated_rather_than_dropped(self):
        got = labels.shorten("supercalifragilisticexpialidocious")
        self.assertLessEqual(len(got), labels.MAX_LEN)
        self.assertTrue(got.endswith("…"))

    def test_a_lone_verb_is_kept(self):
        # Dropping it would leave nothing at all.
        self.assertEqual(labels.shorten("refactor"), "refactor")

    def test_a_verb_followed_only_by_stopwords_still_yields_something(self):
        self.assertTrue(labels.shorten("Update the"))

    def test_short_titles_pass_through_unchanged(self):
        self.assertEqual(labels.shorten("billing worker"), "billing worker")

    def test_empty_input_is_empty(self):
        self.assertEqual(labels.shorten(""), "")
        self.assertEqual(labels.shorten("   "), "")

    def test_is_deterministic(self):
        title = "Implement Granola document demo feature requests"
        self.assertEqual(labels.shorten(title), labels.shorten(title))

    def test_applies_through_format_label(self):
        got = labels.format_label(display_name="Implement the export feature",
                                  repo=None, branch=None, is_worktree=False,
                                  cwd_basename="")
        self.assertEqual(got, "export feature")

    def test_repo_labels_are_not_mangled(self):
        # Only titles get shortened; a repo name is already the identity.
        self.assertEqual(
            labels.format_label(display_name=None, repo="test-runner",
                                branch="main", is_worktree=False,
                                cwd_basename="test-runner"),
            "test-runner")


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

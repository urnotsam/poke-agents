import unittest

from pokeagents import events, harness


class TestRegistry(unittest.TestCase):
    def test_claude_code_is_the_default(self):
        self.assertEqual(harness.get(None).name, "claude-code")

    def test_unknown_harness_falls_back_rather_than_failing(self):
        # A record from an unrecognised harness is better than no record.
        self.assertEqual(harness.get("something-new").name, "claude-code")

    def test_lookup_by_name(self):
        self.assertEqual(harness.get("opencode").name, "opencode")

    def test_names_are_unique(self):
        self.assertEqual(len(harness.names()), len(set(harness.names())))

    def test_agent_commands_are_collected_without_duplicates(self):
        commands = harness.agent_commands()
        self.assertEqual(len(commands), len(set(commands)))
        self.assertIn("claude", commands)
        self.assertIn("opencode", commands)


class TestEveryHarness(unittest.TestCase):
    """Invariants any future harness must satisfy to be wired up correctly."""

    def test_maps_only_onto_canonical_events(self):
        for h in harness.ALL:
            for source, canonical in h.event_map.items():
                self.assertIn(canonical, events.CANONICAL,
                              "%s maps %s to a non-canonical %r"
                              % (h.name, source, canonical))

    def test_covers_the_whole_lifecycle_or_says_why_not(self):
        # Missing any of these leaves sprites that never spawn, never alert, or
        # never go away. A harness whose upstream cannot report them all has to
        # declare the gap, so an accidental omission cannot pass for a deliberate
        # one.
        required = {events.START, events.TOOL, events.NEEDS_USER,
                    events.IDLE, events.END}
        for h in harness.ALL:
            missing = required - set(h.event_map.values())
            if missing:
                self.assertTrue(
                    h.limitations,
                    "%s is missing %s and does not declare a limitation"
                    % (h.name, sorted(missing)))
            else:
                self.assertFalse(
                    h.limitations,
                    "%s declares a limitation but covers everything" % h.name)

    def test_a_complete_harness_needs_no_caveat(self):
        for name in ("claude-code", "opencode"):
            self.assertFalse(harness.get(name).limitations, name)

    def test_crush_declares_its_partial_support(self):
        self.assertTrue(harness.CRUSH.limitations)
        self.assertIn("PreToolUse", harness.CRUSH.limitations)

    def test_every_mapped_event_produces_a_transition(self):
        for h in harness.ALL:
            for source in h.event_map:
                self.assertIsNotNone(h.transition_for(source),
                                     "%s: %s" % (h.name, source))

    def test_unknown_events_are_ignored(self):
        for h in harness.ALL:
            self.assertIsNone(h.transition_for("not-an-event"))
            self.assertIsNone(h.transition_for(None))
            self.assertIsNone(h.transition_for(""))

    def test_declares_at_least_one_agent_command(self):
        for h in harness.ALL:
            self.assertTrue(h.agent_commands, h.name)

    def test_has_a_title(self):
        for h in harness.ALL:
            self.assertTrue(h.title)


class TestGoose(unittest.TestCase):
    def test_maps_its_own_event_names(self):
        h = harness.GOOSE
        self.assertEqual(h.transition_for("SessionStart").state, events.RUNNING)
        self.assertEqual(h.transition_for("Stop").state, events.DONE)
        self.assertTrue(h.transition_for("SessionEnd").deletes)

    def test_reads_gooses_field_names(self):
        # goose sends `event` and `working_dir`, not hook_event_name and cwd.
        payload = {"event": "Stop", "working_dir": "/tmp/p", "session_id": "s1"}
        self.assertEqual(harness.GOOSE.event_name(payload), "Stop")
        self.assertEqual(harness.GOOSE.cwd(payload), "/tmp/p")
        self.assertEqual(harness.GOOSE.session_id(payload), "s1")

    def test_still_accepts_the_default_field_names(self):
        payload = {"hook_event_name": "Stop", "cwd": "/tmp/p"}
        self.assertEqual(harness.GOOSE.event_name(payload), "Stop")
        self.assertEqual(harness.GOOSE.cwd(payload), "/tmp/p")

    def test_a_failed_tool_asks_for_attention(self):
        self.assertEqual(harness.GOOSE.transition_for("PostToolUseFailure").state,
                         events.ATTENTION)


class TestCrush(unittest.TestCase):
    def test_maps_the_one_event_it_has(self):
        self.assertTrue(harness.CRUSH.transition_for("PreToolUse").records_tool)

    def test_reads_crushs_field_names(self):
        payload = {"event": "PreToolUse", "cwd": "/tmp/p", "session_id": "313909e"}
        self.assertEqual(harness.CRUSH.event_name(payload), "PreToolUse")
        self.assertEqual(harness.CRUSH.cwd(payload), "/tmp/p")


class TestFieldReading(unittest.TestCase):
    def test_missing_fields_read_as_none(self):
        for h in harness.ALL:
            self.assertIsNone(h.event_name({}))
            self.assertIsNone(h.cwd({}))
            self.assertIsNone(h.session_id({}))

    def test_non_string_fields_are_rejected(self):
        for h in harness.ALL:
            self.assertIsNone(h.event_name({h.event_field: 42}))
            self.assertIsNone(h.cwd({h.cwd_field: []}))
            self.assertIsNone(h.session_id({h.session_field: 7}))

    def test_an_empty_session_id_is_not_a_session_id(self):
        for h in harness.ALL:
            self.assertIsNone(h.session_id({h.session_field: ""}))


class TestClaudeCode(unittest.TestCase):
    def test_maps_its_own_event_names(self):
        h = harness.CLAUDE_CODE
        self.assertEqual(h.transition_for("SessionStart").state, events.RUNNING)
        self.assertEqual(h.transition_for("Notification").state, events.ATTENTION)
        self.assertEqual(h.transition_for("Stop").state, events.DONE)
        self.assertTrue(h.transition_for("SessionEnd").deletes)
        self.assertTrue(h.transition_for("PreToolUse").records_tool)


class TestOpenCode(unittest.TestCase):
    def test_maps_its_own_event_names(self):
        h = harness.OPENCODE
        self.assertEqual(h.transition_for("session.created").state, events.RUNNING)
        self.assertEqual(h.transition_for("session.idle").state, events.DONE)
        self.assertTrue(h.transition_for("session.deleted").deletes)
        self.assertTrue(h.transition_for("tool.execute.before").records_tool)

    def test_permission_prompts_are_the_attention_signal(self):
        # OpenCode is more precise than Claude Code here: it says specifically
        # that it is blocked on a permission decision.
        h = harness.OPENCODE
        self.assertEqual(h.transition_for("permission.asked").state, events.ATTENTION)
        self.assertEqual(h.transition_for("permission.replied").state, events.RUNNING)

    def test_an_errored_session_asks_for_attention(self):
        self.assertEqual(harness.OPENCODE.transition_for("session.error").state,
                         events.ATTENTION)

    def test_does_not_answer_to_claude_event_names(self):
        self.assertIsNone(harness.OPENCODE.transition_for("SessionStart"))


if __name__ == "__main__":
    unittest.main()

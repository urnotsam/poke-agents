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

    def test_covers_the_whole_lifecycle(self):
        # Missing any of these leaves sprites that never spawn, never alert, or
        # never go away.
        required = {events.START, events.TOOL, events.NEEDS_USER,
                    events.IDLE, events.END}
        for h in harness.ALL:
            self.assertTrue(required.issubset(set(h.event_map.values())),
                            "%s is missing %s"
                            % (h.name, required - set(h.event_map.values())))

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

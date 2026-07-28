import unittest

from pokeagents import events


class TestCanonicalTransitions(unittest.TestCase):
    def test_start_marks_running(self):
        t = events.transition_for(events.START)
        self.assertEqual(t.state, events.RUNNING)
        self.assertFalse(t.deletes)

    def test_activity_marks_running(self):
        self.assertEqual(events.transition_for(events.ACTIVITY).state, events.RUNNING)

    def test_tool_marks_running_and_records_the_tool(self):
        t = events.transition_for(events.TOOL)
        self.assertEqual(t.state, events.RUNNING)
        self.assertTrue(t.records_tool)

    def test_needs_user_marks_attention(self):
        self.assertEqual(events.transition_for(events.NEEDS_USER).state,
                         events.ATTENTION)

    def test_idle_marks_done(self):
        self.assertEqual(events.transition_for(events.IDLE).state, events.DONE)

    def test_end_deletes(self):
        self.assertTrue(events.transition_for(events.END).deletes)

    def test_unknown_event_is_ignored(self):
        self.assertIsNone(events.transition_for("SomeFutureEvent"))

    def test_a_harness_specific_name_is_not_canonical(self):
        # Harness vocabularies are translated before they reach this table.
        self.assertIsNone(events.transition_for("SessionStart"))
        self.assertIsNone(events.transition_for("session.idle"))

    def test_missing_event_name_is_ignored(self):
        self.assertIsNone(events.transition_for(""))
        self.assertIsNone(events.transition_for(None))

    def test_every_canonical_event_has_a_transition(self):
        for name in events.CANONICAL:
            self.assertIsNotNone(events.transition_for(name), name)

    def test_the_table_covers_exactly_the_canonical_events(self):
        self.assertEqual(set(events.HANDLED), set(events.CANONICAL))

    def test_only_end_deletes(self):
        deleting = [n for n in events.CANONICAL if events.transition_for(n).deletes]
        self.assertEqual(deleting, [events.END])

    def test_only_tool_records_a_tool(self):
        recording = [n for n in events.CANONICAL
                     if events.transition_for(n).records_tool]
        self.assertEqual(recording, [events.TOOL])

    def test_every_state_is_reachable(self):
        reached = {events.transition_for(n).state for n in events.CANONICAL}
        for state in events.STATES:
            self.assertIn(state, reached)


if __name__ == "__main__":
    unittest.main()

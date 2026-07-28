import unittest

from claudemon import events


class TestTransitionFor(unittest.TestCase):
    def test_session_start_marks_running(self):
        t = events.transition_for("SessionStart")
        self.assertEqual(t.state, events.RUNNING)
        self.assertFalse(t.deletes)

    def test_user_prompt_submit_marks_running(self):
        self.assertEqual(events.transition_for("UserPromptSubmit").state, events.RUNNING)

    def test_pre_tool_use_marks_running_and_records_tool(self):
        t = events.transition_for("PreToolUse")
        self.assertEqual(t.state, events.RUNNING)
        self.assertTrue(t.records_tool)

    def test_notification_marks_attention(self):
        self.assertEqual(events.transition_for("Notification").state, events.ATTENTION)

    def test_stop_marks_done(self):
        self.assertEqual(events.transition_for("Stop").state, events.DONE)

    def test_session_end_deletes(self):
        t = events.transition_for("SessionEnd")
        self.assertTrue(t.deletes)

    def test_unknown_event_is_ignored(self):
        self.assertIsNone(events.transition_for("SomeFutureHook"))

    def test_missing_event_name_is_ignored(self):
        self.assertIsNone(events.transition_for(""))
        self.assertIsNone(events.transition_for(None))

    def test_every_handled_event_has_a_transition(self):
        for name in events.HANDLED:
            self.assertIsNotNone(events.transition_for(name))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Offline unit tests for nerve_hook (no Nerve server required)."""

from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "nerve_hook.py"


def load_hook():
    spec = importlib.util.spec_from_file_location("nerve_hook", HOOK_PATH)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class NerveHookTests(unittest.TestCase):
    def setUp(self):
        # Host harness env must not leak into offline unit tests.
        import os

        for key in list(os.environ):
            if key.startswith(("GROK_", "CLAUDE_PLUGIN_", "PLUGIN_ROOT", "CODEX_")):
                os.environ.pop(key, None)

        self.mod = load_hook()
        self._posted: list = []

        def capture(alias, machine_kind, job):
            self._posted.append({"alias": alias, "machineKind": machine_kind, "jobs": [job]})
            return True

        self.mod._post_snapshot = capture

    def test_event_name_normalization(self):
        m = self.mod
        self.assertEqual(m._event_name({"hook_event_name": "SessionStart"}), "sessionstart")
        self.assertEqual(m._event_name({"hookEventName": "pre_tool_use"}), "pretooluse")
        self.assertEqual(m._event_name({"event": "stop"}), "stop")

    def test_session_start_job(self):
        payload = {
            "hook_event_name": "SessionStart",
            "session_id": "sess-abc",
            "cwd": "/Users/me/work/nerve",
            "source": "startup",
        }
        job = self.mod.process(payload)
        self.assertIsNotNone(job)
        assert job is not None
        self.assertEqual(job["id"], "claude-code:sess-abc")
        self.assertEqual(job["kind"], "session")
        self.assertEqual(job["lifecycle"], "active")
        self.assertEqual(job["producer"]["id"], "claude-code")
        self.assertIn("nerve", job["name"].lower())
        self.assertTrue(job["alias"])
        self.assertEqual(len(self._posted), 1)
        self.assertEqual(self._posted[0]["alias"], job["alias"])
        self.assertIn("jobs", self._posted[0])

    def test_permission_sets_attention(self):
        payload = {
            "hook_event_name": "PermissionRequest",
            "session_id": "p1",
            "cwd": "/tmp/x",
            "tool_name": "Bash",
            "tool_input": {"command": "rm -rf /tmp/build"},
        }
        job = self.mod.process(payload)
        assert job is not None
        self.assertEqual(job["attention"]["level"], "required")
        self.assertEqual(job["attention"]["reason"], "approval")

    def test_stop_marks_waiting_for_input_attention(self):
        base = {"session_id": "s2", "cwd": "/tmp/y"}
        self.mod.process(
            {
                **base,
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "tool_input": {"command": "ls"},
            }
        )
        job = self.mod.process(
            {
                **base,
                "hook_event_name": "Stop",
                "background_tasks": [],
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "idle")
        self.assertEqual(job["attention"]["level"], "suggested")
        self.assertEqual(job["attention"]["reason"], "input")

    def test_stop_with_background_tasks_is_running(self):
        """Claude Code Stop payload: non-empty background_tasks ⇒ still Running."""
        job = self.mod.process(
            {
                "hook_event_name": "Stop",
                "session_id": "s2b",
                "cwd": "/tmp/y",
                "background_tasks": [
                    {
                        "id": "t1",
                        "type": "subagent",
                        "status": "running",
                        "description": "mol:spec-writer",
                    }
                ],
            }
        )
        assert job is not None
        self.assertEqual(job["lifecycle"], "active")
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertNotEqual(job["attention"].get("reason"), "input")

    def test_notification_uses_structured_type_not_message_text(self):
        # Free-text alone must not drive status.
        free = self.mod.process(
            {
                "hook_event_name": "Notification",
                "session_id": "s3a",
                "cwd": "/tmp/y",
                "message": "Waiting for 1 background agent to finish",
            }
        )
        assert free is not None
        self.assertEqual(free["attention"]["level"], "none")
        self.assertEqual(free["current"]["type"], "info")  # active → Running

        idle = self.mod.process(
            {
                "hook_event_name": "Notification",
                "session_id": "s3b",
                "cwd": "/tmp/y",
                "notification_type": "idle_prompt",
                "message": "anything here is ignored for status",
            }
        )
        assert idle is not None
        self.assertEqual(idle["attention"]["reason"], "input")
        self.assertEqual(idle["current"]["type"], "idle")

        perm = self.mod.process(
            {
                "hook_event_name": "Notification",
                "session_id": "s3c",
                "cwd": "/tmp/y",
                "notification_type": "permission_prompt",
                "message": "Please approve Bash",
            }
        )
        assert perm is not None
        self.assertEqual(perm["attention"]["reason"], "approval")

    def test_subagent_start_is_running_facets(self):
        job = self.mod.process(
            {
                "hook_event_name": "SubagentStart",
                "session_id": "s4",
                "cwd": "/tmp/y",
                "agent_type": "Explore",
            }
        )
        assert job is not None
        self.assertEqual(job["lifecycle"], "active")
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["attention"]["level"], "none")

    def test_session_end_success(self):
        job = self.mod.process(
            {
                "hook_event_name": "SessionEnd",
                "session_id": "end1",
                "cwd": "/tmp/z",
            }
        )
        assert job is not None
        self.assertEqual(job["lifecycle"], "ended")
        self.assertEqual(job["outcome"], "success")

    def test_no_env_required(self):
        """Hook must not read NERVE_* environment variables."""
        import os

        for key in list(os.environ):
            if key.startswith("NERVE_"):
                del os.environ[key]
        job = self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "env-free",
                "cwd": "/tmp/env",
            }
        )
        self.assertIsNotNone(job)

    def test_envelope_shape(self):
        self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "shape",
                "cwd": "/tmp/shape",
            }
        )
        env = self._posted[-1]
        self.assertIn("alias", env)
        self.assertIn("machineKind", env)
        self.assertIn("jobs", env)
        self.assertEqual(env["jobs"][0]["kind"], "session")
        self.assertNotIn("type", env["jobs"][0])
        self.assertNotIn("source", env["jobs"][0])
        self.assertIn("producer", env["jobs"][0])


if __name__ == "__main__":
    unittest.main()

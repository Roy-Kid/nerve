#!/usr/bin/env python3
"""Offline unit tests for nerve_hook (no Nerve server required)."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

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
        self.mod = load_hook()
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        # Isolate state; stub HTTP so tests stay quiet and offline
        self.mod.STATE_DIR = Path(self._tmp.name) / "state"
        self._posted: list = []
        self.mod._post_snapshot = lambda subject: self._posted.append(subject) or True
        os.environ.pop("NERVE_HOOK_DEBUG", None)
        os.environ.pop("NERVE_HOOK_DRY_RUN", None)
        os.environ["NERVE_SOURCE"] = "claude"

    def tearDown(self):
        os.environ.pop("NERVE_SOURCE", None)

    def test_event_name_normalization(self):
        m = self.mod
        self.assertEqual(m._event_name({"hook_event_name": "SessionStart"}), "sessionstart")
        self.assertEqual(m._event_name({"hookEventName": "pre_tool_use"}), "pretooluse")
        self.assertEqual(m._event_name({"event": "stop"}), "stop")

    def test_session_start_subject(self):
        payload = {
            "hook_event_name": "SessionStart",
            "session_id": "sess-abc",
            "cwd": "/Users/me/work/nerve",
            "source": "startup",
        }
        subj = self.mod.process(payload)
        self.assertIsNotNone(subj)
        assert subj is not None
        self.assertEqual(subj["id"], "claude-code:sess-abc")
        self.assertEqual(subj["type"], "agent.session")
        self.assertEqual(subj["lifecycle"], "active")
        self.assertEqual(subj["source"]["id"], "claude-code")
        self.assertIn("nerve", subj["name"].lower())
        self.assertEqual(subj["version"], 1)

    def test_version_monotonic(self):
        base = {
            "session_id": "v-sess",
            "cwd": "/tmp/proj",
        }
        a = self.mod.process({**base, "hook_event_name": "SessionStart", "source": "startup"})
        b = self.mod.process({**base, "hook_event_name": "UserPromptSubmit", "prompt": "hi"})
        self.assertEqual(a["version"], 1)
        self.assertEqual(b["version"], 2)

    def test_permission_sets_attention(self):
        payload = {
            "hook_event_name": "PermissionRequest",
            "session_id": "p1",
            "cwd": "/tmp/x",
            "tool_name": "Bash",
            "tool_input": {"command": "rm -rf /tmp/build"},
        }
        subj = self.mod.process(payload)
        assert subj is not None
        self.assertEqual(subj["attention"]["level"], "required")
        self.assertEqual(subj["attention"]["reason"], "approval")

    def test_stop_clears_attention_keeps_active(self):
        base = {"session_id": "s2", "cwd": "/tmp/y"}
        self.mod.process(
            {
                **base,
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "tool_input": {"command": "ls"},
            }
        )
        subj = self.mod.process(
            {
                **base,
                "hook_event_name": "Stop",
                "last_assistant_message": "All done.",
            }
        )
        assert subj is not None
        self.assertEqual(subj["lifecycle"], "active")
        self.assertEqual(subj["attention"]["level"], "none")
        self.assertEqual(subj["current"]["type"], "idle")

    def test_session_end(self):
        base = {"session_id": "s3", "cwd": "/tmp/z"}
        self.mod.process({**base, "hook_event_name": "SessionStart", "source": "startup"})
        subj = self.mod.process(
            {**base, "hook_event_name": "SessionEnd", "reason": "clear"}
        )
        assert subj is not None
        self.assertEqual(subj["lifecycle"], "ended")
        self.assertEqual(subj["outcome"], "success")
        self.assertIn("endedAt", subj)

    def test_codex_source(self):
        os.environ["NERVE_SOURCE"] = "codex"
        payload = {
            "hook_event_name": "SessionStart",
            "session_id": "cx-1",
            "cwd": "/Users/me/proj",
            "source": "startup",
            "model": "gpt-5.6",
        }
        subj = self.mod.process(payload)
        assert subj is not None
        self.assertEqual(subj["id"], "codex:cx-1")
        self.assertEqual(subj["source"]["id"], "codex")
        self.assertTrue(subj["name"].startswith("Codex"))

    def test_unhandled_event_skipped(self):
        subj = self.mod.process(
            {
                "hook_event_name": "PreCompact",
                "session_id": "x",
                "cwd": "/tmp",
            }
        )
        self.assertIsNone(subj)

    def test_tool_summary_bash(self):
        typ, summary = self.mod._tool_summary(
            {"tool_name": "Bash", "tool_input": {"command": "pytest -q"}}
        )
        self.assertEqual(typ, "tool.bash")
        self.assertIn("pytest", summary or "")


if __name__ == "__main__":
    unittest.main()

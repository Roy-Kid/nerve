#!/usr/bin/env python3
"""Offline unit tests for nerve_hook (no Nerve server required)."""

from __future__ import annotations

import importlib.util
import json
import os
import socket
import subprocess
import tempfile
import threading
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
        # Host harness env must not leak into offline unit tests.
        for key in list(os.environ):
            if key.startswith(
                (
                    "GROK_",
                    "CLAUDE_PLUGIN_",
                    "PLUGIN_ROOT",
                    "CODEX_",
                    "CURSOR_",
                    "VSCODE_",
                )
            ):
                os.environ.pop(key, None)
        # IDE scheme detection keys (not always prefixed).
        for key in (
            "VSCODE_INJECTION",
            "VSCODE_PID",
            "VSCODE_GIT_IPC_HANDLE",
            "CURSOR_TRACE_ID",
            "CURSOR_AGENT",
        ):
            os.environ.pop(key, None)

        self.mod = load_hook()
        self._posted: list = []
        # Isolate slot state so supersede tests don't touch the real temp dir.
        self._state_dir = Path(tempfile.mkdtemp(prefix="nerve-hook-test-"))
        self.mod._STATE_DIR_OVERRIDE = self._state_dir
        # Stable terminal slot so pid-walk noise doesn't split keys mid-test.
        os.environ["TERM_SESSION_ID"] = "test-term-slot-1"
        # Neutral TERM_PROGRAM so Cursor/VS Code host detection stays off.
        self._prev_term_program = os.environ.get("TERM_PROGRAM")
        os.environ["TERM_PROGRAM"] = "Apple_Terminal"

        def capture(alias, machine_kind, job):
            self._posted.append({"alias": alias, "machineKind": machine_kind, "jobs": [job]})
            return True

        self.mod._post_snapshot = capture

    def tearDown(self):
        import shutil

        try:
            shutil.rmtree(self._state_dir, ignore_errors=True)
        except Exception:
            pass
        os.environ.pop("TERM_SESSION_ID", None)
        if getattr(self, "_prev_term_program", None) is None:
            os.environ.pop("TERM_PROGRAM", None)
        else:
            os.environ["TERM_PROGRAM"] = self._prev_term_program

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
        # Ready (starting) — not Running until UserPromptSubmit / tools.
        # Distinct from idle your_turn (Stop / idle_prompt).
        self.assertEqual(job["current"]["type"], "starting")
        self.assertEqual(job["current"]["summary"], "Ready")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertEqual(job["producer"]["id"], "claude-code")
        self.assertEqual(job["name"], "nerve")  # project (cwd basename), not "Claude Code — …"
        self.assertEqual(job["producer"]["name"], "Claude Code")
        self.assertTrue(job["alias"])
        # Liveness helpers for the app (PID reaping + slot supersede).
        self.assertIn("slot", job["extensions"])
        self.assertTrue(job["extensions"]["slot"])
        action_kinds = {a["kind"] for a in job["actions"]}
        # Open/Focus first-class; Copy secondary; never reverse-control.
        self.assertIn("open", action_kinds)
        self.assertIn("copy_summary", action_kinds)
        self.assertNotIn("dismiss", action_kinds)
        self.assertNotIn("approve", action_kinds)
        self.assertEqual(job["actions"][0]["kind"], "open")
        self.assertEqual(job["actions"][0]["title"], "Open")
        # Focus location: reliable openURL + breadcrumb focusHint.
        self.assertIn("location", job)
        self.assertTrue(job["location"].get("openURL", "").startswith("file://"))
        self.assertIn("Claude Code", job["location"].get("focusHint", ""))
        self.assertIn("/Users/me/work/nerve", job["location"].get("focusHint", ""))
        self.assertEqual(len(self._posted), 1)
        self.assertEqual(self._posted[0]["alias"], job["alias"])
        self.assertIn("jobs", self._posted[0])
        self.assertEqual(len(self._posted[0]["jobs"]), 1)

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
        # Honest copy: go back to agent UI — not "Type here" / "Waiting for input".
        self.assertIn("agent", job["attention"]["title"].lower())
        self.assertIn("agent", job["attention"]["summary"].lower())
        self.assertNotIn("type here", job["attention"]["summary"].lower())

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
        # Free-text alone must not drive status (except known harness bg-wait toast).
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
        # Known Claude toast → Running (subagent facet), not Attention.
        self.assertEqual(free["current"]["type"], "subagent")

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
        self.assertIn("agent", perm["attention"]["title"].lower())

        # idle_prompt honest copy
        self.assertIn("agent", idle["attention"]["title"].lower())

    def test_location_ide_scheme_when_cursor_host(self):
        prev = os.environ.get("CURSOR_TRACE_ID")
        os.environ["CURSOR_TRACE_ID"] = "test-cursor"
        try:
            job = self.mod.process(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "ide-1",
                    "cwd": "/Users/me/work/nerve",
                }
            )
            assert job is not None
            url = job["location"]["openURL"]
            self.assertTrue(url.startswith("cursor://file/"), url)
            self.assertEqual(job["actions"][0]["kind"], "open")
        finally:
            if prev is None:
                os.environ.pop("CURSOR_TRACE_ID", None)
            else:
                os.environ["CURSOR_TRACE_ID"] = prev

    def test_permission_copy_is_honest(self):
        job = self.mod.process(
            {
                "hook_event_name": "PermissionRequest",
                "session_id": "perm-honest",
                "cwd": "/tmp/x",
                "tool_name": "Bash",
                "tool_input": {"command": "ls"},
            }
        )
        assert job is not None
        self.assertEqual(job["attention"]["reason"], "approval")
        title = job["attention"]["title"].lower()
        self.assertIn("agent", title)
        # Not a control affordance ("Approve Bash" implies in-app approve).
        self.assertFalse(title.startswith("approve "))

    def test_idle_prompt_background_wait_is_running_not_attention(self):
        """Claude often fires idle_prompt + bg-wait toast without background_tasks."""
        for msg in (
            "Waiting for 1 background agent to finish",
            "Waiting for 2 background agents to finish",
            "Waiting for 3 agents",
            "1 shell still running",
            "1 shell/monitor still running",
            "2 shells still running",
        ):
            with self.subTest(msg=msg):
                job = self.mod.process(
                    {
                        "hook_event_name": "Notification",
                        "session_id": "s3bg",
                        "cwd": "/tmp/y",
                        "notification_type": "idle_prompt",
                        "message": msg,
                        "background_tasks": [],
                    }
                )
                assert job is not None
                self.assertEqual(job["lifecycle"], "active")
                self.assertEqual(job["attention"]["level"], "none")
                self.assertNotEqual(job["attention"].get("reason"), "input")
                self.assertEqual(job["current"]["type"], "subagent")

    def test_idle_prompt_monitor_wait_is_success_not_attention(self):
        """Monitor-only toast → Success (green), not Attention or Running."""
        for msg in (
            "1 monitor still running",
            "Waiting for monitor",
            "2 monitors still running",
        ):
            with self.subTest(msg=msg):
                job = self.mod.process(
                    {
                        "hook_event_name": "Notification",
                        "session_id": "s3mon",
                        "cwd": "/tmp/y",
                        "notification_type": "idle_prompt",
                        "message": msg,
                        "background_tasks": [],
                    }
                )
                assert job is not None
                self.assertEqual(job["lifecycle"], "active")
                self.assertEqual(job["attention"]["level"], "none")
                self.assertNotEqual(job["attention"].get("reason"), "input")
                self.assertEqual(job["current"]["type"], "monitor")
                self.assertEqual(job["outcome"], "partial")

    def test_stop_with_shell_background_is_running(self):
        job = self.mod.process(
            {
                "hook_event_name": "Stop",
                "session_id": "s2shell",
                "cwd": "/tmp/y",
                "background_tasks": [
                    {
                        "id": "sh1",
                        "type": "shell",
                        "status": "running",
                        "description": "npm test",
                    }
                ],
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertNotIn("outcome", job)

    def test_stop_with_monitor_only_background_is_success(self):
        job = self.mod.process(
            {
                "hook_event_name": "Stop",
                "session_id": "s2mon",
                "cwd": "/tmp/y",
                "background_tasks": [
                    {
                        "id": "m1",
                        "type": "monitor",
                        "status": "running",
                        "description": "tail logs",
                    }
                ],
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "monitor")
        self.assertEqual(job["outcome"], "partial")
        self.assertEqual(job["attention"]["level"], "none")

    def test_stop_with_mixed_shell_and_monitor_is_running(self):
        """Shell (or subagent) + monitor → Running; only pure monitor is green."""
        job = self.mod.process(
            {
                "hook_event_name": "Stop",
                "session_id": "s2mix",
                "cwd": "/tmp/y",
                "background_tasks": [
                    {"id": "sh1", "type": "shell", "status": "running"},
                    {"id": "m1", "type": "monitor", "status": "running"},
                ],
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertNotIn("outcome", job)

    def test_subagent_start_updates_main_session_only(self):
        job = self.mod.process(
            {
                "hook_event_name": "SubagentStart",
                "session_id": "s4",
                "cwd": "/tmp/y",
                "agent_id": "agent-abc123",
                "agent_type": "Explore",
            }
        )
        assert job is not None
        self.assertEqual(job["id"], "claude-code:s4")
        self.assertEqual(job["lifecycle"], "active")
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["current"]["name"], "Explore")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertEqual(job["extensions"].get("agentType"), "Explore")
        self.assertEqual(job["extensions"].get("agentId"), "agent-abc123")
        # Single main-session job — no child rows.
        self.assertEqual(len(self._posted[-1]["jobs"]), 1)
        self.assertNotIn("parentJobId", job.get("extensions", {}))
        self.assertNotIn("paintRibbon", job.get("extensions", {}))

    def test_subagent_stop_main_continues_thinking(self):
        job = self.mod.process(
            {
                "hook_event_name": "SubagentStop",
                "session_id": "s5",
                "cwd": "/tmp/y",
                "agent_id": "agent-def",
                "agent_type": "Plan",
                "background_tasks": [],
            }
        )
        assert job is not None
        self.assertEqual(job["id"], "claude-code:s5")
        self.assertEqual(job["lifecycle"], "active")
        self.assertEqual(job["current"]["type"], "thinking")
        self.assertEqual(job["attention"]["level"], "none")
        self.assertEqual(len(self._posted[-1]["jobs"]), 1)

    def test_subagent_stop_with_remaining_background_stays_running(self):
        job = self.mod.process(
            {
                "hook_event_name": "SubagentStop",
                "session_id": "s5b",
                "cwd": "/tmp/y",
                "agent_id": "agent-1",
                "agent_type": "Explore",
                "background_tasks": [
                    {"id": "t2", "type": "subagent", "status": "running", "description": "other"}
                ],
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertEqual(job["attention"]["level"], "none")

    def test_tool_events_inside_subagent_are_ignored(self):
        """PreToolUse with agent_id must not thrash the main session."""
        job = self.mod.process(
            {
                "hook_event_name": "PreToolUse",
                "session_id": "s6",
                "cwd": "/tmp/y",
                "agent_id": "agent-xyz",
                "agent_type": "Explore",
                "tool_name": "Bash",
                "tool_input": {"command": "ls"},
            }
        )
        self.assertIsNone(job)
        self.assertEqual(self._posted, [])

    def test_permission_inside_subagent_still_updates_main(self):
        """Approval needed in a child should surface on the main session row."""
        job = self.mod.process(
            {
                "hook_event_name": "PermissionRequest",
                "session_id": "s7",
                "cwd": "/tmp/y",
                "agent_id": "agent-xyz",
                "agent_type": "Explore",
                "tool_name": "Bash",
                "tool_input": {"command": "rm x"},
            }
        )
        assert job is not None
        self.assertEqual(job["id"], "claude-code:s7")
        self.assertEqual(job["attention"]["reason"], "approval")

    def test_agent_pretool_on_main_sets_subagent_facet(self):
        job = self.mod.process(
            {
                "hook_event_name": "PreToolUse",
                "session_id": "s8",
                "cwd": "/tmp/y",
                "tool_name": "Agent",
                "tool_input": {"subagent_type": "Explore", "prompt": "scan"},
            }
        )
        assert job is not None
        self.assertEqual(job["current"]["type"], "subagent")
        self.assertIn("Explore", job["current"]["summary"])

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

    def test_session_end_clear_is_cancelled_with_reason(self):
        job = self.mod.process(
            {
                "hook_event_name": "SessionEnd",
                "session_id": "end-clear",
                "cwd": "/tmp/z",
                "reason": "clear",
            }
        )
        assert job is not None
        self.assertEqual(job["lifecycle"], "ended")
        self.assertEqual(job["outcome"], "cancelled")
        self.assertEqual(job["extensions"].get("endReason"), "clear")

    def test_session_start_after_prior_session_supersedes_without_session_end(self):
        """/new (and similar) often fire SessionStart only — previous id must leave."""
        first = self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "sess-old",
                "cwd": "/tmp/proj",
                "source": "startup",
            }
        )
        assert first is not None
        self.assertEqual(first["id"], "claude-code:sess-old")
        self.assertEqual(len(self._posted), 1)

        # Simulate /new: new session_id, no SessionEnd for sess-old.
        second = self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "sess-new",
                "cwd": "/tmp/proj",
                "source": "clear",
            }
        )
        assert second is not None
        self.assertEqual(second["id"], "claude-code:sess-new")
        self.assertEqual(second["lifecycle"], "active")

        # First POST of the second turn is the superseded end for the old session.
        self.assertEqual(len(self._posted), 3)
        ended = self._posted[1]["jobs"][0]
        started = self._posted[2]["jobs"][0]
        self.assertEqual(ended["id"], "claude-code:sess-old")
        self.assertEqual(ended["lifecycle"], "ended")
        self.assertEqual(ended["extensions"].get("endReason"), "superseded")
        self.assertEqual(started["id"], "claude-code:sess-new")
        self.assertEqual(started["lifecycle"], "active")

    def test_session_end_then_start_does_not_double_end(self):
        """When SessionEnd fires properly, the next SessionStart must not re-end it."""
        self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "s-a",
                "cwd": "/tmp/p",
            }
        )
        self.mod.process(
            {
                "hook_event_name": "SessionEnd",
                "session_id": "s-a",
                "cwd": "/tmp/p",
                "reason": "clear",
            }
        )
        n = len(self._posted)
        self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "s-b",
                "cwd": "/tmp/p",
                "source": "clear",
            }
        )
        # Only the new SessionStart — no extra superseded end for s-a.
        self.assertEqual(len(self._posted), n + 1)
        self.assertEqual(self._posted[-1]["jobs"][0]["id"], "claude-code:s-b")
        self.assertEqual(self._posted[-1]["jobs"][0]["lifecycle"], "active")

    def test_user_prompt_travels_as_a_durable_extension(self):
        """The prompt outlives `current`: only this hook run ever sees it."""
        job = self.mod.process(
            {
                "hook_event_name": "UserPromptSubmit",
                "session_id": "p-1",
                "cwd": "/tmp/p",
                "prompt": "  fix   the sidebar\n  preview  ",
            }
        )
        assert job is not None
        self.assertEqual(job["extensions"]["lastPrompt"], "fix the sidebar preview")
        self.assertTrue(job["extensions"]["lastPromptAt"])
        # Same text still drives the one-line row summary.
        self.assertEqual(job["current"]["summary"], "fix the sidebar preview")

    def test_long_prompt_is_capped_for_display(self):
        job = self.mod.process(
            {
                "hook_event_name": "UserPromptSubmit",
                "session_id": "p-2",
                "cwd": "/tmp/p",
                "prompt": "x" * 900,
            }
        )
        assert job is not None
        self.assertEqual(len(job["extensions"]["lastPrompt"]), self.mod.PROMPT_MAX)
        self.assertTrue(job["extensions"]["lastPrompt"].endswith("\u2026"))

    def test_other_events_do_not_carry_a_prompt(self):
        """Only UserPromptSubmit reports one — the hub keeps it from there on."""
        job = self.mod.process(
            {
                "hook_event_name": "PreToolUse",
                "session_id": "p-3",
                "cwd": "/tmp/p",
                "tool_name": "Bash",
            }
        )
        assert job is not None
        self.assertNotIn("lastPrompt", job["extensions"])

    def test_empty_prompt_reports_no_extension(self):
        job = self.mod.process(
            {
                "hook_event_name": "UserPromptSubmit",
                "session_id": "p-4",
                "cwd": "/tmp/p",
                "prompt": "   ",
            }
        )
        assert job is not None
        self.assertNotIn("lastPrompt", job["extensions"])

    def test_new_session_after_stop_without_end_still_supersedes(self):
        """Stop leaves the row active; a later SessionStart must still close it."""
        self.mod.process(
            {
                "hook_event_name": "UserPromptSubmit",
                "session_id": "live-1",
                "cwd": "/tmp/q",
                "prompt": "hello",
            }
        )
        self.mod.process(
            {
                "hook_event_name": "Stop",
                "session_id": "live-1",
                "cwd": "/tmp/q",
                "background_tasks": [],
            }
        )
        self._posted.clear()
        self.mod.process(
            {
                "hook_event_name": "SessionStart",
                "session_id": "live-2",
                "cwd": "/tmp/q",
                "source": "startup",
            }
        )
        ids = [p["jobs"][0]["id"] for p in self._posted]
        lifecycles = [p["jobs"][0]["lifecycle"] for p in self._posted]
        self.assertEqual(ids, ["claude-code:live-1", "claude-code:live-2"])
        self.assertEqual(lifecycles, ["ended", "active"])

    def test_job_id_never_includes_agent_id(self):
        """Orthogonality: subagent events still target the main conversation id."""
        job = self.mod.process(
            {
                "hook_event_name": "SubagentStart",
                "session_id": "main-sess",
                "cwd": "/tmp/y",
                "agent_id": "child-aaaa",
                "agent_type": "mol:spec-writer",
            }
        )
        assert job is not None
        self.assertEqual(job["id"], "claude-code:main-sess")
        self.assertEqual(job["id"].count(":"), 1)
        self.assertNotIn("child-aaaa", job["id"])
        self.assertEqual(job["name"], "y")  # project basename, not agent type
        self.assertNotEqual(job["name"], "mol:spec-writer")
        self.assertNotIn("parentJobId", job.get("extensions", {}))
        self.assertNotIn("paintRibbon", job.get("extensions", {}))
        self.assertNotEqual(job.get("extensions", {}).get("role"), "subagent")

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


class IngestTransportTests(unittest.TestCase):
    """The hand-written loopback POST, against a real socket.

    Every other test replaces ``_post_snapshot`` outright, so without this the
    transport that actually reaches ``nerve-hub`` would have no coverage at all.
    """

    def setUp(self):
        self.mod = load_hook()
        self.requests: list[bytes] = []
        self.answer = b"HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\n{\"applied\":1}"
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(1)
        # Point the hook at this one-shot stand-in for the hub.
        self.mod.INGEST_HOST, self.mod.INGEST_PORT = self.server.getsockname()
        self.thread = threading.Thread(target=self._serve_once, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.thread.join(timeout=2)
        self.server.close()

    def _serve_once(self):
        try:
            conn, _ = self.server.accept()
        except OSError:
            return
        with conn:
            received = b""
            conn.settimeout(2)
            while b"\r\n\r\n" not in received:
                piece = conn.recv(4096)
                if not piece:
                    break
                received += piece
            head, _, body = received.partition(b"\r\n\r\n")
            length = 0
            for line in head.split(b"\r\n"):
                if line.lower().startswith(b"content-length:"):
                    length = int(line.split(b":", 1)[1])
            while len(body) < length:
                piece = conn.recv(4096)
                if not piece:
                    break
                body += piece
            self.requests.append(head + b"\r\n\r\n" + body)
            conn.sendall(self.answer)

    def test_post_sends_a_well_formed_request_and_reads_the_status(self):
        status, _ = self.mod._post_json("/v1/snapshot", {"alias": "box", "jobs": []})
        self.assertEqual(status, 200)

        self.thread.join(timeout=2)
        raw = self.requests[0]
        head, _, body = raw.partition(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        self.assertEqual(lines[0], b"POST /v1/snapshot HTTP/1.1")
        headers = {
            k.strip().lower(): v.strip()
            for k, _, v in (line.partition(b":") for line in lines[1:])
        }
        self.assertEqual(headers[b"content-type"], b"application/json")
        self.assertEqual(headers[b"connection"], b"close")
        # Content-Length must count bytes, not characters, or a job name with
        # any non-ASCII in it truncates the body the hub reads.
        self.assertEqual(int(headers[b"content-length"]), len(body))
        self.assertEqual(json.loads(body), {"alias": "box", "jobs": []})

    def test_a_refusal_is_reported_with_its_body_and_never_raises(self):
        self.answer = (
            b"HTTP/1.1 400 Bad Request\r\nContent-Length: 26\r\n\r\n"
            b'{"error":"alias required"}'
        )
        status, detail = self.mod._post_json("/v1/snapshot", {"jobs": []})
        self.assertEqual(status, 400)
        self.assertIn("alias required", detail)

    def test_no_hub_listening_fails_open(self):
        self.server.close()
        self.thread.join(timeout=2)
        # A closed port must reach the caller as an exception it can swallow,
        # never as a hook that blocks or dies.
        posted = self.mod._post_snapshot("box", "darwin", {"id": "claude-code:s1"})
        self.assertFalse(posted)


class ProcessProbeTests(unittest.TestCase):
    """One hook run is one event; the machine it runs on cannot change inside it."""

    def setUp(self):
        self.mod = load_hook()

    def test_the_alias_probe_runs_once_per_process(self):
        first = self.mod._machine_alias()
        calls = {"n": 0}
        real = subprocess.check_output

        def counting(*a, **kw):
            calls["n"] += 1
            return real(*a, **kw)

        subprocess.check_output = counting
        try:
            for _ in range(5):
                self.assertEqual(self.mod._machine_alias(), first)
            self.assertEqual(self.mod._machine_kind(), self.mod._machine_kind())
        finally:
            subprocess.check_output = real
        self.assertEqual(calls["n"], 0, "alias/kind must be answered from cache")

    def test_the_process_climb_asks_about_each_pid_once(self):
        self.mod._agent_process_pid()
        calls = {"n": 0}
        real = subprocess.check_output

        def counting(*a, **kw):
            calls["n"] += 1
            return real(*a, **kw)

        subprocess.check_output = counting
        try:
            for _ in range(4):
                self.mod._agent_process_pid()
                self.mod._host_slot_token()
        finally:
            subprocess.check_output = real
        self.assertEqual(calls["n"], 0, "the pid climb must not re-spawn `ps`")


if __name__ == "__main__":
    unittest.main()

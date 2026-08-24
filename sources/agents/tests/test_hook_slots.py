"""Every official host event has a registered slot in the marketplace plugin."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HOOKS = ROOT / "plugins" / "nerve" / "hooks"

# Official event names. Claude omits WorktreeCreate/WorktreeRemove: a no-op
# hook fails worktree creation (the contract requires a path on stdout).
CLAUDE = {
    "SessionStart",
    "Setup",
    "UserPromptSubmit",
    "UserPromptExpansion",
    "PreToolUse",
    "PermissionRequest",
    "PermissionDenied",
    "PostToolUse",
    "PostToolUseFailure",
    "PostToolBatch",
    "Notification",
    "MessageDisplay",
    "SubagentStart",
    "SubagentStop",
    "TaskCreated",
    "TaskCompleted",
    "Stop",
    "StopFailure",
    "TeammateIdle",
    "InstructionsLoaded",
    "ConfigChange",
    "CwdChanged",
    "DirectoryAdded",
    "FileChanged",
    "PreCompact",
    "PostCompact",
    "Elicitation",
    "ElicitationResult",
    "SessionEnd",
}

CODEX = {
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "Stop",
    "SubagentStart",
    "SubagentStop",
}

GROK = {
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "PermissionDenied",
    "Stop",
    "StopFailure",
    "Notification",
    "SubagentStart",
    "SubagentStop",
    "PreCompact",
    "PostCompact",
}


def events(name: str) -> set[str]:
    data = json.loads((HOOKS / name).read_text())
    return set(data["hooks"])


class HookSlotTests(unittest.TestCase):
    def test_claude_registers_every_safe_official_event(self):
        self.assertEqual(events("hooks.json"), CLAUDE)

    def test_codex_registers_every_official_event(self):
        self.assertEqual(events("codex.json"), CODEX)

    def test_grok_registers_every_official_event(self):
        self.assertEqual(events("grok.json"), GROK)

    def test_claude_does_not_claim_worktree_hooks(self):
        claimed = events("hooks.json")
        self.assertNotIn("WorktreeCreate", claimed)
        self.assertNotIn("WorktreeRemove", claimed)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Nerve agent hook — push Claude Code / Grok / Codex lifecycle into Nerve.

Reads one JSON hook event from stdin, maps it to a Nerve subject snapshot,
and POSTs to the local ingest API. Always exit 0 (observability must never
block the agent). Failures are silent unless NERVE_HOOK_DEBUG=1.

Install (GitHub marketplace — repo root)
----------------------------------------
  Claude:  /plugin marketplace add Roy-Kid/nerve
           /plugin install nerve@nerve
  Codex:   codex plugin marketplace add Roy-Kid/nerve
           codex plugin add nerve@nerve

Environment
-----------
NERVE_URL          Base URL (default http://127.0.0.1:17890)
NERVE_SOURCE       Source id override: claude | grok | codex | …
NERVE_SOURCE_NAME  Display name override
NERVE_HOOK_DEBUG   If 1, log to stderr / ~/.nerve/hook.log
NERVE_HOOK_DRY_RUN If 1, print payload and skip HTTP
NERVE_PORT         Used only when NERVE_URL is unset (default 17890)
CLAUDE_PLUGIN_ROOT Set by Claude/Grok when running as a plugin hook
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

STATE_DIR = Path.home() / ".nerve" / "hook-state"
LOG_PATH = Path.home() / ".nerve" / "hook.log"

SOURCE_META: dict[str, dict[str, str]] = {
    "claude": {"id": "claude-code", "name": "Claude Code", "kind": "agent.claude"},
    "grok": {"id": "grok", "name": "Grok", "kind": "agent.grok"},
    "codex": {"id": "codex", "name": "Codex", "kind": "agent.codex"},
}

def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _debug(msg: str) -> None:
    if os.environ.get("NERVE_HOOK_DEBUG") != "1":
        return
    line = f"[{_now_iso()}] {msg}\n"
    try:
        sys.stderr.write(line)
    except Exception:
        pass
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def _base_url() -> str:
    if url := os.environ.get("NERVE_URL"):
        return url.rstrip("/")
    port = os.environ.get("NERVE_PORT", "17890")
    return f"http://127.0.0.1:{port}"


# ---------------------------------------------------------------------------
# Payload normalization
# ---------------------------------------------------------------------------

def _get(d: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for k in keys:
        if k in d and d[k] is not None and d[k] != "":
            return d[k]
    return default


def _event_name(payload: dict[str, Any]) -> str:
    raw = _get(
        payload,
        "hook_event_name",
        "hookEventName",
        "event",
        "event_name",
        default="",
    )
    # Normalize: SessionStart / sessionStart / session_start → sessionstart
    s = str(raw).strip()
    out = []
    for ch in s:
        if ch in ("_", "-", " "):
            continue
        out.append(ch.lower())
    return "".join(out)


def _detect_source(payload: dict[str, Any]) -> str:
    if forced := os.environ.get("NERVE_SOURCE"):
        return forced.strip().lower()

    env = os.environ

    # Codex plugin host sets PLUGIN_ROOT (and often CLAUDE_PLUGIN_ROOT for
    # compatibility). Prefer Codex when PLUGIN_ROOT is present.
    if env.get("PLUGIN_ROOT") or env.get("CODEX_PLUGIN_ROOT") or env.get(
        "CODEX_THREAD_ID"
    ) or env.get("CODEX_CI"):
        return "codex"

    # Grok plugin host
    if env.get("GROK_PLUGIN_ROOT") or env.get("GROK_SESSION") or env.get(
        "GROK_AGENT_ID"
    ) or env.get("XAI_GROK"):
        return "grok"

    # Claude Code plugin / CLI
    if env.get("CLAUDE_PLUGIN_ROOT") or env.get("CLAUDE_PLUGIN_DATA") or env.get(
        "CLAUDE_PROJECT_DIR"
    ) or env.get("CLAUDE_CODE_ENTRYPOINT") or env.get("CLAUDE_CODE_REMOTE"):
        return "claude"

    # Payload heuristics
    model = str(_get(payload, "model", default="") or "").lower()
    if "gpt" in model or "o3" in model or "o4" in model or "codex" in model:
        return "codex"
    if "grok" in model:
        return "grok"

    # Codex-specific fields
    if "turn_id" in payload and "permission_mode" in payload and "session_id" in payload:
        # Both Claude and Codex have these; weak. Prefer claude as default for shared schema.
        pass

    if payload.get("cursor_version"):
        return "claude"  # treat cursor as claude-compatible for ribbon labels

    return "claude"


def _session_id(payload: dict[str, Any]) -> str:
    sid = _get(
        payload,
        "session_id",
        "sessionId",
        "conversation_id",
        "conversationId",
        "thread_id",
        "threadId",
        default=None,
    )
    if sid:
        return str(sid)
    # Fallback: stable-ish id from cwd + pid window (last resort)
    cwd = _get(payload, "cwd", "workspace_root", "workspaceRoot", default=os.getcwd())
    return f"anon-{abs(hash(str(cwd))) % 10_000_000}"


def _cwd(payload: dict[str, Any]) -> str:
    cwd = _get(payload, "cwd", "working_directory", default=None)
    if cwd:
        return str(cwd)
    roots = payload.get("workspace_roots") or payload.get("workspaceRoots") or []
    if isinstance(roots, list) and roots:
        return str(roots[0])
    return os.getcwd()


def _project_name(cwd: str) -> str:
    if not cwd:
        return "unknown"
    return Path(cwd).name or "unknown"


def _truncate(s: str | None, n: int = 160) -> str | None:
    if not s:
        return None
    s = " ".join(str(s).split())
    if len(s) <= n:
        return s
    return s[: n - 1] + "…"


# ---------------------------------------------------------------------------
# Session state (monotonic version)
# ---------------------------------------------------------------------------

def _state_path(source_id: str, session_id: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in session_id)[:120]
    return STATE_DIR / source_id / f"{safe}.json"


def _load_state(source_id: str, session_id: str) -> dict[str, Any]:
    path = _state_path(source_id, session_id)
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_state(source_id: str, session_id: str, state: dict[str, Any]) -> None:
    path = _state_path(source_id, session_id)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")
    except Exception as e:
        _debug(f"state write failed: {e}")


def _next_version(state: dict[str, Any]) -> int:
    v = int(state.get("version") or 0) + 1
    state["version"] = v
    return v


# ---------------------------------------------------------------------------
# Event → subject facets
# ---------------------------------------------------------------------------

def _tool_summary(payload: dict[str, Any]) -> tuple[str, str | None]:
    """Return (current.type, summary) for tool events."""
    tool = str(_get(payload, "tool_name", "toolName", default="tool") or "tool")
    inp = _get(payload, "tool_input", "toolInput", default={}) or {}
    if not isinstance(inp, dict):
        inp = {}

    # Claude / Codex common shapes
    if tool in ("Bash", "run_terminal_command", "Shell", "exec_command"):
        cmd = inp.get("command") or inp.get("cmd") or ""
        return "tool.bash", _truncate(f"$ {cmd}" if cmd else "shell")
    if tool in ("Edit", "Write", "MultiEdit", "search_replace", "apply_patch"):
        path = (
            inp.get("file_path")
            or inp.get("filePath")
            or inp.get("path")
            or (inp.get("command") if isinstance(inp.get("command"), str) else None)
        )
        return "tool.edit", _truncate(f"edit {path}" if path else "edit files")
    if tool in ("Read", "read_file"):
        path = inp.get("file_path") or inp.get("filePath") or inp.get("path")
        return "tool.read", _truncate(f"read {path}" if path else "read file")
    if tool in ("Grep", "grep", "Glob", "list_dir"):
        return "tool.search", _truncate(tool)
    if tool.startswith("mcp__") or "__" in tool:
        return "tool.mcp", _truncate(tool)
    if tool in ("Task", "spawn_subagent", "Agent"):
        return "tool.subagent", _truncate(inp.get("description") or inp.get("prompt") or tool)
    return f"tool.{tool.lower()}", _truncate(tool)


def _map_event(
    event: str, payload: dict[str, Any], state: dict[str, Any]
) -> dict[str, Any] | None:
    """
    Produce facet updates for a handled event.
    Returns None to skip (no HTTP).
    Keys: lifecycle, current, attention, health, outcome, ended (bool)
    """
    # Default: keep session active
    out: dict[str, Any] = {
        "lifecycle": "active",
        "attention": {"level": "none"},
        "health": "ok",
        "outcome": None,
        "ended": False,
    }

    if event == "sessionstart":
        source = str(_get(payload, "source", default="startup") or "startup")
        out["current"] = {
            "type": "session",
            "name": "Session start",
            "summary": f"Session {source}",
        }
        state["created_at"] = state.get("created_at") or _now_iso()
        return out

    if event == "userpromptsubmit":
        prompt = _get(payload, "prompt", default="") or ""
        out["current"] = {
            "type": "thinking",
            "name": "User prompt",
            "summary": _truncate(prompt, 120) or "Processing prompt",
        }
        return out

    if event == "pretooluse":
        typ, summary = _tool_summary(payload)
        out["current"] = {"type": typ, "name": "Tool", "summary": summary}
        return out

    if event == "posttooluse":
        typ, summary = _tool_summary(payload)
        out["current"] = {
            "type": typ,
            "name": "Tool done",
            "summary": summary,
        }
        return out

    if event == "posttoolusefailure":
        typ, summary = _tool_summary(payload)
        err = _get(payload, "error", "error_message", default="") or ""
        out["current"] = {
            "type": typ,
            "name": "Tool failed",
            "summary": _truncate(f"{summary}: {err}" if err else summary),
        }
        out["health"] = "degraded"
        out["attention"] = {
            "level": "informational",
            "reason": "tool_failure",
            "title": "Tool failed",
            "summary": _truncate(err or summary),
        }
        return out

    if event == "permissionrequest":
        tool = _get(payload, "tool_name", "toolName", default="tool")
        typ, summary = _tool_summary(payload)
        out["current"] = {"type": "waiting", "name": "Permission", "summary": summary}
        out["attention"] = {
            "level": "required",
            "reason": "approval",
            "title": "Permission needed",
            "summary": _truncate(f"Approve {tool}: {summary or ''}"),
        }
        return out

    if event == "notification":
        ntype = str(
            _get(payload, "notification_type", "notificationType", default="") or ""
        )
        message = _get(payload, "message", "title", default="") or ntype or "Notification"
        if ntype in (
            "permission_prompt",
            "elicitation_dialog",
            "agent_needs_input",
        ) or "permission" in ntype or "input" in ntype:
            out["attention"] = {
                "level": "required",
                "reason": "approval" if "permission" in ntype else "input",
                "title": "Needs attention",
                "summary": _truncate(message),
            }
            out["current"] = {
                "type": "waiting",
                "name": "Waiting",
                "summary": _truncate(message),
            }
        elif ntype in ("agent_completed", "idle_prompt"):
            out["current"] = {
                "type": "idle",
                "name": "Idle",
                "summary": _truncate(message) or "Waiting for input",
            }
        else:
            out["current"] = {
                "type": "notification",
                "name": "Notification",
                "summary": _truncate(message),
            }
            out["attention"] = {
                "level": "informational",
                "reason": "notification",
                "title": ntype or "Notification",
                "summary": _truncate(message),
            }
        return out

    if event == "stop":
        last = _get(payload, "last_assistant_message", "lastAssistantMessage", default="")
        out["current"] = {
            "type": "idle",
            "name": "Turn complete",
            "summary": _truncate(last, 120) or "Waiting for next prompt",
        }
        # Session continues; clear attention from prior permission prompts.
        out["attention"] = {"level": "none"}
        return out

    if event == "stopfailure":
        err = _get(payload, "error", "last_assistant_message", default="") or "API error"
        out["current"] = {
            "type": "error",
            "name": "Turn failed",
            "summary": _truncate(err),
        }
        out["health"] = "degraded"
        out["outcome"] = "failure"
        out["attention"] = {
            "level": "informational",
            "reason": "failure",
            "title": "Agent error",
            "summary": _truncate(err),
        }
        return out

    if event == "sessionend":
        reason = str(_get(payload, "reason", "source", default="ended") or "ended")
        out["lifecycle"] = "ended"
        out["ended"] = True
        out["outcome"] = "success" if reason not in ("error", "crash") else "failure"
        out["current"] = {
            "type": "session",
            "name": "Session end",
            "summary": f"Ended ({reason})",
        }
        out["attention"] = {"level": "none"}
        return out

    if event == "subagentstart":
        atype = _get(payload, "agent_type", "agentType", default="subagent")
        out["current"] = {
            "type": "subagent",
            "name": "Subagent",
            "summary": _truncate(f"Running {atype}"),
        }
        return out

    if event == "subagentstop":
        atype = _get(payload, "agent_type", "agentType", default="subagent")
        last = _get(payload, "last_assistant_message", default="")
        out["current"] = {
            "type": "subagent",
            "name": "Subagent done",
            "summary": _truncate(last or f"{atype} finished"),
        }
        return out

    return None


def _build_subject(
    payload: dict[str, Any],
    source_key: str,
    session_id: str,
    facets: dict[str, Any],
    version: int,
    state: dict[str, Any],
) -> dict[str, Any]:
    meta = SOURCE_META.get(source_key, {
        "id": source_key,
        "name": source_key.title(),
        "kind": f"agent.{source_key}",
    })
    if name_override := os.environ.get("NERVE_SOURCE_NAME"):
        meta = {**meta, "name": name_override}

    cwd = _cwd(payload)
    project = _project_name(cwd)
    display = f"{meta['name']} — {project}"
    now = _now_iso()
    created = state.get("created_at") or now
    state["created_at"] = created

    subject_id = f"{meta['id']}:{session_id}"

    subject: dict[str, Any] = {
        "id": subject_id,
        "type": "agent.session",
        "name": display,
        "lifecycle": facets["lifecycle"],
        "current": facets.get("current"),
        "attention": facets.get("attention") or {"level": "none"},
        "health": facets.get("health") or "ok",
        "progress": {"kind": "none"},
        "source": {
            "id": meta["id"],
            "name": meta["name"],
            "kind": meta["kind"],
        },
        "context": {
            "project": project,
            "workspace": cwd,
            "labels": [source_key, "agent"],
        },
        "location": {
            "openURL": f"file://{cwd}" if cwd.startswith("/") else None,
            "focusHint": cwd,
            "logPath": _get(payload, "transcript_path", "transcriptPath", default=None),
        },
        "capabilities": [],
        "actions": [
            {
                "id": "copy",
                "title": "Copy",
                "kind": "copy_summary",
                "state": "available",
                "destructive": False,
                "confirmationRequired": False,
            }
        ],
        "createdAt": created,
        "startedAt": created,
        "updatedAt": now,
        "version": version,
        "extensions": {
            "hookEvent": _get(payload, "hook_event_name", "hookEventName", "event", default=""),
            "sessionId": session_id,
            "sourceKey": source_key,
            "model": _get(payload, "model", default=None),
        },
    }

    if facets.get("outcome"):
        subject["outcome"] = facets["outcome"]
    if facets.get("ended"):
        subject["endedAt"] = now
        subject["lifecycle"] = "ended"

    # Drop null location fields for cleaner JSON
    loc = subject["location"]
    subject["location"] = {k: v for k, v in loc.items() if v is not None}
    if not subject["location"]:
        del subject["location"]

    return subject


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def _post_snapshot(subject: dict[str, Any]) -> bool:
    url = f"{_base_url()}/v1/snapshot"
    body = json.dumps({"subjects": [subject]}).encode("utf-8")
    if os.environ.get("NERVE_HOOK_DRY_RUN") == "1":
        print(json.dumps({"url": url, "subjects": [subject]}, indent=2))
        return True

    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "User-Agent": "nerve-agent-hook/0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            _debug(f"POST {url} → {resp.status}")
            return 200 <= getattr(resp, "status", 200) < 300
    except urllib.error.HTTPError as e:
        _debug(f"HTTP {e.code}: {e.reason}")
        return False
    except Exception as e:
        _debug(f"POST failed: {e}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def process(payload: dict[str, Any]) -> dict[str, Any] | None:
    event = _event_name(payload)
    if not event:
        _debug("empty event name; skip")
        return None

    # Skip high-churn events we don't handle in batch 1
    if event not in {
        "sessionstart",
        "sessionend",
        "userpromptsubmit",
        "pretooluse",
        "posttooluse",
        "posttoolusefailure",
        "permissionrequest",
        "notification",
        "stop",
        "stopfailure",
        "subagentstart",
        "subagentstop",
    }:
        _debug(f"skip unhandled event: {event}")
        return None

    # Optional throttle for PreToolUse (many tools fire rapidly)
    source_key = _detect_source(payload)
    meta = SOURCE_META.get(source_key, {"id": source_key})
    source_id = meta["id"]
    session_id = _session_id(payload)
    state = _load_state(source_id, session_id)

    if event == "pretooluse":
        last = float(state.get("last_pretool_ts") or 0)
        now = time.time()
        # Allow at most ~2 PreToolUse updates/sec per session (still responsive)
        if now - last < 0.45:
            _debug("throttle PreToolUse")
            return None
        state["last_pretool_ts"] = now

    facets = _map_event(event, payload, state)
    if facets is None:
        return None

    version = _next_version(state)
    subject = _build_subject(payload, source_key, session_id, facets, version, state)
    _save_state(source_id, session_id, state)
    _post_snapshot(subject)
    return subject


def main() -> int:
    try:
        raw = sys.stdin.read()
    except Exception:
        return 0
    if not raw or not raw.strip():
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        _debug(f"invalid JSON: {e}")
        return 0
    if not isinstance(payload, dict):
        return 0
    try:
        process(payload)
    except Exception as e:
        _debug(f"process error: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

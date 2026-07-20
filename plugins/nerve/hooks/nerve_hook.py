#!/usr/bin/env python3
"""Nerve hook — push Claude Code / Grok / Codex lifecycle into Nerve as jobs.

Reads one JSON hook event from stdin, maps it to a Job snapshot with machine
alias, and POSTs to the fixed local ingest URL. Always exit 0 (observability
must never block the agent).

No environment variables. No on-disk state. Alias is a free-form machine
label (prefer stable Bonjour LocalHostName on macOS). Nerve shows whatever
alias arrives — no allow-list.

Install (GitHub marketplace — repo root)
----------------------------------------
  Claude:  /plugin marketplace add Roy-Kid/nerve
           /plugin install nerve@nerve
  Codex:   codex plugin marketplace add Roy-Kid/nerve
           codex plugin add nerve@nerve
"""

from __future__ import annotations

import json
import platform
import socket
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Fixed ingest — tunnels (SSH RemoteForward) make remotes look like loopback.
INGEST_BASE = "http://127.0.0.1:17890"

PRODUCER_META: dict[str, dict[str, str]] = {
    "claude": {"id": "claude-code", "name": "Claude Code", "kind": "agent.claude"},
    "grok": {"id": "grok", "name": "Grok", "kind": "agent.grok"},
    "codex": {"id": "codex", "name": "Codex", "kind": "agent.codex"},
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _version_ms() -> int:
    return int(time.time() * 1000)


def _machine_alias() -> str:
    """Prefer stable Bonjour LocalHostName on macOS; fall back to gethostname short.

    Campus / DHCP networks often rewrite DNS hostnames (e.g. RoydeAir.kemi…,
    emp-181-64.eduroam…), while Nerve Settings “This Mac” uses the Bonjour
    LocalHostName (e.g. RoydeMacBook-Air). Mismatch → 403 and silent drop.
    """
    if sys.platform == "darwin":
        try:
            import subprocess

            out = subprocess.check_output(
                ["/usr/sbin/scutil", "--get", "LocalHostName"],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1.0,
            ).strip()
            if out:
                return out
        except Exception:
            pass
    host = socket.gethostname() or "local"
    short = host.split(".")[0].strip() or host
    return short


def _machine_kind() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "darwin"
    if system == "linux":
        # crude WSL check without env
        try:
            release = platform.release().lower()
            if "microsoft" in release or "wsl" in release:
                return "wsl"
        except Exception:
            pass
        return "linux"
    if system == "windows":
        return "windows"
    return "unknown"


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
    s = str(raw).strip()
    out = []
    for ch in s:
        if ch in ("_", "-", " "):
            continue
        out.append(ch.lower())
    return "".join(out)


def _detect_producer(payload: dict[str, Any]) -> str:
    """Detect producer from host env (plugin runner) then payload heuristics."""
    import os

    # Host harness injects these for plugin hooks — most reliable signal.
    if os.environ.get("GROK_PLUGIN_ROOT") or os.environ.get("GROK_SESSION_ID") or os.environ.get(
        "GROK_HOOK_EVENT"
    ):
        return "grok"
    if os.environ.get("CODEX_HOME") or os.environ.get("PLUGIN_ROOT"):
        # Codex plugin runner sets PLUGIN_ROOT; Claude uses CLAUDE_PLUGIN_ROOT only.
        # Prefer explicit codex markers when present.
        if os.environ.get("CODEX_HOME") or "codex" in (
            os.environ.get("PLUGIN_ROOT") or ""
        ).lower():
            return "codex"

    model = str(_get(payload, "model", default="") or "").lower()
    if "grok" in model:
        return "grok"
    if "gpt" in model or "o3" in model or "o4" in model or "codex" in model:
        return "codex"

    # Schema heuristics
    if payload.get("cursor_version"):
        return "claude"

    session_source = str(_get(payload, "source", default="") or "").lower()
    if "codex" in session_source:
        return "codex"
    if "grok" in session_source:
        return "grok"

    # Claude plugin runner always sets CLAUDE_PLUGIN_ROOT (Grok also sets it as an
    # alias, but GROK_* was already checked above).
    if os.environ.get("CLAUDE_PLUGIN_ROOT") and not os.environ.get("GROK_PLUGIN_ROOT"):
        return "claude"

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
    cwd = _get(payload, "cwd", "workspace_root", "workspaceRoot", default="")
    return f"anon-{abs(hash(str(cwd))) % 10_000_000}"


def _cwd(payload: dict[str, Any]) -> str:
    cwd = _get(payload, "cwd", "working_directory", default=None)
    if cwd:
        return str(cwd)
    roots = payload.get("workspace_roots") or payload.get("workspaceRoots") or []
    if isinstance(roots, list) and roots:
        return str(roots[0])
    return str(Path.cwd())


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


def _notification_type(payload: dict[str, Any]) -> str:
    """Structured notification kind from the harness (never parse free-text message)."""
    raw = _get(
        payload,
        "notification_type",
        "notificationType",
        default="",
    )
    return str(raw or "").strip().lower().replace("-", "_")


def _background_tasks(payload: dict[str, Any]) -> list[Any]:
    """In-flight background work from Stop / SubagentStop (Claude Code ≥ 2.1.145).

    Empty or missing ⇒ none. Non-empty ⇒ parent is paused on background agents/shells,
    not waiting for the human. Do not infer this from free-text UI strings.
    """
    raw = payload.get("background_tasks")
    if raw is None:
        raw = payload.get("backgroundTasks")
    return raw if isinstance(raw, list) else []


def _background_work_facets(payload: dict[str, Any], tasks: list[Any]) -> dict[str, Any]:
    """Structured facets while background_tasks is non-empty → Running."""
    n = len(tasks)
    label = "subagent"
    desc = None
    first = tasks[0] if tasks else None
    if isinstance(first, dict):
        label = str(first.get("type") or first.get("kind") or "subagent")
        desc = first.get("description") or first.get("name")
    summary = f"{n} background task(s)"
    if desc:
        summary = f"{summary}: {_truncate(str(desc), 100)}"
    return {
        "lifecycle": "active",
        "current": {
            "type": "subagent",
            "name": label,
            "summary": summary,
            "startedAt": _now_iso(),
        },
        "attention": {"level": "none"},
        "health": "ok",
    }


def _map_event(event: str, payload: dict[str, Any]) -> dict[str, Any] | None:
    """Map hook **event type** (+ structured fields) → job facets.

    Status is never inferred from free-text titles/messages. Controlled vocabulary:
      current.type: starting | thinking | tool | subagent | waiting | idle | info
      attention.reason: input | approval | failure | (none)
    """
    if event == "sessionstart":
        return {
            "lifecycle": "active",
            "current": {
                "type": "starting",
                "summary": "Session started",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "sessionend":
        return {
            "lifecycle": "ended",
            "outcome": "success",
            "current": {"type": "idle", "summary": "Session ended"},
            "attention": {"level": "none"},
            "health": "ok",
            "ended": True,
        }

    if event == "userpromptsubmit":
        prompt = _truncate(_get(payload, "prompt", "user_prompt", default=""), 120)
        return {
            "lifecycle": "active",
            "current": {
                "type": "thinking",
                "summary": prompt or "New prompt",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "pretooluse":
        tool = str(_get(payload, "tool_name", "toolName", default="tool"))
        # Structured tool names for “parent blocked on child agent output”.
        if tool in (
            "spawn_subagent",
            "get_command_or_subagent_output",
            "Task",
            "Agent",
        ):
            return {
                "lifecycle": "active",
                "current": {
                    "type": "subagent",
                    "name": tool,
                    "summary": f"Using {tool}",
                    "startedAt": _now_iso(),
                },
                "attention": {"level": "none"},
                "health": "ok",
            }
        return {
            "lifecycle": "active",
            "current": {
                "type": "tool",
                "name": tool,
                "summary": f"Using {tool}",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "posttooluse":
        tool = str(_get(payload, "tool_name", "toolName", default="tool"))
        return {
            "lifecycle": "active",
            "current": {
                "type": "tool",
                "name": tool,
                "summary": f"Finished {tool}",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "subagentstart":
        # Structured event: a child agent is running → Running.
        name = str(_get(payload, "agent_type", "agentType", "description", default="subagent"))
        return {
            "lifecycle": "active",
            "current": {
                "type": "subagent",
                "name": name,
                "summary": f"Subagent: {name}",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "subagentstop":
        # Subagent finished; parent session still active (more work or later Stop).
        name = str(
            _get(
                payload,
                "agent_type",
                "agentType",
                "tool_name",
                "toolName",
                "description",
                default="subagent",
            )
        )
        return {
            "lifecycle": "active",
            "current": {
                "type": "tool",
                "name": name,
                "summary": f"Subagent finished: {name}",
                "startedAt": _now_iso(),
            },
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event in ("posttoolusefailure", "stopfailure"):
        tool = str(_get(payload, "tool_name", "toolName", default="tool"))
        return {
            "lifecycle": "active",
            "current": {
                "type": "tool",
                "name": tool,
                "summary": f"Failed: {tool}",
            },
            "attention": {
                "level": "informational",
                "reason": "failure",
                "title": f"{tool} failed",
            },
            "health": "degraded",
        }

    if event == "permissionrequest":
        tool = str(_get(payload, "tool_name", "toolName", default="tool"))
        return {
            "lifecycle": "active",
            "current": {
                "type": "waiting",
                "summary": f"Permission: {tool}",
            },
            "attention": {
                "level": "required",
                "reason": "approval",
                "title": f"Approve {tool}",
                "summary": _truncate(
                    json.dumps(_get(payload, "tool_input", "toolInput", default={}), default=str),
                    140,
                ),
            },
            "health": "ok",
        }

    if event == "notification":
        # Claude Code documents notification_type as a closed enum — use that only.
        # Never classify by message/title text.
        ntype = _notification_type(payload)
        title = str(_get(payload, "title", "message", default="") or "")
        summary = _truncate(title, 120) or ntype or "Notification"
        bg = _background_tasks(payload)

        if ntype in ("permission_prompt", "permission"):
            return {
                "lifecycle": "active",
                "current": {"type": "waiting", "summary": summary},
                "attention": {
                    "level": "required",
                    "reason": "approval",
                    "title": "Needs approval",
                    "summary": summary,
                },
                "health": "ok",
            }

        # idle_prompt only means “human’s turn” when no background work remains.
        if ntype in ("idle_prompt", "agent_needs_input", "elicitation_dialog"):
            if bg:
                return _background_work_facets(payload, bg)
            return {
                "lifecycle": "active",
                "current": {"type": "idle", "summary": summary},
                "attention": {
                    "level": "suggested",
                    "reason": "input",
                    "title": "Waiting for input",
                    "summary": summary,
                },
                "health": "ok",
            }

        if ntype in ("agent_completed", "elicitation_complete", "elicitation_response", "auth_success"):
            return {
                "lifecycle": "active",
                "current": {"type": "info", "summary": summary},
                "attention": {"level": "none"},
                "health": "ok",
            }

        # Unknown / missing type (e.g. Grok UI toasts): keep session active Running.
        # Do not invent Attention from free-text. Real idle is Stop / idle_prompt.
        if bg:
            return _background_work_facets(payload, bg)
        return {
            "lifecycle": "active",
            "current": {"type": "info", "summary": summary},
            "attention": {"level": "none"},
            "health": "ok",
        }

    if event == "stop":
        # Claude Code Stop carries background_tasks[] (structured). Non-empty means
        # the main agent paused on background work — still Running, not Attention.
        bg = _background_tasks(payload)
        if bg:
            return _background_work_facets(payload, bg)
        return {
            "lifecycle": "active",
            "current": {"type": "idle", "summary": "Waiting for your input"},
            "attention": {
                "level": "suggested",
                "reason": "input",
                "title": "Waiting for input",
                "summary": "Waiting for your input",
            },
            "health": "ok",
        }

    return None


def _build_job(
    payload: dict[str, Any],
    producer_key: str,
    session_id: str,
    facets: dict[str, Any],
) -> dict[str, Any]:
    meta = PRODUCER_META.get(
        producer_key,
        {"id": producer_key, "name": producer_key.title(), "kind": f"agent.{producer_key}"},
    )
    cwd = _cwd(payload)
    project = _project_name(cwd)
    display = f"{meta['name']} — {project}"
    now = _now_iso()
    alias = _machine_alias()
    job_id = f"{meta['id']}:{session_id}"

    job: dict[str, Any] = {
        "id": job_id,
        "kind": "session",
        "name": display,
        "alias": alias,
        "lifecycle": facets["lifecycle"],
        "current": facets.get("current"),
        "attention": facets.get("attention") or {"level": "none"},
        "health": facets.get("health") or "ok",
        "progress": {"kind": "none"},
        "producer": {
            "id": meta["id"],
            "name": meta["name"],
            "kind": meta["kind"],
        },
        "context": {
            "project": project,
            "workspace": cwd,
            "labels": [producer_key, "session"],
        },
        "location": {
            "openURL": f"file://{cwd}" if str(cwd).startswith("/") else None,
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
        "createdAt": now,
        "startedAt": now,
        "updatedAt": now,
        "version": _version_ms(),
        "extensions": {
            "hookEvent": _get(payload, "hook_event_name", "hookEventName", "event", default=""),
            "sessionId": session_id,
            "model": _get(payload, "model", default=None),
        },
    }

    if facets.get("outcome"):
        job["outcome"] = facets["outcome"]
    if facets.get("ended"):
        job["endedAt"] = now
        job["lifecycle"] = "ended"

    loc = job["location"]
    job["location"] = {k: v for k, v in loc.items() if v is not None}
    if not job["location"]:
        del job["location"]

    return job


def _post_snapshot(alias: str, machine_kind: str, job: dict[str, Any]) -> bool:
    url = f"{INGEST_BASE}/v1/snapshot"
    body = json.dumps(
        {
            "alias": alias,
            "machineKind": machine_kind,
            "jobs": [job],
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "User-Agent": "nerve-hook/0.2",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            return 200 <= getattr(resp, "status", 200) < 300
    except urllib.error.HTTPError as e:
        # Fail open, but leave a breadcrumb for "why is Nerve empty?".
        try:
            detail = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            detail = ""
        print(
            f"[nerve] snapshot HTTP {e.code} alias={alias!r} {detail}",
            file=sys.stderr,
        )
        return False
    except Exception as e:
        print(f"[nerve] snapshot failed alias={alias!r}: {e}", file=sys.stderr)
        return False


def process(payload: dict[str, Any]) -> dict[str, Any] | None:
    event = _event_name(payload)
    if not event:
        return None

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
        return None

    facets = _map_event(event, payload)
    if facets is None:
        return None

    producer_key = _detect_producer(payload)
    session_id = _session_id(payload)
    job = _build_job(payload, producer_key, session_id, facets)
    alias = job["alias"]
    _post_snapshot(alias, _machine_kind(), job)
    return job


def main() -> int:
    try:
        raw = sys.stdin.read()
    except Exception:
        return 0
    if not raw or not raw.strip():
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0
    if not isinstance(payload, dict):
        return 0
    try:
        process(payload)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

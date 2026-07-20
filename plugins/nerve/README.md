# nerve (job status plugin)

Reports agent session lifecycle to the **Nerve** menu-bar hub as **jobs**.

- Fail-open: if Nerve is down, hooks exit `0` and never block the agent.
- **No environment variables.** Ingest URL is fixed: `http://127.0.0.1:17890`.
- **Stateless:** no `~/.nerve` state files; each event posts a full job snapshot.
- **Alias** = free-form machine label (prefer Bonjour LocalHostName on macOS). Nerve shows whatever arrives; Settings → Machines is only for SSH tunnels.

## Install from GitHub

### Claude Code

```text
/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve
```

### Codex CLI

```bash
codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve
```

## Remote machines

On the **Mac running Nerve**:

1. Settings → **Machines** → **Add Machine…**
2. Alias = remote hostname short name
3. Host / user / optional identity file
4. Enable + Connect (SSH reverse tunnel managed by Nerve)

On the remote, install this plugin and run sessions as usual — hooks post to `127.0.0.1:17890`, which the tunnel forwards to the host.

## What it reports

| Hook (structured) | Facets | Ribbon |
|-------------------|--------|--------|
| `SessionStart` | `active` + `starting` | Running |
| `UserPromptSubmit` / `PreToolUse` / `PostToolUse` | `active` + `thinking`/`tool` | Running |
| `SubagentStart` | `active` + `subagent` | Running |
| `SubagentStop` | still `active` | Running |
| `PermissionRequest` / `Notification` `permission_prompt` | `attention.reason=approval` | Attention |
| `Stop` with empty `background_tasks` / `idle_prompt` | `attention.reason=input` | Attention |
| `Stop` with non-empty `background_tasks` / `SubagentStart` | `current.type=subagent` | Running |
| `SessionEnd` | `ended` + success | **Leaves panel** (no Success linger) |
| Other `Notification` (no type) | `active` + `info` (message is display-only) | Running |

Status is **never** inferred from free-text titles/messages — only event name + fields like `notification_type`.

Job ids: `{producer}:{session_id}` e.g. `claude-code:…`, `codex:…`, `grok:…`.

## Development

```bash
python3 sources/agents/tests/test_nerve_hook.py
```

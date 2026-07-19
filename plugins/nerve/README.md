# nerve (agent status plugin)

Reports agent session lifecycle to the **Nerve** menu-bar status hub at `http://127.0.0.1:17890`.

- Fail-open: if Nerve is down, hooks exit `0` and never block the agent.
- One GitHub repo is the marketplace for **Claude Code** and **Codex** (and Grok via Claude-compatible hooks).

## Install from GitHub

Marketplace lives at the **repository root** (`.claude-plugin/marketplace.json`). There is no extra nested marketplace directory.

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

Or in an interactive Codex session: `/plugins` → marketplace **nerve** → install **nerve**.

If Codex prompts to review hooks, trust them once via `/hooks`.

### Alternatives

```bash
# Full git URL
codex plugin marketplace add https://github.com/Roy-Kid/nerve.git

# Local checkout (development)
codex plugin marketplace add /ABS/PATH/TO/nerve
# Claude Code:
# /plugin marketplace add /ABS/PATH/TO/nerve
```

Then:

1. Start Nerve: `./scripts/run.sh` (from this repo, or your installed app)
2. Open a Claude / Codex / Grok session
3. Ribbon shows **Claude Code — &lt;project&gt;** or **Codex — &lt;project&gt;**

### Verify / uninstall

**Claude**

```text
/plugin
/hooks
/plugin uninstall nerve@nerve
```

**Codex**

```bash
codex plugin list --marketplace nerve
codex plugin remove nerve@nerve
codex plugin marketplace remove nerve   # optional
```

## What it reports

| Hook | Ribbon effect |
|------|----------------|
| `SessionStart` | New `agent.session` (Running) |
| `UserPromptSubmit` / `PreToolUse` | Update current activity |
| `PermissionRequest` / permission `Notification` | Attention (orange) |
| `Stop` | Idle between turns (session still active) |
| `SessionEnd` | Ended / Success |
| `StopFailure` / tool failure | Degraded / informational |

Subject ids (auto-detected):

- `claude-code:{session_id}`
- `codex:{session_id}`
- `grok:{session_id}`

## Environment (optional)

| Variable | Default | Meaning |
|----------|---------|---------|
| `NERVE_URL` | `http://127.0.0.1:17890` | Ingest base URL |
| `NERVE_PORT` | `17890` | Used if `NERVE_URL` unset |
| `NERVE_SOURCE` | auto | Force `claude` / `codex` / `grok` |
| `NERVE_HOOK_DEBUG` | off | Log to stderr + `~/.nerve/hook.log` |
| `NERVE_HOOK_DRY_RUN` | off | Print snapshot JSON; skip HTTP |

Detection notes:

- Codex sets `PLUGIN_ROOT` (and often `CLAUDE_PLUGIN_ROOT` for compatibility) → reported as **Codex**
- Claude plugin host sets `CLAUDE_PLUGIN_ROOT` → **Claude Code**
- Grok session / plugin env → **Grok**

## Layout

```
plugins/nerve/
  .claude-plugin/plugin.json   # Claude plugin metadata
  .codex-plugin/plugin.json    # Codex plugin metadata
  hooks/hooks.json             # lifecycle wiring (${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT}})
  hooks/nerve_hook.py          # stdin JSON → POST /v1/snapshot
  README.md
```

## Development

```bash
# Unit tests (no Nerve server required)
python3 sources/agents/tests/test_nerve_hook.py

# Dry-run a SessionStart payload
NERVE_HOOK_DRY_RUN=1 python3 plugins/nerve/hooks/nerve_hook.py <<'EOF'
{"hook_event_name":"SessionStart","session_id":"demo","cwd":"/tmp/demo","source":"startup"}
EOF
```

After editing the plugin, reinstall so the host reloads the cache:

```bash
codex plugin remove nerve@nerve && codex plugin add nerve@nerve
# Claude: /plugin uninstall nerve@nerve then /plugin install nerve@nerve
```

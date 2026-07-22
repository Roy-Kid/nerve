<p align="center">
  <img src="assets/logo-512.png" alt="Nerve" width="160" />
</p>

# Nerve for macOS

Lightweight **menu-bar** status hub for long-running work: sessions, builds, tests, jobs — all modeled as **Jobs** on **Machines**.

Nerve does **not** run your agents. It aggregates status they push over a local HTTP ingest API into one continuous ribbon.

Product signal model (lifecycle, privacy, scope): the site’s **[Signal](./index-page/)** section — run `cd index-page && npm run dev`.

## Quick start

```bash
./scripts/run.sh
```

A continuous **ribbon** appears in the macOS menu bar (no Dock icon, no floating window).

| Gesture | Action |
|---------|--------|
| **Left-click** ribbon | Status panel (↑/↓, Enter expand; detail + timeline + actions) |
| **Right-click** ribbon | **Settings…** or **Quit Nerve** |

Settings tabs: **General** · **Machines** · **Appearance** · **Notifications** · **About**

### Machines (Settings — no CLI)

1. Open **Settings → Machines**
2. **This Mac** is always present (alias = hostname short name)
3. **Add Machine…** for a remote: alias, host, SSH user, optional identity file
4. Toggle **Enabled** / **Connect** — Nerve writes a managed block into `~/.ssh/config` and opens `ssh -N` with `RemoteForward` so the remote’s `127.0.0.1:17890` reaches this Mac

Use the **remote hostname short name** as the alias so hooks match without extra setup.

```bash
./scripts/inject_demo.sh
./scripts/verify_loop.sh
```

## Agent plugins (Claude Code · Codex · Grok)

Push live sessions as **jobs** from **one GitHub marketplace**. Hooks are fail-open, **stateless**, and use **no environment variables**.

| Harness | Install |
|---------|---------|
| **Claude Code** | `/plugin marketplace add Roy-Kid/nerve` then `/plugin install nerve@nerve` |
| **Codex** | `codex plugin marketplace add Roy-Kid/nerve` then `codex plugin add nerve@nerve` |
| **Grok** | Same Claude-compatible marketplace / plugin |

**One job per conversation.** Subagents only refine the main session’s `current` facet (not separate panel rows). Tool noise inside subagents is ignored.

Full plugin docs: [`plugins/nerve/README.md`](./plugins/nerve/README.md)

```bash
python3 sources/agents/tests/test_nerve_hook.py
```

## Privacy (by design)

- **Jobs, timelines, and pending actions are memory-only** for the current process.
- Quitting Nerve clears them.
- Only **preferences** (machines list, colors, notifications, coach flags) use `UserDefaults`.
- Machine SSH definitions are also mirrored into a **managed block** in `~/.ssh/config`.
- Loopback ingest only (`127.0.0.1`); remotes arrive via SSH reverse forward.

## Ingest API

Loopback: `http://127.0.0.1:17890`

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/v1/health` | Liveness |
| GET | `/v1/jobs` | Current jobs (in memory) |
| POST | `/v1/snapshot` | Full job snapshot(s) — requires `alias` |
| POST | `/v1/events` | Incremental events — requires `alias` when creating jobs |
| POST | `/v1/demo` | Built-in demo jobs |
| POST | `/v1/clear` | Clear in-memory jobs |
| GET | `/v1/actions/pending?producerId=` | Poll action queue |
| POST | `/v1/actions/result?producerId=` | Report action completion |
| POST | `/v1/actions/invoke` | Invoke as from UI |

### Snapshot body

```json
{
  "alias": "gpu-box",
  "machineKind": "linux",
  "jobs": [
    {
      "id": "claude-code:sess_1",
      "kind": "session",
      "name": "nerve",
      "alias": "gpu-box",
      "producer": { "id": "claude-code", "name": "Claude Code", "kind": "agent.claude" },
      "lifecycle": "active",
      "current": { "type": "thinking", "summary": "…" },
      "attention": { "level": "none" },
      "health": "ok",
      "progress": { "kind": "none" },
      "createdAt": "…",
      "updatedAt": "…",
      "version": 1
    }
  ]
}
```

- **`alias`** — free-form machine label shown in the panel (any string; Settings → Machines is only for SSH tunnels).
- **`kind`** — job shape (`session`, `build`, `test`, …), not “agent”.
- **`producer`** — who reported the job.
- **`name`** — typically project basename (`cwd`); status lives in `current` / `attention`.

Wire sample: [`fixtures/demo_snapshot.json`](./fixtures/demo_snapshot.json).

## Job status (default colors)

| Status | Default | Meaning |
|--------|---------|---------|
| Problem | Red | Failed / cannot continue |
| Attention | Orange | Needs input, auth, or decision |
| Waiting | Purple | Waiting on system / resources / deps |
| Running | Blue | Actively executing |
| Success | Green | Reserved (sessions leave the panel on `SessionEnd`) |
| Inactive | Gray | Paused, idle, or unknown |

Open agent sessions stay on the panel while `lifecycle` is active. On **`SessionEnd`** the job is removed immediately (no Recent / Success linger). Waiting for input is **Attention**, not leave.

## Requirements

- macOS 14+
- Xcode 15+
- Python 3 (agent hook plugin only)
- OpenSSH client (for remote machines)

## Website

Marketing site (Rsbuild + React) lives in [`index-page/`](./index-page/):

```bash
cd index-page && npm install && npm run dev
```

Production build: `npm run build` → `index-page/dist/`. App Store / GitHub URLs: `index-page/src/config.ts`.

## Layout

```
.claude-plugin/          GitHub marketplace
plugins/nerve/           Hooks → local ingest (jobs + alias)
sources/agents/          Hook tests + symlink
Nerve/Nerve/
  App/                   AppModel, Settings (Machines tab)
  Models/                Job, MachineConfig, events
  Store/                 JobStore (memory), SettingsStore
  Services/              Notifications, Actions, SSH + tunnels
  Ingest/                Loopback HTTP
  UI/…                   Ribbon, panel, coach
index-page/              Marketing site (Rsbuild) — Signal / Sources / Privacy
fixtures/                Demo snapshot JSON
scripts/                 run / inject_demo / verify_loop
assets/                  Brand marks
```

## License

See repository license (if present). Private use / distribution as you prefer until a license file is added.

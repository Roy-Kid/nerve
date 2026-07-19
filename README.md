# Nerve for macOS

Lightweight **menu-bar** status hub for long-running work: agents, builds, tests, jobs, and custom subjects.

Nerve does **not** run your agents. It aggregates status they push over a local HTTP ingest API into one continuous ribbon.

Implementation status: [`docs/IMPLEMENTATION.md`](./docs/IMPLEMENTATION.md)

## Quick start

```bash
./scripts/run.sh
```

A continuous **ribbon** appears in the macOS menu bar (no Dock icon, no floating window).

| Gesture | Action |
|---------|--------|
| **Left-click** ribbon | Status panel (↑/↓, Enter expand; detail + timeline + actions) |
| **Right-click** ribbon | **Settings…** or **Quit Nerve** |

Settings tabs: **General** · **Appearance** (ribbon size + status → color map) · **Notifications** · **About**

The status panel **Group by** control (Priority / Status / Source) reorders the menu-bar ribbon to match the panel list.

```bash
./scripts/inject_demo.sh   # or: curl -X POST http://127.0.0.1:17890/v1/demo
./scripts/verify_loop.sh
```

## Agent plugins (Claude Code · Codex · Grok)

Push live agent sessions into the ribbon from **one GitHub marketplace**. No install scripts; no nested marketplace path.

| Harness | Install |
|---------|---------|
| **Claude Code** | `/plugin marketplace add Roy-Kid/nerve` then `/plugin install nerve@nerve` |
| **Codex** | `codex plugin marketplace add Roy-Kid/nerve` then `codex plugin add nerve@nerve` |
| **Grok** | Same Claude-compatible marketplace / plugin |

Then start Nerve and open a session — the ribbon shows e.g. **Claude Code — &lt;project&gt;** or **Codex — &lt;project&gt;**.

Full plugin docs: [`plugins/nerve/README.md`](./plugins/nerve/README.md)

```bash
# Offline hook unit tests
python3 sources/agents/tests/test_nerve_hook.py
```

## Privacy (by design)

- **Subjects, timelines, and pending actions are memory-only** for the current process.
- Quitting Nerve clears them. Nothing is written under Application Support for subject data.
- Only **preferences** (colors, notification toggles, DND, mute lists, coach flags) use `UserDefaults`.
- Loopback ingest only (`127.0.0.1`).

## Ingest API

Loopback: `http://127.0.0.1:17890`

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/v1/health` | Liveness |
| GET | `/v1/subjects` | Current subjects (in memory) |
| POST | `/v1/snapshot` | Full subject snapshot(s) |
| POST | `/v1/events` | Incremental events |
| POST | `/v1/demo` | Built-in demo subjects |
| POST | `/v1/clear` | Clear in-memory subjects |
| GET | `/v1/actions/pending?sourceId=` | Poll remote action queue |
| POST | `/v1/actions/result?sourceId=` | Report action completion |
| POST | `/v1/actions/invoke` | Invoke as from UI |

Wire format: [`fixtures/demo_snapshot.json`](./fixtures/demo_snapshot.json).

## Ribbon statuses (default colors)

| Status | Default | Meaning |
|--------|---------|---------|
| Problem | Red | Failed / cannot continue |
| Attention | Orange | Needs input, auth, or decision |
| Waiting | Purple | Waiting on system / resources / deps |
| Running | Blue | Actively executing |
| Success | Green | Recently completed OK |
| Inactive | Gray | Paused, idle, or unknown |

Edit under **Settings → Appearance** (reset to defaults anytime).

## Requirements

- macOS 14+
- Xcode 15+ (tested with Xcode 26)
- Python 3 (agent hook plugin only)

## Layout

```
.claude-plugin/          GitHub marketplace (Claude + Codex discover this)
plugins/nerve/           Agent status plugin (hooks → local ingest)
sources/agents/          Hook tests + symlink to plugin script
Nerve/Nerve/
  App/                   NerveApp, AppModel, Settings
  Models/                Subject, Event, History, Actions, CoreTypes
  Store/                 SubjectStore (memory), SettingsStore
  Services/              Notifications, ActionService
  Ingest/                Loopback HTTP
  UI/MenuBar             Status-item ribbon + context menu
  UI/Panel               Status popover
  UI/Onboarding          First-run coach
  UI/Ribbon              Palette helpers
fixtures/                Demo snapshot JSON
scripts/                 run / inject_demo / verify_loop
docs/                    Implementation status
```

## License

See repository license (if present). Private use / distribution as you prefer until a license file is added.

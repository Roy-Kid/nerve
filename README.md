# Nerve for macOS

Lightweight **menu-bar** status hub for long-running work: agents, builds, tests, jobs, and custom subjects.

Nerve does **not** run your agents. It aggregates status they push over a local HTTP ingest API into one continuous ribbon.

Product requirements: [`SPEC.md`](./SPEC.md)  
Implementation status: [`docs/IMPLEMENTATION.md`](./docs/IMPLEMENTATION.md)

## Quick start

```bash
./scripts/run.sh
```

A continuous **ribbon** appears in the macOS menu bar (no Dock icon, no floating window).

| Gesture | Action |
|---------|--------|
| **Left-click** ribbon | Status panel (↑/↓, Enter expand; detail + timeline + actions) |
| **Right-click** ribbon | **Preferences…** or **Quit Nerve** |

Preferences tabs: **General** · **Customize** (status → color map) · **Notifications** · **About**

```bash
./scripts/inject_demo.sh   # or: curl -X POST http://127.0.0.1:17890/v1/demo
./scripts/verify_loop.sh
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

Wire format: `fixtures/demo_snapshot.json`.

## Ribbon statuses (default colors)

| Status | Default | Meaning |
|--------|---------|---------|
| Problem | Red | Failed / cannot continue |
| Attention | Orange | Needs input, auth, or decision |
| Waiting | Purple | Waiting on system / resources / deps |
| Running | Blue | Actively executing |
| Success | Green | Recently completed OK |
| Inactive | Gray | Paused, idle, or unknown |

Edit under **Preferences → Customize** (reset to defaults anytime).

## Requirements

- macOS 14+
- Xcode 15+ (tested with Xcode 26)

## Layout

```
Nerve/Nerve/
  App/           NerveApp, AppModel, Preferences
  Models/        Subject, Event, History types, Actions, CoreTypes
  Store/         SubjectStore (memory), SettingsStore (UserDefaults)
  Services/      Notifications, ActionService
  Ingest/        Loopback HTTP
  UI/MenuBar     Status-item ribbon + minimal context menu
  UI/Panel       Status popover
  UI/Onboarding  First-run coach
  UI/Ribbon      Palette helpers
```

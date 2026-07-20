# Nerve for macOS — Implementation Status

Last updated: 2026-07-20

---

## Scope decisions

- **Multi-display independent ribbons:** out of scope (menu-bar status item is OS-managed).
- **No job disk storage:** jobs, timelines, and pending actions are **memory-only**. Settings only (UserDefaults) + managed `~/.ssh/config` block for machines.
- **Machine vs Job:** machines are configured in Settings (SSH alias + tunnel); work units are **Jobs** (not agents). Producer ≠ machine.
- **No project env vars** on the hook; fixed loopback ingest URL.
- **No Privacy / Data preference panes:** demo/clear via ingest HTTP only.
- Custom **status → color** map is in Settings.

---

## Done

### Core

- [x] Resident menu-bar app (no Dock / no floating ribbon)
- [x] Continuous multi-color ribbon (length ∝ active count)
- [x] Ribbon **order follows panel grouping** (Priority / Status / Source — same list order, adjacent same-status merged)
- [x] Ribbon **length scale + thickness** adjustable in Settings → Appearance
- [x] Six display statuses with **user-editable color map** + reset defaults
- [x] Job / Facets / Current / Event / Action model (open kinds + extensions)
- [x] MachineConfig in Settings + SSH config writer + reverse-forward tunnel manager
- [x] Loopback HTTP ingest: snapshot (`alias` + `jobs`), events, demo, clear
- [x] Open alias ingest (any reported alias is shown; Settings machines are tunnels only)
- [x] Idempotent events + version guards
- [x] **Memory-only** runtime job state (legacy Application Support wiped on launch)

### UI

- [x] Left-click → Status panel only (no History product surface)
- [x] Single-line rows; expand detail + live timeline
- [x] Status panel **grouping modes**: Priority / Status / Source
- [x] Right-click → **Settings…** / **Quit** only
- [x] Settings tabs: General · Machines · Appearance · Notifications · About
- [x] First-run coach (skippable); “Show Welcome Tips…” under About
- [x] Keyboard: ↑/↓ focus, Enter/Space expand
- [x] Accessibility labels / values / focus ring; respects Reduce Motion
- [x] Panel group by Priority / Status / **Machine**

### Notifications

- [x] Required / Urgent / Failure / Unresponsive / long success
- [x] Dedupe, sound toggle, pause all
- [x] DND schedule (start/end, overnight wrap)
- [x] Mute source / mute project
- [x] Click notification → open subject

### Privacy

- [x] No subject/timeline/pending persistence
- [x] No “save names/summaries” toggles (nothing to save)
- [x] Settings-only UserDefaults

### Actions

- [x] Local: open, copy summary, open logs (when declared)
- [x] Remote queue: approve/reject/cancel/… → owning source only
- [x] `GET /v1/actions/pending?sourceId=`
- [x] `POST /v1/actions/result?sourceId=`
- [x] `POST /v1/actions/invoke`
- [x] Destructive actions require confirmation

### Agent plugins (batch 1)

- [x] Shared hook: `plugins/nerve/hooks/nerve_hook.py` → `POST /v1/snapshot`
- [x] **Repo-root GitHub marketplace** (`.claude-plugin/marketplace.json`)
  - Claude Code: `/plugin marketplace add Roy-Kid/nerve` → `/plugin install nerve@nerve`
  - Codex: `codex plugin marketplace add Roy-Kid/nerve` → `codex plugin add nerve@nerve`
- [x] Dual plugin metadata: `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json`
- [x] Auto source detect: `PLUGIN_ROOT` → codex, Claude plugin env → claude, Grok env → grok
- [x] Events: SessionStart/End, UserPromptSubmit, Pre/PostToolUse, PermissionRequest, Notification, Stop/StopFailure, SubagentStart/Stop
- [x] Fail-open hooks (exit 0; never block the agent)
- [x] Offline unit tests: `sources/agents/tests/test_nerve_hook.py`
- [x] No nested marketplace path; no shell install scripts

---

## Explicitly not building

- Multi-display ribbon modes
- Disk-backed history / restart recovery of subjects
- Cloud sync, team features, full log viewer, in-app agent chat
- Remote Action *execution* inside foreign processes (sources poll themselves)
- Cursor-native marketplace packaging (Grok/Cursor can still use Claude-compatible hooks)

---

## Run & verify

```bash
./scripts/run.sh
./scripts/verify_loop.sh
./scripts/inject_demo.sh
python3 sources/agents/tests/test_nerve_hook.py
```

### Action protocol (sources)

```bash
curl -s 'http://127.0.0.1:17890/v1/actions/pending?sourceId=my-source'
curl -s -X POST 'http://127.0.0.1:17890/v1/actions/result?sourceId=my-source' \
  -H 'Content-Type: application/json' \
  -d '{"id":"<pending-id>","state":"succeeded","message":"ok"}'
```

### Plugin install (after GitHub push)

```text
# Claude Code
/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve

# Codex
codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve
```

---

## Layout

```
.claude-plugin/marketplace.json   # marketplace name: nerve
plugins/nerve/
  .claude-plugin/plugin.json
  .codex-plugin/plugin.json
  hooks/hooks.json
  hooks/nerve_hook.py
sources/agents/
  nerve_hook.py                   # symlink → plugins/nerve/hooks/nerve_hook.py
  tests/test_nerve_hook.py
  README.md
  codex/hooks.json                # legacy manual template (prefer marketplace)

Nerve/Nerve/
  App/          NerveApp, AppModel, Settings
  Models/       Subject, Event, History, Actions, CoreTypes
  Store/        SubjectStore (memory), SettingsStore, Persistence (legacy wipe)
  Services/     Notifications, ActionService
  Ingest/       HTTP loopback server
  UI/MenuBar    Status-item ribbon + minimal context menu
  UI/Panel      Status popover
  UI/Onboarding First-run coach
  UI/Ribbon     Palette (colors from SettingsStore)
```

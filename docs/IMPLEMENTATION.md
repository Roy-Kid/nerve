# Nerve for macOS — Implementation Status

**Source of truth:** `SPEC.md`  
Last updated: 2026-07-19

---

## Scope decisions

- **Multi-display independent ribbons:** out of scope (menu-bar status item is OS-managed).
- **No subject disk storage:** subjects, timelines, and pending actions are **memory-only**. Preferences only (UserDefaults).
- **No Privacy / Data preference panes:** storage toggles removed; demo/clear via ingest HTTP only.
- Custom **status → color** map is in Preferences (P0 for usability; SPEC listed as P1 originally — implemented early).

---

## Done

### Core
- [x] Resident menu-bar app (no Dock / no floating ribbon)
- [x] Continuous self-luminous multi-color ribbon (length ∝ active count)
- [x] Six display statuses with **user-editable color map** + reset defaults
- [x] Subject / Facets / Current / Event / Action model (open types + extensions)
- [x] Loopback HTTP ingest: snapshot, events, demo, clear
- [x] Idempotent events + version guards
- [x] **Memory-only** runtime state (legacy Application Support wiped on launch)

### UI
- [x] Left-click → Status panel only (no History product surface)
- [x] Single-line rows; expand detail + live timeline
- [x] Status panel **grouping modes**: Priority / Status / Source
- [x] Right-click → **Preferences…** / **Quit** only
- [x] Preferences tabs: General · Customize · Notifications · About
- [x] First-run coach (skippable); “Show Welcome Tips…” under About
- [x] Keyboard: ↑/↓ focus, Enter/Space expand
- [x] Accessibility labels / values / focus ring; respects Reduce Motion

### Notifications
- [x] Required / Urgent / Failure / Unresponsive / long success
- [x] Dedupe, sound toggle, pause all
- [x] DND schedule (start/end, overnight wrap)
- [x] Mute source / mute project
- [x] Click notification → open subject

### Privacy
- [x] No subject/timeline/pending persistence
- [x] No “save names/summaries” toggles (nothing to save)
- [x] Preferences-only UserDefaults

### Actions
- [x] Local: open, copy summary, open logs (when declared)
- [x] Remote queue: approve/reject/cancel/… → owning source only
- [x] `GET /v1/actions/pending?sourceId=`
- [x] `POST /v1/actions/result?sourceId=`
- [x] `POST /v1/actions/invoke`
- [x] Destructive actions require confirmation

---

## Explicitly not building

- Multi-display ribbon modes
- Disk-backed history / restart recovery of subjects
- Cloud sync, team features, full log viewer, in-app agent chat
- Remote Action *execution* inside foreign processes (sources poll themselves)

---

## Run & verify

```bash
./scripts/run.sh
./scripts/verify_loop.sh
./scripts/inject_demo.sh
```

### Action protocol (sources)

```bash
curl -s 'http://127.0.0.1:17890/v1/actions/pending?sourceId=my-source'
curl -s -X POST 'http://127.0.0.1:17890/v1/actions/result?sourceId=my-source' \
  -H 'Content-Type: application/json' \
  -d '{"id":"<pending-id>","state":"succeeded","message":"ok"}'
```

---

## Layout

```
Nerve/Nerve/
  App/          NerveApp, AppModel, Preferences (SettingsView)
  Models/       Subject, Event, History types, Actions, CoreTypes
  Store/        SubjectStore (memory), SettingsStore, Persistence (legacy wipe)
  Services/     Notifications, ActionService
  Ingest/       HTTP loopback server
  UI/MenuBar    Status-item ribbon + minimal context menu
  UI/Panel      Status popover
  UI/Onboarding First-run coach
  UI/Ribbon     Palette (colors from SettingsStore)
```

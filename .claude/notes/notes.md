# Notes

<!-- mol:note:topic:arch-hub-topology -->
## 2026-08-23 — State hub topology (supersedes in-app ingest)

Why: surfaces must be peers; the app quitting must not take state down; tmux plugin joined as a second surface.

**Rule**: State authority is the standalone `nerve-hub` daemon (`crates/nerve-hub`, fixed `127.0.0.1:17890`, port bind = single-instance lock). Surfaces hold a `GET /v1/stream` SSE connection as their presence token; hub self-exits ~30s after the last one drops. `JobStore` in the app is a frame-fed read-only cache (writes leave only via request sinks); notifications derive from adjacent-frame diffs incl. `departed` terminal pairs, and fire from the macOS surface only. Hook wire contract unchanged; producers never spawn the hub.

**Supersedes**: in-process `IngestServer.swift` + `JobStore`-owned state semantics (deleted 2026-08-22/23, spec chain `nerve-hub` → `nerve-macos-surface-01..03` → `nerve-tmux-surface`).

## 2026-07-23 — Focus A+B (no reverse-control)

- Product: **do not** C/D (approve / submit_input / in-panel chat). Enhance **A+B**.
- A Attention semantics already clear (input vs approval vs failure; bg wait ≠ Attention).
- B Focus first-class:
  - Hook `location.openURL`: Cursor/VS Code deep link when host is IDE, else `file://` workspace URI; `focusHint` = producer · project · host · path.
  - Panel primary action **Open / Focus** (borderedProminent), then Copy. No Approve.
  - Notification click → `focusAndOpenJob` (select + expand + open location) + best-effort panel reveal.
  - Honest copy: “Your turn in agent” / “Approval needed in agent” — return to agent UI, never “Type here”.
- Local open/copy actions stay re-usable (not stuck `.succeeded`).

## 2026-07-22 — Notifications: suggested attention was silent

- Bug: `NotificationService` only fired for `attention.level` `required` / `urgent`.
- Hooks set Stop / idle_prompt to **`suggested`** (paints Status.attention) — no banner.
- Fix: escalate notify on `suggested` + `required` (Settings “Needs attention”); `urgent` separate.
- Also fire Failures on `attention.reason=failure` (tool/turn fail without outcome).
- Auth denied → log to Console; empty body no longer drops banner.

## 2026-07-22 — Ribbon ambient motion (settings)

- Menu-bar ribbon keeps transition ease (length / segment cross-fade).
- Continuous styles via `RibbonMotionStyle`: transitionsOnly | breathe | shimmer | statusPulse | full.
- Settings → General → Ribbon motion; gated by `animationsEnabled` + Reduce Motion.
- Live paint path is SwiftUI `MenuBarRibbonLabel` (`TimelineView` ~24fps when ambient active).

## 2026-07-22 — Remote tunnels: local SSH config + known_hosts

- Machines list = Hosts from `~/.ssh/config` (refresh only; no manual add).
- Managed block: **RemoteForward + ExitOnForwardFailure** only.
- Connect: `ssh -O forward` if ControlMaster up; else `ssh -n -N`. OTP → Terminal first.

## 2026-07-22 — Shell / monitor bg wait ≠ Attention

- Toast / `background_tasks` for shell · subagent · “shell/monitor still running” → **Running** (never Attention).
- Monitor-**only** queue (or pure monitor toast) → `current.type=monitor` + `outcome=partial` → **Success green** (phase done, waiting for feedback).
- Mixed shell+monitor → Running. Real human idle remains Stop empty bg / idle_prompt without bg toast.

## 2026-07-22 — SessionStart is starting/Ready, not Running

- `/new` / SessionStart with no user prompt yet must **not** paint Running.
- Hook: SessionStart → `lifecycle=active` + `current.type=starting` + summary “Ready” (no attention).
- `starting` ≠ `idle`: idle + attention.input is your_turn (Stop); starting is open with no turn yet.
- App: `starting` / `idle` / `booting` → Inactive; only thinking/tool/subagent/info → Running.
- First UserPromptSubmit flips to thinking → Running.

## 2026-07-22 — Session leave paths (P0/P1)

- Authoritative: SessionEnd (`endReason` + outcome success|cancelled) → evict.
- Supersede: same UI `slot` + new SessionStart → previous ended (`superseded`).
- Local PID reaping: snapshot `extensions.pid` + hub's 5s maintenance tick; dead local process → `process_gone`.
- No manual Dismiss control — leave paths above only (Copy remains as local action).
- Snapshots carry `extensions.slot` + `extensions.pid` when known.

## 2026-07-22 — Public docs on the website only

- Removed repo `docs/` (former `IMPLEMENTATION.md`).
- Product handbook is `index-page/src/docs/content.ts` with SPA routes under `/docs/*`.
- Root / plugin / sources READMEs are short pointers to the site.
- Hook model: **one job per conversation**; subagents only refine main `current`; ignore tool noise when `agent_id` is set (except permission / lifecycle brackets).

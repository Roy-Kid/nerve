# Notes

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
- Local PID reaping: snapshot `extensions.pid` + 5s timer; dead local process → `process_gone`.
- Dismiss action: local-only row remove (`dismissed`); does not signal the agent.
- Snapshots carry `extensions.slot` + `extensions.pid` when known.

## 2026-07-22 — Public docs on the website only

- Removed repo `docs/` (former `IMPLEMENTATION.md`).
- Product handbook is `index-page/src/docs/content.ts` with SPA routes under `/docs/*`.
- Root / plugin / sources READMEs are short pointers to the site.
- Hook model: **one job per conversation**; subagents only refine main `current`; ignore tool noise when `agent_id` is set (except permission / lifecycle brackets).

# Notes

<!-- mol:note:topic:vscode-surface -->
## 2026-08-24 — VS Code is a third peer surface

Why: macOS and tmux Focus often terminate in `vscode://` / `cursor://`. Once the human is in the editor, that hop is empty; the agent is already a terminal or sidebar in this window.

**Rule**: `vsc-ext/` consumes `GET /v1/stream?surface=vscode`. Native chrome only in v1 (status bar + Activity Bar tree). No OS banners (those stay macOS). No reverse-control. Hub port stays 17890; the extension may spawn `nerve-hub` the way tmux does and never kills it. Focus ranks pid → this-window terminal, then cwd → here, then folder; a foreign pid/`file://` is never compared locally. Default filter is All. Status is a third golden copy of `Subject.swift`. Build is molvis-style rslib/rspack, extension-host bundle only.

**Supersedes**: “two surfaces” wording in CLAUDE.md invariant 7.

<!-- mol:note:topic:status-palette -->
## 2026-08-24 — Status colors: five rainbow + gray

Why: waiting-as-purple asked the user to memorize a sixth “needs a look” hue. Monitor is a different job: watching a stream, not blocked and not executing.

**Rule**: shared job status is five rainbow hues (red problem, orange attention, blue running, violet monitor, green success) plus gray idle. Seven is the ceiling. Waiting on the system shares **Attention**. A background shell/subagent still executing is **Running**; only `current.type=monitor` (or active + `outcome=partial`) is **Monitor**. Ended success stays green. Chrome stays gray/slate.

**Surfaces**: `Status.painted` / tmux `colors.rs` / site `statusMeta` are the three copies of the same map. `{waiting}` remains a summary token (always empty from derivation); `{monitor}` is in the default `@nerve_status_format`.

<!-- mol:note:topic:arch-hub-topology -->
## 2026-08-23 — State hub topology (supersedes in-app ingest)

Why: surfaces must be peers; the app quitting must not take state down; tmux plugin joined as a second surface.

**Rule**: State authority is the standalone `nerve-hub` daemon (`crates/nerve-hub`, fixed `127.0.0.1:17890`, port bind = single-instance lock). Surfaces hold a `GET /v1/stream` SSE connection as their presence token; hub self-exits ~30s after the last one drops. `JobStore` in the app is a frame-fed read-only cache (writes leave only via request sinks); notifications derive from adjacent-frame diffs incl. `departed` terminal pairs, and fire from the macOS surface only. Hook wire contract unchanged; producers never spawn the hub.

**Supersedes**: in-process `IngestServer.swift` + `JobStore`-owned state semantics (deleted 2026-08-22/23, spec chain `nerve-hub` → `nerve-macos-surface-01..03` → `nerve-tmux-surface`).

## 2026-08-23 — Jobs on another machine: the ssh pane is the pane

Why: selecting the `arrhenius1` job in the tmux sidebar answered “no local pane” — the scan matched a remote job's pid and workspace against local panes, which can only fail (or, worse, collide with an unrelated local pid).

**Rule**: a surface matches a job to a pane only when the job is on **its own** machine. `machine::local_alias()` (Bonjour LocalHostName → short hostname, the hook's own order) decides; a machine that cannot name itself treats everything as local, so the fallback is the old behaviour. Same principle as the hub's reaper: “remote pids are meaningless here”.

**Rule**: a job on another machine matches the pane running **ssh to that machine** (`crate::ssh`) — `Enter` jumps to it, and the **preview never mirrors it**: that pane is a route to the *machine*, so every job on it resolves to the same pane and a mirror would show three jobs one terminal and call it each of them. Selecting a remote job announces where it runs and leaves the slot alone. Destination comes from `ps -t <pane_tty> -o args=` on panes whose `pane_current_command` is a client (`ssh`/`autossh`/`mosh`), ranked exact > first label > shared prefix, resolved through `~/.ssh/config` `HostName` so `ssh Arrhenius` matches alias `arrhenius1`. `-N` tunnels are refused: the Nerve RemoteForward is exactly that shape and has no terminal to return to. A miss now says which machine it is, not “no local pane”.

**Rule**: `Enter` on a remote job also steers the far side. One `ssh <host> sh -s` runs the *same* `pid → tty → pane` resolution over there and issues `select-window` / `select-pane`, plus `switch-client` when exactly one client is attached (with several, the one in this ssh pane cannot be told from someone else's — so none is moved). `crate::remote`, fire-and-forget on its own thread: the local jump already happened and a sidebar must never block on someone else's network. `BatchMode=yes` + `ConnectTimeout=3`, script on stdin (so the remote login shell never parses it, and the only interpolated value is a `u32` pid). Measured on Arrhenius over a live ControlMaster: 200–300ms, `pid 668866 → %25`.

**Rule**: there is no "preview" state — the highlight moves and the pane beside the sidebar follows it, local or remote. Two defects made it drift out of step and both are fixed: (a) `show()` wrote its memo *before* checking whether the window was on screen, so a selection that changed while the window was hidden (the list re-sorts every frame) counted as shown and the pane stayed on the previous job for good — the memo is now written after that check, and a hidden window is re-checked once a second rather than five times; (b) two sidebars scanning `list-panes -a` took turns yanking one agent pane out of each other's slot — a pane now carries `@nerve_preview_owner` while a sidebar shows it, and every other scan skips it.

**Rule**: it goes both ways. The highlight moves and the pane follows (`pid → tty → pane`); walk into a pane yourself and the highlight comes to you (`pane_tty → ps -t → the job whose reported pid is there`, `panes::pids_on_tty` + `state::job_running_as`, polled every 400ms and skipped while the sidebar itself has the keyboard). A pane already in the sidebar's own window is never swapped — it is visible where it is, and moving it would shuffle the layout under whoever is standing in it.

**Rule**: the same call is what makes a *remote* row follow the cursor. Selecting a remote job brings its ssh pane beside the sidebar *and* asks the far side to turn to that job, so one shared session shows the row under the cursor. Requests go through `remote::RemoteSelector`: one call in flight, newest wins, so holding `j` across three remote rows lands on the row the cursor stopped at rather than wherever the slowest call finished. `Enter` uses the same queue.

**Fix**: `Enter` no longer forgets what it showed (`PanePreview::settle`, was `restore`). Clearing the memo meant the next tick re-previewed the same job the moment the human came back to the sidebar — dragging the pane they had just walked into out of its own window.

**Why not `tmux -CC`**: control mode (what iTerm2 speaks) streams a whole window tree, cursor and resize events so a *terminal emulator* can render remote panes. This surface is a TUI inside tmux, not an emulator — it needs one imperative "select that window". Socket forwarding (`ssh -L` onto the remote tmux socket) is a dead end besides: client/server protocol versions must match (3.7c vs 3.2a here) and a forwarded socket cannot pass a tty fd.

**Fix**: the sidebar cursor is anchored to a **job id**, not a row. The list re-sorts on every frame (`compare_jobs`: attention, health, `updatedAt`), so a job arriving — or merely reporting activity — slid a different job under a cursor that never moved, and the preview swap followed it. `restore_selection(fallback)` re-finds the anchored job after every rebuild; a job that left hands the cursor to the row it held.

**Fix**: the preview memo is keyed on `(job id, pid)`. A job first seen without a pid matches on its workspace path alone — ambiguous between two agents in one project — and the frame that finally carries the pid has to re-scan instead of counting as “already showing”.

**Rule**: macOS answers the same question the same way. `RemoteMachine` (`Models/MachineConfig.swift`, next to `LocalMachine`) decides whether a job is on this Mac; `ActionService.openLocation` routes a foreign one to `openRemote`: IDE deep link → `ssh://<Host>` via NSWorkspace (Terminal by default, Host resolved from `SSHConfigWriter.loadLocalHosts()` with the same exact > label > prefix scoring) → copy the breadcrumb. A remote `file://` path is never handed to NSWorkspace. The panel button reads **Open on \<alias\>**, because opening a terminal on another machine is not the same act as revealing a folder here. `--test-swift` now also compiles `ActionService.swift` + `SSHConfigWriter.swift`.

**Layout**: the tmux surface's matching half now lives in `crate::panes` (which pane belongs to a job — decides only), `crate::preview` is what the sidebar *does* with that answer (swap / restore / jump), `crate::ssh` reads ssh panes, `crate::remote` talks to the far side, `crate::machine` answers "is this job mine". `preview.rs` had grown past the 800-line ceiling.

**Rule**: `prefix + e` on a window with no sidebar opens it **focused** — a person asking for the sidebar should land in it, not press the key twice. Auto-create stays unfocused (a new window must not steal the keyboard). `prefix + q` closes *and* selects the pane the sidebar interrupted (`@nerve_sidebar_return`), instead of letting tmux pick.

**Rule**: unit tests build `AppState` with `PanePreview::detached()`. `AppState::new` detects `$TMUX_PANE` and can swap real panes, so `cargo test` run from inside tmux used to be able to rearrange the window it was started in.

## 2026-08-23 — Sidebar detail panel is the last prompt, and it folds

Why: the panel showed the hub timeline, which `/v1/snapshot` never fills (only `/v1/events` records one), so it fell back to the row's own activity text — a second copy of what the row already said.

**Rule**: the panel under the job list is **Prompt** — what the human last asked that agent. Never falls back to the activity summary. `Space` (or a click on the title row) folds it to its title line; `Shift-Tab` switches Prompt ⇄ Git. Same fact on macOS: `Job.lastPrompt` (`Models/Subject.swift`) paints a wrapped **Prompt** block at the top of an expanded row's detail (`StatusPanelView.promptBlock`) — both surfaces read the one field, neither derives it.

**Rule**: the prompt travels as `extensions.lastPrompt` (+ `lastPromptAt`, 400 chars, `nerve_hook.py` `PROMPT_MAX`) on the `UserPromptSubmit` snapshot only — a hook is one process per event and no later run knows the prompt. The hub keeps it: `STICKY_EXTENSIONS` in `state/store.rs` carries those keys onto snapshots that omit them, the snapshot-door twin of the per-key patch merge. Live status keys (`pid`, `hookEvent`) stay non-sticky — a producer that stops reporting one means it. Still memory-only, still loopback (invariant 4).

**Rule**: a preview swap is recorded in the window option `@nerve_preview_swap` (`<foreign> <slot>`). `prefix+q` and the next sidebar start both undo a stranded one — a sidebar killed rather than closed never runs its own restore, and the moved pane would otherwise stay in the wrong window.

**Fix**: `auto-close` treated a pane with no `@nerve_pane_role` as "nothing left" and killed windows that still held live shells. Only the sidebar ever sets a role, so every pane must *be* the sidebar before the window closes (`only_sidebar_remains`).

## 2026-08-23 — tmux sidebar: cursor stays in the job list; pane match is identity-first

Why: the cursor wandered into the Activity panel (nothing to select there), and selecting a job never swapped the right-hand pane.

**Rule**: the sidebar has exactly one cursor and it lives in the job list. The bottom panel is a view *of* the selection — `Ctrl-d`/`Ctrl-u`/`PgDn`/`PgUp`/wheel scroll it, `Shift-Tab` switches Prompt ⇄ Git, and nothing moves the cursor there (`Focus` enum deleted). `j`/`k` clamp at the ends; `h`/`l`/`Tab` always cycle the filter.

**Rule**: job → pane matching is identity first. `extensions.pid` → `ps -p … -o tty=` → the pane on that tty wins outright (`PaneRank` compares `tty` before `path`/session/window); a scan row that matches nothing is skipped, never fatal. Before: one `?` on a non-matching pane aborted the whole `list-panes -a` scan, so the preview never found anything, and a same-window content pane sharing the project dir outranked the agent's real pane.

**Rule**: preview swaps are coalesced — `sync_preview` runs once per loop tick, not per keypress, and `restore()` is the only thing that clears `showing()` (an unswap mid-`show` used to re-fire a swap every 200ms).

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
- Product handbook is `index/src/docs/content.ts` with SPA routes under `/docs/*`.
- Root / plugin / sources READMEs are short pointers to the site.
- Hook model: **one job per conversation**; subagents only refine main `current`; ignore tool noise when `agent_id` is set (except permission / lifecycle brackets).

## 2026-08-23 — Performance pass + oversized-file split

- **Hub and tmux surface stay Rust-only.** Wiring, the sidebar TUI, and the
  hub daemon have no bash/Python on the hot path. `surfaces/tmux/nerve.tmux`
  is a fail-open trampoline that `exec`s `nerve-tmux-surface install`;
  `nerve.conf` is gone. TPM still needs a `*.tmux` file.
- **Hub runtime** — `#[tokio::main(flavor = "current_thread")]`. A handful of
  loopback connections and a 150 ms pump do not need a worker pool.
- **Hub frame render** — `sse::Frame` borrows the store and serialises a
  `JobsSeq` straight into a sized buffer. It used to collect a `Vec<JobView>`
  (and before that, two `serde_json::Value` trees) just to walk them again; a
  frame is the hub's hottest work (full job set per 150 ms window).
  `jobs_json()` stays for `GET /v1/jobs` and the state tests.
- **tmux sidebar tick** — `refresh_from_hub` re-grouped and re-sorted the whole
  list 5×/s whether or not a frame arrived. It now compares snapshot `Arc`
  identity and rebuilds only on arrival; `now`, pane-follow and git keep their
  own throttles. Ratatui draws on input, a new snapshot, or once a second
  (relative ages) — not five times a second on a quiet pane.
- **tmux subprocess tax** — one `ps -ax` snapshot per 250 ms answers pid→tty,
  tty→pids and ssh destinations (was one spawn per pid / per ssh pane). Git
  panel is one `status --porcelain=v1 -b` (was five git processes). `~/.ssh/config`
  is `OnceLock`. Opening the sidebar no longer runs `sh -lc` (login shell).
- **Status derivation** — `StatusClass::of` no longer lower-cases `reason` /
  `current.type` per job (it is asked once per job for the filter bar, once per
  section and once per row). Vocabulary matching is `eq_ignore_ascii_case`.
  Row text (`activity_text`, `cell_text`, `truncate`) borrows instead of copying.
- **`percent_decode` was wrong, not just slow** — it pushed each *byte* as a
  `char`, so `/Users/me/项目` decoded to mojibake and the Git panel got a path
  that does not exist. Decodes into bytes now, `from_utf8_lossy` at the end.
- **Hooks are host-native, not rust-only.** Official type + official language:
  Claude Code `command` exec form (`node` + `args` → `hooks/nerve.js`);
  Codex `command` (`python3 ${PLUGIN_ROOT}/hooks/nerve.py`, as their docs show);
  Grok `type: "http"` (Grok POSTs the event; hub `/v1/hook` maps it because
  there is no user script). Mapping for Claude/Codex is in the native script
  and POSTs `/v1/snapshot`.
- **macOS store** — `conversationJobs` / `openJobs` are derived once per write
  (`rederive()`), pre-sorted. Eight readers used to filter the dictionary and
  re-sort; a filter keeps order, so every section now inherits the sort.
- **File split** (user rule: 800 lines max) — `StatusPanelView` 1331 → 550,
  `MenuBarRibbonController` 1391 → 640, `SettingsView` 964 → 782, cut on the
  files' own `// MARK:` seams into 9 new files. Types that moved out of the
  file that declared them lost `private`.
- **`scripts/nerve.sh`** — the EXIT traps read locals of the function that
  armed them, so every verify run ended `hub_pid: unbound variable` *after*
  printing ALL OK. Trap state is script-scope now.
- **Site** — deleted 6 modules unreachable from any route (`Sources`, `Signal`,
  `Quiet`, `HomePage`, `usePointer`, `useScrollProgress`) — leftovers of the
  `index-page/` → `index/` move.
  - **Left alone, deliberately:** ~400 lines of `.sources` / `.signal` CSS in
    `global.css` and the `config.ts` data they read. The macOS page groups
    those selectors with live ones (`.product-page .story, .product-page
    .signal, …`), so untangling needs a visual check, and the config data is
    product copy, not dead machinery.

## 2026-08-23 — Site styling unified on Tailwind v4

Tailwind v4 was installed and `@import`ed but did nothing: 26 components carried
**zero** utility classes and 5327 lines of hand-written CSS did all the work,
against a `:root` token set that ran parallel to an unused `@theme`.

- **One token source.** `@theme` in `styles/theme.css` is it — colours, fonts,
  `--container-page`, shadows, easing, and the two breakpoints (`lap` 900px,
  `wide` 960px) that are not on Tailwind's scale. The parallel `:root` block and
  every `var(--ink)`-style alias are gone.
- **Components carry their own layout.** Nav, Footer, LanguageToggle, the four
  hub sections, Stage/Story/Get, all four docs views and the tmux guide are
  utilities now. Shared recipes (`homeLink`, `sectionTitle`, `focus-ring`) live
  in `lib/ui.ts` and one `@utility`.
- **What stays CSS, on purpose:** the two device mockups
  (`styles/mac-preview.css`, `styles/tmux-preview.css`). A laptop lid, a
  drifting wallpaper and pulsing status dots are pseudo-elements and keyframes;
  no utility expresses those. They now own their sizes as variants
  (`--hero` / `--card`) instead of being reached into by parent selectors.
- **Layering matters.** Un-layered CSS beats every Tailwind layer, so the
  remaining rules sit in `@layer components` — otherwise a utility on the
  element loses to a stylesheet that merely loads later.

Net: 5327 → 1356 CSS lines; the built stylesheet 84.7 kB → 65.6 kB
(18.5 → 13.6 kB gzip), total bundle roughly flat.

**How it was kept honest.** A Playwright script shot 12 routes × 4 widths
before and after every step and a Pillow diff compared them; the pass ends at
**0.000% visibly-changed pixels** across all 48. Two things only that harness
caught: a `<p>` added to the hero for a `heroLede` that never existed (dead CSS
with no markup behind it), and `list-disc` on the docs lists, which preflight
had been stripping all along.

Three `App.test.tsx` assertions keyed on class names (`.home-hero-tagline`,
`a.docs-card`, `is-active`); they assert structure and `aria-current` now — the
nav marks its active link for assistive tech either way, which it did not before.

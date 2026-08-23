# CLAUDE.md

<!-- nerve:harness:managed begin -->
<!-- Thin agent router. Public product docs live on the website, not under docs/. -->

## What this repo is

**Nerve** — agent/job status for your machines. Hooks push jobs over loopback HTTP to the **`nerve-hub` daemon** (`127.0.0.1:17890`, state authority); peer **surfaces** render it: the macOS menu-bar app and the tmux plugin. Nerve does **not** run agents.

Stack: `nerve-hub` + tmux helper (Rust, `crates/`), SwiftUI menu-bar app (`Nerve/`), tmux plugin entry (`surfaces/tmux/`), Python marketplace hooks (`plugins/nerve/`), Rsbuild React site + handbook (`index/`).

## Where things live

| Zone | Path |
|------|------|
| State hub daemon | `crates/nerve-hub/` (ingest contract, SSE frames, refcount lifecycle) |
| macOS app (surface) | `Nerve/Nerve/` (App, Models, Store, Services incl. `Services/Hub/`, UI) |
| tmux surface | `surfaces/tmux/` (TPM entry) + `crates/nerve-tmux-surface/` (helper) |
| Marketplace plugin | `plugins/nerve/` (`hooks/nerve_hook.py`, `hooks.json`) |
| Hook tests (stable path) | `sources/agents/tests/` — `nerve_hook.py` → plugin symlink |
| Website + **public docs** | `index/` → routes `/docs/*`; body `index/src/docs/content.ts` |
| Demo / scripts | `fixtures/`, `scripts/` |
| Passive agent notes | `.claude/notes/` |
| Active specs (if any) | `.claude/specs/` |

**There is no `docs/` tree.** Product handbook is the site:

- `/` · `/macos` · `/tmux/zh` · `/tmux/en` — home hub + surfaces
- `/docs` · `/docs/get-started` · `/docs/plugin` · `/docs/machines`
- `/docs/status` · `/docs/ingest` · `/docs/tmux` · `/docs/privacy`

```bash
cd index && npm run dev   # http://localhost:3000/docs
```

## Commands

```bash
./scripts/nerve.sh --help                           # dev launcher (explicit flags only)
./scripts/nerve.sh --run                            # build + open Nerve.app
./scripts/nerve.sh --build --tmux --tmux-reload     # install tmux surface + reload
./scripts/nerve.sh --demo                           # POST demo fixture (hub must be up)
cargo test --workspace                              # hub + tmux-surface tests
./scripts/nerve.sh --verify-loop                    # ingest contract E2E (needs hub)
./scripts/nerve.sh --verify-surface                 # macOS surface regression
./scripts/nerve.sh --verify-tmux                    # tmux surface E2E (isolated tmux)
./scripts/nerve.sh --test-swift                     # Swift value-type unit harness
python3 sources/agents/tests/test_nerve_hook.py     # hook unit tests
cd index && npm test && npm run build               # site tests + static build
```

## Invariants (do not break casually)

1. **One job per conversation** — id `{producer}:{session_id}`. Subagents refine main `current` only; no child session rows. Batch/chain producers may use `role=group|member` with tree panel (display).
2. **Fail-open hooks** — exit 0 always; never block the agent. No `NERVE_*` env; ingest fixed `http://127.0.0.1:17890`, served by `nerve-hub` (the port bind is its single-instance lock). Producers never spawn the hub.
3. **Status from structured fields only** — never free-text message classification (`notification_type`, `background_tasks`, event name).
4. **Memory-only runtime jobs** — jobs/timelines/pending live in `nerve-hub` process RAM; hub exits ~30s after the last surface disconnects (SSE refcount). Settings + managed `~/.ssh/config` only on disk.
5. **Open alias ingest** — any snapshot `alias` shows; Settings Machines are tunnels only (Hosts from local `~/.ssh/config` + known_hosts; managed block is RemoteForward-only; ControlMaster via `ssh -O forward` when master is up). Tunnels target 17890, so remote producers *and* remote surfaces reach the hub for free.
6. **Display only** — Nerve never reverse-controls agents or jobs (no approve/cancel/submit_input). Local actions: **Open/Focus** (location) + Copy; rows leave via SessionEnd / slot supersede / PID reap. Attention means “return to agent UI”, not “type here”.
7. **Surfaces are peers** — macOS app and tmux plugin only consume the hub contract (`GET /v1/jobs`, `GET /v1/stream` full frames with `departed` terminal states); neither owns state, neither knows the other. System notifications fire from the macOS surface only. Hook wire contract is unchanged by all of this.
8. **Public docs** — edit `index/src/docs/content.ts` (and site UI), not a repo `docs/` folder. Keep root/plugin READMEs as short pointers.

## Default workflow

1. Product copy / API handbook → `index/src/docs/content.ts` (+ pages under `src/pages/`)
2. Hook lifecycle → `plugins/nerve/hooks/nerve_hook.py` + `sources/agents/tests/test_nerve_hook.py`
3. State semantics / ingest contract → `crates/nerve-hub/` (golden parity tests guard it)
4. App UI / surface glue → `Nerve/Nerve/`; tmux surface → `surfaces/tmux/` + `crates/nerve-tmux-surface/`
5. Capture decisions → `.claude/notes/notes.md`

<!-- nerve:harness:managed end -->

# CLAUDE.md

<!-- nerve:harness:managed begin -->
<!-- Thin agent router. Public product docs live on the website, not under docs/. -->

## What this repo is

**Nerve** — macOS menu-bar status hub. Agents/builds push jobs over loopback HTTP (`127.0.0.1:17890`); Nerve paints a continuous ribbon. It does **not** run agents.

Stack: SwiftUI menu-bar app (`Nerve/`), Python marketplace hooks (`plugins/nerve/`), Rsbuild React site + handbook (`index-page/`).

## Where things live

| Zone | Path |
|------|------|
| macOS app | `Nerve/Nerve/` (App, Models, Store, Ingest, Services, UI) |
| Marketplace plugin | `plugins/nerve/` (`hooks/nerve_hook.py`, `hooks.json`) |
| Hook tests (stable path) | `sources/agents/tests/` — `nerve_hook.py` → plugin symlink |
| Website + **public docs** | `index-page/` → routes `/docs/*`; body `index-page/src/docs/content.ts` |
| Demo / scripts | `fixtures/`, `scripts/` |
| Passive agent notes | `.claude/notes/` |
| Active specs (if any) | `.claude/specs/` |

**There is no `docs/` tree.** Product handbook is the site:

- `/docs` · `/docs/get-started` · `/docs/plugin` · `/docs/machines`
- `/docs/status` · `/docs/ingest` · `/docs/privacy`

```bash
cd index-page && npm run dev   # http://localhost:3000/docs
```

## Commands

```bash
./scripts/run.sh                                    # build + launch app
./scripts/inject_demo.sh                            # POST demo snapshot
./scripts/verify_loop.sh
python3 sources/agents/tests/test_nerve_hook.py     # hook unit tests
cd index-page && npm test && npm run build          # site tests + static build
```

## Invariants (do not break casually)

1. **One job per conversation** — id `{producer}:{session_id}`. Subagents refine main `current` only; no child session rows. Batch/chain producers may use `role=group|member` with tree panel (display).
2. **Fail-open hooks** — exit 0 always; never block the agent. No `NERVE_*` env; ingest fixed `http://127.0.0.1:17890`.
3. **Status from structured fields only** — never free-text message classification (`notification_type`, `background_tasks`, event name).
4. **Memory-only runtime jobs** — jobs/timelines/pending are process RAM; Settings + managed `~/.ssh/config` only on disk.
5. **Open alias ingest** — any snapshot `alias` shows; Settings Machines are tunnels only (Hosts from local `~/.ssh/config` + known_hosts; managed block is RemoteForward-only; ControlMaster via `ssh -O forward` when master is up).
6. **Display only** — Nerve never reverse-controls agents or jobs (no approve/cancel/submit_input). Local actions: **Open/Focus** (location) + Copy; rows leave via SessionEnd / slot supersede / PID reap. Attention means “return to agent UI”, not “type here”.
7. **Public docs** — edit `index-page/src/docs/content.ts` (and site UI), not a repo `docs/` folder. Keep root/plugin READMEs as short pointers.

## Default workflow

1. Product copy / API handbook → `index-page/src/docs/content.ts` (+ pages under `src/pages/`)
2. Hook lifecycle → `plugins/nerve/hooks/nerve_hook.py` + `sources/agents/tests/test_nerve_hook.py`
3. App UI/store → `Nerve/Nerve/`
4. Capture decisions → `.claude/notes/notes.md`

<!-- nerve:harness:managed end -->

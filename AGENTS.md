# AGENTS.md

Agent entry for Codex / Grok / other harnesses. Same contract as [`CLAUDE.md`](./CLAUDE.md).

## Repo map

- **App:** `Nerve/Nerve/` (Swift, menu bar + ingest)
- **VS Code surface:** `vsc-ext/` (rslib/rspack; `cd vsc-ext && npm test`)
- **Tether surface:** `surfaces/tether/` (`swift test --package-path surfaces/tether`)
- **Plugin:** `plugins/nerve/hooks/` — Claude `nerve.js` (Node exec), Codex `nerve.py` (python3), Grok `grok-post.js` (command POST; Grok `type: http` cannot reach loopback)
- **Hook tests:** `python3 sources/agents/tests/test_nerve_hook.py` · `node --test plugins/nerve/hooks/nerve.test.js`
- **Public docs (website only):** `index/src/docs/content.ts` → `/docs/*`
- **Agent notes:** `.claude/notes/`

No `docs/` directory. Run site docs locally: `cd index && npm run dev`.

## Commands

```bash
./scripts/nerve.sh --help                           # dev launcher (explicit flags only)
./scripts/nerve.sh --run                            # build + open Nerve.app
./scripts/nerve.sh --build --tmux --tmux-reload     # install tmux surface + reload
./scripts/nerve.sh --demo                           # POST demo fixture (hub must be up)
cargo test --workspace                              # hub (incl. hook mapper) + tmux-surface tests
./scripts/nerve.sh --verify-loop                    # ingest contract E2E (needs hub)
./scripts/nerve.sh --verify-surface                 # macOS surface regression
./scripts/nerve.sh --verify-tmux                    # tmux surface E2E (isolated tmux)
./scripts/nerve.sh --verify-vscode                  # VS Code surface unit tests
./scripts/nerve.sh --check-windows                  # compile portable crates for Windows (no linker)
./scripts/nerve.ps1 -Help                           # Windows launcher (install / verify / run)
./scripts/nerve.sh --test-swift                     # Swift value-type unit harness
cd vsc-ext && npm test                              # extension host unit tests
cd index && npm test && npm run build               # site tests + static build
node scripts/capture-vscode-surface.mjs             # capture the VS Code surface screenshot
```

## Hard rules

- One job per conversation; fail-open hooks; fixed loopback ingest; no free-text status inference.
- Prefer editing site docs content over long repo READMEs.

# AGENTS.md

Agent entry for Codex / Grok / other harnesses. Same contract as [`CLAUDE.md`](./CLAUDE.md).

## Repo map

- **App:** `Nerve/Nerve/` (Swift, menu bar + ingest)
- **VS Code surface:** `vsc-ext/` (rslib/rspack; `cd vsc-ext && npm test`)
- **Plugin:** `plugins/nerve/hooks/` — Claude `nerve.js` (Node exec), Codex `nerve.py` (python3), Grok `type: http`
- **Hook tests:** `python3 sources/agents/tests/test_nerve_hook.py` · `node --test plugins/nerve/hooks/nerve.test.js`
- **Public docs (website only):** `index/src/docs/content.ts` → `/docs/*`
- **Agent notes:** `.claude/notes/`

No `docs/` directory. Run site docs locally: `cd index && npm run dev`.

## Hard rules

- One job per conversation; fail-open hooks; fixed loopback ingest; no free-text status inference.
- Prefer editing site docs content over long repo READMEs.

# nerve

Marketplace plugin: push Claude Code / Codex / Grok **session lifecycle** into the Nerve menu-bar hub (`http://127.0.0.1:17890`).

## Docs

Full handbook (install, hook map, noise rules, remotes):

→ **Website** `/docs/plugin` — from repo root:

```bash
cd index && npm run dev
# http://localhost:3000/docs/plugin
```

Body source: [`index/src/docs/content.ts`](../../index/src/docs/content.ts).

## Install

```text
# Claude Code
/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve
```

```bash
# Codex
codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve
```

## Develop

```bash
# from repo root
python3 sources/agents/tests/test_nerve_hook.py
```

- Fail-open (exit `0`); no env vars; one job per conversation.
- Implementation: `hooks/nerve_hook.py` · events: `hooks/hooks.json`.

# Agent sources

| Item | Path |
|------|------|
| Claude native hook | `plugins/nerve/hooks/nerve.js` |
| Codex official hook | `plugins/nerve/hooks/nerve.py` |
| Grok command POST | `plugins/nerve/hooks/grok.json` + `grok-post.js` → `POST /v1/hook` |
| Symlink (tests) | `sources/agents/nerve_hook.py` → Codex mapper |
| Tests | `python3 sources/agents/tests/test_nerve_hook.py` · `node --test plugins/nerve/hooks/nerve.test.js` |
| Docs | website **`/docs/plugin`** |

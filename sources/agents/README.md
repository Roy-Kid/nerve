# Agent sources

Offline tests and the stable import path for the marketplace plugin.

| Item | Path |
|------|------|
| Hook implementation | `plugins/nerve/hooks/nerve_hook.py` |
| Symlink | `sources/agents/nerve_hook.py` → plugin |
| Tests | `sources/agents/tests/test_nerve_hook.py` |
| Docs | website **`/docs/plugin`** (`index-page/src/docs/content.ts`) |

```bash
# from repo root
python3 sources/agents/tests/test_nerve_hook.py
```

Prefer marketplace install over the legacy `codex/hooks.json` template.

# nerve

Marketplace plugin: push Claude Code / Codex / Grok **session lifecycle** into nerve-hub (`http://127.0.0.1:17890`).

Each host uses **its official native hook type and language**:

| Host | Official type | Native script |
|------|---------------|---------------|
| Claude Code | `command` exec form (`node` + `args`) | `hooks/nerve.js` |
| Codex | `command` (`python3 ${PLUGIN_ROOT}/…`) | `hooks/nerve.py` |
| Grok | `command` | `hooks/grok-post.js` POSTs stdin to `/v1/hook`. Grok `type: http` blocks loopback (SSRF). |

Fail-open: never block the agent.

## Docs

→ Website `/docs/plugin` (`index/src/docs/content.ts`).

## Install

```text
# Claude Code
/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve
```

```bash
codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve
```

## Develop

```bash
python3 sources/agents/tests/test_nerve_hook.py
node --test plugins/nerve/hooks/nerve.test.js
cargo test -p nerve-hub hook   # Grok HTTP mapper in the hub
```

# Nerve agent sources

Adapters that push agent lifecycle into Nerve’s local ingest API.

| Harness | Install | Source id |
|---------|---------|-----------|
| **Claude Code** | GitHub marketplace on this repo | `claude-code` |
| **Codex** | Same repo via `codex plugin …` | `codex` |
| **Grok** | Claude-compatible marketplace | `grok` |

Canonical plugin + docs: [`plugins/nerve/`](../../plugins/nerve/).

## Install (GitHub)

Marketplace is the **repo root**. Claude and Codex both consume it.

### Claude Code

```text
/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve
```

### Codex

```bash
codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve
```

Interactive Codex: `/plugins` → **nerve** → install **nerve**. Trust hooks with `/hooks` if prompted.

Local development:

```bash
codex plugin marketplace add /ABS/PATH/TO/nerve
codex plugin add nerve@nerve
```

## Tests

```bash
python3 sources/agents/tests/test_nerve_hook.py
```

`sources/agents/nerve_hook.py` is a **symlink** to `plugins/nerve/hooks/nerve_hook.py` so tests and tools can import a stable path.

## Layout

```
.claude-plugin/marketplace.json   # shared marketplace (name: nerve)
plugins/nerve/                    # installable plugin
sources/agents/
  nerve_hook.py                   # → plugins/nerve/hooks/nerve_hook.py
  tests/test_nerve_hook.py
  codex/hooks.json                # legacy manual ~/.codex/hooks.json template
  README.md
```

Prefer marketplace install over the legacy Codex template.

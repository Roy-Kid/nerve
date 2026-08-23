# Architecture (blueprint)

> Passive map for agents. Public prose lives on the site Signal + `/docs/*`.

## Layers

```
plugins/nerve/hooks/         →  POST /v1/snapshot  →  nerve-hub (loopback :17890)
sources/agents/tests/        →  offline unit tests of the hook
crates/nerve-hub/            →  state authority: ingest + SSE frames + refcount lifecycle
Nerve/Nerve/Services/Hub     →  macOS surface client (spawn, SSE, frame diff)
Nerve/Nerve/Store            →  JobStore (frame-fed read-only cache + ribbon segments)
Nerve/Nerve/UI               →  menu-bar ribbon + status panel
surfaces/tmux/ + crates/nerve-tmux-surface/  →  tmux surface (segment + popup)
index/                  →  marketing + /docs handbook (React SPA)
```

> Full rebuild pending: run `/mol:map` for a fresh blueprint (this block is a minimal truth patch).

## Job model

- Unit of work: **Job** (`kind`: session, build, …) on a machine **alias**.
- **Producer** = who reported (claude-code, codex, grok, demo…), not the machine.
- Display **Status** derived from lifecycle / attention / health / current — single source for ribbon + panel.
- Session close (`lifecycle == ended`) **evicts** immediately (no Success linger).

## Hook → facets (main session only)

See website `/docs/plugin` and `/docs/status`. Implementation: `plugins/nerve/hooks/nerve_hook.py`.

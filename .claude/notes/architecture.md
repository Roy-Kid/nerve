# Architecture (blueprint)

> Passive map for agents. Public prose lives on the site Signal + `/docs/*`.

## Layers

```
plugins/nerve/hooks/     →  POST /v1/snapshot  →  Nerve Ingest (loopback)
sources/agents/tests/    →  offline unit tests of the hook
Nerve/Nerve/Ingest       →  HTTP server :17890
Nerve/Nerve/Store        →  SubjectStore (memory jobs + ribbon segments)
Nerve/Nerve/UI           →  menu-bar ribbon + status panel
index-page/              →  marketing + /docs handbook (React SPA)
```

## Job model

- Unit of work: **Job** (`kind`: session, build, …) on a machine **alias**.
- **Producer** = who reported (claude-code, codex, grok, demo…), not the machine.
- Display **Status** derived from lifecycle / attention / health / current — single source for ribbon + panel.
- Session close (`lifecycle == ended`) **evicts** immediately (no Success linger).

## Hook → facets (main session only)

See website `/docs/plugin` and `/docs/status`. Implementation: `plugins/nerve/hooks/nerve_hook.py`.

# Architecture (blueprint)

> Passive map for agents. Public prose lives on the site Signal + `/docs/*`.

## Layers

```
plugins/nerve/hooks/nerve.js  →  Claude Node exec  →  POST /v1/snapshot
plugins/nerve/hooks/nerve.py  →  Codex python3     →  POST /v1/snapshot
plugins/nerve/hooks/grok.json →  Grok type:http    →  POST /v1/hook
crates/nerve-hub/src/hook/    →  Grok HTTP body → job facets
crates/nerve-hub/            →  state authority: ingest + SSE frames + refcount lifecycle
Nerve/Nerve/Services/Hub     →  macOS surface client (spawn, SSE, frame diff)
Nerve/Nerve/Store            →  JobStore (frame-fed read-only cache + ribbon segments)
Nerve/Nerve/UI               →  menu-bar ribbon + status panel
surfaces/tmux/nerve.tmux + crates/nerve-tmux-surface/  →  tmux surface (trampoline → rust install + sidebar)
index/                  →  marketing + /docs handbook (React SPA)
```

> Full rebuild pending: run `/mol:map` for a fresh blueprint (this block is a minimal truth patch).

## Job model

- Unit of work: **Job** (`kind`: session, build, …) on a machine **alias**.
- **Producer** = who reported (claude-code, codex, grok, demo…), not the machine.
- Display **Status** derived from lifecycle / attention / health / current — single source for ribbon + panel. Six painted hues: rainbow red / orange / blue / violet / green (problem, attention, running, monitor, success) plus gray idle. Waiting shares attention. Background shell/subagent is Running; monitor-only is Monitor.
- Session close (`lifecycle == ended`) **evicts** immediately (no Success linger).

## Hook → facets (main session only)

See website `/docs/plugin` and `/docs/status`. Implementation: `crates/nerve-hub/src/hook/` (`POST /v1/hook`).

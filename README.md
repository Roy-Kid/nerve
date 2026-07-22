<p align="center">
  <img src="assets/logo-512.png" alt="Nerve" width="160" />
</p>

# Nerve for macOS

Lightweight **menu-bar** status hub for agents, builds, tests, and long jobs. Nerve does **not** run them — it aggregates status they push over local HTTP into one continuous ribbon.

## Documentation (website)

Product docs are **not** in a `docs/` folder. They live on the site handbook:

| Topic | Local path |
|-------|------------|
| Docs hub | http://localhost:3000/docs |
| Get started | …/docs/get-started |
| Agent plugins | …/docs/plugin |
| Machines & remotes | …/docs/machines |
| Status & lifecycle | …/docs/status |
| Ingest API | …/docs/ingest |
| Privacy | …/docs/privacy |

```bash
cd index-page && npm install && npm run dev
```

Source of truth for handbook copy: [`index-page/src/docs/content.ts`](./index-page/src/docs/content.ts).

Agent-facing layout: [`CLAUDE.md`](./CLAUDE.md) · [`AGENTS.md`](./AGENTS.md).

## Quick commands

```bash
./scripts/run.sh                                 # build + open Nerve.app
./scripts/inject_demo.sh                         # sample jobs
python3 sources/agents/tests/test_nerve_hook.py  # hook tests
cd index-page && npm test && npm run build       # site
```

## Layout

```
CLAUDE.md / AGENTS.md   Agent harness (router)
.claude/notes/          Passive agent notes
plugins/nerve/          Marketplace hooks → :17890
sources/agents/         Hook tests (symlink to plugin)
Nerve/                  macOS menu-bar app
index-page/             Marketing site + /docs SPA
fixtures/ · scripts/ · assets/
```

## License

See repository license (if present). Private use / distribution as you prefer until a license file is added.

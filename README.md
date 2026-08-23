<p align="center">
  <img src="assets/logo-512.png" alt="Nerve" width="160" />
</p>

# Nerve

**An open nerve for everything your machines run.**

Every agent, build, and long job reports through one open protocol into a single strip of color in your menu bar or tmux, and every line of it is open source.

- **Open protocol** — one `POST http://127.0.0.1:17890/v1/snapshot` is the entire integration contract, documented and versioned.
- **Open surfaces** — the macOS menu bar and the tmux sidebar are plain clients of the same open stream, so nothing stops you writing a third.
- **Open by proof** — runtime state lives only in memory on loopback, and the MIT-licensed source that proves it is public.

## Documentation (website)

Product docs are **not** in a `docs/` folder. They live on the site handbook:

| Topic | Local path |
|-------|------------|
| Home hub | http://localhost:3000/ |
| macOS ribbon | …/macos |
| tmux sidebar (中文) | …/tmux/zh |
| tmux sidebar (EN) | …/tmux/en |
| Docs hub | …/docs |

```bash
cd index && npm install && npm run dev
```

Source of truth for handbook copy: [`index/src/docs/content.ts`](./index/src/docs/content.ts).

Agent-facing layout: [`CLAUDE.md`](./CLAUDE.md) · [`AGENTS.md`](./AGENTS.md).

## Quick commands

```bash
./scripts/nerve.sh --help                        # dev launcher (explicit flags)
./scripts/nerve.sh --run                         # build + open Nerve.app
./scripts/nerve.sh --demo                        # sample jobs (hub must be up)
python3 sources/agents/tests/test_nerve_hook.py  # hook tests
cd index && npm test && npm run build            # site
```

## Layout

```
CLAUDE.md / AGENTS.md   Agent harness (router)
.claude/notes/          Passive agent notes
plugins/nerve/          Marketplace hooks → :17890
sources/agents/         Hook tests (symlink to plugin)
Nerve/                  macOS menu-bar app (surface)
crates/                 Rust: nerve-hub daemon + nerve-tmux-surface helper
surfaces/tmux/          tmux plugin surface (TPM entry)
index/                  Marketing site + /docs SPA
fixtures/ · scripts/ · assets/
```

## License

[MIT](./LICENSE) — use it, fork it, ship your own surface against the protocol.

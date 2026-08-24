# Nerve for VS Code

A peer surface of the macOS menu-bar app and the tmux sidebar. It does not
run agents and does not own state. It holds one `GET /v1/stream?surface=vscode`
against `nerve-hub` on `127.0.0.1:17890` and paints jobs in the status bar
and the Activity Bar.

Docs: the site handbook `/docs/vscode` (`index/src/docs/content.ts`).
This file is a pointer, not the handbook.

## Develop

```bash
cd vsc-ext
npm install
npm test
npm run watch
```

Then Run and Debug → **Run Nerve Extension** (F5), or:

```bash
./scripts/nerve.sh --vscode
```

## Invariants

Display only: Focus and Copy. No approve / cancel / submit. System
notifications stay on the macOS surface. The hub port is not configurable.

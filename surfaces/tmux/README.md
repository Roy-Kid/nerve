# nerve — tmux surface

A tmux status-line segment and a read-only popup, fed by the same `nerve-hub`
the menu-bar app reads (`http://127.0.0.1:17890`). The two surfaces are peers:
neither needs the other, and this one runs fine on a headless Linux box.

## Docs

Full handbook (install, options, popup, refcount, remotes):

→ **Website** `/docs/tmux` — from repo root:

```bash
cd index-page && npm run dev
# http://localhost:3000/docs/tmux
```

Body source: [`index-page/src/docs/content.ts`](../../index-page/src/docs/content.ts).

## Install

```bash
cargo install --path crates/nerve-tmux-surface
```

```bash
# ~/.tmux.conf — from a checkout
run-shell ~/src/nerve/surfaces/tmux/nerve.tmux

# ~/.tmux.conf — with TPM handling the clone and updates
set -g @plugin 'Roy-Kid/nerve'
run-shell ~/.tmux/plugins/nerve/surfaces/tmux/nerve.tmux
```

TPM auto-sources only the `*.tmux` files at a plugin repo's root; Nerve is a
monorepo, so `@plugin` clones and updates while `run-shell` points at the entry
point. Sourcing twice is a no-op.

## Options

| Option | Default | What it sets |
|--------|---------|--------------|
| `@nerve_status_format` | counts + colours | Segment template (`{running}`, `{attention}`, `{problem}`, `{waiting}`, `{success}`, `{inactive}`, `{total}`) |
| `@nerve_status_offline` | `nerve: offline` | Shown while no hub answers |
| `@nerve_popup_key` | `N` | `prefix` + this key opens the popup |

## Verify

```bash
bash scripts/verify_tmux_surface.sh   # isolated tmux server; never touches yours
```

Display only — the popup has no approve / cancel / submit, and this surface
posts no system notifications (those belong to the macOS app).

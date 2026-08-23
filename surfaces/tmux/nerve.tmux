#!/usr/bin/env bash
# TPM entry point for the Nerve tmux surface.
#
# Four things, in order: find the helper, make status-right able to show it,
# bind the popup key, start the helper. Then get out of the way.
#
# Always fail-open (exit 0) — the same rule plugins/nerve/hooks/run.sh follows.
# A surface is an instrument, and an instrument that breaks your tmux is worse
# than no instrument. Every step below is allowed to fail on its own.
#
# What this script deliberately does NOT do:
#   * check whether a helper is already running — the helper claims
#     @nerve_surface_pid itself (crates/nerve-tmux-surface/src/instance.rs), so
#     a second one stands down without ever opening a stream. Racing it here
#     would be a second, worse answer to the same question.
#   * read @nerve_status_format or @nerve_status_offline — `run` reads both out
#     of tmux at startup. Passing them would fork the defaults.
#   * notify. Notifications are the macOS surface's job; attention shows up here
#     as segment colour and nothing else.
set -u

# Keep a usable PATH even when tmux was started from a minimal environment.
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# The binary that does all of the work.
HELPER_NAME="nerve-tmux-surface"

# Shown when there is no helper to show anything else.
SETUP_HINT="nerve: setup"

# Default popup key, overridable with @nerve_popup_key.
DEFAULT_POPUP_KEY="N"

# What status-right must contain for the segment to appear. tmux expands a user
# option's value when it interpolates it, which is also why the helper escapes
# `#` in job text before writing it (src/summary.rs).
STATUS_FORMAT='#{@nerve_status}'

# Nothing here is meaningful without tmux to talk to.
command -v tmux >/dev/null 2>&1 || exit 0

# ---------------------------------------------------------------------------
# 1. Locate the helper.
#
# The repo build first so a checkout runs what it just compiled, then the two
# Homebrew prefixes, then a cargo install, then whatever the shell would find.
# This mirrors HubLocator's order for nerve-hub (src/locate.rs) — one habit,
# two binaries.
HELPER=""
for candidate in \
  "${CURRENT_DIR}/../../target/release/${HELPER_NAME}" \
  "/opt/homebrew/bin/${HELPER_NAME}" \
  "/usr/local/bin/${HELPER_NAME}" \
  "${HOME:-}/.cargo/bin/${HELPER_NAME}"
do
  if [[ -x "${candidate}" ]]; then
    HELPER="${candidate}"
    break
  fi
done

if [[ -z "${HELPER}" ]]; then
  HELPER="$(command -v "${HELPER_NAME}" 2>/dev/null || true)"
fi

if [[ -z "${HELPER}" ]]; then
  # Say so in the status line rather than silently doing nothing: a segment that
  # never appears reads exactly like a broken install.
  # `cargo install --path crates/nerve-tmux-surface` is the fix.
  tmux set -g @nerve_status "${SETUP_HINT}" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Put the segment in status-right, once.
#
# Appending to whatever is there keeps the user's own status line: this plugin
# adds a segment, it does not own the line. Re-sourcing must therefore be a
# no-op, or a config reload would stack copies of the segment.
STATUS_RIGHT="$(tmux show-options -gqv status-right 2>/dev/null || true)"
case "${STATUS_RIGHT}" in
  *"${STATUS_FORMAT}"*)
    : # already wired
    ;;
  *)
    tmux set -g status-right "${STATUS_RIGHT}${STATUS_RIGHT:+ }${STATUS_FORMAT}" 2>/dev/null || true
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Bind the popup.
#
# `-E` closes the popup when the command exits, and the command is one-shot
# stdout, so the window is read-only by construction: there is no prompt to type
# into and no action to invoke (CLAUDE.md invariant 6). `popup` talks to the hub
# directly and touches no tmux, so this key works even where `run` could not.
POPUP_KEY="$(tmux show-options -gqv @nerve_popup_key 2>/dev/null || true)"
POPUP_KEY="${POPUP_KEY:-${DEFAULT_POPUP_KEY}}"

# Quoted because display-popup hands the string to a shell and the helper's path
# is discovered, not fixed.
tmux bind-key "${POPUP_KEY}" display-popup -E "'${HELPER}' popup" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Start the helper.
#
# Detached and silent: it outlives this script, and its stdout would land in
# whatever pane sourced the config. It attaches to the hub — starting one if
# needed — and holds a single stream open for as long as it lives. That open
# stream is this surface's presence in the hub's refcount, which is why there is
# no daemon, no unit file and nothing on disk to clean up.
nohup "${HELPER}" run >/dev/null 2>&1 </dev/null &
disown 2>/dev/null || true

exit 0

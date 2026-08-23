#!/usr/bin/env bash
# Nerve tmux sidebar — entry point (aligned with tmux-agent-sidebar).
#
# Finds the helper, sources nerve.conf, exits 0 always.
set -u

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HELPER_NAME="nerve-tmux-surface"

command -v tmux >/dev/null 2>&1 || exit 0

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
  exit 0
fi

tmux set -g @nerve_sidebar_bin "${HELPER}" 2>/dev/null || true
tmux source-file "${CURRENT_DIR}/nerve.conf" 2>/dev/null || true

exit 0

#!/bin/sh
# TPM / run-shell trampoline. All wiring lives in `nerve-tmux-surface install`.
# Fail-open: missing helper or a refused exec still exits 0.
set -u

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

CURRENT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
HELPER_NAME="nerve-tmux-surface"

for candidate in \
  "${CURRENT_DIR}/../../target/release/${HELPER_NAME}" \
  "/opt/homebrew/bin/${HELPER_NAME}" \
  "/usr/local/bin/${HELPER_NAME}" \
  "${HOME:-}/.cargo/bin/${HELPER_NAME}"
do
  if [ -x "${candidate}" ]; then
    exec "${candidate}" install
  fi
done

HELPER="$(command -v "${HELPER_NAME}" 2>/dev/null || true)"
if [ -n "${HELPER}" ]; then
  exec "${HELPER}" install
fi

exit 0

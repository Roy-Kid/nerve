#!/usr/bin/env bash
# Resolve plugin root robustly, then run nerve_hook.py.
# Hosts expand ${CLAUDE_PLUGIN_ROOT} in hooks.json before invoking this script;
# we still re-resolve so a broken expansion / alternate host still works.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

for v in CLAUDE_PLUGIN_ROOT PLUGIN_ROOT GROK_PLUGIN_ROOT; do
  # bash indirect expansion
  eval "val=\${$v:-}"
  if [[ -n "${val}" && -d "${val}" ]]; then
    ROOT="${val}"
    break
  fi
done

HOOK="${ROOT}/hooks/nerve_hook.py"
if [[ ! -f "${HOOK}" ]]; then
  # Last resort: next to this script
  HOOK="${HERE}/nerve_hook.py"
fi

if [[ ! -f "${HOOK}" ]]; then
  # Fail open for observability hooks — never block the agent.
  echo "[nerve] hook script not found under ${ROOT}" >&2
  exit 0
fi

exec python3 "${HOOK}"

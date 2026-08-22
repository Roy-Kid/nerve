#!/usr/bin/env bash
# Resolve plugin root robustly, then run nerve_hook.py.
# Hosts may set CLAUDE_PLUGIN_ROOT (Claude), PLUGIN_ROOT (Codex), and/or
# GROK_PLUGIN_ROOT. Prefer env when present; otherwise resolve from this script.
# Always fail-open (exit 0) — observability must never block the agent.
set -u

# Keep a usable PATH even when the host sandbox is minimal (missing dirname/python3).
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

_src="${BASH_SOURCE[0]:-$0}"
# Prefer %/ strip over dirname so a stripped PATH still works.
case "${_src}" in
  /*) _here="${_src%/*}" ;;
  */*) _here="$(pwd)/${_src%/*}" ;;
  *) _here="$(pwd)" ;;
esac
HERE="${_here}"
ROOT="${HERE}/.."

for v in CLAUDE_PLUGIN_ROOT PLUGIN_ROOT GROK_PLUGIN_ROOT; do
  eval "val=\${$v:-}"
  if [[ -n "${val}" && -d "${val}" ]]; then
    ROOT="${val}"
    break
  fi
done

# Normalize ROOT when we derived it as HERE/..
if [[ -d "${ROOT}" ]]; then
  ROOT="$(cd "${ROOT}" 2>/dev/null && pwd || echo "${ROOT}")"
fi

HOOK="${ROOT}/hooks/nerve_hook.py"
if [[ ! -f "${HOOK}" ]]; then
  HOOK="${HERE}/nerve_hook.py"
fi

if [[ ! -f "${HOOK}" ]]; then
  echo "[nerve] hook script not found under ${ROOT}" >&2
  exit 0
fi

PY=""
for c in python3 /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if command -v "${c}" >/dev/null 2>&1 || [[ -x "${c}" ]]; then
    PY="${c}"
    break
  fi
done

if [[ -z "${PY}" ]]; then
  echo "[nerve] python3 not found; skipping ingest" >&2
  exit 0
fi

exec "${PY}" "${HOOK}"

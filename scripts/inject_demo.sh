#!/usr/bin/env bash
set -euo pipefail
PORT="${NERVE_PORT:-17890}"
BASE="http://127.0.0.1:${PORT}"

echo "Health:"
curl -sS "$BASE/v1/health"
echo

echo "Loading built-in demo jobs..."
curl -sS -X POST "$BASE/v1/demo"
echo

echo "Jobs:"
curl -sS "$BASE/v1/jobs" | python3 -m json.tool | head -80

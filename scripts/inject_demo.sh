#!/usr/bin/env bash
set -euo pipefail
PORT="${NERVE_PORT:-17890}"
BASE="http://127.0.0.1:${PORT}"
FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/demo_snapshot.json"

echo "Health:"
curl -sS "$BASE/v1/health"
echo

echo "Posting $FIXTURE ..."
curl -sS -X POST "$BASE/v1/snapshot" \
  -H 'Content-Type: application/json' \
  --data @"$FIXTURE"
echo

echo "Jobs:"
curl -sS "$BASE/v1/jobs" | python3 -m json.tool | head -80

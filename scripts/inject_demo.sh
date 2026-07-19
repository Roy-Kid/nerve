#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${NERVE_PORT:-17890}"
BASE="http://127.0.0.1:${PORT}"

echo "Health:"
curl -sS "$BASE/v1/health"
echo

echo "Loading fixture snapshot..."
curl -sS -X POST "$BASE/v1/snapshot" \
  -H 'Content-Type: application/json' \
  --data-binary @"$ROOT/fixtures/demo_snapshot.json"
echo

echo "Subjects:"
curl -sS "$BASE/v1/subjects" | python3 -m json.tool | head -80

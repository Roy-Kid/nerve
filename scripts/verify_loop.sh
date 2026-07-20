#!/usr/bin/env bash
# Automated checks for the closed loop (non-visual).
set -euo pipefail
PORT="${NERVE_PORT:-17890}"
BASE="http://127.0.0.1:${PORT}"

# Discover local alias from hostname (same rule as LocalMachine / hook).
ALIAS=$(python3 - <<'PY'
import socket
h = socket.gethostname() or "local"
print((h.split(".")[0] or h).strip() or "local")
PY
)

echo "== health =="
curl -sf "$BASE/v1/health" | grep -q '"ok":true'

echo "== clear =="
curl -sf -X POST "$BASE/v1/clear" >/dev/null

echo "== inject multi-state jobs =="
curl -sf -X POST "$BASE/v1/snapshot" -H 'Content-Type: application/json' -d "{
  \"alias\": \"$ALIAS\",
  \"machineKind\": \"darwin\",
  \"jobs\": [
    {\"id\":\"a1\",\"kind\":\"session\",\"name\":\"A1\",\"alias\":\"$ALIAS\",\"lifecycle\":\"active\",\"attention\":{\"level\":\"none\"},\"health\":\"ok\",\"progress\":{\"kind\":\"none\"},\"producer\":{\"id\":\"t\"},\"capabilities\":[],\"actions\":[],\"createdAt\":\"2026-07-19T00:00:00Z\",\"updatedAt\":\"2026-07-19T00:00:00Z\",\"version\":1,\"extensions\":{\"x\":1}},
    {\"id\":\"a2\",\"kind\":\"custom.foo\",\"name\":\"A2\",\"alias\":\"$ALIAS\",\"lifecycle\":\"active\",\"attention\":{\"level\":\"required\",\"reason\":\"approval\"},\"health\":\"ok\",\"progress\":{\"kind\":\"none\"},\"producer\":{\"id\":\"t\"},\"capabilities\":[],\"actions\":[],\"createdAt\":\"2026-07-19T00:00:00Z\",\"updatedAt\":\"2026-07-19T00:00:00Z\",\"version\":1,\"extensions\":{}},
    {\"id\":\"a3\",\"kind\":\"build\",\"name\":\"A3\",\"alias\":\"$ALIAS\",\"lifecycle\":\"active\",\"attention\":{\"level\":\"none\"},\"health\":\"unresponsive\",\"progress\":{\"kind\":\"none\"},\"producer\":{\"id\":\"t\"},\"capabilities\":[],\"actions\":[],\"createdAt\":\"2026-07-19T00:00:00Z\",\"updatedAt\":\"2026-07-19T00:00:00Z\",\"version\":1,\"extensions\":{}},
    {\"id\":\"a4\",\"kind\":\"test\",\"name\":\"A4\",\"alias\":\"$ALIAS\",\"lifecycle\":\"active\",\"attention\":{\"level\":\"none\"},\"health\":\"ok\",\"progress\":{\"kind\":\"none\"},\"producer\":{\"id\":\"t\"},\"capabilities\":[],\"actions\":[],\"createdAt\":\"2026-07-19T00:00:00Z\",\"updatedAt\":\"2026-07-19T00:00:00Z\",\"version\":1,\"extensions\":{}},
    {\"id\":\"a5\",\"kind\":\"workflow\",\"name\":\"A5\",\"alias\":\"$ALIAS\",\"lifecycle\":\"ended\",\"outcome\":\"failure\",\"attention\":{\"level\":\"informational\"},\"health\":\"ok\",\"progress\":{\"kind\":\"none\"},\"producer\":{\"id\":\"t\"},\"capabilities\":[],\"actions\":[],\"createdAt\":\"2026-07-19T00:00:00Z\",\"endedAt\":\"2026-07-19T00:01:00Z\",\"updatedAt\":\"2026-07-19T00:01:00Z\",\"version\":1,\"extensions\":{}}
  ]
}" | grep -q '"applied":5'

echo "== event patch =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d "{
  \"alias\": \"$ALIAS\",
  \"events\":[{\"id\":\"ev1\",\"jobId\":\"a1\",\"kind\":\"attention.changed\",\"timestamp\":\"2026-07-19T00:02:00Z\",\"producerId\":\"t\",\"version\":2,\"attention\":{\"level\":\"urgent\",\"reason\":\"input\",\"title\":\"Need input\"}}]
}" | grep -q '"applied":1'

echo "== idempotent event =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d "{
  \"alias\": \"$ALIAS\",
  \"events\":[{\"id\":\"ev1\",\"jobId\":\"a1\",\"kind\":\"attention.changed\",\"timestamp\":\"2026-07-19T00:02:00Z\",\"producerId\":\"t\",\"version\":2,\"attention\":{\"level\":\"urgent\",\"reason\":\"input\",\"title\":\"Need input\"}}]
}" | grep -q '"applied":0'

echo "== stale version ignored =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d "{
  \"alias\": \"$ALIAS\",
  \"events\":[{\"id\":\"ev2\",\"jobId\":\"a1\",\"kind\":\"attention.changed\",\"timestamp\":\"2026-07-19T00:02:00Z\",\"producerId\":\"t\",\"version\":1,\"attention\":{\"level\":\"none\"}}]
}" | grep -q '"applied":0'

COUNT=$(curl -sf "$BASE/v1/jobs" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
test "$COUNT" = "5"

python3 - <<PY
import json, os, urllib.request
port = os.environ.get("NERVE_PORT", "17890")
data = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/jobs"))
by_id = {s["id"]: s for s in data}
assert by_id["a1"]["attention"]["level"] == "urgent"
assert by_id["a2"]["kind"] == "custom.foo"
assert by_id["a1"]["alias"]
active = [s for s in data if s["lifecycle"] != "ended"]
assert len(active) == 4
print("active", len(active), "OK model checks")
PY

curl -sf "$BASE/v1/actions/pending?producerId=t" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list); print('pending_ok', len(d))"

code=$(curl -s -o /tmp/nerve_action_result.json -w "%{http_code}" -X POST "$BASE/v1/actions/result?producerId=missing" \
  -H 'Content-Type: application/json' -d '{"id":"nope","state":"succeeded","message":"x"}')
test "$code" = "404"

echo "== unknown alias rejected =="
code=$(curl -s -o /tmp/nerve_unknown_alias.json -w "%{http_code}" -X POST "$BASE/v1/snapshot" \
  -H 'Content-Type: application/json' -d '{"alias":"__not_configured__","jobs":[]}')
test "$code" = "403" -o "$code" = "400"

echo "ALL OK"

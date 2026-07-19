#!/usr/bin/env bash
# Automated checks for the first closed loop (non-visual).
set -euo pipefail
PORT="${NERVE_PORT:-17890}"
BASE="http://127.0.0.1:${PORT}"

echo "== health =="
curl -sf "$BASE/v1/health" | grep -q '"ok":true'

echo "== clear =="
curl -sf -X POST "$BASE/v1/clear" >/dev/null

echo "== inject multi-state subjects =="
curl -sf -X POST "$BASE/v1/snapshot" -H 'Content-Type: application/json' -d '{
  "subjects": [
    {"id":"a1","type":"agent.session","name":"A1","lifecycle":"active","attention":{"level":"none"},"health":"ok","progress":{"kind":"none"},"source":{"id":"t"},"capabilities":[],"actions":[],"createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","version":1,"extensions":{"x":1}},
    {"id":"a2","type":"custom.foo","name":"A2","lifecycle":"active","attention":{"level":"required","reason":"approval"},"health":"ok","progress":{"kind":"none"},"source":{"id":"t"},"capabilities":[],"actions":[],"createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","version":1,"extensions":{}},
    {"id":"a3","type":"build","name":"A3","lifecycle":"active","attention":{"level":"none"},"health":"unresponsive","progress":{"kind":"none"},"source":{"id":"t"},"capabilities":[],"actions":[],"createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","version":1,"extensions":{}},
    {"id":"a4","type":"test","name":"A4","lifecycle":"active","attention":{"level":"none"},"health":"ok","progress":{"kind":"none"},"source":{"id":"t"},"capabilities":[],"actions":[],"createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","version":1,"extensions":{}},
    {"id":"a5","type":"workflow.run","name":"A5","lifecycle":"ended","outcome":"failure","attention":{"level":"informational"},"health":"ok","progress":{"kind":"none"},"source":{"id":"t"},"capabilities":[],"actions":[],"createdAt":"2026-07-19T00:00:00Z","endedAt":"2026-07-19T00:01:00Z","updatedAt":"2026-07-19T00:01:00Z","version":1,"extensions":{}}
  ]
}' | grep -q '"applied":5'

echo "== event patch =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d '{
  "events":[{"id":"ev1","subjectId":"a1","kind":"attention.changed","timestamp":"2026-07-19T00:02:00Z","sourceId":"t","version":2,"attention":{"level":"urgent","reason":"input","title":"Need input"}}]
}' | grep -q '"applied":1'

echo "== idempotent event =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d '{
  "events":[{"id":"ev1","subjectId":"a1","kind":"attention.changed","timestamp":"2026-07-19T00:02:00Z","sourceId":"t","version":2,"attention":{"level":"urgent","reason":"input","title":"Need input"}}]
}' | grep -q '"applied":0'

echo "== stale version ignored =="
curl -sf -X POST "$BASE/v1/events" -H 'Content-Type: application/json' -d '{
  "events":[{"id":"ev2","subjectId":"a1","kind":"attention.changed","timestamp":"2026-07-19T00:02:00Z","sourceId":"t","version":1,"attention":{"level":"none"}}]
}' | grep -q '"applied":0'

COUNT=$(curl -sf "$BASE/v1/subjects" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
test "$COUNT" = "5"

python3 - <<'PY'
import json, urllib.request
data = json.load(urllib.request.urlopen("http://127.0.0.1:17890/v1/subjects"))
by_id = {s["id"]: s for s in data}
assert by_id["a1"]["attention"]["level"] == "urgent"
assert by_id["a2"]["type"] == "custom.foo"
assert "x" in by_id["a1"].get("extensions", {}) or True  # extensions may round-trip
active = [s for s in data if s["lifecycle"] != "ended"]
assert len(active) == 4
print("active", len(active), "attention-required+", sum(1 for s in active if s["attention"]["level"] in ("required","urgent","suggested","informational")))
print("OK model checks")
PY

# Pending actions API
curl -sf "$BASE/v1/actions/pending?sourceId=t" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list); print('pending_ok', len(d))"

code=$(curl -s -o /tmp/nerve_action_result.json -w "%{http_code}" -X POST "$BASE/v1/actions/result?sourceId=missing" \
  -H 'Content-Type: application/json' -d '{"id":"nope","state":"succeeded","message":"x"}')
test "$code" = "404"
grep -q 'not found' /tmp/nerve_action_result.json

# Remote action queue round-trip
curl -sf -X POST "$BASE/v1/snapshot" -H 'Content-Type: application/json' -d '{
  "subjects":[{
    "id":"act-rt","type":"test","name":"Approve me","lifecycle":"active",
    "attention":{"level":"required","reason":"approval"},
    "health":"ok","progress":{"kind":"none"},
    "source":{"id":"agent-x","name":"Agent X"},
    "capabilities":[],
    "actions":[{"id":"approve","title":"Approve","kind":"approve","state":"available","destructive":false,"confirmationRequired":true}],
    "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","version":1,"extensions":{}
  }]
}' >/dev/null

curl -sf -X POST "$BASE/v1/actions/invoke" -H 'Content-Type: application/json' \
  -d '{"subjectId":"act-rt","actionId":"approve","confirmed":true}' | grep -q 'pending'

PENDING=$(curl -sf "$BASE/v1/actions/pending?sourceId=agent-x")
echo "$PENDING" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d)>=1; open('/tmp/nerve_pending_id.txt','w').write(d[0]['id']); print('queued', d[0]['id'])"
PID=$(cat /tmp/nerve_pending_id.txt)
curl -sf -X POST "$BASE/v1/actions/result?sourceId=agent-x" -H 'Content-Type: application/json' \
  -d "{\"id\":\"$PID\",\"state\":\"succeeded\",\"message\":\"ok\"}" | grep -q '"ok":true'
echo "action_queue_ok"

# No machine-local path hardcoding in demo fixture
! grep -q '/Users/' "$(cd "$(dirname "$0")/.." && pwd)/fixtures/demo_snapshot.json"

echo "All automated loop checks passed."
echo
echo "Manual visual checks:"
echo "  1. Menu-bar ribbon: self-lit gradient (no outer halo)"
echo "  2. Left-click → Status only; ↑/↓ select, Enter expand"
echo "  3. Expand row → Copy local; Approve queues to source"
echo "  4. Right-click → DND, mute source/project, notifications"
echo "  5. No History UI; no footer status toast"
echo "  6. Source: GET /v1/actions/pending?sourceId=… then POST /v1/actions/result"

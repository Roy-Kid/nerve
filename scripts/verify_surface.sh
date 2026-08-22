#!/usr/bin/env bash
#
# Automated checks for the macOS *surface* cutover (non-visual).
#
# verify_loop.sh proves the ingest contract. This script proves the surface
# side of it: the app ships a hub it can spawn, that hub round-trips a real
# fixture, and the retired ingest-port knob left nothing behind in the Swift
# sources. Everything a human still has to look at is listed in the manual
# matrix at the bottom of this file.
#
# Usage: bash scripts/verify_surface.sh
# Exit:  0 all green, 1 an assertion failed.
#
# This script never launches the GUI and never touches ~/.ssh/config.
#
# It DOES clear hub state before posting the fixture (same as verify_loop.sh),
# so do not run it against a hub whose jobs you care about.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/Nerve/build/Build/Products/Debug/Nerve.app"
HUB="$APP/Contents/MacOS/nerve-hub"
FIXTURE="$ROOT/fixtures/demo_snapshot.json"
BASE="http://127.0.0.1:17890"

# Long enough that the checks below cannot race the no-subscriber countdown:
# this script is an ingest client, never an SSE surface, so from the hub's point
# of view nobody is watching the whole time. We kill our own hub on exit.
GRACE_SECS=120

HUB_PID=""
HUB_LOG=""

cleanup() {
  if [[ -n "$HUB_PID" ]]; then
    echo "== stopping hub we started (pid $HUB_PID) =="
    kill "$HUB_PID" 2>/dev/null || true
    wait "$HUB_PID" 2>/dev/null || true
  fi
  [[ -n "$HUB_LOG" ]] && rm -f "$HUB_LOG"
  return 0
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
echo "== bundled hub =="
# The app spawns the hub from its own bundle (HubProcessManager looks in
# Contents/MacOS first), so a bundle without one is a broken surface.
[[ -d "$APP" ]] || fail "no app bundle at $APP — run ./scripts/run.sh first"
[[ -f "$HUB" ]] || fail "no nerve-hub in $APP/Contents/MacOS — run ./scripts/run.sh (it builds and embeds it)"
[[ -x "$HUB" ]] || fail "$HUB is not executable"
# Existence is not runnability: prove it actually executes on this arch.
"$HUB" --help >/dev/null 2>&1 || fail "$HUB did not run (wrong architecture, or unsigned after embedding?)"
echo "ok: $HUB"

# ---------------------------------------------------------------------------
echo "== hub reachable on :17890 =="
if curl -sf "$BASE/v1/health" >/dev/null 2>&1; then
  echo "ok: reusing the hub already holding the port"
else
  HUB_LOG="$(mktemp "${TMPDIR:-/tmp}/nerve-verify-surface.XXXXXX")"
  "$HUB" serve --grace-secs "$GRACE_SECS" >"$HUB_LOG" 2>&1 &
  HUB_PID=$!

  ready=""
  for _ in $(seq 1 100); do
    if curl -sf "$BASE/v1/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    kill -0 "$HUB_PID" 2>/dev/null || break
    sleep 0.1
  done
  if [[ -z "$ready" ]]; then
    echo "--- hub log ---" >&2
    cat "$HUB_LOG" >&2 || true
    fail "bundled hub never answered /v1/health"
  fi
  echo "ok: started bundled hub (pid $HUB_PID)"
fi

curl -sf "$BASE/v1/health" | grep -q '"ok":true' || fail "/v1/health did not report ok"

# ---------------------------------------------------------------------------
echo "== fixture round trip =="
curl -sf -X POST "$BASE/v1/clear" >/dev/null || fail "POST /v1/clear failed"

curl -sf -X POST "$BASE/v1/snapshot" \
  -H 'Content-Type: application/json' \
  --data @"$FIXTURE" | grep -q '"applied":2' || fail "POST /v1/snapshot did not apply the fixture's 2 jobs"

python3 - <<'PY' || exit 1
import json, sys, urllib.request

jobs = json.load(urllib.request.urlopen("http://127.0.0.1:17890/v1/jobs"))
if len(jobs) != 2:
    print(f"FAIL: GET /v1/jobs returned {len(jobs)} job(s), expected 2", file=sys.stderr)
    sys.exit(1)

ids = sorted(j["id"] for j in jobs)
if ids != ["demo-agent-1", "demo-build-1"]:
    print(f"FAIL: GET /v1/jobs returned unexpected ids {ids}", file=sys.stderr)
    sys.exit(1)

print("ok: GET /v1/jobs ->", len(jobs), "jobs", ids)
PY

# ---------------------------------------------------------------------------
echo "== no stray ingest-port knob =="
# The local port is a constant (Services/Hub/NerveEndpoint.swift), not a
# setting. Sources only: Nerve/build/ is gitignored derived data, and its stale
# index blobs still quote pre-cutover text (ripgrep skips it for the same
# reason). Two reads, because the two spellings fail differently:
#
#   1. the bare identifier must be gone entirely;
#   2. case-insensitively, every remaining hit must be one of the two
#      *qualified* fields that legitimately survive --
#        remoteIngestPort  the far end of the SSH RemoteForward (per machine),
#        localIngestPort   SSHConfigWriter's parameter, fed from NerveEndpoint.
SWIFT_SCAN=(-rn --include='*.swift' --exclude-dir=build)

if grep "${SWIFT_SCAN[@]}" 'ingestPort' Nerve/; then
  fail "the retired local ingest-port knob is still referenced in Nerve/ (see above)"
fi

if grep "${SWIFT_SCAN[@]}" -i 'ingestport' Nerve/ | grep -vE 'remoteIngestPort|localIngestPort'; then
  fail "unqualified ingest-port reference in Nerve/ (see above)"
fi
echo "ok: only remoteIngestPort / localIngestPort remain"

echo ""
echo "ALL OK"

# ---------------------------------------------------------------------------
# Manual regression matrix — not automatable here, still required before the
# surface spec closes. Run these against a launched app (./scripts/run.sh).
#
# 1. Notifications, three scenarios (structured fields only, never free text):
#    a. attention.level=suggested   -> banner fires ("Needs attention" setting);
#    b. attention.reason=failure    -> Failures banner fires;
#    c. departed path               -> a job that ends while its banner is up
#       still resolves (frame `departed` entry, not a stuck row).
#    Click-through must select + expand the job and run Open/Focus.
#
# 2. Hub lifecycle, by hand:
#    a. quit the app  -> hub exits ~30s later (last surface gone + grace);
#    b. relaunch      -> app spawns the bundled hub again and repaints;
#    c. bind conflict -> with a hub already on :17890, a second one prints a
#       note and exits 0 (never a crash dialog, never a second store).
#
# 3. Tunnels, verbatim regression (Settings -> Machines; needs a real remote):
#    connect, then diff the managed block in ~/.ssh/config against a copy taken
#    before the cutover. Per enabled Host it must still read exactly these two
#    lines, two-space indented, and nothing else:
#        RemoteForward 17890 127.0.0.1:17890
#        ExitOnForwardFailure yes
#    Connect / disconnect behaviour unchanged. This script deliberately does not
#    write ~/.ssh/config, so nothing here can prove it for you.
#
# 4. Settings UI inspection:
#    a. no ingest-port input anywhere in Settings;
#    b. Local Endpoint reads 127.0.0.1:17890 and is selectable;
#    c. a prefs blob written by an older build (one that still carried the port
#       key) loads without error and keeps its other values.
#
# 5. Endpoint literals (spec acceptance A2, by eye): the surface's own address
#    exists only in NerveEndpoint. The remaining `17890` literals in Nerve/ are
#    per-machine *remote* port defaults (MachineConfig, SSHConfigWriter,
#    MachineTunnelManager's fallback) and are intentionally left alone.

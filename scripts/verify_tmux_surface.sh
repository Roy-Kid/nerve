#!/usr/bin/env bash
#
# Automated checks for the tmux *surface* (non-visual).
#
# verify_surface.sh proves the macOS surface attaches to a hub. This script
# proves the other one does, on its own terms: sourcing surfaces/tmux/nerve.tmux
# wires the status line, binds the popup key and brings up exactly one helper;
# that helper turns a real fixture into a real segment; and when it dies the hub
# it was holding open lets go.
#
# Everything runs against an isolated tmux server (-L nervesurf), so your own
# tmux — sessions, options, key table — is never read and never written.
#
# Usage: bash scripts/verify_tmux_surface.sh
# Exit:  0 all green, 1 an assertion failed.
#
# It needs :17890 free, because the last assertion is that the hub *this script
# started* exits. A hub you care about would be a hub we refuse to outlive, so
# we decline to run rather than reuse one.
#
# Env:
#   NERVE_GRACE_SECS  hub linger after the last surface leaves (default 20).
#                     This is the wall-clock cost of the refcount assertion;
#                     the shipped default is 30 (crates/nerve-hub/src/cli.rs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLUGIN="$ROOT/surfaces/tmux/nerve.tmux"
FIXTURE="$ROOT/fixtures/demo_snapshot.json"
BASE="http://127.0.0.1:17890"

# Its own tmux server, its own socket, its own option namespace.
LABEL="nervesurf"

# Long enough that a loaded machine cannot lose the startup race (the same
# number is also the "nobody has ever connected" budget), short enough that
# waiting one out is not the point of the script.
GRACE_SECS="${NERVE_GRACE_SECS:-20}"

# Polling budgets, in 0.1s ticks (verify_surface.sh counts the same way).
TICK=0.1
TICKS_HEALTH=100  # 10s — hub binding the port
TICKS_CLAIM=50    # 5s  — helper claiming @nerve_surface_pid
TICKS_SEGMENT=100 # 10s — injected fixture reaching the status option

HUB_PID=""
HUB_LOG=""

# Runs on every exit, including the successful one — so every step has to
# tolerate having already happened. `|| true` on each, because under `set -e` a
# failing last command of a trap becomes the script's exit status.
cleanup() {
  # The helper first: it is the thing holding the hub open, and leaving one
  # attached to a killed tmux server is how you get a stray process.
  local helper
  helper="$(tmux_opt @nerve_surface_pid)"
  if [[ -n "$helper" ]]; then
    kill "$helper" 2>/dev/null || true
  fi

  tmux -L "$LABEL" kill-server 2>/dev/null || true

  if [[ -n "$HUB_PID" ]]; then
    kill "$HUB_PID" 2>/dev/null || true
    wait "$HUB_PID" 2>/dev/null || true
  fi
  if [[ -n "$HUB_LOG" ]]; then
    rm -f "$HUB_LOG" || true
  fi
  return 0
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# One global option off the isolated server; empty when unset or unreachable.
tmux_opt() {
  tmux -L "$LABEL" show-options -gqv "$1" 2>/dev/null || true
}

port_free() {
  ! curl -sf "$BASE/v1/health" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
echo "== preflight =="
command -v tmux >/dev/null 2>&1 || fail "tmux is not installed"
command -v curl >/dev/null 2>&1 || fail "curl is not installed"

[[ -f "$PLUGIN" ]] || fail "no plugin entry at $PLUGIN"
[[ -x "$PLUGIN" ]] || fail "$PLUGIN is not executable (chmod +x it — TPM runs it directly)"
[[ -f "$FIXTURE" ]] || fail "no fixture at $FIXTURE"

# Release first, debug second: the same order nerve.tmux and HubLocator use, so
# whichever pair a developer has built is the pair under test.
BIN_DIR=""
for candidate in "$ROOT/target/release" "$ROOT/target/debug"; do
  if [[ -x "$candidate/nerve-hub" && -x "$candidate/nerve-tmux-surface" ]]; then
    BIN_DIR="$candidate"
    break
  fi
done
[[ -n "$BIN_DIR" ]] || fail "no nerve-hub + nerve-tmux-surface pair in target/{release,debug} — run cargo build --workspace --release"

HUB="$BIN_DIR/nerve-hub"
HELPER="$BIN_DIR/nerve-tmux-surface"
echo "ok: $BIN_DIR"

# nerve.tmux looks in ../../target/release before anything else, which is this
# repo when release is what got built. Putting BIN_DIR on PATH covers the debug
# case through the plugin's last candidate rather than special-casing it.
export PATH="$BIN_DIR:$PATH"

port_free || fail ":17890 is already serving — this script must own the hub it outlives (stop it, or quit Nerve.app, and retry)"

# A stale server from an interrupted run would hand us its options.
tmux -L "$LABEL" kill-server 2>/dev/null || true

# ---------------------------------------------------------------------------
echo "== hub on :17890 (grace ${GRACE_SECS}s) =="
HUB_LOG="$(mktemp "${TMPDIR:-/tmp}/nerve-verify-tmux.XXXXXX")"
"$HUB" serve --grace-secs "$GRACE_SECS" >"$HUB_LOG" 2>&1 &
HUB_PID=$!

ready=""
for _ in $(seq 1 "$TICKS_HEALTH"); do
  if curl -sf "$BASE/v1/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  kill -0 "$HUB_PID" 2>/dev/null || break
  sleep "$TICK"
done
if [[ -z "$ready" ]]; then
  echo "--- hub log ---" >&2
  cat "$HUB_LOG" >&2 || true
  fail "hub never answered /v1/health"
fi
echo "ok: hub serving (pid $HUB_PID)"

# ---------------------------------------------------------------------------
echo "== isolated tmux server =="
tmux -L "$LABEL" new-session -d -s verify || fail "could not start tmux -L $LABEL"

SOCKET="$(tmux -L "$LABEL" display-message -p '#{socket_path}')"
[[ -n "$SOCKET" ]] || fail "tmux -L $LABEL did not report a socket path"

# What tmux exports into a pane, and what tmux(1) reads back to find its server
# when no -L/-S is given. This is the whole reason the helper needs no socket
# flag: it inherits the server it belongs to.
export TMUX="${SOCKET},0,0"
echo "ok: $SOCKET"

# ---------------------------------------------------------------------------
echo "== nerve.tmux wires the surface =="
"$PLUGIN" || fail "nerve.tmux exited $? — the entry point is fail-open and must always exit 0"

STATUS_RIGHT="$(tmux_opt status-right)"
grep -qF '#{@nerve_status}' <<<"$STATUS_RIGHT" \
  || fail "status-right does not interpolate #{@nerve_status} (got: ${STATUS_RIGHT:-<empty>})"
echo "ok: status-right -> $STATUS_RIGHT"

POPUP_KEY="$(tmux_opt @nerve_popup_key)"
POPUP_KEY="${POPUP_KEY:-N}"
BINDING="$(tmux -L "$LABEL" list-keys -T prefix 2>/dev/null | grep -F 'display-popup' || true)"
[[ -n "$BINDING" ]] || fail "no display-popup binding in the prefix table"
grep -qF "nerve-tmux-surface" <<<"$BINDING" || fail "the display-popup binding does not run the helper: $BINDING"
grep -qF " popup" <<<"$BINDING" || fail "the display-popup binding does not run the popup subcommand: $BINDING"
echo "ok: prefix + $POPUP_KEY -> $(tr -s ' ' <<<"$BINDING")"

# ---------------------------------------------------------------------------
echo "== single surface, idempotent wiring =="
claimed=""
for _ in $(seq 1 "$TICKS_CLAIM"); do
  claimed="$(tmux_opt @nerve_surface_pid)"
  [[ -n "$claimed" ]] && break
  sleep "$TICK"
done
[[ -n "$claimed" ]] || fail "@nerve_surface_pid was never claimed — did the helper start?"
kill -0 "$claimed" 2>/dev/null || fail "@nerve_surface_pid names $claimed, which is not running"
echo "ok: helper $claimed holds the surface"

# Sourcing twice is what TPM does across a config reload, and what a user does
# by hand. The second run must add nothing and take nothing over.
"$PLUGIN" || fail "the second nerve.tmux run exited $? — sourcing twice must stay fail-open"

AGAIN="$(tmux_opt status-right)"
[[ "$AGAIN" == "$STATUS_RIGHT" ]] || fail "status-right changed on the second run — the wiring is not idempotent: $AGAIN"

# Give the second helper time to read the option and stand down before we look.
sleep 1
still="$(tmux_opt @nerve_surface_pid)"
[[ "$still" == "$claimed" ]] || fail "a second helper took the surface over ($claimed -> $still)"
kill -0 "$claimed" 2>/dev/null || fail "the owning helper $claimed died on the second run"
echo "ok: still one surface ($claimed), status-right untouched"

# ---------------------------------------------------------------------------
echo "== injected fixture reaches the segment =="
INJECT_LOG="$(mktemp "${TMPDIR:-/tmp}/nerve-verify-tmux-inject.XXXXXX")"
if ! bash "$ROOT/scripts/inject_demo.sh" >"$INJECT_LOG" 2>&1; then
  cat "$INJECT_LOG" >&2 || true
  rm -f "$INJECT_LOG"
  fail "scripts/inject_demo.sh failed"
fi
rm -f "$INJECT_LOG"

# Both fixture jobs are lifecycle=active, health=ok, attention=none with a
# current.type this table does not name, so both derive Running
# (crates/nerve-tmux-surface/src/status.rs). The default template renders that
# as `2>` and drops the three zero segments whole.
SEGMENT=""
for _ in $(seq 1 "$TICKS_SEGMENT"); do
  SEGMENT="$(tmux_opt @nerve_status)"
  grep -qF '2>' <<<"$SEGMENT" && break
  sleep "$TICK"
done
grep -qF '2>' <<<"$SEGMENT" || fail "@nerve_status never showed the 2 running jobs (got: ${SEGMENT:-<empty>})"
echo "ok: @nerve_status -> $SEGMENT"

# Zero-count elision, from the same reading: nothing is problem, attention or
# waiting, so none of their markers survive.
for marker in '0!' '0?' '0~'; do
  if grep -qF "$marker" <<<"$SEGMENT"; then
    fail "zero-count segment '$marker' was not elided: $SEGMENT"
  fi
done
echo "ok: zero counts elided"

# ---------------------------------------------------------------------------
echo "== popup is a read-only job list =="
POPUP="$("$HELPER" popup)" || fail "$HELPER popup exited non-zero"
for expected in 'Demo' 'nerve' 'xcodebuild Nerve' 'running'; do
  grep -qF "$expected" <<<"$POPUP" || fail "popup output is missing '$expected':
$POPUP"
done
[[ "$(grep -c . <<<"$POPUP")" -eq 2 ]] || fail "popup printed $(grep -c . <<<"$POPUP") rows, expected 2:
$POPUP"
echo "ok: popup ->"
printf '     %s\n' "${POPUP//$'\n'/$'\n'     }"

# ---------------------------------------------------------------------------
echo "== hub outlives nothing: helper leaves, refcount drops =="
kill "$claimed" 2>/dev/null || fail "could not signal the helper $claimed"

# The stream was this surface's only presence, and it was the only surface. The
# hub must now wait out its grace and exit on its own — nobody kills it here.
deadline=$(( GRACE_SECS + 15 ))
gone=""
for _ in $(seq 1 $(( deadline * 10 )) ); do
  if ! kill -0 "$HUB_PID" 2>/dev/null; then
    gone=1
    break
  fi
  sleep "$TICK"
done
if [[ -z "$gone" ]]; then
  echo "--- hub log ---" >&2
  cat "$HUB_LOG" >&2 || true
  fail "hub was still running ${deadline}s after the last surface left (grace ${GRACE_SECS}s)"
fi

wait "$HUB_PID" 2>/dev/null || true
HUB_PID=""
port_free || fail ":17890 still answers after the hub exited"
echo "ok: hub exited within grace, port released"

# ---------------------------------------------------------------------------
echo "== no notifications, no daemons, no disk state =="
# Acceptance A11, mechanised. Notifications belong to the macOS surface; this
# one expresses attention inside tmux and nowhere else. Single-instance state
# lives in a tmux option, which dies with the server — so no unit files and no
# dotfiles either.
SCAN_DIRS=("$ROOT/surfaces" "$ROOT/crates/nerve-tmux-surface")
FORBIDDEN='osascript|terminal-notifier|UNUserNotification|NSUserNotification|afplay|say -v|launchctl|systemctl'

if grep -rnE "$FORBIDDEN" "${SCAN_DIRS[@]}"; then
  fail "a notification or daemon call reached the tmux surface (see above)"
fi

UNITS="$(find "${SCAN_DIRS[@]}" \( -name '*.plist' -o -name '*.service' \) -print)"
[[ -z "$UNITS" ]] || fail "launchd/systemd unit files under the tmux surface:
$UNITS"
echo "ok: segment highlighting only, no unit files"

echo ""
echo "ALL OK"

# ---------------------------------------------------------------------------
# Manual regression matrix — the parts a script cannot see. Run these in a real
# tmux, against a real hub (spec Testing, acceptance A7 / A8 / A9 / A10).
#
# 1. Live segment (A7): install via TPM, inject fixtures/demo_snapshot.json, and
#    watch status-right pick up the running count within ~2s. Then POST a job
#    with attention.level=required and confirm the segment recolours rather than
#    only recounting. Let a job end and confirm the count falls on the next
#    frame (the `departed` path, which must not notify).
#
# 2. Popup (A8): prefix + N. The rows are producer / name / status / attention /
#    age and there is no key that approves, cancels or submits anything. ESC
#    closes it, and neither the helper nor the hub notices.
#
# 3. Two surfaces (A9): Nerve.app and tmux attached at once.
#      a. pkill -f nerve-tmux-surface  -> hub keeps running (the app holds it);
#      b. quit the app                 -> hub exits ~30s later;
#      c. source nerve.tmux again      -> helper starts the hub back up and the
#         segment returns. This script covers only the one-surface half: with
#         nothing else attached, the hub exits.
#
# 4. Fail-open (A10), four ways, none of which may disturb tmux: no nerve-hub
#    binary installed; :17890 closed; kill -9 the helper; restart the hub under
#    it. The segment degrades to @nerve_status_offline and comes back by itself.
#
# 5. Remote (design bonus, needs a real remote): with the machine's RemoteForward
#    tunnel up, source nerve.tmux on the remote host. It reaches this Mac's hub
#    through 127.0.0.1:17890 with no configuration of its own — the helper has
#    no concept of "remote" to configure.

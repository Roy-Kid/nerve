//! Lifecycle tests (spec `nerve-hub` · T6 · acceptance A7, automated part).
//!
//! RED on purpose: `nerve_hub::HubRuntime` does not exist yet. T7 implements
//! `lifecycle/` against the contract in this header; this file is the API
//! definition. The frame side of the same runtime is pinned by
//! `tests/sse_stream.rs`, which also owns the one test that binds an SSE
//! connection to the reference counted here.
//!
//! ─────────────────────────────────────────────────────────────────────────
//! MINIMAL API CONTRACT (what T7 must expose)
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```text
//! nerve_hub::HubRuntime
//! impl HubRuntime {
//!     pub fn new(store: JobStore, grace: Duration) -> Self;
//!     pub fn router(&self) -> axum::Router;
//!     pub fn shutdown(&self) -> impl Future<Output = ()>;   // may borrow `&self`
//!     pub fn subscribe(&self) -> _;   // opaque guard; Drop releases the reference
//! }
//! ```
//!
//! Rules:
//!
//! 1. **The runtime owns the timer, not the future.** `new()` arms the grace
//!    timer (a hub nobody ever connects to must still exit); `subscribe()`
//!    disarms it on 0→1; dropping the last guard re-arms it on 1→0, from
//!    scratch — a grace is never resumed. Intermediate transitions (2→1) change
//!    nothing.
//! 2. **`shutdown()` observes, it never arms.** It may be called any number of
//!    times, before or after the fact, and polling it must have no effect on the
//!    refcount or the timer. It is level-triggered and latching: once the exit
//!    condition is reached the signal stays resolved, so a call made afterwards
//!    resolves on its first poll.
//! 3. **The grace timer runs on `tokio::time`**, so `#[tokio::test(start_paused)]`
//!    controls it. An implementation that reaches for `std::thread::sleep` or
//!    `Instant::now()` deltas will hang these tests instead of passing them.
//! 4. **Producer traffic does not renew the grace** (spec D3). Only a
//!    subscription is a surface's proof of presence.
//! 5. `subscribe()` returns whatever guard type T7 likes; no test names it.
//!
//! ─────────────────────────────────────────────────────────────────────────
//! HARNESS
//! ─────────────────────────────────────────────────────────────────────────
//!
//! Paused virtual time plus a real socket deadlocks (auto-advance only happens
//! when the runtime is idle, and a socket read never is), so this file uses no
//! socket at all: it drives the refcount through `subscribe()` and the write
//! path through `router()` with `ConnectInfo` injected, exactly as
//! `tests/contract_http.rs` does. Nothing here binds a port — least of all
//! 17890, which is the real hub's single-instance lock.
//!
//! Two measurement styles, both deterministic:
//!
//! * "must not exit yet" → [`settle`] then [`is_pending`], a single poll with a
//!   no-op waker. Polling never yields, so the paused clock cannot auto-advance
//!   underneath the assertion; the [`settle`] before it is what makes the
//!   assertion honest, by letting a timer that *did* fire record its decision
//!   first. Without it a hub that exited too early would go unnoticed.
//! * "must exit after N" → await the signal and assert the **virtual** elapsed
//!   time. Auto-advance jumps to the nearest deadline, so the measured delay is
//!   the implementation's grace, not the test's patience. The outer
//!   [`SHUTDOWN_BUDGET`] only turns a never-firing timer into a clean failure
//!   instead of a hang.
//!
//! Every refcount transition is followed by [`settle`], which hands the runtime
//! a few scheduler turns before virtual time moves again. Under a paused clock a
//! background task that has not run yet would otherwise arm its timer *later*
//! than the transition and measure a longer grace than it implements. Deriving
//! the deadline from the instant of the transition (`Instant::now() + grace`
//! stored on the spot, awaited with `sleep_until`) makes this robust either way.
//!
//! Determinism: fake clock inside the store, fake `PidProbe`, injected machine
//! alias, virtual time throughout. No wall clock, no socket, no filesystem.

use std::future::Future;
use std::net::SocketAddr;
use std::sync::Arc;
use std::task::{Context, Poll, Wake, Waker};
use std::time::Duration;

use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use serde_json::{json, Value};
use time::macros::datetime;
use tokio::time::{advance, timeout, Instant};
use tower::ServiceExt;

use nerve_hub::clock::FakeClock;
use nerve_hub::state::{JobStore, PidProbe, PidState};
use nerve_hub::HubRuntime;

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Wire instant every fixture is anchored to.
const T0: &str = "2026-07-19T00:00:00Z";

/// The alias injected into `JobStore::new` — "this machine" for the hub.
const MACHINE_ALIAS: &str = "test-mac";

/// The shipped default (`serve --grace-secs 30`).
const GRACE: Duration = Duration::from_secs(30);

/// Virtual budget for a signal that is supposed to fire. Never reached when the
/// timer works: auto-advance stops at the grace deadline first.
const SHUTDOWN_BUDGET: Duration = Duration::from_secs(3_600);

/// How far past a deadline a measured delay may land before it counts as a
/// different number. Virtual time, so this is rounding slack, not jitter.
const SLACK: Duration = Duration::from_secs(1);

/// The last stretch of a grace, used to step up to a deadline without crossing
/// it. Any value below `GRACE` and above `SLACK` would do.
const LAST_STRETCH: Duration = Duration::from_secs(5);

fn store() -> JobStore {
    let clock = Arc::new(FakeClock::new(datetime!(2026-07-19 00:00:00 UTC)));
    JobStore::new(clock, MACHINE_ALIAS.to_string(), Arc::new(EveryPidAlive))
}

fn runtime(grace: Duration) -> HubRuntime {
    HubRuntime::new(store(), grace)
}

/// Liveness oracle that never reaps: these tests are about the refcount, not
/// the reaper.
struct EveryPidAlive;

impl PidProbe for EveryPidAlive {
    fn state(&self, _pid: i32) -> PidState {
        PidState::Alive
    }
}

fn job(id: &str) -> Value {
    json!({
        "id": id,
        "kind": "session",
        "name": id,
        "alias": MACHINE_ALIAS,
        "lifecycle": "active",
        "attention": { "level": "none" },
        "health": "ok",
        "progress": { "kind": "none" },
        "producer": { "id": "t" },
        "capabilities": [],
        "actions": [],
        "createdAt": T0,
        "startedAt": T0,
        "updatedAt": T0,
        "version": 1,
        "extensions": {}
    })
}

// ── Driving the runtime ─────────────────────────────────────────────────────

/// One producer snapshot through the runtime's own router.
async fn post_snapshot(runtime: &HubRuntime, id: &str) {
    let body = json!({ "alias": MACHINE_ALIAS, "jobs": [job(id)] }).to_string();
    let mut request = Request::builder()
        .method("POST")
        .uri("/v1/snapshot")
        .header("content-type", "application/json")
        .body(Body::from(body))
        .expect("test request must build");
    // What `into_make_service_with_connect_info::<SocketAddr>()` installs in
    // production; injected here so no port is ever bound.
    request
        .extensions_mut()
        .insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 54_321))));

    let response = runtime
        .router()
        .oneshot(request)
        .await
        .expect("router must answer every request");
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "the write path must work while the hub is winding down"
    );
}

// ── Measuring the signal ────────────────────────────────────────────────────

/// Poll a future exactly once. No `.await`, so the paused clock cannot
/// auto-advance while the question is being asked.
fn is_pending<F: Future>(future: F) -> bool {
    let mut future = Box::pin(future);
    let waker = Waker::from(Arc::new(NoopWake));
    let mut context = Context::from_waker(&waker);
    matches!(future.as_mut().poll(&mut context), Poll::Pending)
}

struct NoopWake;

impl Wake for NoopWake {
    fn wake(self: Arc<Self>) {}
}

/// Wait for the exit signal and report how much **virtual** time it took.
async fn exit_delay(runtime: &HubRuntime) -> Duration {
    let start = Instant::now();
    timeout(SHUTDOWN_BUDGET, runtime.shutdown())
        .await
        .expect("the hub must reach its shutdown signal");
    start.elapsed()
}

/// Let the runtime observe a refcount transition before virtual time moves.
///
/// Yields only — the clock cannot auto-advance while a task is runnable, so
/// this costs nothing in virtual time and nothing in wall time.
async fn settle() {
    for _ in 0..8 {
        tokio::task::yield_now().await;
    }
}

fn assert_delay(actual: Duration, expected: Duration, what: &str) {
    assert!(
        actual >= expected && actual < expected + SLACK,
        "{what}: expected ~{expected:?}, waited {actual:?}"
    );
}

// ════════════════════════════════════════════════════════════════════════════
// 1. The last subscription leaving starts the clock (acceptance A7)
// ════════════════════════════════════════════════════════════════════════════

#[tokio::test(start_paused = true)]
async fn test_the_hub_exits_one_grace_after_the_last_subscription_drops() {
    let runtime = runtime(GRACE);
    let subscription = runtime.subscribe();

    drop(subscription);

    settle().await;
    advance(GRACE - LAST_STRETCH).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "the hub must not exit before its grace has elapsed"
    );
    assert_delay(
        exit_delay(&runtime).await,
        LAST_STRETCH,
        "the rest of the grace",
    );
}

#[tokio::test(start_paused = true)]
async fn test_a_live_subscription_holds_the_hub_open_indefinitely() {
    let runtime = runtime(GRACE);
    let _subscription = runtime.subscribe();
    settle().await;

    // A surface that stays connected for hours is the normal case.
    advance(GRACE * 100).await;

    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "a subscribed surface must keep the hub alive"
    );
}

// ════════════════════════════════════════════════════════════════════════════
// 2. Reconnecting inside the grace cancels the exit (acceptance A7)
// ════════════════════════════════════════════════════════════════════════════

#[tokio::test(start_paused = true)]
async fn test_a_new_subscription_inside_the_grace_cancels_the_timer() {
    let runtime = runtime(GRACE);
    drop(runtime.subscribe());
    settle().await;
    advance(GRACE / 2).await;

    let _second = runtime.subscribe();
    settle().await;

    // Far past the deadline the cancelled timer would have fired at.
    advance(GRACE * 10).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "a surface reconnecting inside the grace must cancel the exit"
    );
}

#[tokio::test(start_paused = true)]
async fn test_the_grace_restarts_from_scratch_after_a_reconnect() {
    let runtime = runtime(GRACE);
    drop(runtime.subscribe());
    settle().await;
    advance(GRACE / 2).await;
    let second = runtime.subscribe();
    settle().await;

    drop(second);

    // A restarted grace, not the remainder of the first one.
    settle().await;
    advance(GRACE - LAST_STRETCH).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "the grace must restart at the new 1→0, not resume where it stopped"
    );
    assert_delay(
        exit_delay(&runtime).await,
        LAST_STRETCH,
        "the restarted grace",
    );
}

#[tokio::test(start_paused = true)]
async fn test_dropping_one_of_two_subscriptions_is_not_the_last_one_leaving() {
    let runtime = runtime(GRACE);
    let first = runtime.subscribe();
    let second = runtime.subscribe();
    settle().await;

    drop(first);

    settle().await;
    advance(GRACE * 10).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "2→1 is not 1→0: the second surface is still watching"
    );
    drop(second);
    settle().await;
    assert_delay(
        exit_delay(&runtime).await,
        GRACE,
        "the grace after the last of two",
    );
}

// ════════════════════════════════════════════════════════════════════════════
// 3. Start-up and zero grace (acceptance A7)
// ════════════════════════════════════════════════════════════════════════════

#[tokio::test(start_paused = true)]
async fn test_a_hub_nobody_connects_to_exits_after_its_grace() {
    // Spawn-and-forget: a surface may start a hub and then die before it
    // connects. Counting from start-up is what stops that hub leaking forever.
    let start = Instant::now();
    let runtime = runtime(GRACE);
    settle().await;

    advance(GRACE - LAST_STRETCH).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "the start-up grace must be the same grace"
    );
    exit_delay(&runtime).await;
    assert_delay(start.elapsed(), GRACE, "the grace from start-up");
}

#[tokio::test(start_paused = true)]
async fn test_zero_grace_exits_as_soon_as_the_last_subscription_drops() {
    let runtime = runtime(Duration::ZERO);
    let subscription = runtime.subscribe();
    settle().await;
    advance(GRACE * 10).await;
    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "zero grace still waits for the last subscription to leave"
    );

    drop(subscription);

    settle().await;
    assert_delay(exit_delay(&runtime).await, Duration::ZERO, "zero grace");
}

#[tokio::test(start_paused = true)]
async fn test_the_shutdown_signal_latches_for_later_callers() {
    let runtime = runtime(Duration::ZERO);
    drop(runtime.subscribe());
    settle().await;
    exit_delay(&runtime).await;

    // Level-triggered: `serve` and any other observer asking after the fact must
    // see the decision, not wait for a second one that never comes.
    assert!(
        !is_pending(runtime.shutdown()),
        "the shutdown signal must stay resolved once it has fired"
    );
}

// ════════════════════════════════════════════════════════════════════════════
// 4. Producers are not surfaces (acceptance A7 · spec D3)
// ════════════════════════════════════════════════════════════════════════════

#[tokio::test(start_paused = true)]
async fn test_producer_posts_do_not_renew_the_grace() {
    // A busy agent pushing snapshots into a hub no surface is watching must not
    // keep it alive: hooks are fire-and-forget, they never read a frame.
    let start = Instant::now();
    let runtime = runtime(GRACE);
    settle().await;

    for id in ["a1", "a2", "a3"] {
        advance(GRACE / 4).await;
        post_snapshot(&runtime, id).await;
    }

    settle().await;
    assert!(
        is_pending(runtime.shutdown()),
        "writes must not shorten the grace either"
    );
    exit_delay(&runtime).await;
    // Renewal on POST would put this at the last write plus a full grace.
    assert_delay(start.elapsed(), GRACE, "the grace from start-up, unrenewed");
}

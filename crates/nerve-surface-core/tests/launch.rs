//! `launch.rs` — bringing a hub up, at most once per window (spec T4 ·
//! acceptance A3).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/launch.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_surface_core::launch
//!
//! /// How long a spawn attempt suppresses the next one.
//! pub const THROTTLE: std::time::Duration = std::time::Duration::from_secs(10);
//!
//! /// `GET http://127.0.0.1:17890/v1/health` — is a hub already serving?
//! pub trait HealthProbe { fn is_serving(&self) -> bool; }
//!
//! /// Start a detached process. **Arg array only** — there is no shell
//! /// anywhere in this crate (spec Domain basis, same rule as
//! /// `plugins/nerve/hooks/nerve_hook.py`).
//! pub trait ProcessSpawner {
//!     fn spawn(&mut self, program: &Path, args: &[&str]) -> Result<(), SpawnError>;
//! }
//!
//! /// Injected wall clock, as in `crates/nerve-hub/src/clock.rs`.
//! pub trait Clock { fn now(&self) -> time::OffsetDateTime; }
//!
//! /// Why the OS refused. `Display` carries the reason.
//! #[derive(Debug)]
//! pub struct SpawnError(/* … */);
//! impl SpawnError { pub fn new(message: impl Into<String>) -> Self; }
//!
//! /// What `ensure` did. Every arm is fail-open: none is an error the caller
//! /// may propagate out of `main` as a non-zero exit.
//! #[derive(Clone, Copy, Debug, PartialEq, Eq)]
//! pub enum Launch {
//!     /// A hub already answers `/v1/health`; nothing was spawned.
//!     AlreadyServing,
//!     /// A hub was started; it is not serving yet.
//!     Spawned,
//!     /// Health is down, but the last attempt is younger than `THROTTLE`.
//!     Throttled,
//!     /// No `nerve-hub` binary anywhere (spec Open questions 1).
//!     Missing,
//!     /// The binary is there and the OS refused to start it.
//!     Failed,
//! }
//!
//! impl Launch {
//!     /// Whether the surface paints the offline placeholder rather than a
//!     /// live segment. Only `AlreadyServing` is false.
//!     pub fn is_offline(self) -> bool;
//! }
//!
//! pub struct HubLauncher<S: ProcessSpawner, C: Clock, H: HealthProbe> { /* … */ }
//!
//! impl<S: ProcessSpawner, C: Clock, H: HealthProbe> HubLauncher<S, C, H> {
//!     pub fn new(spawner: S, clock: C, health: H) -> Self;
//!
//!     /// Decide, and act, in this order:
//!     ///   1. health serving              -> `AlreadyServing` (never spawns)
//!     ///   2. `hub` is `None`             -> `Missing` (records no attempt)
//!     ///   3. an attempt within `THROTTLE`-> `Throttled`
//!     ///   4. otherwise spawn `hub serve` -> `Spawned` | `Failed`
//!     /// A spawn — successful or refused — records the attempt; `Missing`
//!     /// does not, so a hub installed a second later starts a second later.
//!     pub fn ensure(&mut self, hub: Option<&Path>) -> Launch;
//! }
//! ```
//!
//! Determinism: injected clock, fake spawner, fake health probe. No process is
//! started, no port is touched, no wall clock is read.

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration as StdDuration;

use time::macros::datetime;
use time::{Duration, OffsetDateTime};

use nerve_surface_core::launch::{
    Clock, HealthProbe, HubLauncher, Launch, ProcessSpawner, SpawnError, THROTTLE,
};

const START: OffsetDateTime = datetime!(2026-07-19 08:00:00 UTC);
const HUB: &str = "/opt/homebrew/bin/nerve-hub";

type Calls = Rc<RefCell<Vec<(PathBuf, Vec<String>)>>>;

// ── Fakes ───────────────────────────────────────────────────────────────────

struct FakeClock {
    now: Rc<Cell<OffsetDateTime>>,
}

impl Clock for FakeClock {
    fn now(&self) -> OffsetDateTime {
        self.now.get()
    }
}

struct FakeHealth {
    serving: Rc<Cell<bool>>,
}

impl HealthProbe for FakeHealth {
    fn is_serving(&self) -> bool {
        self.serving.get()
    }
}

struct FakeSpawner {
    calls: Calls,
    accepts: Rc<Cell<bool>>,
    /// Whether the hub this spawner starts actually comes up.
    comes_up: bool,
    serving: Rc<Cell<bool>>,
}

impl ProcessSpawner for FakeSpawner {
    fn spawn(&mut self, program: &Path, args: &[&str]) -> Result<(), SpawnError> {
        self.calls.borrow_mut().push((
            program.to_path_buf(),
            args.iter().map(|arg| (*arg).to_string()).collect(),
        ));
        if !self.accepts.get() {
            return Err(SpawnError::new("No such file or directory (os error 2)"));
        }
        if self.comes_up {
            self.serving.set(true);
        }
        Ok(())
    }
}

// ── Harness ─────────────────────────────────────────────────────────────────

/// Handles onto the fakes, kept after they were moved into the launcher.
struct Wires {
    calls: Calls,
    now: Rc<Cell<OffsetDateTime>>,
    serving: Rc<Cell<bool>>,
    accepts: Rc<Cell<bool>>,
}

impl Wires {
    fn spawns(&self) -> usize {
        self.calls.borrow().len()
    }

    fn advance(&self, step: Duration) {
        self.now.set(self.now.get() + step);
    }
}

/// A launcher over fakes.
///
/// * `serving` — what `/v1/health` answers to begin with.
/// * `comes_up` — whether a spawned hub then starts answering.
fn launcher(
    serving: bool,
    comes_up: bool,
) -> (HubLauncher<FakeSpawner, FakeClock, FakeHealth>, Wires) {
    let calls: Calls = Rc::new(RefCell::new(Vec::new()));
    let now = Rc::new(Cell::new(START));
    let serving = Rc::new(Cell::new(serving));
    let accepts = Rc::new(Cell::new(true));

    let spawner = FakeSpawner {
        calls: Rc::clone(&calls),
        accepts: Rc::clone(&accepts),
        comes_up,
        serving: Rc::clone(&serving),
    };
    let clock = FakeClock {
        now: Rc::clone(&now),
    };
    let health = FakeHealth {
        serving: Rc::clone(&serving),
    };

    (
        HubLauncher::new(spawner, clock, health),
        Wires {
            calls,
            now,
            serving,
            accepts,
        },
    )
}

fn hub() -> &'static Path {
    Path::new(HUB)
}

// ── A hub that is already there ─────────────────────────────────────────────

/// Acceptance A3: health probe succeeds → **zero** spawns.
#[test]
fn test_a_serving_hub_is_never_spawned() {
    let (mut launcher, wires) = launcher(true, false);

    assert_eq!(launcher.ensure(Some(hub())), Launch::AlreadyServing);
    assert_eq!(wires.spawns(), 0);
}

#[test]
fn test_a_serving_hub_is_the_only_state_that_is_not_offline() {
    assert!(!Launch::AlreadyServing.is_offline());
    assert!(Launch::Spawned.is_offline());
    assert!(Launch::Throttled.is_offline());
    assert!(Launch::Missing.is_offline());
    assert!(Launch::Failed.is_offline());
}

/// Health is consulted before the throttle, so a hub that came up one second
/// after being spawned is reported as serving rather than as throttled.
#[test]
fn test_health_is_consulted_before_the_throttle() {
    let (mut launcher, wires) = launcher(false, false);
    assert_eq!(launcher.ensure(Some(hub())), Launch::Spawned);

    wires.serving.set(true);
    wires.advance(Duration::seconds(1));

    assert_eq!(launcher.ensure(Some(hub())), Launch::AlreadyServing);
    assert_eq!(wires.spawns(), 1);
}

// ── Spawning ────────────────────────────────────────────────────────────────

#[test]
fn test_a_down_hub_with_a_binary_is_spawned() {
    let (mut launcher, wires) = launcher(false, false);

    assert_eq!(launcher.ensure(Some(hub())), Launch::Spawned);
    assert_eq!(wires.spawns(), 1);
}

/// The whole command line, hard-coded: the located binary, then the single
/// subcommand `nerve-hub` understands (`crates/nerve-hub/src/cli.rs:61`).
#[test]
fn test_the_hub_is_started_as_an_arg_array_never_a_shell() {
    let (mut launcher, wires) = launcher(false, false);
    launcher.ensure(Some(hub()));

    let calls = wires.calls.borrow();
    assert_eq!(calls.len(), 1);
    let (program, args) = &calls[0];
    assert_eq!(program, Path::new(HUB));
    assert_eq!(args, &vec!["serve".to_string()]);
    for arg in args {
        assert!(
            !arg.contains(' ') && !arg.contains(';') && !arg.contains('|') && !arg.contains('&'),
            "argument `{arg}` looks like a shell line"
        );
    }
}

// ── Throttling ──────────────────────────────────────────────────────────────

#[test]
fn test_the_throttle_window_is_ten_seconds() {
    assert_eq!(THROTTLE, StdDuration::from_secs(10));
}

/// Acceptance A3: health down, binary present, the surface retrying once a
/// second for thirty seconds — and the hub is started **exactly once**,
/// because the one it started answers from then on.
#[test]
fn test_thirty_seconds_of_retries_spawn_the_hub_exactly_once() {
    let (mut launcher, wires) = launcher(false, true);

    let mut outcomes = Vec::new();
    for _ in 0..=30 {
        outcomes.push(launcher.ensure(Some(hub())));
        wires.advance(Duration::seconds(1));
    }

    assert_eq!(wires.spawns(), 1);
    assert_eq!(outcomes[0], Launch::Spawned);
    assert!(
        outcomes[1..]
            .iter()
            .all(|outcome| *outcome == Launch::AlreadyServing),
        "after the hub came up nothing else may be spawned: {outcomes:?}"
    );
}

/// A hub that refuses to come up is retried, but never faster than `THROTTLE`.
#[test]
fn test_a_second_attempt_inside_the_window_is_throttled() {
    let (mut launcher, wires) = launcher(false, false);
    assert_eq!(launcher.ensure(Some(hub())), Launch::Spawned);

    wires.advance(Duration::milliseconds(9_999));

    assert_eq!(launcher.ensure(Some(hub())), Launch::Throttled);
    assert_eq!(wires.spawns(), 1);
}

#[test]
fn test_the_window_reopens_exactly_at_the_throttle_boundary() {
    let (mut launcher, wires) = launcher(false, false);
    launcher.ensure(Some(hub()));

    wires.advance(Duration::seconds(10));

    assert_eq!(launcher.ensure(Some(hub())), Launch::Spawned);
    assert_eq!(wires.spawns(), 2);
}

#[test]
fn test_a_hub_that_never_comes_up_is_retried_once_per_throttle_window() {
    let (mut launcher, wires) = launcher(false, false);

    for _ in 0..=30 {
        launcher.ensure(Some(hub()));
        wires.advance(Duration::seconds(1));
    }

    // t=0, t=10, t=20, t=30.
    assert_eq!(wires.spawns(), 4);
}

// ── Nothing to spawn ────────────────────────────────────────────────────────

/// Acceptance A3: no binary → no spawn, and an offline placeholder rather than
/// a crash. `nerve.tmux` still exits 0 (spec Testing, fail-open row).
#[test]
fn test_a_missing_binary_is_never_spawned() {
    let (mut launcher, wires) = launcher(false, false);

    let outcome = launcher.ensure(None);

    assert_eq!(outcome, Launch::Missing);
    assert!(outcome.is_offline());
    assert_eq!(wires.spawns(), 0);
}

/// A missing binary records no attempt: installing one does not then have to
/// wait out a throttle window nobody used.
#[test]
fn test_a_missing_binary_does_not_consume_the_throttle_window() {
    let (mut launcher, wires) = launcher(false, false);
    assert_eq!(launcher.ensure(None), Launch::Missing);

    assert_eq!(launcher.ensure(Some(hub())), Launch::Spawned);
    assert_eq!(wires.spawns(), 1);
}

#[test]
fn test_a_missing_binary_is_still_missing_when_a_hub_is_serving() {
    let (mut launcher, wires) = launcher(true, false);

    assert_eq!(launcher.ensure(None), Launch::AlreadyServing);
    assert_eq!(wires.spawns(), 0);
}

// ── A refused spawn ─────────────────────────────────────────────────────────

#[test]
fn test_a_refused_spawn_is_reported_rather_than_raised() {
    let (mut launcher, wires) = launcher(false, false);
    wires.accepts.set(false);

    assert_eq!(launcher.ensure(Some(hub())), Launch::Failed);
    assert_eq!(wires.spawns(), 1);
}

/// A refusal still counts as an attempt: a broken binary must not be fired at
/// the OS on every frame.
#[test]
fn test_a_refused_spawn_still_consumes_the_throttle_window() {
    let (mut launcher, wires) = launcher(false, false);
    wires.accepts.set(false);
    launcher.ensure(Some(hub()));

    wires.advance(Duration::seconds(1));

    assert_eq!(launcher.ensure(Some(hub())), Launch::Throttled);
    assert_eq!(wires.spawns(), 1);
}

#[test]
fn test_spawn_error_explains_itself() {
    let err = SpawnError::new("No such file or directory (os error 2)");

    assert_eq!(err.to_string(), "No such file or directory (os error 2)");
}

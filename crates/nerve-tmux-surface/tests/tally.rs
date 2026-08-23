//! `tally.rs` — counting a frame's jobs by class (spec T3 · acceptance A1).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/tally.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_tmux_surface::tally
//!
//! /// One count per `StatusClass`. Public fields so a test (and a renderer)
//! /// can state a whole expectation in one literal.
//! #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
//! pub struct Tally {
//!     pub problem: usize,
//!     pub attention: usize,
//!     pub waiting: usize,
//!     pub running: usize,
//!     pub success: usize,
//!     pub inactive: usize,
//! }
//!
//! impl Tally {
//!     /// Count `jobs` by `StatusClass::of`. Pure — no filtering, no sorting.
//!     pub fn of(jobs: &[frame::JobView]) -> Tally;
//!     pub fn count(&self, class: status::StatusClass) -> usize;
//!     pub fn total(&self) -> usize;
//!     pub fn is_empty(&self) -> bool;
//! }
//! ```
//!
//! **`departed` is excluded structurally, not by a filter.** `Frame` keeps the
//! two lists apart (`crates/nerve-hub/src/sse/frame.rs`), and callers tally
//! `frame.jobs`. A departed row is a removal hint, never a count and never a
//! reason to alarm (spec Domain basis, "全量帧 + departed").
//!
//! Determinism: literal frames, no clock, no socket, no filesystem, no hub.

mod common;

use serde_json::json;

use nerve_tmux_surface::status::StatusClass;
use nerve_tmux_surface::tally::Tally;

use common::{frame, job, SIX_STATE_FRAME};

// ── Basics ──────────────────────────────────────────────────────────────────

#[test]
fn test_the_six_state_frame_counts_one_of_each_class() {
    let decoded = frame(SIX_STATE_FRAME);

    assert_eq!(
        Tally::of(&decoded.jobs),
        Tally {
            problem: 1,
            attention: 1,
            waiting: 1,
            running: 1,
            success: 1,
            inactive: 1,
        }
    );
}

#[test]
fn test_total_is_the_sum_of_every_class() {
    let decoded = frame(SIX_STATE_FRAME);

    assert_eq!(Tally::of(&decoded.jobs).total(), 6);
}

#[test]
fn test_count_reads_the_same_numbers_as_the_fields() {
    let decoded = frame(SIX_STATE_FRAME);
    let tally = Tally::of(&decoded.jobs);

    for class in StatusClass::ALL {
        assert_eq!(tally.count(class), 1, "class {}", class.label());
    }
}

#[test]
fn test_jobs_of_the_same_class_accumulate() {
    let jobs = vec![
        job(json!({ "id": "a", "lifecycle": "active" })),
        job(json!({ "id": "b", "lifecycle": "active" })),
        job(json!({ "id": "c", "lifecycle": "active", "outcome": "failure" })),
    ];

    assert_eq!(
        Tally::of(&jobs),
        Tally {
            running: 2,
            problem: 1,
            ..Tally::default()
        }
    );
}

// ── departed never counts ───────────────────────────────────────────────────

/// The departed row of `SIX_STATE_FRAME` is a `failure` + `unresponsive` +
/// `urgent` row: were it counted, `problem` would be 2.
#[test]
fn test_departed_rows_do_not_enter_the_counts() {
    let decoded = frame(SIX_STATE_FRAME);

    assert_eq!(Tally::of(&decoded.jobs).problem, 1);
    assert_eq!(Tally::of(&decoded.jobs).total(), 6);
}

/// …and it *would* have counted, which is what makes the exclusion above a
/// fact about the two lists rather than an accident of the fixture.
#[test]
fn test_the_departed_row_is_itself_a_problem_when_tallied_alone() {
    let decoded = frame(SIX_STATE_FRAME);

    assert_eq!(
        Tally::of(&decoded.departed),
        Tally {
            problem: 1,
            ..Tally::default()
        }
    );
}

// ── Edge ────────────────────────────────────────────────────────────────────

#[test]
fn test_an_empty_frame_tallies_to_zero() {
    let decoded = frame(r#"{"jobs":[],"departed":[]}"#);

    let tally = Tally::of(&decoded.jobs);
    assert_eq!(tally, Tally::default());
    assert_eq!(tally.total(), 0);
    assert!(tally.is_empty());
}

#[test]
fn test_a_tally_with_any_count_is_not_empty() {
    let jobs = vec![job(json!({ "id": "a", "lifecycle": "suspended" }))];

    let tally = Tally::of(&jobs);
    assert!(!tally.is_empty());
    assert_eq!(tally.inactive, 1);
}

/// Counting is pure: the same slice tallied twice gives the same answer, and
/// the jobs are untouched.
#[test]
fn test_tallying_twice_gives_the_same_answer() {
    let decoded = frame(SIX_STATE_FRAME);

    assert_eq!(Tally::of(&decoded.jobs), Tally::of(&decoded.jobs));
}

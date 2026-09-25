//! Ribbon weights — the reason one problem among forty is still visible.

use nerve_surface_core::ribbon::{Run, weighted_runs};
use nerve_surface_core::status::StatusClass::{
    Attention, Inactive, Monitor, Problem, Running, Success,
};

fn weights(runs: &[(nerve_surface_core::status::StatusClass, usize)]) -> Vec<f32> {
    weighted_runs(runs)
        .iter()
        .map(|run: &Run| run.weight)
        .collect()
}

fn sums_to_one(runs: &[(nerve_surface_core::status::StatusClass, usize)]) {
    let total: f32 = weights(runs).iter().sum();
    assert!((total - 1.0).abs() < 1e-5, "weights summed to {total}");
}

#[test]
fn nothing_weighs_nothing() {
    assert!(weighted_runs(&[]).is_empty());
}

#[test]
fn one_status_takes_the_whole_strip() {
    assert_eq!(weights(&[(Running, 7)]), vec![1.0]);
}

#[test]
fn equal_counts_split_evenly() {
    let w = weights(&[(Running, 3), (Monitor, 3)]);
    assert!((w[0] - w[1]).abs() < 1e-6, "{w:?}");
    sums_to_one(&[(Running, 3), (Monitor, 3)]);
}

/// The case the floors exist for: at a true 1/41 this band would be too small
/// to see, and the one thing the ribbon is for would be invisible.
#[test]
fn a_single_problem_among_forty_running_stays_visible() {
    let runs = [(Problem, 1), (Running, 40)];
    let w = weights(&runs);
    assert!(w[0] > 0.10, "problem got {:.3} of the strip", w[0]);
    sums_to_one(&runs);
}

#[test]
fn attention_gets_the_same_floor_as_problem() {
    let problem = weights(&[(Problem, 1), (Running, 40)]);
    let attention = weights(&[(Attention, 1), (Running, 40)]);
    assert_eq!(problem, attention);
}

#[test]
fn success_gets_its_own_smaller_floor() {
    let success = weights(&[(Success, 1), (Running, 40)])[0];
    let problem = weights(&[(Problem, 1), (Running, 40)])[0];
    assert!(success > 0.08, "success got {success:.3}");
    assert!(success < problem, "success floor is below the loud one");
}

#[test]
fn a_quiet_status_has_no_floor() {
    // Inactive is chrome, not a call to action: it may shrink to nothing.
    let w = weights(&[(Inactive, 1), (Problem, 40)]);
    assert!(w[0] < 0.05, "inactive got {:.3}", w[0]);
}

#[test]
fn order_is_preserved_because_regrouping_must_reorder_the_strip() {
    let runs = weighted_runs(&[(Success, 2), (Problem, 1), (Running, 3)]);
    let classes: Vec<_> = runs.iter().map(|run| run.class).collect();
    assert_eq!(classes, vec![Success, Problem, Running]);
}

#[test]
fn counts_survive_the_weighting() {
    let runs = weighted_runs(&[(Problem, 1), (Running, 40)]);
    assert_eq!(runs[0].count, 1);
    assert_eq!(runs[1].count, 40);
}

#[test]
fn many_loud_statuses_still_sum_to_one() {
    // Every floor claimed at once overshoots 1.0 before normalising; the strip
    // must still fill exactly once rather than overflow.
    sums_to_one(&[
        (Problem, 1),
        (Attention, 1),
        (Success, 1),
        (Running, 1),
        (Monitor, 1),
        (Inactive, 1),
    ]);
}

// ── Length ──────────────────────────────────────────────────────────────────

#[test]
fn nothing_running_has_no_length() {
    assert_eq!(nerve_surface_core::ribbon::length_factor(0), 0.0);
}

#[test]
fn the_first_few_counts_are_obviously_different() {
    use nerve_surface_core::ribbon::length_factor;
    // The whole point of the ladder: one job and two jobs must not look alike.
    let steps: Vec<f32> = (1..=5).map(length_factor).collect();
    for pair in steps.windows(2) {
        assert!(pair[1] - pair[0] > 0.07, "{pair:?} too close to tell apart");
    }
}

#[test]
fn the_ladder_only_ever_climbs() {
    use nerve_surface_core::ribbon::length_factor;
    let mut previous = 0.0;
    for active in 0..200 {
        let factor = length_factor(active);
        assert!(factor >= previous, "dipped at {active}");
        assert!(factor <= 1.0, "overflowed at {active}");
        previous = factor;
    }
}

#[test]
fn a_hundred_jobs_still_fit() {
    assert_eq!(nerve_surface_core::ribbon::length_factor(1000), 1.0);
}

//! Folding seven statuses into three learnable slots.

use nerve_surface_core::palette;
use nerve_surface_core::tally::Tally;
use nerve_windows_surface::tray::bands::{has_work, stack};

fn tally(
    problem: usize,
    attention: usize,
    waiting: usize,
    running: usize,
    monitor: usize,
    success: usize,
    inactive: usize,
) -> Tally {
    Tally {
        problem,
        attention,
        waiting,
        running,
        monitor,
        success,
        inactive,
        ask: 0,
    }
}

#[test]
fn nothing_running_has_no_bands() {
    assert!(stack(&Tally::default()).is_empty());
    assert!(!has_work(&Tally::default()));
}

#[test]
fn inactive_alone_is_not_work() {
    // Inactive is chrome. An icon that lit up for it would never be dark.
    let idle = tally(0, 0, 0, 0, 0, 0, 5);
    assert!(stack(&idle).is_empty());
    assert!(!has_work(&idle));
}

#[test]
fn one_status_is_one_band() {
    let bands = stack(&tally(0, 0, 0, 4, 0, 0, 0));
    assert_eq!(bands.len(), 1);
    assert_eq!(bands[0].color, palette::RUNNING);
    assert_eq!(bands[0].count, 4);
}

#[test]
fn the_slots_keep_their_order_whatever_is_present() {
    // Top is always "needs you", middle always "happening", bottom always
    // "finished" — three positions to learn instead of seven stripes to read.
    let bands = stack(&tally(1, 0, 0, 2, 0, 3, 0));
    let colors: Vec<_> = bands.iter().map(|band| band.color).collect();
    assert_eq!(
        colors,
        vec![palette::PROBLEM, palette::RUNNING, palette::SUCCESS]
    );
}

#[test]
fn an_empty_slot_is_dropped_rather_than_drawn() {
    let bands = stack(&tally(1, 0, 0, 0, 0, 2, 0));
    assert_eq!(bands.len(), 2);
    assert_eq!(bands[0].color, palette::PROBLEM);
    assert_eq!(bands[1].color, palette::SUCCESS);
}

#[test]
fn a_slot_merges_its_pair_into_one_count() {
    let bands = stack(&tally(2, 3, 0, 0, 0, 0, 0));
    assert_eq!(bands.len(), 1);
    assert_eq!(bands[0].count, 5);
}

#[test]
fn the_louder_of_a_pair_names_the_colour() {
    // A problem is not an attention, and a monitor is not a success.
    assert_eq!(
        stack(&tally(1, 9, 0, 0, 0, 0, 0))[0].color,
        palette::PROBLEM
    );
    assert_eq!(
        stack(&tally(0, 0, 0, 0, 1, 9, 0))[0].color,
        palette::MONITOR
    );
}

#[test]
fn the_quieter_of_a_pair_names_it_when_alone() {
    assert_eq!(
        stack(&tally(0, 3, 0, 0, 0, 0, 0))[0].color,
        palette::ATTENTION
    );
    assert_eq!(
        stack(&tally(0, 0, 0, 0, 0, 3, 0))[0].color,
        palette::SUCCESS
    );
    // Waiting shares attention's colour and its slot is the running one.
    let waiting = stack(&tally(0, 0, 2, 0, 0, 0, 0));
    assert_eq!(waiting[0].color, palette::ATTENTION);
}

#[test]
fn weights_across_the_stack_sum_to_one() {
    let bands = stack(&tally(1, 0, 0, 40, 0, 2, 0));
    let total: f32 = bands.iter().map(|band| band.weight).sum();
    assert!((total - 1.0).abs() < 1e-5, "{total}");
}

#[test]
fn one_problem_among_forty_running_keeps_a_visible_share() {
    let bands = stack(&tally(1, 0, 0, 40, 0, 0, 0));
    assert!(bands[0].weight > 0.10, "problem got {:.3}", bands[0].weight);
}

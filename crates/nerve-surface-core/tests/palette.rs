//! The six product colours, and the rules that keep them six.

use nerve_surface_core::palette::{self, Rgb};
use nerve_surface_core::status::StatusClass;

#[test]
fn the_documented_hex_values_are_what_ship() {
    // These strings appear in `SettingsStore.swift`, in the tmux palette's doc
    // comment and on the site. If one of them changes, it changes here first.
    assert_eq!(palette::PROBLEM.hex(), "#FF3B30");
    assert_eq!(palette::ATTENTION.hex(), "#FF9F0A");
    assert_eq!(palette::RUNNING.hex(), "#0A84FF");
    assert_eq!(palette::MONITOR.hex(), "#BF5AF2");
    assert_eq!(palette::SUCCESS.hex(), "#30D158");
    assert_eq!(palette::INACTIVE.hex(), "#8E8E93");
}

#[test]
fn waiting_shares_attention_so_needs_a_look_is_one_colour() {
    assert_eq!(
        palette::color_of(StatusClass::Waiting),
        palette::color_of(StatusClass::Attention)
    );
}

#[test]
fn every_status_paints_one_of_six() {
    let all = [
        StatusClass::Problem,
        StatusClass::Attention,
        StatusClass::Waiting,
        StatusClass::Running,
        StatusClass::Monitor,
        StatusClass::Success,
        StatusClass::Inactive,
    ];
    let mut seen: Vec<Rgb> = all.iter().map(|c| palette::color_of(*c)).collect();
    seen.sort_by_key(|c| (c.r, c.g, c.b));
    seen.dedup();
    assert_eq!(seen.len(), 6, "seven statuses, six colours");
}

#[test]
fn blending_zero_changes_nothing_and_one_arrives() {
    assert_eq!(
        palette::PROBLEM.blend(palette::WHITE, 0.0),
        palette::PROBLEM
    );
    assert_eq!(palette::PROBLEM.blend(palette::WHITE, 1.0), palette::WHITE);
}

#[test]
fn a_lift_moves_towards_the_blend_target() {
    let lifted = palette::RUNNING.blend(palette::WHITE, 0.04);
    assert!(lifted.r > palette::RUNNING.r, "lift brightens");
    assert!(lifted.r - palette::RUNNING.r < 20, "and only slightly");
}

#[test]
fn a_fraction_outside_the_range_is_clamped() {
    assert_eq!(
        palette::PROBLEM.blend(palette::WHITE, -1.0),
        palette::PROBLEM
    );
    assert_eq!(palette::PROBLEM.blend(palette::WHITE, 9.0), palette::WHITE);
}

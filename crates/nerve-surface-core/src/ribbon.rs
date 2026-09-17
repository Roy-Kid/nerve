//! How much of the ribbon each status gets.
//!
//! Not proportions. A single problem among forty running jobs is the thing the
//! ribbon exists to show, and at a true `1/41` it would be two pixels wide. So
//! the loud statuses reserve a floor first, and what is left is shared out
//! among the quiet ones. Ported from `SubjectStore.weightedStatusRuns`, which
//! the macOS menu bar has always drawn with.
//!
//! A Windows tray icon is 16 pixels square and cannot show a strip at all, so
//! it folds the same weights into stacked bands — same arithmetic, different
//! geometry. That is why this lives here rather than in a surface.

use crate::status::StatusClass;

/// The smallest share a loud status may have.
const MIN_HIGH: f32 = 0.12;
/// The smallest share a finished-well status may have.
const MIN_SUCCESS: f32 = 0.10;

/// One band of colour, and how much of the whole it occupies.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Run {
    pub class: StatusClass,
    pub count: usize,
    /// Share of the ribbon, in `0.0..=1.0`. All the runs sum to 1.
    pub weight: f32,
}

/// Does this status get the high-priority floor?
///
/// Problem, attention and waiting: the three a person is meant to act on.
fn is_high_priority(class: StatusClass) -> bool {
    matches!(
        class,
        StatusClass::Problem | StatusClass::Attention | StatusClass::Waiting
    )
}

/// Turn `(class, count)` pairs into weights that sum to 1.
///
/// Order is preserved — the caller decides what left-to-right means, and the
/// ribbon's whole trick is that regrouping visibly reorders it.
pub fn weighted_runs(runs: &[(StatusClass, usize)]) -> Vec<Run> {
    if runs.is_empty() {
        return Vec::new();
    }
    let total = runs.iter().map(|(_, count)| *count).sum::<usize>().max(1) as f32;

    // Loud statuses take their floor off the top; the quiet ones share what is
    // left in proportion to each other.
    let mut weights: Vec<f32> = Vec::with_capacity(runs.len());
    let mut reserved = 0.0_f32;
    let mut free_count = 0.0_f32;
    for (class, count) in runs {
        let share = *count as f32 / total;
        if is_high_priority(*class) {
            let weight = share.max(MIN_HIGH);
            reserved += weight;
            weights.push(weight);
        } else if *class == StatusClass::Success {
            let weight = share.max(MIN_SUCCESS);
            reserved += weight;
            weights.push(weight);
        } else {
            free_count += *count as f32;
            weights.push(-1.0);
        }
    }

    let free_budget = (1.0 - reserved).max(0.0001);
    for (index, weight) in weights.iter_mut().enumerate() {
        if *weight >= 0.0 {
            continue;
        }
        let count = runs[index].1 as f32;
        *weight = if free_count > 0.0 {
            (count / free_count) * free_budget
        } else {
            0.0
        };
    }

    // The floors can push the total past 1, so normalise rather than clip:
    // every run keeps its relative size and the strip still fills exactly once.
    let sum: f32 = weights.iter().sum();
    runs.iter()
        .zip(weights)
        .map(|((class, count), weight)| Run {
            class: *class,
            count: *count,
            weight: if sum > 0.0 { weight / sum } else { 0.0 },
        })
        .collect()
}

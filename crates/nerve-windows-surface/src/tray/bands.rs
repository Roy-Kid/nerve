//! A tally, folded into at most three stacked bands.
//!
//! A menu-bar ribbon is a hundred points wide and can give every status its own
//! stripe. A notification-area icon is sixteen pixels square and cannot. So the
//! seven statuses collapse into three fixed slots, and a slot that has nothing
//! in it is dropped rather than drawn empty:
//!
//! | slot | statuses            | reads as        |
//! |------|---------------------|-----------------|
//! | 1    | problem, attention  | something needs you |
//! | 2    | running, waiting    | work is happening   |
//! | 3    | monitor, success    | work finished       |
//!
//! Slots keep their order whatever is present, so the top band always means
//! the same thing. That is the whole reason to fold rather than to shrink: a
//! person learns three positions, not seven two-pixel stripes.

use nerve_surface_core::palette::{self, Rgb};
use nerve_surface_core::ribbon::weighted_runs;
use nerve_surface_core::status::StatusClass;
use nerve_surface_core::tally::Tally;

/// One bar in the stack.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Band {
    pub color: Rgb,
    /// Share of the icon's width, in `0.0..=1.0`.
    pub weight: f32,
    /// How many jobs this band stands for.
    pub count: usize,
}

/// The three slots, in the order they are stacked.
///
/// The first class listed is the one whose colour wins when both are present:
/// a problem is not an attention, and a monitor is not a success.
const SLOTS: [(StatusClass, StatusClass); 3] = [
    (StatusClass::Problem, StatusClass::Attention),
    (StatusClass::Running, StatusClass::Waiting),
    (StatusClass::Monitor, StatusClass::Success),
];

/// Fold `tally` into the bands to draw, top to bottom.
///
/// Empty when there is nothing running at all — the caller draws its idle mark
/// rather than an empty stack.
pub fn stack(tally: &Tally) -> Vec<Band> {
    let mut present: Vec<(StatusClass, usize)> = Vec::with_capacity(SLOTS.len());
    for (dominant, other) in SLOTS {
        let count = tally.count(dominant) + tally.count(other);
        if count == 0 {
            continue;
        }
        // Whichever of the pair is actually there decides the colour; the
        // dominant one wins a tie because it is the louder reading.
        let class = if tally.count(dominant) > 0 {
            dominant
        } else {
            other
        };
        present.push((class, count));
    }

    weighted_runs(&present)
        .into_iter()
        .map(|run| Band {
            color: palette::color_of(run.class),
            weight: run.weight,
            count: run.count,
        })
        .collect()
}

/// Whether the icon has any work to show.
///
/// Inactive jobs deliberately do not count: they are chrome, and an icon that
/// lit up for them would never be dark.
pub fn has_work(tally: &Tally) -> bool {
    SLOTS
        .iter()
        .any(|(a, b)| tally.count(*a) + tally.count(*b) > 0)
}

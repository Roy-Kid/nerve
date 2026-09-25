//! Counting a frame's jobs by derived class.
//!
//! Pure arithmetic: no filtering, no sorting, no opinion about what a count
//! means. `departed` never reaches here — [`crate::frame::Frame`] keeps the two
//! lists apart and callers tally `frame.jobs`, so a removal hint cannot become
//! a count by accident.

use crate::frame::JobView;
use crate::status::{StatusClass, is_ask_elevated};

/// One count per [`StatusClass`], plus `{ask}` for interruptible human asks.
///
/// Public fields so a caller — and a test — can state a whole expectation in
/// one literal.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Tally {
    pub problem: usize,
    pub attention: usize,
    pub waiting: usize,
    pub running: usize,
    pub monitor: usize,
    pub success: usize,
    pub inactive: usize,
    /// Ask reasons at `level ≥ suggested` — soft status-line reminder count.
    /// Independent of paint: Wait still increments `attention`, not `ask`.
    pub ask: usize,
}

impl Tally {
    /// Count `jobs` by [`StatusClass::of`] and Ask elevation.
    pub fn of(jobs: &[JobView]) -> Self {
        let mut tally = Self::default();
        for job in jobs {
            *tally.slot(StatusClass::of(job)) += 1;
            if is_ask_elevated(job) {
                tally.ask += 1;
            }
        }
        tally
    }

    /// How many jobs landed on `class`.
    pub fn count(&self, class: StatusClass) -> usize {
        match class {
            StatusClass::Problem => self.problem,
            StatusClass::Attention => self.attention,
            StatusClass::Waiting => self.waiting,
            StatusClass::Running => self.running,
            StatusClass::Monitor => self.monitor,
            StatusClass::Success => self.success,
            StatusClass::Inactive => self.inactive,
        }
    }

    /// Every counted job, whatever its class.
    pub fn total(&self) -> usize {
        self.problem
            + self.attention
            + self.waiting
            + self.running
            + self.monitor
            + self.success
            + self.inactive
    }

    /// Whether there is nothing at all to paint.
    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }

    fn slot(&mut self, class: StatusClass) -> &mut usize {
        match class {
            StatusClass::Problem => &mut self.problem,
            StatusClass::Attention => &mut self.attention,
            StatusClass::Waiting => &mut self.waiting,
            StatusClass::Running => &mut self.running,
            StatusClass::Monitor => &mut self.monitor,
            StatusClass::Success => &mut self.success,
            StatusClass::Inactive => &mut self.inactive,
        }
    }
}

//! Status filter bar — same six buckets as tmux-agent-sidebar, mapped onto
//! Nerve's derived [`crate::status::StatusClass`].

use crate::frame::JobView;
use crate::status::StatusClass;

/// Filter buckets shown in the sidebar header (`≡ ● ◎ ◐ ○ ✕`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum StatusFilter {
    #[default]
    All,
    Running,
    Background,
    Waiting,
    Idle,
    Error,
}

impl StatusFilter {
    pub const ALL: [Self; 6] = [
        Self::All,
        Self::Running,
        Self::Background,
        Self::Waiting,
        Self::Idle,
        Self::Error,
    ];

    pub fn next(self) -> Self {
        let idx = Self::ALL.iter().position(|f| *f == self).unwrap_or(0);
        Self::ALL[(idx + 1) % Self::ALL.len()]
    }

    pub fn prev(self) -> Self {
        let idx = Self::ALL.iter().position(|f| *f == self).unwrap_or(0);
        Self::ALL[(idx + Self::ALL.len() - 1) % Self::ALL.len()]
    }

    pub fn matches(self, job: &JobView) -> bool {
        self.matches_class(StatusClass::of(job), is_background(job))
    }

    pub fn count(self, jobs: &[JobView]) -> usize {
        jobs.iter().filter(|job| self.matches(job)).count()
    }

    /// Every bucket's count in one pass, in [`Self::ALL`] order.
    ///
    /// The filter bar needs all six on every draw; counting them separately
    /// re-derives each job's [`StatusClass`] once per bucket.
    pub fn counts(jobs: &[JobView]) -> [usize; Self::ALL.len()] {
        let mut counts = [0usize; Self::ALL.len()];
        for job in jobs {
            let class = StatusClass::of(job);
            let background = is_background(job);
            for (slot, filter) in counts.iter_mut().zip(Self::ALL) {
                if filter.matches_class(class, background) {
                    *slot += 1;
                }
            }
        }
        counts
    }

    /// Bucket test over already-derived facts about a job.
    fn matches_class(self, class: StatusClass, background: bool) -> bool {
        match self {
            Self::All => true,
            Self::Running => class == StatusClass::Running,
            Self::Background => background,
            Self::Waiting => matches!(class, StatusClass::Waiting | StatusClass::Attention),
            Self::Idle => matches!(class, StatusClass::Inactive | StatusClass::Success),
            Self::Error => class == StatusClass::Problem,
        }
    }
}

/// Background-style work: monitor phase or long-running current summary.
fn is_background(job: &JobView) -> bool {
    if let Some(current) = &job.current {
        if current.kind.eq_ignore_ascii_case("monitor") {
            return true;
        }
    }
    false
}

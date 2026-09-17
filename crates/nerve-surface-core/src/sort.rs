//! One order for every surface's job list.
//!
//! The rule is the macOS store's `sortComparator` (`SubjectStore.swift`), and
//! it is applied once per snapshot rather than per section: a filter preserves
//! order, so every grouping inherits the same sort.
//!
//! `now` is a parameter, never sampled here. Jobs that report no `updatedAt`
//! fall back to it, so a comparator that resampled the clock would stop being
//! a consistent ordering — two such jobs would never tie, and `createdAt`
//! would never get to decide.

use std::cmp::Ordering;

use time::OffsetDateTime;

use crate::frame::{Health, JobView, Outcome};

/// Loudest first: attention, then health, then failure, then recency.
///
/// Same ordering as macOS `SubjectStore.sortComparator`.
pub fn compare_jobs(now: OffsetDateTime, a: &JobView, b: &JobView) -> Ordering {
    match a.attention.level.cmp(&b.attention.level).reverse() {
        Ordering::Equal => {}
        o => return o,
    }
    match health_rank(a.health).cmp(&health_rank(b.health)).reverse() {
        Ordering::Equal => {}
        o => return o,
    }
    let a_fail = a.outcome == Some(Outcome::Failure);
    let b_fail = b.outcome == Some(Outcome::Failure);
    if a_fail != b_fail {
        return if a_fail && !b_fail {
            Ordering::Less
        } else {
            Ordering::Greater
        };
    }
    match job_updated(now, a).cmp(&job_updated(now, b)).reverse() {
        Ordering::Equal => {}
        o => return o,
    }
    job_started(now, a).cmp(&job_started(now, b)).reverse()
}

fn health_rank(health: Health) -> u8 {
    match health {
        Health::Unresponsive => 3,
        Health::Degraded => 2,
        Health::Unknown => 1,
        Health::Ok => 0,
    }
}

fn job_updated(now: OffsetDateTime, job: &JobView) -> OffsetDateTime {
    job.updated_at.map(|t| t.instant()).unwrap_or(now)
}

fn job_started(now: OffsetDateTime, job: &JobView) -> OffsetDateTime {
    job.created_at
        .map(|t| t.instant())
        .unwrap_or_else(|| job_updated(now, job))
}

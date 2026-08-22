//! Per-job observation log.
//!
//! Small on purpose: a panel detail strip, not a history product. Newest first,
//! capped per job, and heartbeats never enter (`SubjectStore.swift:836`).

use std::collections::BTreeMap;

use serde::Serialize;

use crate::model::{EventKind, WireTime};

/// Entries kept per job. Older observations fall off the end.
pub const MAX_TIMELINE_PER_JOB: usize = 40;

/// One observation about a job.
///
/// `id` is opaque and only has to be stable within a hub run, so it is a
/// sequence number rather than a uuid dependency.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineEntry {
    pub id: String,
    pub job_id: String,
    pub kind: String,
    pub title: String,
    pub timestamp: WireTime,
}

/// Every job's timeline, owned by the store and published inside each job.
#[derive(Debug, Default)]
pub struct Timelines {
    entries: BTreeMap<String, Vec<TimelineEntry>>,
    recorded: u64,
}

impl Timelines {
    /// Append an observation, newest first.
    ///
    /// Heartbeats are dropped: they say "still here", which the job's own
    /// `updatedAt` already says.
    pub fn record(&mut self, job_id: &str, kind: &str, title: String, at: WireTime) {
        if kind == EventKind::Heartbeat.wire() {
            return;
        }
        self.recorded = self.recorded.saturating_add(1);
        let entry = TimelineEntry {
            id: format!("tl-{}", self.recorded),
            job_id: job_id.to_string(),
            kind: kind.to_string(),
            title,
            timestamp: at,
        };
        let list = self.entries.entry(job_id.to_string()).or_default();
        list.insert(0, entry);
        list.truncate(MAX_TIMELINE_PER_JOB);
    }

    /// Newest-first entries for one job; empty when the job has none.
    pub fn of(&self, job_id: &str) -> &[TimelineEntry] {
        self.entries.get(job_id).map_or(&[], Vec::as_slice)
    }

    pub fn forget(&mut self, job_id: &str) {
        self.entries.remove(job_id);
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }
}

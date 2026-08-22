//! At-most-once event application.
//!
//! Hooks retry and fan out, so the same event id can arrive twice. Remembering
//! ids bounds that at the cost of a fixed-size window (`SubjectStore.swift:26`).

use std::collections::{HashSet, VecDeque};

/// How many event ids stay remembered before the oldest are forgotten.
pub const MAX_SEEN_EVENTS: usize = 4_000;

/// How many ids are dropped once the window overflows — batching keeps the
/// eviction cost amortised instead of paying it on every insert
/// (`SubjectStore.swift:860`).
pub const SEEN_EVENT_EVICT_BATCH: usize = 500;

/// The sliding window of applied event ids.
#[derive(Debug, Default)]
pub struct SeenEvents {
    ids: HashSet<String>,
    order: VecDeque<String>,
}

impl SeenEvents {
    /// Record `id` as applied.
    ///
    /// Returns `false` when it was already applied — the caller must then
    /// ignore the event entirely.
    pub fn remember(&mut self, id: &str) -> bool {
        if !self.ids.insert(id.to_string()) {
            return false;
        }
        self.order.push_back(id.to_string());
        if self.order.len() > MAX_SEEN_EVENTS {
            self.evict_oldest();
        }
        true
    }

    pub fn clear(&mut self) {
        self.ids.clear();
        self.order.clear();
    }

    fn evict_oldest(&mut self) {
        for _ in 0..SEEN_EVENT_EVICT_BATCH {
            let Some(oldest) = self.order.pop_front() else {
                break;
            };
            self.ids.remove(&oldest);
        }
    }
}

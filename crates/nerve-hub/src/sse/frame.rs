//! What one SSE frame says.
//!
//! There is no delta protocol (spec D4): every frame carries the authoritative
//! full job set, so a surface that just connected, one that reconnected after an
//! hour and one that has been listening all along all end up in the same state.
//!
//! `departed` exists because eviction is immediate — a session that ends is
//! gone from `jobs` in the same breath (`SubjectStore.swift:699`), so a plain
//! frame-to-frame diff would lose its terminal state. It is a hint, never the
//! authority: `jobs` is.

use serde::Serialize;
use serde_json::Value;

use crate::state::JobStore;

/// One frame: two keys, forever.
#[derive(Debug, Serialize)]
pub struct Frame {
    jobs: Value,
    departed: Value,
}

impl Frame {
    /// The frame a joining surface gets.
    ///
    /// Nothing is taken from the departed buffer: it belongs to every
    /// subscriber, and a surface that has just arrived has no earlier frame to
    /// reconcile it with anyway.
    pub fn connect(store: &JobStore) -> Self {
        Self {
            jobs: store.jobs_json(),
            departed: Value::Array(Vec::new()),
        }
    }

    /// The frame a change produces: the full set, plus the terminal states
    /// buffered since the previous frame, which this one drains.
    pub fn published(store: &mut JobStore) -> Self {
        Self {
            departed: store.drain_departed_json(),
            jobs: store.jobs_json(),
        }
    }

    /// Compact JSON on a single line.
    ///
    /// An SSE `data:` field may not be split across lines without changing what
    /// it means, so the frame must never be pretty-printed.
    pub fn render(&self) -> String {
        // Plain data built from two `serde_json::Value`s: serialising it cannot
        // fail. The fallback keeps the shape rather than the content, because a
        // frame with the wrong keys would break a surface's parser outright.
        serde_json::to_string(self).unwrap_or_else(|_| r#"{"jobs":[],"departed":[]}"#.to_string())
    }
}

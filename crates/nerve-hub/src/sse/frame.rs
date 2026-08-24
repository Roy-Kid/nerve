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
//!
//! A frame borrows the store rather than copying it. Rendering is the hub's
//! hottest work — one full job set per coalescing window, every window in which
//! anything moved — so it serialises the stored jobs in a single pass instead
//! of building a `serde_json::Value` tree and walking it again to write it out.

use serde::Serialize;

use crate::model::Job;
use crate::state::{JobStore, JobView, JobsSeq};

/// One frame: two keys, forever.
pub struct Frame<'a> {
    store: &'a JobStore,
    /// Owned because draining is what makes them this frame's — the store no
    /// longer has them to lend.
    departed: Vec<Job>,
}

/// The wire shape, assembled only for the length of one [`Frame::render`].
///
/// `jobs` is a seq wrapper so the renderer never materialises a `Vec<JobView>`
/// just to throw it away after `serde` walks it.
#[derive(Serialize)]
struct Wire<'a> {
    jobs: JobsSeq<'a>,
    departed: Vec<JobView<'a>>,
}

impl<'a> Frame<'a> {
    /// The frame a joining surface gets.
    ///
    /// Nothing is taken from the departed buffer: it belongs to every
    /// subscriber, and a surface that has just arrived has no earlier frame to
    /// reconcile it with anyway.
    pub fn connect(store: &'a JobStore) -> Self {
        Self {
            store,
            departed: Vec::new(),
        }
    }

    /// The frame a change produces: the full set, plus the terminal states
    /// buffered since the previous frame, which this one drains.
    pub fn published(store: &'a mut JobStore) -> Self {
        let departed = store.drain_departed_deduped();
        Self {
            store: &*store,
            departed,
        }
    }

    /// Compact JSON on a single line.
    ///
    /// An SSE `data:` field may not be split across lines without changing what
    /// it means, so the frame must never be pretty-printed.
    pub fn render(&self) -> String {
        let wire = Wire {
            jobs: JobsSeq(self.store),
            departed: self.departed.iter().map(JobView::departed).collect(),
        };
        // Sized for a quiet hub (empty set) and grown by serde; a busy one
        // still writes once into this buffer instead of building a Value tree.
        let mut buf = Vec::with_capacity(64 + self.store.job_count() * 384);
        // Plain data borrowed from the store: serialising it cannot fail. The
        // fallback keeps the shape rather than the content, because a frame
        // with the wrong keys would break a surface's parser outright.
        match serde_json::to_writer(&mut buf, &wire) {
            Ok(()) => String::from_utf8(buf)
                .unwrap_or_else(|_| r#"{"jobs":[],"departed":[]}"#.to_string()),
            Err(_) => r#"{"jobs":[],"departed":[]}"#.to_string(),
        }
    }
}

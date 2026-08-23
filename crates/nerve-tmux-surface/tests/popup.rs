//! `popup.rs` — the read-only job list behind `prefix + N` (spec T8 ·
//! acceptance A8, unit half).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/popup.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_tmux_surface::popup
//!
//! /// What a popup with nothing to show prints.
//! pub const EMPTY: &str = "nerve: no jobs";
//!
//! pub struct PopupRenderer { /* now */ }
//!
//! impl PopupRenderer {
//!     /// The instant ages are measured against.
//!     ///
//!     /// A frozen reading rather than a `Clock` trait: `display-popup -E`
//!     /// runs a one-shot process that renders once and exits, so "now" is
//!     /// read exactly once, at the composition root. That makes this the
//!     /// injection point *and* removes a port nobody would implement twice.
//!     pub fn at(now: time::OffsetDateTime) -> Self;
//!
//!     /// One line per job, in the order given.
//!     pub fn render(&self, jobs: &[frame::JobView]) -> String;
//! }
//! ```
//!
//! ─────────────────────────────────────────────────────────────────────────
//! ROW FORMAT (pinned here so the implementer has no latitude)
//! ─────────────────────────────────────────────────────────────────────────
//!
//! `producer  name  status  attention  age`, two spaces between columns, the
//! first four left-aligned and padded to the widest cell **in this render**,
//! the last unpadded. Every line ends with `\n`, including the last.
//!
//! | column | value |
//! |--------|-------|
//! | producer | `producer.name`, else `producer.id`, else `-` |
//! | name | `name`, else `-` |
//! | status | `StatusClass::of(job).label()` |
//! | attention | `attention.reason`, else the level when it is above `none`, else `-` |
//! | age | `now - updatedAt` as `<60s`→`Ns`, `<60m`→`Nm`, `<24h`→`Nh`, else `Nd`; `-` when the job carries no `updatedAt` |
//!
//! No `#` escaping: a popup is plain stdout, not a tmux option value, so
//! `summary::escape_dynamic` must **not** be applied here.
//!
//! Read-only is structural: `render` takes job facts and answers a string.
//! There is no action, no key, no callback to add one to (CLAUDE.md
//! invariant 6).
//!
//! Determinism: injected instant, compile-time fixture, literal jobs. No
//! clock, no socket, no filesystem at run time, no hub.

mod common;

use serde_json::json;
use time::macros::datetime;
use time::OffsetDateTime;

use nerve_tmux_surface::frame::JobView;
use nerve_tmux_surface::popup::{PopupRenderer, EMPTY};

use common::job;

/// Five minutes after `fixtures/demo_snapshot.json` last updated its rows.
const NOW: OffsetDateTime = datetime!(2026-07-19 08:15:00 UTC);

fn render(jobs: &[JobView]) -> String {
    PopupRenderer::at(NOW).render(jobs)
}

/// A row whose four padded columns are always `demo` / `j` / `running` / `-`,
/// so an age assertion can be a whole-line golden.
fn aged(updated_at: &str) -> String {
    render(&[job(json!({
        "id": "demo:j",
        "name": "j",
        "lifecycle": "active",
        "producer": { "id": "demo" },
        "updatedAt": updated_at
    }))])
}

// ── The fixture, golden ─────────────────────────────────────────────────────

/// `fixtures/demo_snapshot.json` rendered at a fixed instant, hard-coded.
#[test]
fn test_the_demo_fixture_renders_the_golden_popup() {
    let rendered = render(&common::demo_jobs());

    assert_eq!(
        rendered,
        "Demo  nerve             running  -  5m\n\
         Demo  xcodebuild Nerve  running  -  5m\n"
    );
}

/// Columns are padded to the widest cell, so the second row's longer name sets
/// the width of the first row's.
#[test]
fn test_columns_line_up_across_rows() {
    let rendered = render(&common::demo_jobs());

    let starts: Vec<usize> = rendered
        .lines()
        .map(|line| line.find("running").expect("every row shows its status"))
        .collect();
    assert_eq!(starts, vec![24, 24]);
}

// ── One row, column by column ───────────────────────────────────────────────

#[test]
fn test_a_row_shows_producer_name_status_attention_and_age() {
    let rendered = render(&[job(json!({
        "id": "claude-code:s1",
        "name": "nerve",
        "lifecycle": "active",
        "current": { "type": "idle" },
        "attention": { "level": "required", "reason": "input" },
        "producer": { "id": "claude-code", "name": "Claude Code" },
        "updatedAt": "2026-07-19T08:14:30Z"
    }))]);

    assert_eq!(rendered, "Claude Code  nerve  attention  input  30s\n");
}

#[test]
fn test_a_producer_without_a_name_falls_back_to_its_id() {
    let rendered = render(&[job(json!({
        "id": "xcode:build",
        "name": "Nerve",
        "lifecycle": "active",
        "producer": { "id": "xcode" },
        "updatedAt": "2026-07-19T08:14:00Z"
    }))]);

    assert_eq!(rendered, "xcode  Nerve  running  -  1m\n");
}

#[test]
fn test_an_anonymous_row_still_renders_every_column() {
    let rendered = render(&[job(json!({ "id": "orphan" }))]);

    assert_eq!(rendered, "-  -  running  -  -\n");
}

#[test]
fn test_an_elevated_attention_without_a_reason_shows_its_level() {
    let rendered = render(&[job(json!({
        "id": "demo:j",
        "name": "j",
        "lifecycle": "active",
        "attention": { "level": "urgent" },
        "producer": { "id": "demo" },
        "updatedAt": "2026-07-19T08:15:00Z"
    }))]);

    assert_eq!(rendered, "demo  j  attention  urgent  0s\n");
}

// ── Ages ────────────────────────────────────────────────────────────────────

#[test]
fn test_an_age_under_a_minute_is_seconds() {
    assert_eq!(aged("2026-07-19T08:15:00Z"), "demo  j  running  -  0s\n");
    assert_eq!(aged("2026-07-19T08:14:01Z"), "demo  j  running  -  59s\n");
}

#[test]
fn test_a_full_minute_becomes_minutes() {
    assert_eq!(aged("2026-07-19T08:14:00Z"), "demo  j  running  -  1m\n");
    assert_eq!(aged("2026-07-19T07:16:00Z"), "demo  j  running  -  59m\n");
}

#[test]
fn test_a_full_hour_becomes_hours() {
    assert_eq!(aged("2026-07-19T07:15:00Z"), "demo  j  running  -  1h\n");
    assert_eq!(aged("2026-07-18T09:15:00Z"), "demo  j  running  -  23h\n");
}

#[test]
fn test_a_full_day_becomes_days() {
    assert_eq!(aged("2026-07-18T08:15:00Z"), "demo  j  running  -  1d\n");
    assert_eq!(aged("2026-07-09T08:15:00Z"), "demo  j  running  -  10d\n");
}

/// A producer whose clock runs ahead must not print a negative age.
#[test]
fn test_a_future_timestamp_reads_as_zero_seconds() {
    assert_eq!(aged("2026-07-19T08:20:00Z"), "demo  j  running  -  0s\n");
}

#[test]
fn test_a_job_without_an_updated_at_has_no_age() {
    let rendered = render(&[job(json!({
        "id": "demo:j",
        "name": "j",
        "lifecycle": "active",
        "producer": { "id": "demo" }
    }))]);

    assert_eq!(rendered, "demo  j  running  -  -\n");
}

// ── Edge ────────────────────────────────────────────────────────────────────

#[test]
fn test_an_empty_job_list_says_so() {
    assert_eq!(render(&[]), format!("{EMPTY}\n"));
}

#[test]
fn test_the_empty_text_is_the_literal_the_docs_publish() {
    assert_eq!(EMPTY, "nerve: no jobs");
}

/// Ordering belongs to the hub; the popup shows what it was handed.
#[test]
fn test_rows_keep_the_order_they_were_given() {
    let jobs = vec![
        job(json!({ "id": "b", "name": "b", "lifecycle": "active", "producer": { "id": "p" } })),
        job(
            json!({ "id": "a", "name": "a", "lifecycle": "active", "outcome": "failure",
                    "producer": { "id": "p" } }),
        ),
    ];

    let rendered = render(&jobs);

    let names: Vec<&str> = rendered
        .lines()
        .map(|line| {
            line.split_whitespace()
                .nth(1)
                .expect("every row has a name")
        })
        .collect();
    assert_eq!(names, vec!["b", "a"]);
}

/// A popup is stdout, not a tmux option value: the escaping `summary.rs` does
/// would show up here as a bug.
#[test]
fn test_a_hash_in_a_job_name_is_not_escaped() {
    let rendered = render(&[job(json!({
        "id": "demo:j",
        "name": "fix #42",
        "lifecycle": "active",
        "producer": { "id": "demo" },
        "updatedAt": "2026-07-19T08:10:00Z"
    }))]);

    assert_eq!(rendered, "demo  fix #42  running  -  5m\n");
}

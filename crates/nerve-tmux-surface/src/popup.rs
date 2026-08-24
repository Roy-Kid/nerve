//! The read-only job list behind `prefix + N`.
//!
//! Read-only is structural, not a policy: [`PopupRenderer::render`] takes job
//! facts and answers a string. There is no action, no key and no callback to
//! hang one on (CLAUDE.md invariant 6).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! Row format: `{icon}  {name}  {activity}  {age}`, two spaces between the
//! padded name and activity columns, age unpadded. Status is a coloured glyph
//! in the sidebar; here it is the same icon without escape codes. Every line
//! ends with `\n`.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! A popup is plain stdout, not a tmux option value, so
//! [`crate::summary::escape_dynamic`] must not be applied here: a job called
//! `fix #42` is printed as `fix #42`.

use time::OffsetDateTime;

use crate::columns::{self, activity_text, cell_text, GAP};
use crate::frame::JobView;
use crate::icons;
use crate::status::StatusClass;

/// What a popup with nothing to show prints.
pub const EMPTY: &str = "nerve: no jobs";

/// The two padded columns: session name and current activity.
const PADDED_COLUMNS: usize = 2;

/// Renders job rows against one frozen reading of the clock.
pub struct PopupRenderer {
    now: OffsetDateTime,
}

impl PopupRenderer {
    /// The instant ages are measured against.
    ///
    /// A frozen reading rather than a `Clock` port: `display-popup -E` runs a
    /// one-shot process that renders once and exits, so "now" is read exactly
    /// once, at the composition root. That makes this the injection point and
    /// removes a port nobody would implement twice.
    pub fn at(now: OffsetDateTime) -> Self {
        Self { now }
    }

    /// One line per job, in the order given. Ordering belongs to the hub.
    pub fn render(&self, jobs: &[JobView]) -> String {
        if jobs.is_empty() {
            return format!("{EMPTY}\n");
        }

        let rows: Vec<Vec<String>> = jobs
            .iter()
            .map(|job| {
                vec![
                    cell_text(&job.name).to_string(),
                    cell_text(activity_text(job)).to_string(),
                    self.age(job),
                ]
            })
            .collect();
        let padded = columns::pad_columns(&rows, PADDED_COLUMNS);

        let mut rendered = String::new();
        for (job, row) in jobs.iter().zip(padded) {
            let class = StatusClass::of(job);
            rendered.push_str(icons::status_icon(class));
            rendered.push(' ');
            rendered.push_str(&row[0]);
            rendered.push_str(GAP);
            rendered.push_str(&row[1]);
            rendered.push(' ');
            rendered.push_str(&row[2]);
            rendered.push('\n');
        }
        rendered
    }

    /// How long ago the job last said anything.
    fn age(&self, job: &JobView) -> String {
        columns::age_label(self.now, job)
    }
}

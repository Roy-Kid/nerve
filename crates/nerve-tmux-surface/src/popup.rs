//! The read-only job list behind `prefix + N`.
//!
//! Read-only is structural, not a policy: [`PopupRenderer::render`] takes job
//! facts and answers a string. There is no action, no key and no callback to
//! hang one on (CLAUDE.md invariant 6).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! Row format: `producer  name  status  attention  age`, two spaces between
//! columns, the first four left-aligned and padded to the widest cell in this
//! render, the last unpadded. Every line ends with `\n`.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! A popup is plain stdout, not a tmux option value, so
//! [`crate::summary::escape_dynamic`] must not be applied here: a job called
//! `fix #42` is printed as `fix #42`.

use time::OffsetDateTime;

use crate::frame::{AttentionLevel, JobView};
use crate::status::StatusClass;

/// What a popup with nothing to show prints.
pub const EMPTY: &str = "nerve: no jobs";

/// Shown wherever a job carries nothing for a column.
const MISSING: &str = "-";

/// Two spaces, the gap between every pair of columns.
const GAP: &str = "  ";

/// The four columns that are padded; `age` closes the line and is not.
const PADDED_COLUMNS: usize = 4;

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

        let rows: Vec<[String; 5]> = jobs.iter().map(|job| self.row(job)).collect();
        let widths = Self::widths(&rows);

        let mut rendered = String::new();
        for row in &rows {
            for (column, cell) in row.iter().enumerate() {
                if column > 0 {
                    rendered.push_str(GAP);
                }
                rendered.push_str(cell);
                if column < PADDED_COLUMNS {
                    for _ in cell.chars().count()..widths[column] {
                        rendered.push(' ');
                    }
                }
            }
            rendered.push('\n');
        }
        rendered
    }

    fn row(&self, job: &JobView) -> [String; 5] {
        [
            Self::producer(job),
            Self::text(&job.name),
            StatusClass::of(job).label().to_string(),
            Self::attention(job),
            self.age(job),
        ]
    }

    /// The widest cell of each padded column, in characters.
    fn widths(rows: &[[String; 5]]) -> [usize; PADDED_COLUMNS] {
        let mut widths = [0usize; PADDED_COLUMNS];
        for row in rows {
            for (column, width) in widths.iter_mut().enumerate() {
                *width = (*width).max(row[column].chars().count());
            }
        }
        widths
    }

    fn producer(job: &JobView) -> String {
        match job.producer.name.as_deref() {
            Some(name) if !name.trim().is_empty() => name.to_string(),
            _ => Self::text(&job.producer.id),
        }
    }

    /// The reason a job wants a human, else the level when it is raised at all.
    fn attention(job: &JobView) -> String {
        match job.attention.reason.as_deref() {
            Some(reason) if !reason.trim().is_empty() => reason.to_string(),
            _ if job.attention.level > AttentionLevel::None => {
                job.attention.level.wire().to_string()
            }
            _ => MISSING.to_string(),
        }
    }

    /// How long ago the job last said anything.
    ///
    /// A producer whose clock runs ahead reads as `0s` rather than as a
    /// negative age.
    fn age(&self, job: &JobView) -> String {
        let Some(updated) = job.updated_at else {
            return MISSING.to_string();
        };
        let seconds = (self.now - updated.instant()).whole_seconds().max(0);
        match seconds {
            0..=59 => format!("{seconds}s"),
            60..=3_599 => format!("{}m", seconds / 60),
            3_600..=86_399 => format!("{}h", seconds / 3_600),
            _ => format!("{}d", seconds / 86_400),
        }
    }

    fn text(value: &str) -> String {
        if value.trim().is_empty() {
            MISSING.to_string()
        } else {
            value.to_string()
        }
    }
}

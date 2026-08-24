//! Shared tabular row layout for sidebar and popup.

use std::borrow::Cow;

use time::OffsetDateTime;
use unicode_width::UnicodeWidthStr;

use crate::frame::{AttentionLevel, JobView};

/// Two spaces between padded columns — matches popup layout.
pub const GAP: &str = "  ";

/// Shown when a cell has nothing to print.
pub const MISSING: &str = "-";

/// Activity / attention title — mirrored from `StatusPanelView.activityText`.
///
/// Borrowed from the job: every row asks for this on every repaint, and the
/// answer is always a field the job already holds.
pub fn activity_text(job: &JobView) -> &str {
    if job.attention.level >= AttentionLevel::Suggested {
        if let Some(title) = job.attention.title.as_deref().filter(|s| !s.is_empty()) {
            return title;
        }
    }
    if let Some(current) = &job.current {
        if let Some(summary) = current.summary.as_deref().filter(|s| !s.is_empty()) {
            return summary;
        }
        if let Some(name) = current.name.as_deref().filter(|s| !s.is_empty()) {
            return name;
        }
    }
    ""
}

/// What a cell prints, with [`MISSING`] standing in for nothing at all.
pub fn cell_text(value: &str) -> &str {
    if value.trim().is_empty() {
        MISSING
    } else {
        value
    }
}

/// How long ago the job last said anything.
///
/// A producer whose clock runs ahead reads as `0s` rather than as a negative
/// age. One ladder for the sidebar and the popup, so the two cannot drift.
pub fn age_label(now: OffsetDateTime, job: &JobView) -> String {
    let Some(updated) = job.updated_at else {
        return MISSING.to_string();
    };
    let seconds = (now - updated.instant()).whole_seconds().max(0);
    match seconds {
        0..=59 => format!("{seconds}s"),
        60..=3_599 => format!("{}m", seconds / 60),
        3_600..=86_399 => format!("{}h", seconds / 3_600),
        _ => format!("{}d", seconds / 86_400),
    }
}

/// Left-align `cells` to the widest cell in each column.
///
/// Accepts any row that borrows as a `[String]` slice, so a caller holding
/// fixed-size rows does not have to reallocate them into `Vec`s first.
pub fn pad_columns<R: AsRef<[String]>>(cells: &[R], padded: usize) -> Vec<Vec<String>> {
    let mut widths = vec![0usize; padded];
    for row in cells {
        for (col, width) in widths.iter_mut().enumerate() {
            if let Some(cell) = row.as_ref().get(col) {
                *width = (*width).max(display_width(cell));
            }
        }
    }
    cells
        .iter()
        .map(|row| {
            row.as_ref()
                .iter()
                .enumerate()
                .map(|(col, cell)| {
                    if col >= padded {
                        return cell.clone();
                    }
                    pad_cell(cell, widths[col])
                })
                .collect()
        })
        .collect()
}

pub fn pad_cell(cell: &str, width: usize) -> String {
    let w = display_width(cell);
    if w >= width {
        return cell.to_string();
    }
    let mut out = cell.to_string();
    for _ in w..width {
        out.push(' ');
    }
    out
}

pub fn display_width(text: &str) -> usize {
    UnicodeWidthStr::width(text)
}

/// `text` cut to `max` display columns, with `…` marking what was dropped.
///
/// Borrowed back unchanged when it already fits — the common case on every row
/// of every repaint.
pub fn truncate(text: &str, max: usize) -> Cow<'_, str> {
    if display_width(text) <= max {
        return Cow::Borrowed(text);
    }
    let mut out = String::new();
    let mut width = 0;
    for ch in text.chars() {
        let w = unicode_width::UnicodeWidthChar::width(ch).unwrap_or(0);
        if width + w + 1 > max {
            out.push('…');
            break;
        }
        out.push(ch);
        width += w;
    }
    Cow::Owned(out)
}

//! Monospace column layout for the sidebar and the popup.
//!
//! What a cell *says* is [`nerve_surface_core::display`]; this is how wide it
//! is. The two are separate because terminal-cell arithmetic is the one thing
//! a GUI surface has no use for.

use std::borrow::Cow;

use unicode_width::UnicodeWidthStr;

// Re-exported while the extraction lands: the sidebar and popup reach for
// these through `crate::columns::`. Removed with the rest of the facade.
pub use nerve_surface_core::display::{activity_text, age_label, cell_text, MISSING};

/// Two spaces between padded columns — matches popup layout.
pub const GAP: &str = "  ";

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

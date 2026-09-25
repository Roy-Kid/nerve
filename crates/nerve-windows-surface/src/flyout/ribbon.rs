//! The ribbon, at the size it was designed for.
//!
//! This is the real one — the continuous strip the macOS menu bar carries,
//! drawn with the same weights ([`nerve_surface_core::ribbon`]). It could not
//! survive the move to a 16 px tray icon, so it moved here instead, and the
//! icon became its folded summary. Seeing it is the answer to whether the
//! Windows surface is the same product.

use egui::{Color32, Rect, Response, Sense, Ui, Vec2};
use nerve_surface_core::palette;
use nerve_surface_core::ribbon::{Run, length_factor, weighted_runs};
use nerve_surface_core::status::StatusClass;
use nerve_surface_core::tally::Tally;

use super::theme::color;
use crate::tray::icon::Theme;

/// Height of the strip.
const HEIGHT: f32 = 10.0;
/// Corner radius; half the height, so the ends are caps.
const RADIUS: f32 = HEIGHT / 2.0;
/// The shortest the strip may be, as a share of the width available.
const MIN_SPAN: f32 = 0.30;

/// The runs, left to right, in the order the panel lists its rows.
///
/// Adjacent rows of the same status merge into one band, which is what makes
/// regrouping visibly reorder the strip rather than just recolour it.
pub fn runs_for(classes: &[StatusClass]) -> Vec<Run> {
    let mut merged: Vec<(StatusClass, usize)> = Vec::new();
    for class in classes {
        match merged.last_mut() {
            Some((last, count)) if last == class => *count += 1,
            _ => merged.push((*class, 1)),
        }
    }
    weighted_runs(&merged)
}

/// Draw the strip and return its response, so the caller can hang a tooltip on
/// it.
pub fn show(ui: &mut Ui, runs: &[Run], tally: &Tally, offline: bool, theme: Theme) -> Response {
    let width = ui.available_width();
    let (rect, response) = ui.allocate_exact_size(Vec2::new(width, HEIGHT), Sense::hover());
    let painter = ui.painter();

    if runs.is_empty() {
        // The idle pill: present, so the strip is visibly resting rather than
        // missing, and gray, because idle is chrome and not a status.
        let pill = Rect::from_min_size(rect.min, Vec2::new(width * MIN_SPAN, HEIGHT));
        painter.rect_filled(pill, RADIUS, color(palette::INACTIVE).gamma_multiply(0.55));
        return response;
    }

    // The strip lengthens with how much is happening, the same ladder the
    // menu bar uses — without it a single running job fills the panel exactly
    // as forty would.
    let active: usize = runs.iter().map(|run| run.count).sum();
    let span = (MIN_SPAN + (1.0 - MIN_SPAN) * length_factor(active)) * width;
    let dim = if offline { 0.40 } else { 1.0 };

    let mut x = rect.min.x;
    for run in runs {
        let run_width = (run.weight.clamp(0.0, 1.0) * span).max(2.0);
        let band = Rect::from_min_size(egui::pos2(x, rect.min.y), Vec2::new(run_width, HEIGHT));
        painter.rect_filled(band, RADIUS, lift(run.class, theme).gamma_multiply(dim));
        x += run_width;
    }

    if offline {
        // The same "no signal" slash the tray icon carries, so the two states
        // read as one thing in two places.
        painter.line_segment(
            [
                egui::pos2(rect.min.x, rect.max.y),
                egui::pos2(rect.min.x + span, rect.min.y),
            ],
            egui::Stroke::new(1.0_f32, color(palette::INACTIVE)),
        );
    }

    let _ = tally;
    response
}

/// The same small lift the icon and the macOS ribbon apply.
fn lift(class: StatusClass, theme: Theme) -> Color32 {
    let base = palette::color_of(class);
    color(match theme {
        Theme::Dark => base.blend(palette::WHITE, 0.04),
        Theme::Light => base.blend(palette::BLACK, 0.06),
    })
}

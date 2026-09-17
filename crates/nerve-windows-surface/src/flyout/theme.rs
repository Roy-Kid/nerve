//! The panel's colours, from the system's.

use egui::{Color32, Visuals};
use nerve_surface_core::palette::Rgb;

use crate::tray::icon::Theme;

/// egui's own colour type, from ours.
pub fn color(rgb: Rgb) -> Color32 {
    Color32::from_rgb(rgb.r, rgb.g, rgb.b)
}

/// Start from egui's own light or dark and adjust only what the product has an
/// opinion about.
///
/// Deliberately little: a status panel that invents its own chrome stops
/// looking like it belongs to the desktop it sits on, and the six status hues
/// are the only colours here that carry meaning.
pub fn visuals(theme: Theme) -> Visuals {
    let mut visuals = match theme {
        Theme::Light => Visuals::light(),
        Theme::Dark => Visuals::dark(),
    };
    // The flyout has no title bar, so its own background is the whole frame.
    visuals.window_shadow = egui::epaint::Shadow::NONE;
    visuals.window_stroke = egui::Stroke::new(
        1.0_f32,
        match theme {
            Theme::Light => Color32::from_gray(0xD0),
            Theme::Dark => Color32::from_gray(0x3A),
        },
    );
    visuals
}

/// The muted colour for text that is context rather than content.
pub fn secondary(theme: Theme) -> Color32 {
    match theme {
        Theme::Light => Color32::from_gray(0x6A),
        Theme::Dark => Color32::from_gray(0x9A),
    }
}

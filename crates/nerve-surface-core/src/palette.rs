//! The status colours, once.
//!
//! Five rainbow hues a person can name — red problem, orange attention, blue
//! running, violet monitor, green success — plus a gray idle that is chrome
//! rather than a status. Seven is the ceiling. Waiting shares attention on
//! purpose, so "needs a look" is one colour.
//!
//! This is the source every surface renders from: the tmux sidebar maps it to
//! ANSI-256 (`nerve_tmux_surface::colors`), the macOS app to `NSColor`
//! (`SettingsStore.swift`), a tray to an RGBA pixel. Those were three
//! hand-synced copies of the same six hex values; this is the one they agree
//! with.

use crate::status::StatusClass;

/// A colour as the wire and the docs write it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b }
    }

    /// `#RRGGBB`, the spelling the site and the Swift comments use.
    pub fn hex(self) -> String {
        format!("#{:02X}{:02X}{:02X}", self.r, self.g, self.b)
    }

    /// Move `fraction` of the way towards `other` (0.0 = unchanged).
    ///
    /// How a surface lifts a colour off a dark background or presses it into a
    /// light one without giving each status a second hue.
    pub fn blend(self, other: Rgb, fraction: f32) -> Rgb {
        let f = fraction.clamp(0.0, 1.0);
        let mix = |a: u8, b: u8| (f32::from(a) + (f32::from(b) - f32::from(a)) * f).round() as u8;
        Rgb::new(
            mix(self.r, other.r),
            mix(self.g, other.g),
            mix(self.b, other.b),
        )
    }
}

/// Problem — rainbow red.
pub const PROBLEM: Rgb = Rgb::new(0xFF, 0x3B, 0x30);
/// Attention, and waiting with it — rainbow orange.
pub const ATTENTION: Rgb = Rgb::new(0xFF, 0x9F, 0x0A);
/// Running — rainbow blue.
pub const RUNNING: Rgb = Rgb::new(0x0A, 0x84, 0xFF);
/// Monitor — rainbow violet.
pub const MONITOR: Rgb = Rgb::new(0xBF, 0x5A, 0xF2);
/// Success — rainbow green.
pub const SUCCESS: Rgb = Rgb::new(0x30, 0xD1, 0x58);
/// Inactive / idle — chrome gray, not a rainbow status.
pub const INACTIVE: Rgb = Rgb::new(0x8E, 0x8E, 0x93);

/// The colour a status paints.
pub fn color_of(class: StatusClass) -> Rgb {
    match class {
        StatusClass::Problem => PROBLEM,
        // Waiting shares attention: one colour for "needs a look".
        StatusClass::Attention | StatusClass::Waiting => ATTENTION,
        StatusClass::Running => RUNNING,
        StatusClass::Monitor => MONITOR,
        StatusClass::Success => SUCCESS,
        StatusClass::Inactive => INACTIVE,
    }
}

pub const WHITE: Rgb = Rgb::new(0xFF, 0xFF, 0xFF);
pub const BLACK: Rgb = Rgb::new(0x00, 0x00, 0x00);

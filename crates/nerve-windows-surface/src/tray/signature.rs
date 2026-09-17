//! When the tray icon is worth redrawing.
//!
//! `Shell_NotifyIcon(NIM_MODIFY)` is a shell round trip, and an icon that
//! changes many times a second reads to a Windows user as malware rather than
//! as activity. So the surface computes what the icon *would* say and only
//! calls the shell when that differs.
//!
//! What is deliberately absent is as important as what is here: a job's
//! `revision` bumps on every tool call, and including it would mean redrawing
//! the icon continuously through work whose colour never changed. This is the
//! lesson `SubjectStore.ribbonSignature` already encodes on macOS.

use nerve_surface_core::palette::Rgb;

use super::bands::Band;
use super::icon::Theme;

/// Everything the drawn icon depends on, and nothing else.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Signature(u64);

/// Hash the icon's inputs.
///
/// Weights are quantised to a thousandth before hashing: below that they are
/// the same pixels, and float noise would defeat the whole gate.
pub fn of(bands: &[Band], offline: bool, theme: Theme, size: u32) -> Signature {
    // FNV-1a: no dependency, and the cost has to stay under the shell call it
    // is there to avoid.
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    let mut eat = |value: u64| {
        for byte in value.to_le_bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    };

    eat(size as u64);
    eat(u64::from(offline));
    eat(match theme {
        Theme::Light => 1,
        Theme::Dark => 2,
    });
    eat(bands.len() as u64);
    for band in bands {
        let Rgb { r, g, b } = band.color;
        eat(u64::from(r) << 16 | u64::from(g) << 8 | u64::from(b));
        eat(band.count as u64);
        eat((band.weight.clamp(0.0, 1.0) * 1000.0).round() as u64);
    }
    Signature(hash)
}

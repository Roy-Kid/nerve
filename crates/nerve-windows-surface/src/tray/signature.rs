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

use std::hash::{Hash, Hasher};

use rustc_hash::FxHasher;

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
    // A non-cryptographic hasher, because this runs on every frame and exists
    // to avoid a shell round trip — it has to cost less than what it saves.
    let mut hasher = FxHasher::default();

    size.hash(&mut hasher);
    offline.hash(&mut hasher);
    matches!(theme, Theme::Light).hash(&mut hasher);
    bands.len().hash(&mut hasher);
    for band in bands {
        band.color.r.hash(&mut hasher);
        band.color.g.hash(&mut hasher);
        band.color.b.hash(&mut hasher);
        band.count.hash(&mut hasher);
        ((band.weight.clamp(0.0, 1.0) * 1000.0).round() as u64).hash(&mut hasher);
    }
    Signature(hasher.finish())
}

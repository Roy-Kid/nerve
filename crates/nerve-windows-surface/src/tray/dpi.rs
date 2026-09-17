//! Which icon size Windows is asking for.
//!
//! Notification-area icons are `SM_CXSMICON` square, which scales with the
//! display: 16 px at 100%, and one rung per 25% after that. Asking winit for
//! the window's `scale_factor` gets this without a `GetSystemMetricsForDpi`
//! call, and therefore without `unsafe`.

/// The rungs Windows actually uses. Anything denser clamps to the last.
const RUNGS: [(f32, u32); 5] = [(1.0, 16), (1.25, 20), (1.5, 24), (1.75, 28), (2.0, 32)];

/// Icon edge length in pixels for a given scale factor.
///
/// Rounds to the nearest rung rather than multiplying and truncating: a
/// non-integer icon size is resampled by the shell, and a resampled 16 px icon
/// is a blurry one.
pub fn icon_px(scale_factor: f64) -> u32 {
    let factor = if scale_factor.is_finite() {
        scale_factor.max(0.0) as f32
    } else {
        1.0
    };
    let mut best = RUNGS[0];
    let mut best_distance = f32::INFINITY;
    for rung in RUNGS {
        let distance = (rung.0 - factor).abs();
        if distance < best_distance {
            best_distance = distance;
            best = rung;
        }
    }
    // Past 200% the shell still asks for 32; there is no 48 px tray rung.
    if factor >= RUNGS[RUNGS.len() - 1].0 {
        return RUNGS[RUNGS.len() - 1].1;
    }
    best.1
}

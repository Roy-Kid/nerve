//! Status palette — keep in sync with `Nerve/Nerve/Store/SettingsStore.swift`
//! (`StatusColorMap.default`). Only `IDLE` is muted gray; every other class is
//! vivid on both tmux (256-color indices) and macOS (sRGB).

/// Problem — `#FF453A`
pub const PROBLEM: u8 = 203;
/// Attention — `#FF9F0A`
pub const ATTENTION: u8 = 214;
/// Waiting — `#BF5AF2`
pub const WAITING: u8 = 141;
/// Running — `#0A84FF`
pub const RUNNING: u8 = 39;
/// Success — `#30D158`
pub const SUCCESS: u8 = 82;
/// Inactive / idle — `#8E8E93` (the only subdued status color)
pub const IDLE: u8 = 245;

/// Alias used by filter/error paths.
pub const ERROR: u8 = PROBLEM;

/// “All jobs” filter chip.
pub const ALL: u8 = 255;

pub const FILTER_INACTIVE: u8 = 245;
pub const BORDER: u8 = 240;
pub const ACCENT: u8 = 153;
pub const SELECTION: u8 = 239;
pub const TEXT_ACTIVE: u8 = 255;
pub const TEXT_MUTED: u8 = 252;
pub const TEXT_INACTIVE: u8 = 244;
pub const ACTIVITY_TS: u8 = 109;
pub const BRANCH: u8 = 109;

//! Status palette — keep in sync with `Nerve/Nerve/Store/SettingsStore.swift`
//! (`StatusColorMap.default`).
//!
//! Shared job statuses (the ribbon, dots, filter chips): five rainbow hues a
//! person can name — red problem, orange attention, blue running, violet
//! monitor, green success — plus gray idle. Seven is the ceiling. Waiting
//! shares attention so “needs a look” is one color.
//!
//! Chrome (borders, text, git, selection) stays on a muted gray/slate
//! 256-color scale. It must not grow its own rainbow.

/// Problem — rainbow red `#FF3B30`
pub const PROBLEM: u8 = 196;
/// Attention (and waiting) — rainbow orange `#FF9F0A`
pub const ATTENTION: u8 = 214;
/// Waiting shares attention. Kept as a name so call sites do not fork.
pub const WAITING: u8 = ATTENTION;
/// Running — rainbow blue `#0A84FF`
pub const RUNNING: u8 = 33;
/// Monitor — rainbow violet `#BF5AF2`
pub const MONITOR: u8 = 171;
/// Success — rainbow green `#30D158`
pub const SUCCESS: u8 = 41;
/// Inactive / idle — `#8E8E93` (chrome gray, not a rainbow status)
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

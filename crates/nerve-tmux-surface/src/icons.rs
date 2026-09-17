//! Status icons — same glyphs as tmux-agent-sidebar defaults.

pub const ALL: &str = "≡";
pub const RUNNING: &str = "●";
pub const BACKGROUND: &str = "◎";
pub const WAITING: &str = "◐";
pub const IDLE: &str = "○";
pub const ERROR: &str = "✕";

use nerve_surface_core::filter::StatusFilter;
use nerve_surface_core::status::StatusClass;

pub fn filter_icon(filter: StatusFilter) -> &'static str {
    match filter {
        StatusFilter::All => ALL,
        StatusFilter::Running => RUNNING,
        StatusFilter::Background => BACKGROUND,
        StatusFilter::Waiting => WAITING,
        StatusFilter::Idle => IDLE,
        StatusFilter::Error => ERROR,
    }
}

pub fn status_icon(class: StatusClass) -> &'static str {
    match class {
        StatusClass::Problem => ERROR,
        StatusClass::Attention => WAITING,
        StatusClass::Waiting => WAITING,
        StatusClass::Running => RUNNING,
        StatusClass::Monitor => BACKGROUND,
        StatusClass::Success => BACKGROUND,
        StatusClass::Inactive => IDLE,
    }
}

//! nerve-tmux-surface: the tmux peer of the macOS menu-bar surface.
//!
//! UI and interaction are aligned with tmux-agent-sidebar: a split-pane sidebar
//! with a status filter bar, scrollable job list, and a foldable Prompt/Git panel.
//! Data comes from nerve-hub over SSE, not from agent hooks.

// Moved to `nerve-surface-core`, re-exported here so `crate::frame::JobView`
// and `nerve_tmux_surface::status::StatusClass` keep resolving while the rest
// of the extraction lands. Removed once every call site names the core crate.
pub use nerve_surface_core::{filter, frame, hub, launch, locate, machine, status, store, tally};

pub mod app;
pub mod cli;
pub mod colors;
pub mod columns;
pub mod git;
pub mod icons;
pub mod panes;
pub mod popup;
pub mod preview;
mod procs;
pub mod remote;
pub mod ssh;
pub mod state;
pub mod stream;
pub mod summary;
pub mod tmux;
pub mod ui;

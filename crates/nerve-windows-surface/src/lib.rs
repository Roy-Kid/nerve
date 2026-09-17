//! The Windows peer of the macOS menu bar and the tmux sidebar.
//!
//! Windows has no menu bar, so the surface lives in the notification area: a
//! tray icon that carries the whole machine's state at a glance, and a flyout
//! panel behind it that carries the rows.
//!
//! The ribbon does not survive the move to a 16 px icon — nothing does — so it
//! moves *into* the flyout, drawn with the same weights the menu bar uses
//! ([`nerve_surface_core::ribbon`]), and the icon becomes its folded summary.
//!
//! Everything that decides *what* is on screen — bands, weights, tooltip text,
//! where the flyout opens, what Open does — is a pure function in a module
//! below, tested on whatever machine runs `cargo test`. Only the pixels need
//! Windows.

pub mod actions;
pub mod app;
pub mod flyout;
pub mod notify;
pub mod platform;
pub mod settings;
pub mod tray;

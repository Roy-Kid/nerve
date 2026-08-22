//! What surfaces are told, and when.
//!
//! [`frame`] owns the shape of one frame; [`broadcaster`] owns the timing. The
//! route that serves them is `http::stream`, so this module stays free of axum
//! and can be exercised with a store and a clock alone.

pub mod broadcaster;
pub mod frame;

pub use broadcaster::{Broadcaster, ChangeSignal};
pub use frame::Frame;

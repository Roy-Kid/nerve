//! How long the hub stays alive, and who may interrupt.
//!
//! [`refcount`] counts the surfaces watching; [`grace`] turns a count of zero
//! into an exit. [`roster`] hangs a label on each subscription so [`notify`]
//! can elect one owner for OS banners. Count and lease meet over a `watch`
//! channel and a change signal, never over a shared struct.

pub mod grace;
pub mod notify;
pub mod refcount;
pub mod roster;

pub use grace::{ExitSignal, GraceTimer};
pub use notify::{NotifyLease, NotifyPolicy};
pub use refcount::{Presence, Subscription, Watchers};
pub use roster::{RosterGuard, SurfaceRoster};

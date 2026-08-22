//! How long the hub stays alive.
//!
//! Two collaborators, split so neither needs the other to be tested: a
//! reference count of the surfaces watching ([`refcount`]), and the timer that
//! turns "nobody is watching" into an exit decision ([`grace`]). They meet over
//! a `watch` channel of the count, never over a shared struct.

pub mod grace;
pub mod refcount;

pub use grace::{ExitSignal, GraceTimer};
pub use refcount::{Presence, Subscription, Watchers};

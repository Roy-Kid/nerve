//! How many surfaces are watching, and since when.
//!
//! A surface proves it is present by holding an SSE subscription (spec D3);
//! producer traffic proves nothing, because a hook never reads a frame. This
//! module counts references and publishes every change — deciding what a count
//! of zero means is [`super::grace`]'s job, so the count itself stays free of
//! policy and needs no timer to be tested.

use std::sync::Arc;

use tokio::sync::watch;
use tokio::time::Instant;

/// How many surfaces are watching, and the instant that number last changed.
///
/// `since` travels with the count so a timer armed later still measures from
/// the transition rather than from the moment it happened to look.
#[derive(Clone, Copy, Debug)]
pub struct Watchers {
    pub count: usize,
    pub since: Instant,
}

/// The hub's surface count.
///
/// Clone it to hand subscriptions out from more than one place; every clone
/// counts into the same number.
#[derive(Clone)]
pub struct Presence {
    watchers: Arc<watch::Sender<Watchers>>,
}

impl Presence {
    /// A hub nobody has connected to yet: zero watchers, as of now.
    pub fn new() -> Self {
        let (watchers, _) = watch::channel(Watchers {
            count: 0,
            since: Instant::now(),
        });
        Self {
            watchers: Arc::new(watchers),
        }
    }

    /// One surface arrives. The reference lives until the returned guard drops.
    pub fn subscribe(&self) -> Subscription {
        self.watchers.send_modify(|watchers| {
            watchers.count = watchers.count.saturating_add(1);
            watchers.since = Instant::now();
        });
        Subscription {
            watchers: Arc::clone(&self.watchers),
        }
    }

    /// Follow the count — how the grace timer learns about 0→1 and 1→0.
    pub fn watch(&self) -> watch::Receiver<Watchers> {
        self.watchers.subscribe()
    }
}

impl Default for Presence {
    fn default() -> Self {
        Self::new()
    }
}

/// One surface's presence.
///
/// Dropping it *is* the disconnect: the SSE response body owns one, so a closed
/// socket releases the reference without anyone having to notice the close.
pub struct Subscription {
    watchers: Arc<watch::Sender<Watchers>>,
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.watchers.send_modify(|watchers| {
            watchers.count = watchers.count.saturating_sub(1);
            watchers.since = Instant::now();
        });
    }
}

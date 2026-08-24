//! When a hub nobody is watching stops.
//!
//! The rule (spec D3): the last subscription leaving — and start-up itself,
//! since a surface may spawn a hub and then die before it connects — starts a
//! `--grace-secs` countdown. A new subscription cancels it; the next 1→0 starts
//! a fresh one, never the remainder of the old.
//!
//! The timer is owned by a task rather than by whoever awaits the decision, so
//! the answer to "is the hub going to exit?" is the same for every observer and
//! does not depend on someone polling.

use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::watch;
use tokio::time::sleep_until;

use super::refcount::Watchers;

/// The hub's decision to stop: level-triggered and latching.
///
/// Raised once, by the timer. Every observer after that is answered on its
/// first poll instead of waiting for a second decision that never comes.
#[derive(Clone)]
pub struct ExitSignal {
    raised: Arc<watch::Sender<bool>>,
}

impl ExitSignal {
    pub fn new() -> Self {
        let (raised, _) = watch::channel(false);
        Self {
            raised: Arc::new(raised),
        }
    }

    /// Decide to stop. Idempotent — the second call changes nothing.
    pub fn raise(&self) {
        self.raised.send_replace(true);
    }

    /// Resolve once the decision has been made.
    ///
    /// Owned rather than borrowing `&self`, so `serve` can hand it to
    /// `with_graceful_shutdown`. A dropped signal (the runtime went away)
    /// resolves too: nothing is left to serve.
    pub fn wait(&self) -> impl Future<Output = ()> + Send + 'static {
        let mut raised = self.raised.subscribe();
        async move {
            // The level, not the edge: a decision made before this future
            // existed still resolves it.
            while !*raised.borrow_and_update() {
                if raised.changed().await.is_err() {
                    return;
                }
            }
        }
    }
}

impl Default for ExitSignal {
    fn default() -> Self {
        Self::new()
    }
}

/// Watches the surface count and raises [`ExitSignal`] when nobody has been
/// watching for a whole grace.
pub struct GraceTimer {
    grace: Duration,
    watchers: watch::Receiver<Watchers>,
    exit: ExitSignal,
}

impl GraceTimer {
    pub fn new(grace: Duration, watchers: watch::Receiver<Watchers>, exit: ExitSignal) -> Self {
        Self {
            grace,
            watchers,
            exit,
        }
    }

    /// Own the timer until it fires.
    ///
    /// Level-triggered on the count: the loop re-reads the current number every
    /// time rather than reacting to transitions, so a 0→1→0 burst it never
    /// witnessed still leaves it armed correctly. The deadline is derived from
    /// the instant the count changed, not from the instant this loop looked, so
    /// a late observation cannot lengthen a grace.
    pub async fn run(mut self) {
        loop {
            let watchers = *self.watchers.borrow_and_update();
            if watchers.count > 0 {
                // Someone is watching: no deadline exists to wait for.
                if self.watchers.changed().await.is_err() {
                    return;
                }
                continue;
            }

            let deadline = watchers.since + self.grace;
            tokio::select! {
                () = sleep_until(deadline) => {
                    self.exit.raise();
                    return;
                }
                changed = self.watchers.changed() => {
                    if changed.is_err() {
                        return;
                    }
                }
            }
        }
    }
}
